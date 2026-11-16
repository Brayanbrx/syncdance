import { HttpEventType } from '@angular/common/http';
import {
  ChangeDetectionStrategy,
  Component,
  DestroyRef,
  ElementRef,
  OnInit,
  computed,
  inject,
  signal,
  viewChild,
} from '@angular/core';
import { ActivatedRoute, RouterLink } from '@angular/router';

import { StudioRoutine, apiError, clock } from '../../core/api.models';
import { RoutineMediaService } from '../../core/routine-media.service';
import { StudioService } from '../../core/studio.service';
import {
  MAX_BPM,
  MAX_COUNTS,
  MIN_BPM,
  MIN_TAPS,
  TAP_GAP_MS,
  Tempo,
  beatAt,
  beatToMs,
  countOf,
  fitTaps,
  nearestBeat,
  overlapping,
} from './choreography';

interface DraftStep {
  /** Stable identity for the list while steps move around. */
  key: number;
  name: string;
  start_beat: number;
  counts: number;
  tip: string;
}

const NUDGE_MS = 20;

/**
 * The instructor marks the tempo by tapping along to the video and splits the
 * routine into steps. Students see the list and loop each step, slower, with
 * the counts on screen. Publishing the routine is what sends it to them.
 */
@Component({
  selector: 'sd-studio-choreography',
  imports: [RouterLink],
  changeDetection: ChangeDetectionStrategy.OnPush,
  host: { '(document:keydown)': 'shortcut($event)' },
  templateUrl: './studio-choreography.page.html',
  styleUrl: './studio-choreography.page.scss',
})
export class StudioChoreographyPage implements OnInit {
  private readonly studio = inject(StudioService);
  private readonly media = inject(RoutineMediaService);
  private readonly destroyRef = inject(DestroyRef);
  private readonly videoRef = viewChild<ElementRef<HTMLVideoElement>>('video');

  readonly id = Number(inject(ActivatedRoute).snapshot.paramMap.get('id'));
  readonly clock = clock;
  readonly minTaps = MIN_TAPS;
  readonly minBpm = MIN_BPM;
  readonly maxBpm = MAX_BPM;
  readonly maxCounts = MAX_COUNTS;
  readonly eight = [1, 2, 3, 4, 5, 6, 7, 8];
  readonly speeds = [
    { value: 0.5, label: '0,5×' },
    { value: 0.75, label: '0,75×' },
    { value: 1, label: '1×' },
  ];

  readonly routine = signal<StudioRoutine | null>(null);
  readonly videoUrl = signal<string | null>(null);
  readonly loadingVideo = signal<number | null>(null);
  readonly bpm = signal<number | null>(null);
  readonly firstBeat = signal<number | null>(null);
  readonly steps = signal<DraftStep[]>([]);
  readonly taps = signal<number[]>([]);
  readonly position = signal(0);
  readonly speed = signal(1);
  readonly metronome = signal(false);
  readonly busy = signal(false);
  readonly dirty = signal(false);
  readonly message = signal('');
  readonly error = signal('');

  readonly tempo = computed<Tempo | null>(() => {
    const bpm = this.bpm();
    const first = this.firstBeat();
    if (bpm === null || first === null || !(bpm >= MIN_BPM && bpm <= MAX_BPM)) return null;
    return { bpm, firstBeatMs: first };
  });
  readonly beat = computed(() => {
    const tempo = this.tempo();
    return tempo ? beatAt(this.position(), tempo) : null;
  });
  readonly count = computed(() => {
    const beat = this.beat();
    return beat === null ? null : countOf(beat);
  });
  /** The step being danced at the playhead. */
  readonly current = computed(() => {
    const beat = this.beat();
    if (beat === null) return null;
    return this.steps().find((s) => beat >= s.start_beat && beat < s.start_beat + s.counts) ?? null;
  });
  readonly overlaps = computed(() => overlapping(this.steps()));
  /** Steps that end after the video does. */
  readonly tooLong = computed(() => {
    const tempo = this.tempo();
    const duration = this.routine()?.duration_ms ?? 0;
    const bad = new Set<number>();
    if (!tempo) return bad;
    this.steps().forEach((s, i) => {
      if (beatToMs(s.start_beat + s.counts, tempo) > duration) bad.add(i);
    });
    return bad;
  });
  readonly problem = computed(() => {
    if (this.steps().length && !this.tempo()) return 'Marca el tempo antes de los pasos.';
    if (this.steps().some((s) => !s.name.trim())) return 'Cada paso necesita un nombre.';
    if (this.overlaps().size) return 'Hay pasos que empiezan antes de que termine el anterior.';
    if (this.tooLong().size) return 'Hay pasos que terminan después del final del video.';
    return '';
  });

