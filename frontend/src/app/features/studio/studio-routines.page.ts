import { DatePipe } from '@angular/common';
import { ChangeDetectionStrategy, Component, OnInit, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';

import {
  DIFFICULTY_LABELS,
  StudioRoutine,
  apiError,
  clock,
  routineState,
} from '../../core/api.models';
import { StudioService } from '../../core/studio.service';

@Component({
  selector: 'sd-studio-routines',
  imports: [DatePipe, RouterLink],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="page-head">
      <div>
        <h1>Mis rutinas</h1>
        <p>
          Sube el video de una coreografía, revisa cómo quedó y publícala en tus cursos. Solo la ven
          tus alumnos.
        </p>
      </div>
      <a class="button" routerLink="/estudio/nueva">Subir rutina</a>
    </div>

    @if (error()) {
      <p class="alert" role="alert">{{ error() }}</p>
    }

    @if (loaded() && routines().length === 0) {
      <div class="empty">
        <h2>Todavía no subiste rutinas</h2>
        <p>
          Graba la coreografía de frente, de cuerpo entero y sin otras personas en cuadro. Un minuto
          alcanza para empezar.
        </p>
        <a class="button" routerLink="/estudio/nueva">Subir mi primera rutina</a>
      </div>
    } @else {
      <ul class="list">
        @for (routine of routines(); track routine.id) {
          <li>
            <a [routerLink]="['/estudio/rutinas', routine.id]">
              <strong>{{ routine.name }}</strong>
              <span class="muted">
                {{ levels[routine.difficulty] }}{{ routine.style ? ', ' + routine.style : '' }}
                @if (routine.duration_ms) {
                  — {{ clock(routine.duration_ms) }}
                }
              </span>
            </a>
            <span class="status status--{{ state(routine).tone }}">{{ state(routine).label }}</span>
            <span class="muted when">{{ routine.updated_at | date: 'd MMM y' }}</span>
          </li>
        }
      </ul>
    }
  `,
  styles: `
    .list {
      list-style: none;
      padding: 0;
      margin: 1.5rem 0 0;
      display: grid;
      gap: 0.5rem;
    }
    li {
      display: grid;
      grid-template-columns: minmax(0, 1fr) auto auto;
      align-items: center;
      gap: 1rem;
      padding: 0.9rem 1.1rem;
      background: var(--paper);
      border: 1px solid var(--line);
      border-radius: 12px;
    }
    li a {
      display: grid;
      gap: 0.15rem;
      text-decoration: none;
      min-width: 0;
    }
    .muted {
      color: var(--muted);
      font-size: var(--step--1);
    }
    .status--neutral {
      background: var(--floor);
      color: var(--ink-soft);
    }
    .empty {
      margin-top: 2rem;
      padding: 2rem;
      border: 1.5px dashed var(--line);
      border-radius: 16px;
      max-width: 36rem;
    }
    @media (max-width: 40rem) {
      li {
        grid-template-columns: 1fr;
        gap: 0.4rem;
      }
    }
  `,
})
export class StudioRoutinesPage implements OnInit {
  private readonly studio = inject(StudioService);

  readonly levels = DIFFICULTY_LABELS;
  readonly state = routineState;
  readonly clock = clock;
  readonly routines = signal<StudioRoutine[]>([]);
  readonly loaded = signal(false);
  readonly error = signal('');

  ngOnInit(): void {
    this.studio.routines().subscribe({
      next: (routines) => {
        this.routines.set(routines);
        this.loaded.set(true);
      },
      error: (error: unknown) =>
        this.error.set(apiError(error, 'No se pudieron cargar tus rutinas.')),
    });
  }
}
