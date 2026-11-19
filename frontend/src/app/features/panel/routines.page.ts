import { ChangeDetectionStrategy, Component, OnInit, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';

import { PanelRoutine, ReferenceStatus, apiError } from '../../core/api.models';
import { PanelService } from '../../core/panel.service';
import { PagerComponent } from '../../shared/pager.component';

const LEVELS = { BEGINNER: 'Principiante', INTERMEDIATE: 'Intermedio', ADVANCED: 'Avanzado' };

const REFERENCE: Record<ReferenceStatus, { label: string; tone: string }> = {
  READY: { label: 'Lista', tone: 'ok' },
  PENDING: { label: 'En cola', tone: 'warn' },
  PROCESSING: { label: 'Procesando', tone: 'warn' },
  FAILED: { label: 'Con error', tone: 'danger' },
};

@Component({
  selector: 'sd-routines',
  imports: [PagerComponent, RouterLink],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="page-head">
      <div>
        <h1>Rutinas</h1>
        <p>
          Una rutina oculta deja de aparecer en la app, en el catálogo y en los cursos; las
          prácticas guardadas se conservan. Las que proponen los instructores se aprueban en
          <a routerLink="/panel/revision">Revisión del catálogo</a>. Las tuyas se suben, se marcan
          con compás y pasos y se publican en el catálogo desde el
          <a routerLink="/estudio">estudio</a>.
        </p>
      </div>
      <a class="button" routerLink="/estudio/nueva">Subir rutina al catálogo</a>
    </div>

    @if (error()) {
      <p class="alert" role="alert">{{ error() }}</p>
    }

    <div class="table-scroll">
      <table class="table">
        <thead>
          <tr>
            <th>Rutina</th>
            <th>Nivel</th>
            <th>Instructor</th>
            <th>Referencia</th>
            <th class="num">Prácticas</th>
            <th>Dónde</th>
            <th>Activa</th>
            <th><span class="visually-hidden">Editar</span></th>
          </tr>
        </thead>
        <tbody>
          @for (routine of routines(); track routine.id) {
            <tr>
              <td>
                <strong>{{ routine.name }}</strong>
                @if (routine.style) {
                  <br /><span class="muted">{{ routine.style }}</span>
                }
              </td>
              <td>
                {{ levels[routine.difficulty] }}
                @if (routine.curriculum_position !== null) {
                  <br /><span class="muted">Paso {{ routine.curriculum_position }} del camino</span>
                }
              </td>
              <td>{{ routine.instructor }}</td>
              <td>
                @if (routine.reference_status; as status) {
                  <span [class]="'status status--' + reference[status].tone">
                    {{ reference[status].label }}
                  </span>
                  <span class="muted"> v{{ routine.reference_version }}</span>
                } @else {
                  <span class="status">Sin referencia</span>
                }
              </td>
              <td class="num">{{ routine.sessions }}</td>
              <td>{{ where(routine) }}</td>
              <td>
                <label class="toggle">
                  <input
                    type="checkbox"
                    [checked]="routine.is_active"
                    (change)="toggle(routine)"
                    [attr.aria-label]="'Mostrar ' + routine.name + ' en la app'"
                  />
                  {{ routine.is_active ? 'Visible' : 'Oculta' }}
                </label>
              </td>
              <td>
                <a [href]="'/admin/routines/routine/' + routine.id + '/change/'">Editar</a>
              </td>
            </tr>
          } @empty {
            <tr>
              <td colspan="8">
                No hay rutinas. Instala el catálogo por defecto con
                <code>load_default_catalog</code> y <code>generate_standard_catalog</code>.
              </td>
            </tr>
          }
        </tbody>
      </table>
    </div>
    <sd-pager [count]="count()" [page]="page()" (pageChange)="load($event)" />
  `,
  styles: `
    .muted {
      color: var(--muted);
    }
    .toggle {
      display: flex;
      align-items: center;
      gap: 0.4rem;
      font-weight: 400;
    }
  `,
})
export class RoutinesPage implements OnInit {
  private readonly panel = inject(PanelService);
  readonly levels = LEVELS;
  readonly reference = REFERENCE;
  readonly routines = signal<PanelRoutine[]>([]);
  readonly count = signal(0);
  readonly page = signal(1);
  readonly error = signal('');

  ngOnInit(): void {
    this.load(1);
  }

  load(page: number): void {
    this.page.set(page);
    this.panel.routines(page).subscribe({
      next: (result) => {
        this.routines.set(result.results);
        this.count.set(result.count);
      },
      error: (error: unknown) => this.error.set(apiError(error, 'No se pudieron cargar.')),
    });
  }

  /** Who can see it: everyone (catalog), the instructor's courses, or nobody yet. */
  where(routine: PanelRoutine): string {
    if (!routine.published_at) return 'Borrador';
    if (routine.visibility === 'CATALOG') return 'Catálogo';
    return routine.catalog_review === 'PENDING' ? 'Cursos (en revisión)' : 'Cursos';
  }

  toggle(routine: PanelRoutine): void {
    this.error.set('');
    this.panel.setRoutineActive(routine.id, !routine.is_active).subscribe({
      next: (saved) =>
        this.routines.update((list) => list.map((r) => (r.id === saved.id ? saved : r))),
      error: (error: unknown) => {
        this.error.set(apiError(error, 'No se pudo cambiar la rutina.'));
        this.load(this.page());
      },
    });
  }
}