  private nextKey = 1;
  private frame = 0;
  private lastBeat: number | null = null;
  private audio?: AudioContext;

  constructor() {
    this.destroyRef.onDestroy(() => {
      cancelAnimationFrame(this.frame);
      const url = this.videoUrl();
      if (url) URL.revokeObjectURL(url);
      void this.audio?.close();
    });
  }

  ngOnInit(): void {
    this.studio.routine(this.id).subscribe({
      next: (routine) => {
        this.routine.set(routine);
        this.useDraft(routine);
        const processing = routine.processing;
        if (processing?.status === 'READY') this.loadVideo(processing.version);
      },
      error: (error: unknown) => this.error.set(apiError(error, 'No se encontró la rutina.')),
    });
  }

  private useDraft(routine: StudioRoutine): void {
    const draft = routine.choreography;
    this.bpm.set(draft.bpm);
    this.firstBeat.set(draft.first_beat_ms);
    this.steps.set(draft.steps.map((step) => ({ ...step, key: this.nextKey++ })));
    this.dirty.set(false);
  }

  private loadVideo(version: number): void {
    this.loadingVideo.set(0);
    this.media.video(this.id, version).subscribe({
      next: (event) => {
        if (event.type === HttpEventType.DownloadProgress && event.total) {
          this.loadingVideo.set(Math.round((100 * event.loaded) / event.total));
        } else if (event.type === HttpEventType.Response && event.body) {
          this.videoUrl.set(URL.createObjectURL(event.body));
          this.loadingVideo.set(null);
        }
      },
      error: (error: unknown) => {
        this.loadingVideo.set(null);
        this.error.set(apiError(error, 'No se pudo cargar el video.'));
      },
    });
  }

  // --- playback ---------------------------------------------------------------

  private get video(): HTMLVideoElement | undefined {
    return this.videoRef()?.nativeElement;
  }

  /** Follows the playhead every frame while playing: counts and metronome. */
  private readonly tick = () => {
    const video = this.video;
    if (!video) return;
    this.position.set(Math.round(video.currentTime * 1000));
    const beat = this.beat();
    if (this.metronome() && beat !== null && beat !== this.lastBeat) this.click(beat % 8 === 0);
    this.lastBeat = beat;
    if (!video.paused) this.frame = requestAnimationFrame(this.tick);
  };

  playing(): void {
    cancelAnimationFrame(this.frame);
    this.lastBeat = this.beat();
    this.frame = requestAnimationFrame(this.tick);
  }

  moved(): void {
    const video = this.video;
    if (video?.paused) this.position.set(Math.round(video.currentTime * 1000));
  }

  setSpeed(speed: number): void {
    this.speed.set(speed);
    if (this.video) this.video.playbackRate = speed;
  }

  toggleMetronome(on: boolean): void {
    this.metronome.set(on);
    // Created on the click: browsers only allow sound after a gesture.
    if (on) {
      this.audio ??= new AudioContext();
      void this.audio.resume();
    }
  }

  private click(accent: boolean): void {
    const audio = this.audio;
    if (!audio) return;
    const tone = audio.createOscillator();
    const gain = audio.createGain();
    tone.frequency.value = accent ? 1600 : 1000;
    gain.gain.setValueAtTime(0.25, audio.currentTime);
    gain.gain.exponentialRampToValueAtTime(0.001, audio.currentTime + 0.05);
    tone.connect(gain).connect(audio.destination);
    tone.start();
    tone.stop(audio.currentTime + 0.06);
  }

  private seek(ms: number): void {
    const video = this.video;
    if (!video) return;
    video.pause();
    video.currentTime = ms / 1000;
    this.position.set(Math.round(ms));
  }

  // --- tempo ------------------------------------------------------------------

  /** One tap on the beat, in video time; a long pause starts a new series. */
  tap(event?: Event): void {
    event?.preventDefault();
    const video = this.video;
    if (!video || video.paused) {
      this.message.set('');
      this.error.set('Reproduce el video y toca en cada tiempo de la música.');
      return;
    }
    this.error.set('');
    const time = video.currentTime * 1000;
    const taps = this.taps();
    const last = taps.at(-1);
    const series =
      last === undefined || time <= last || time - last > TAP_GAP_MS ? [time] : [...taps, time];
    this.taps.set(series);
    const fit = fitTaps(series);
    if (fit) {
      this.bpm.set(fit.bpm);
      this.firstBeat.set(fit.firstBeatMs);
      this.dirty.set(true);
    }
  }

  /** "T" taps from anywhere on the page, except while typing. */
  shortcut(event: KeyboardEvent): void {
    const target = event.target;
    if (target instanceof Element && target.closest('input, textarea, select')) return;
    if (event.repeat) return; // a held key is one tap
    if (event.key === 't' || event.key === 'T') this.tap(event);
  }

