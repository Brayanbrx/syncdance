import { DatePipe } from '@angular/common';
import { ChangeDetectionStrategy, Component, OnInit, inject, signal } from '@angular/core';

import {
  CatalogProposal,
  DIFFICULTY_LABELS,
  MUSIC_RIGHTS_LABELS,
  apiError,
  clock,
  percent,
} from '../../core/api.models';
import { PanelService } from '../../core/panel.service';
import { RoutinePreviewComponent } from '../../shared/routine-preview.component';

/** Routines instructors proposed for the free catalog: watch, approve or reject. */
@Component({
  selector: 'sd-proposals',
  imports: [DatePipe, RoutinePreviewComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="page-head">
      <div>
        <h1>Revisión del catálogo</h1>
        <p>
          Rutinas que los instructores proponen para el catálogo gratuito. Al aprobarla, la ven
          todos los alumnos de la app; al rechazarla, el instructor lee tu motivo en su estudio.
        </p>
      </div>
    </div>

    @if (notice()) {
      <p class="notice" role="status">{{ notice() }}</p>
    }
    @if (error()) {
      <p class="alert" role="alert">{{ error() }}</p>
    }

    @if (loaded() && !proposals().length) {
      <div class="empty">
        <h2>No hay propuestas pendientes</h2>
        <p>Cuando un instructor proponga una rutina, aparecerá aquí.</p>
      </div>
    }

    <ul class="queue">
      @for (p of proposals(); track p.id) {
        <li>
          @if (p.processing; as processing) {
            <sd-routine-preview
              [routine]="p.id"
              [version]="processing.version"
              [poster]="processing.poster"
            />
          }
          <div class="info">
            <h2>{{ p.name }}</h2>
            <p class="muted">
              {{ levels[p.difficulty] }}{{ p.style ? ', ' + p.style : '' }} —
              {{ clock(p.duration_ms) }} — de {{ p.instructor }}
            </p>
            @if (p.description) {
              <p>{{ p.description }}</p>
            }
            <dl class="facts">
              <div>
                <dt>Una sola persona visible</dt>
                <dd>{{ percent(p.single_person) }}</dd>
              </div>
              <div>
                <dt>Música</dt>
                <dd>{{ p.music_rights ? rights[p.music_rights] : '—' }}</dd>
              </div>
              <div>
                <dt>Publicada en</dt>
                <dd>{{ p.courses }} {{ p.courses === 1 ? 'curso' : 'cursos' }}</dd>
              </div>
              <div>
                <dt>Propuesta el</dt>
                <dd>{{ p.catalog_requested_at | date: 'd MMM y' }}</dd>
              </div>
            </dl>
            @if (rejecting() === p.id) {
              <label>
                Motivo para el instructor
                <textarea
                  rows="3"
                  maxlength="1000"
                  [value]="note()"
                  (input)="note.set($any($event.target).value)"
                ></textarea>
              </label>
              <div class="actions">
                <button
                  class="button button--danger"
                  type="button"
                  [disabled]="!note().trim() || busy()"
                  (click)="reject(p)"
                >
                  Rechazar
                </button>
                <button class="button button--quiet" type="button" (click)="rejecting.set(null)">
                  Cancelar
                </button>
              </div>
            } @else {
              <div class="actions">
                <button class="button" type="button" [disabled]="busy()" (click)="approve(p)">
                  Aprobar
                </button>
                <button
                  class="button button--quiet"
                  type="button"
                  [disabled]="busy()"
                  (click)="startRejecting(p)"
                >
                  Rechazar…
                </button>
              </div>
            }
          </div>
        </li>
      }
    </ul>
  `,
  styles: `
    .queue {
      list-style: none;
      padding: 0;
      margin: 1.5rem 0 0;
      display: grid;
      gap: 1rem;
    }
    li {
      display: grid;
      grid-template-columns: minmax(0, 18rem) minmax(0, 1fr);
      gap: 1.5rem;
      padding: 1.25rem;
      background: var(--paper);
      border: 1px solid var(--line);
      border-radius: 14px;
    }
    h2 {
      font-size: var(--step-1);
      margin: 0 0 0.25rem;
    }
    .muted {
      color: var(--muted);
    }
    .facts {
      display: flex;
      flex-wrap: wrap;
      gap: 0.5rem 2rem;
      margin: 1rem 0;

      dt {
        font-size: var(--step--1);
        color: var(--muted);
      }
      dd {
        margin: 0;
        font-weight: 700;
      }
    }
    label {
      display: grid;
      gap: 0.4rem;
      margin-bottom: 0.75rem;
    }
    textarea {
      font: inherit;
      padding: 0.6rem 0.75rem;
      border: 1.5px solid var(--line);
      border-radius: 10px;
    }
    .actions {
      display: flex;
      flex-wrap: wrap;
      gap: 0.75rem;
    }
    .empty {
      margin-top: 2rem;
      padding: 2rem;
      border: 1.5px dashed var(--line);
      border-radius: 16px;
      max-width: 36rem;
    }
    @media (max-width: 48rem) {
      li {
        grid-template-columns: 1fr;
      }
    }
  `,
})
export class ProposalsPage implements OnInit {
  private readonly panel = inject(PanelService);

  readonly levels = DIFFICULTY_LABELS;
  readonly rights = MUSIC_RIGHTS_LABELS;
  readonly clock = clock;
  readonly percent = percent;
  readonly proposals = signal<CatalogProposal[]>([]);
  readonly loaded = signal(false);
  readonly busy = signal(false);
  readonly rejecting = signal<number | null>(null);
  readonly note = signal('');
  readonly notice = signal('');
  readonly error = signal('');

  ngOnInit(): void {
    this.load();
  }

  private load(): void {
    this.panel.proposals().subscribe({
      next: (proposals) => {
        this.proposals.set(proposals);
        this.loaded.set(true);
      },
      error: (error: unknown) =>
        this.error.set(apiError(error, 'No se pudieron cargar las propuestas.')),
    });
  }

  startRejecting(proposal: CatalogProposal): void {
    this.note.set('');
    this.rejecting.set(proposal.id);
  }

  approve(proposal: CatalogProposal): void {
    this.answer(
      proposal,
      this.panel.approveProposal(proposal.id),
      `«${proposal.name}» ya está en el catálogo.`,
    );
  }

  reject(proposal: CatalogProposal): void {
    this.answer(
      proposal,
      this.panel.rejectProposal(proposal.id, this.note().trim()),
      `«${proposal.name}» no se aceptó. ${proposal.instructor} verá tu motivo en su estudio.`,
    );
  }

  private answer(
    proposal: CatalogProposal,
    call: ReturnType<PanelService['approveProposal']>,
    done: string,
  ): void {
    this.busy.set(true);
    this.notice.set('');
    this.error.set('');
    call.subscribe({
      next: () => {
        this.busy.set(false);
        this.rejecting.set(null);
        this.proposals.update((list) => list.filter((p) => p.id !== proposal.id));
        this.notice.set(done);
      },
      error: (error: unknown) => {
        this.busy.set(false);
        // Answered by someone else or withdrawn meanwhile: show the queue as it is.
        this.error.set(apiError(error, 'No se pudo guardar la respuesta.'));
        this.load();
      },
    });
  }
}
