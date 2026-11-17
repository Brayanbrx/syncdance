import { HttpEventType } from '@angular/common/http';
import { DatePipe } from '@angular/common';
import {
  ChangeDetectionStrategy,
  Component,
  DestroyRef,
  OnInit,
  computed,
  inject,
  signal,
} from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { FormBuilder, ReactiveFormsModule, Validators } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { EMPTY, Observable, catchError, filter, switchMap, timer } from 'rxjs';

import {
  DIFFICULTY_LABELS,
  Difficulty,
  MUSIC_RIGHTS_LABELS,
  MusicRights,
  QualityReport,
  StudioCourse,
  StudioRoutine,
  apiError,
  clock,
  percent,
  routineState,
} from '../../core/api.models';
import { StudioService } from '../../core/studio.service';
import { RoutinePreviewComponent } from '../../shared/routine-preview.component';

const PROBLEM_LABELS: Record<string, string> = {
  NO_USABLE_POSE: 'no se ve el cuerpo completo',
  MULTIPLE_PEOPLE: 'aparece más de una persona',
};

@Component({
  selector: 'sd-studio-routine',
  imports: [DatePipe, ReactiveFormsModule, RouterLink, RoutinePreviewComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './studio-routine.page.html',
  styleUrl: './studio-routine.page.scss',
})
export class StudioRoutinePage implements OnInit {
  private readonly studio = inject(StudioService);
  private readonly router = inject(Router);
  private readonly destroyRef = inject(DestroyRef);
  private readonly id = Number(inject(ActivatedRoute).snapshot.paramMap.get('id'));

  readonly levels: Difficulty[] = ['BEGINNER', 'INTERMEDIATE', 'ADVANCED'];
  readonly levelLabels = DIFFICULTY_LABELS;
  readonly rightsOptions = Object.entries(MUSIC_RIGHTS_LABELS) as [MusicRights, string][];
  readonly percent = percent;
  readonly clock = clock;

  readonly routine = signal<StudioRoutine | null>(null);
  readonly quality = signal<QualityReport | null>(null);
  readonly videoAccept = 'video/mp4,video/quicktime,video/webm,video/x-matroska,.mkv';
  readonly courses = signal<StudioCourse[]>([]);
  readonly chosen = signal<Set<number>>(new Set());
  readonly rights = signal<MusicRights | ''>('');
  readonly busy = signal(false);
  readonly progress = signal<number | null>(null);
  readonly message = signal('');
  readonly error = signal('');

  readonly state = computed(() => {
    const routine = this.routine();
    return routine ? routineState(routine) : null;
  });
  readonly processing = computed(() =>
    ['PENDING', 'PROCESSING'].includes(this.routine()?.processing?.status ?? ''),
  );
  readonly ready = computed(() => this.routine()?.processing?.status === 'READY');
  readonly publishedIn = computed(() => {
    const ids = new Set(this.routine()?.courses ?? []);
    return this.courses().filter((course) => ids.has(course.id));
  });
  readonly canPublish = computed(
    () =>
      this.ready() &&
      this.quality()?.publishable !== false &&
      !!this.rights() &&
      this.chosen().size > 0 &&
      !this.busy(),
  );

  readonly form = inject(FormBuilder).nonNullable.group({
    name: ['', [Validators.required, Validators.maxLength(150)]],
    difficulty: ['BEGINNER' as Difficulty],
    style: [''],
    description: [''],
  });

  ngOnInit(): void {
    this.studio.routine(this.id).subscribe({
      next: (routine) => this.show(routine),
      error: (error: unknown) => this.error.set(apiError(error, 'No se encontró la rutina.')),
    });
    this.studio.courses().subscribe((courses) => this.courses.set(courses));
    // While the worker processes the video, check again every 5 seconds.
    // A failed check waits for the next one instead of ending the polling.
    timer(5000, 5000)
      .pipe(
        filter(() => this.processing()),
        switchMap(() => this.studio.routine(this.id).pipe(catchError(() => EMPTY))),
        takeUntilDestroyed(this.destroyRef),
      )
      .subscribe((routine) => this.showProcessing(routine));
  }

  private show(routine: StudioRoutine): void {
    this.form.setValue({
      name: routine.name,
      difficulty: routine.difficulty,
      style: routine.style,
      description: routine.description,
    });
    this.rights.set(routine.music_rights);
    this.chosen.set(new Set(routine.courses));
    this.showProcessing(routine);
  }

  /** A check while processing: the instructor is usually filling in the
   *  data meanwhile, so the form, the courses and the rights are kept. */
  private showProcessing(routine: StudioRoutine): void {
    const wasReady = this.ready();
    this.routine.set(routine);
    // A melody has no pose to report on.
    if (
      routine.kind !== 'SING' &&
      routine.processing?.status === 'READY' &&
      (!wasReady || !this.quality())
    ) {
      this.studio.quality(routine.id).subscribe({
        next: (report) => this.quality.set(report),
        error: () => this.quality.set(null),
      });
    } else if (routine.processing?.status !== 'READY') {
      this.quality.set(null);
    }
  }

  problemLabel(kind: string): string {
    return PROBLEM_LABELS[kind] ?? 'no se puede medir';
  }

  toggle(course: number, checked: boolean): void {
    const next = new Set(this.chosen());
    if (checked) next.add(course);
    else next.delete(course);
    this.chosen.set(next);
  }

  private run(action: string, call: () => Observable<StudioRoutine>): void {
    this.busy.set(true);
    this.error.set('');
    this.message.set('');
    call().subscribe({
      next: (routine) => {
        this.busy.set(false);
        this.show(routine);
        this.message.set(action);
      },
      error: (error: unknown) => {
        this.busy.set(false);
        this.error.set(apiError(error, 'No se pudo guardar el cambio.'));
      },
    });
  }

  save(): void {
    this.run('Datos guardados.', () => this.studio.update(this.id, this.form.getRawValue()));
  }

  publish(): void {
    const rights = this.rights();
    if (!rights) return;
    this.run('Publicada: tus alumnos ya la ven en la app.', () =>
      this.studio.publish(this.id, [...this.chosen()], rights),
    );
  }

  unpublish(): void {
    this.run('Retirada: vuelve a ser un borrador.', () => this.studio.unpublish(this.id));
  }

  proposeForCatalog(): void {
    this.run('Propuesta enviada. El resultado de la revisión aparecerá aquí.', () =>
      this.studio.proposeForCatalog(this.id),
    );
  }

  leaveCatalog(): void {
    const pending = this.routine()?.catalog_review === 'PENDING';
    this.run(
      pending ? 'Propuesta retirada.' : 'Quitada del catálogo: sigue publicada en tus cursos.',
      () => this.studio.leaveCatalog(this.id),
    );
  }

  replace(event: Event): void {
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0];
    if (!file) return;
    this.busy.set(true);
    this.error.set('');
    this.progress.set(0);
    this.studio.replaceVideo(this.id, file).subscribe({
      next: (httpEvent) => {
        if (httpEvent.type === HttpEventType.UploadProgress && httpEvent.total) {
          this.progress.set(Math.round((100 * httpEvent.loaded) / httpEvent.total));
        } else if (httpEvent.type === HttpEventType.Response && httpEvent.body) {
          this.busy.set(false);
          this.progress.set(null);
          this.quality.set(null);
          this.show(httpEvent.body);
          this.message.set(
            'Archivo reemplazado: se está procesando y la rutina volvió a borrador.',
          );
        }
      },
      error: (error: unknown) => {
        this.busy.set(false);
        this.progress.set(null);
        input.value = '';
        this.error.set(apiError(error, 'No se pudo subir el archivo.'));
      },
    });
  }

  remove(): void {
    if (!confirm('¿Borrar esta rutina para siempre?')) return;
    this.busy.set(true);
    this.studio.remove(this.id).subscribe({
      next: () => this.router.navigateByUrl('/estudio'),
      error: (error: unknown) => {
        this.busy.set(false);
        this.error.set(apiError(error, 'No se pudo borrar.'));
      },
    });
  }
}