  resetTaps(): void {
    this.taps.set([]);
  }

  setBpm(value: string): void {
    const bpm = Number(value.replace(',', '.'));
    this.bpm.set(value.trim() && Number.isFinite(bpm) ? Math.round(bpm * 100) / 100 : null);
    this.dirty.set(true);
  }

  nudge(delta: number): void {
    const first = this.firstBeat();
    if (first === null) return;
    this.firstBeat.set(Math.max(0, first + delta * NUDGE_MS));
    this.dirty.set(true);
  }

  firstBeatHere(): void {
    this.firstBeat.set(this.position());
    this.dirty.set(true);
  }

  // --- steps ------------------------------------------------------------------

  beatLabel(beat: number): string {
    const { eight, count } = countOf(beat);
    return `ocho ${eight}, tiempo ${count}`;
  }

  startMs(step: DraftStep): number {
    const tempo = this.tempo();
    return tempo ? beatToMs(step.start_beat, tempo) : 0;
  }

  /** A new step at the playhead, 8 counts or up to the next step. */
  addStep(): void {
    const tempo = this.tempo();
    if (!tempo) return;
    const start = nearestBeat(this.position(), tempo);
    const steps = this.steps();
    if (steps.some((s) => start >= s.start_beat && start < s.start_beat + s.counts)) {
      this.error.set('Ya hay un paso en ese tiempo: mueve el video a donde empieza el nuevo.');
      return;
    }
    const next = steps.find((s) => s.start_beat > start);
    const counts = Math.max(1, Math.min(8, next ? next.start_beat - start : 8));
    this.error.set('');
    this.setSteps([
      ...steps,
      { key: this.nextKey++, name: `Paso ${steps.length + 1}`, start_beat: start, counts, tip: '' },
    ]);
  }

  update(key: number, change: Partial<DraftStep>): void {
    this.setSteps(this.steps().map((s) => (s.key === key ? { ...s, ...change } : s)));
  }

  setCounts(key: number, value: string): void {
    const counts = Math.round(Number(value));
    if (counts >= 1 && counts <= MAX_COUNTS) this.update(key, { counts });
  }

  shift(step: DraftStep, beats: number): void {
    this.update(step.key, { start_beat: Math.max(0, step.start_beat + beats) });
  }

  startHere(step: DraftStep): void {
    const tempo = this.tempo();
    if (tempo) this.update(step.key, { start_beat: nearestBeat(this.position(), tempo) });
  }

  watch(step: DraftStep): void {
    this.seek(this.startMs(step));
    void this.video?.play();
  }

  remove(key: number): void {
    this.setSteps(this.steps().filter((s) => s.key !== key));
  }

  private setSteps(steps: DraftStep[]): void {
    this.steps.set([...steps].sort((a, b) => a.start_beat - b.start_beat));
    this.dirty.set(true);
  }

  // --- saving -----------------------------------------------------------------

  save(): void {
    const tempo = this.tempo();
    this.persist({
      bpm: tempo?.bpm ?? null,
      first_beat_ms: tempo?.firstBeatMs ?? null,
      steps: this.steps().map(({ name, start_beat, counts, tip }) => ({
        name: name.trim(),
        start_beat,
        counts,
        tip: tip.trim(),
      })),
    });
  }

  clearAll(): void {
    if (!confirm('¿Borrar el tempo y todos los pasos?')) return;
    this.taps.set([]);
    this.persist({ bpm: null, first_beat_ms: null, steps: [] });
  }

  private persist(draft: Parameters<StudioService['saveChoreography']>[1]): void {
    this.busy.set(true);
    this.message.set('');
    this.error.set('');
    this.studio.saveChoreography(this.id, draft).subscribe({
      next: (routine) => {
        this.busy.set(false);
        this.routine.set(routine);
        this.useDraft(routine);
        this.message.set(
          routine.is_published
            ? 'Guardado. Tus alumnos lo verán cuando publiques los cambios.'
            : 'Guardado. Tus alumnos lo verán cuando publiques la rutina.',
        );
      },
      error: (error: unknown) => {
        this.busy.set(false);
        this.error.set(apiError(error, 'No se pudo guardar.'));
      },
    });
  }

  /** Same courses and music rights: only the tempo and steps change. */
  publishChanges(): void {
    const routine = this.routine();
    if (!routine?.music_rights) return;
    this.busy.set(true);
    this.studio.publish(this.id, routine.courses, routine.music_rights).subscribe({
      next: (published) => {
        this.busy.set(false);
        this.routine.set(published);
        this.message.set('Publicado: tus alumnos ya ven el compás y los pasos.');
      },
      error: (error: unknown) => {
        this.busy.set(false);
        this.error.set(apiError(error, 'No se pudo publicar.'));
      },
    });
  }
}
