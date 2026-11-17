import { DatePipe } from '@angular/common';
import {
  ChangeDetectionStrategy,
  Component,
  OnInit,
  computed,
  inject,
  signal,
} from '@angular/core';
import { ActivatedRoute, RouterLink } from '@angular/router';

import {
  CoursePractices,
  DifficultyMap,
  FollowModeCode,
  PracticeRow,
  StudioCourseDetail,
  apiError,
  percent,
} from '../../core/api.models';
import { StudioService } from '../../core/studio.service';

const SPEEDS: Record<string, string> = { '1': '1×', '0.75': '0,75×', '0.5': '0,5×' };
const MODES: Record<FollowModeCode, string> = { mirror: 'Espejo', 'same-side': 'Mismos lados' };

/** A course for its instructor: where students struggle and their practices. */
@Component({
  selector: 'sd-studio-course',
  imports: [DatePipe, RouterLink],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './studio-course.page.html',
  styleUrl: './studio-course.page.scss',
})
export class StudioCoursePage implements OnInit {
  private readonly studio = inject(StudioService);
  readonly id = Number(inject(ActivatedRoute).snapshot.paramMap.get('id'));

  readonly percent = percent;
  readonly speeds = SPEEDS;
  readonly modes = MODES;
  readonly ratings = [1, 2, 3, 4, 5];

  readonly course = signal<StudioCourseDetail | null>(null);
  readonly map = signal<DifficultyMap | null>(null);
  readonly practices = signal<CoursePractices | null>(null);
  readonly routine = signal<number | null>(null);
  readonly followMode = signal<FollowModeCode>('mirror');
  readonly speed = signal('1');
  readonly commenting = signal<string | null>(null);
  readonly comment = signal('');
  readonly busy = signal(false);
  readonly message = signal('');
  readonly error = signal('');

  /** The map is for dance: singing sends no results to the server yet. */
  readonly danceRoutines = computed(
    () => this.course()?.routines.filter((r) => r.kind !== 'SING') ?? [],
  );
  readonly singingRoutines = computed(
    () => (this.course()?.routines.length ?? 0) - this.danceRoutines().length,
  );

  /** Steps that have frequent errors to list under the map. */
  readonly withErrors = computed(
    () => this.map()?.steps.filter((step) => step.frequent_errors.length) ?? [],
  );

  ngOnInit(): void {
    this.studio.course(this.id).subscribe({
      next: (course) => {
        this.course.set(course);
        // Start on a routine that has steps: the map needs them.
        const dance = this.danceRoutines();
        const first = dance.find((r) => r.steps) ?? dance[0];
        if (first) this.chooseRoutine(first.id);
      },
      error: (error: unknown) => this.error.set(apiError(error, 'No se encontró el curso.')),
    });
    this.loadPractices();
  }

  chooseRoutine(id: number | string): void {
    this.routine.set(Number(id));
    this.loadMap();
  }

  chooseMode(mode: string): void {
    this.followMode.set(mode as FollowModeCode);
    this.loadMap();
  }

  chooseSpeed(speed: string): void {
    this.speed.set(speed);
    this.loadMap();
  }

  private loadMap(): void {
    const routine = this.routine();
    if (routine === null) return;
    this.studio.difficultyMap(this.id, routine, this.followMode(), Number(this.speed())).subscribe({
      next: (map) => this.map.set(map),
      error: (error: unknown) => this.error.set(apiError(error, 'No se pudo cargar el mapa.')),
    });
  }

  private loadPractices(): void {
    this.studio.practices(this.id).subscribe({
      next: (practices) => this.practices.set(practices),
      error: (error: unknown) =>
        this.error.set(apiError(error, 'No se pudieron cargar las prácticas.')),
    });
  }

  /** Same bands as the dance game: GOOD from 50, GREAT from 70. */
  tone(score: number | null): string {
    if (score === null) return 'none';
    return score >= 70 ? 'good' : score >= 50 ? 'fair' : 'low';
  }

  round(value: number | null): string {
    return value === null ? '—' : String(Math.round(value));
  }

  rho(value: number): string {
    return value.toFixed(2).replace('.', ',');
  }

  speedLabel(speed: number): string {
    return SPEEDS[String(speed)] ?? `${speed}×`;
  }

  stars(count: number | null): string {
    return count === null ? '—' : '★'.repeat(count) + '☆'.repeat(5 - count);
  }

  rate(practice: PracticeRow, rating: number): void {
    this.save(practice, rating, '', `Calificaste la práctica de ${practice.student}.`);
  }

  openComment(practice: PracticeRow): void {
    this.comment.set('');
    this.commenting.set(practice.id);
  }

  sendComment(practice: PracticeRow): void {
    const rating = practice.rating;
    const text = this.comment().trim();
    if (rating === null || !text) return;
    this.save(practice, rating, text, `${practice.student} verá tu comentario en la app.`);
  }

  private save(practice: PracticeRow, rating: number, comment: string, done: string): void {
    this.busy.set(true);
    this.error.set('');
    this.message.set('');
    this.studio.rate(practice.id, rating, comment).subscribe({
      next: () => {
        this.busy.set(false);
        this.commenting.set(null);
        this.message.set(done);
        this.loadPractices(); // the concordance changes with every rating
      },
      error: (error: unknown) => {
        this.busy.set(false);
        this.error.set(apiError(error, 'No se pudo guardar la calificación.'));
      },
    });
  }
}
