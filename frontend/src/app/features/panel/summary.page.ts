import { DatePipe } from '@angular/common';
import { ChangeDetectionStrategy, Component, OnInit, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';

import { PlatformSummary, apiError, formatSize } from '../../core/api.models';
import { PanelService } from '../../core/panel.service';

@Component({
  selector: 'sd-summary',
  imports: [DatePipe, RouterLink],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="page-head">
      <div>
        <h1>Resumen</h1>
        <p>Cifras de toda la plataforma. Las prácticas cuentan cuando el teléfono las envía.</p>
      </div>
    </div>

    @if (error()) {
      <p class="alert" role="alert">{{ error() }}</p>
    }

    @if (data(); as s) {
      <div class="groups">
        <section>
          <h2>Personas</h2>
          <dl>
            <div>
              <dt>Estudiantes</dt>
              <dd>{{ s.users.students }}</dd>
            </div>
            <div>
              <dt>Instructores</dt>
              <dd>{{ s.users.instructors }}</dd>
            </div>
            <div>
              <dt>Administradores</dt>
              <dd>{{ s.users.admins }}</dd>
            </div>
            <div>
              <dt>Cuentas nuevas en 7 días</dt>
              <dd>{{ s.users.joined_last_7_days }}</dd>
            </div>
            <div>
              <dt>Cuentas desactivadas</dt>
              <dd>{{ s.users.inactive }}</dd>
            </div>
          </dl>
          <a routerLink="/panel/usuarios">Gestionar usuarios</a>
        </section>

        <section>
          <h2>Práctica</h2>
          <dl>
            <div>
              <dt>Prácticas en 7 días</dt>
              <dd>{{ s.practice.sessions_last_7_days }}</dd>
            </div>
            <div>
              <dt>Alumnos que practicaron en 7 días</dt>
              <dd>{{ s.practice.active_students_last_7_days }}</dd>
            </div>
            <div>
              <dt>Prácticas en total</dt>
              <dd>{{ s.practice.sessions }}</dd>
            </div>
            <div>
              <dt>De ellas, partidas del juego</dt>
              <dd>{{ s.practice.games }}</dd>
            </div>
          </dl>
        </section>

        <section>
          <h2>Catálogo</h2>
          <dl>
            <div>
              <dt>Rutinas activas</dt>
              <dd>{{ s.catalog.active_routines }} de {{ s.catalog.routines }}</dd>
            </div>
            <div>
              <dt>Propuestas por revisar</dt>
              <dd>{{ s.catalog.proposals_pending }}</dd>
            </div>
            <div>
              <dt>Referencias listas</dt>
              <dd>{{ s.catalog.references_ready }}</dd>
            </div>
            <div>
              <dt>Referencias en proceso</dt>
              <dd>{{ s.catalog.references_processing }}</dd>
            </div>
            <div>
              <dt>Referencias con error</dt>
              <dd [class.bad]="s.catalog.references_failed > 0">
                {{ s.catalog.references_failed }}
              </dd>
            </div>
          </dl>
          <a routerLink="/panel/rutinas">Ver rutinas</a>
          @if (s.catalog.proposals_pending) {
            <a routerLink="/panel/revision">Revisar propuestas</a>
          }
        </section>

        <section>
          <h2>Cursos</h2>
          <dl>
            <div>
              <dt>Cursos</dt>
              <dd>{{ s.courses.courses }}</dd>
            </div>
            <div>
              <dt>Alumnos inscritos</dt>
              <dd>{{ s.courses.enrollments }}</dd>
            </div>
            <div>
              <dt>Tareas asignadas</dt>
              <dd>{{ s.courses.assignments }}</dd>
            </div>
          </dl>
          <a routerLink="/panel/cursos">Ver cursos</a>
        </section>
      </div>

      <section class="release">
        <h2>App Android</h2>
        @if (s.latest_release; as r) {
          <p>
            En la landing se descarga la versión <strong>{{ r.version_name }}</strong> ({{
              size(r.size_bytes)
            }}), publicada el {{ r.published_at | date: 'd MMM y' }}.
          </p>
        } @else {
          <p>Todavía no hay una versión publicada: la landing muestra la descarga desactivada.</p>
        }
        <a class="button button--small" routerLink="/panel/app">Gestionar versiones</a>
      </section>
    } @else if (!error()) {
      <p role="status">Cargando…</p>
    }
  `,
  styles: `
    .groups {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(15rem, 1fr));
      gap: 1.5rem;
    }
    section {
      background: var(--paper);
      border: 1px solid var(--line);
      border-radius: 12px;
      padding: 1.25rem;
    }
    h2 {
      font-size: var(--step-1);
    }
    dl {
      margin: 0 0 1rem;
    }
    dl div {
      display: flex;
      justify-content: space-between;
      gap: 1rem;
      padding: 0.4rem 0;
      border-bottom: 1px dashed var(--line);
    }
    dt {
      color: var(--muted);
    }
    dd {
      margin: 0;
      font: 700 var(--step-1) / 1.2 var(--display);
      font-variant-numeric: tabular-nums;
    }
    dd.bad {
      color: var(--danger);
    }
    a:not(.button) {
      font-size: var(--step--1);
    }
    a:not(.button) + a:not(.button) {
      margin-left: 1rem;
    }
    .release {
      margin-top: 1.5rem;
    }
  `,
})
export class SummaryPage implements OnInit {
  private readonly panel = inject(PanelService);
  readonly data = signal<PlatformSummary | null>(null);
  readonly error = signal('');
  readonly size = formatSize;

  ngOnInit(): void {
    this.panel.summary().subscribe({
      next: (summary) => this.data.set(summary),
      error: (error: unknown) => this.error.set(apiError(error, 'No se pudo cargar el resumen.')),
    });
  }
}
