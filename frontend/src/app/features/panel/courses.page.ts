import { DatePipe } from '@angular/common';
import { ChangeDetectionStrategy, Component, OnInit, inject, signal } from '@angular/core';

import { PanelCourse, apiError } from '../../core/api.models';
import { PanelService } from '../../core/panel.service';
import { PagerComponent } from '../../shared/pager.component';

@Component({
  selector: 'sd-courses',
  imports: [DatePipe, PagerComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="page-head">
      <div>
        <h1>Cursos</h1>
        <p>
          Cada instructor crea y gestiona sus cursos en su panel. Aquí se ven todos, con su código
          para unirse.
        </p>
      </div>
    </div>

    @if (error()) {
      <p class="alert" role="alert">{{ error() }}</p>
    }

    <div class="table-scroll">
      <table class="table">
        <thead>
          <tr>
            <th>Curso</th>
            <th>Instructor</th>
            <th>Código</th>
            <th>Inscripciones</th>
            <th class="num">Alumnos</th>
            <th class="num">Tareas</th>
            <th>Creado</th>
            <th><span class="visually-hidden">Acciones</span></th>
          </tr>
        </thead>
        <tbody>
          @for (course of courses(); track course.id) {
            <tr>
              <td>
                <strong>{{ course.name }}</strong>
              </td>
              <td>{{ course.instructor }}</td>
              <td>
                <code>{{ course.join_code }}</code>
              </td>
              <td>
                <span [class]="course.accepts_students ? 'status status--ok' : 'status'">
                  {{ course.accepts_students ? 'Abiertas' : 'Cerradas' }}
                </span>
              </td>
              <td class="num">{{ course.students }}</td>
              <td class="num">{{ course.assignments }}</td>
              <td>{{ course.created_at | date: 'd MMM y' }}</td>
              <td class="links">
                <a [href]="'/admin/coaching/course/' + course.id + '/progreso/'">Progreso</a>
                <a [href]="'/admin/coaching/course/' + course.id + '/change/'">Editar</a>
              </td>
            </tr>
          } @empty {
            <tr>
              <td colspan="8">
                Todavía no hay cursos. Un instructor los crea desde su panel y comparte el código.
              </td>
            </tr>
          }
        </tbody>
      </table>
    </div>
    <sd-pager [count]="count()" [page]="page()" (pageChange)="load($event)" />
  `,
  styles: `
    .links {
      display: flex;
      gap: 0.75rem;
      white-space: nowrap;
    }
  `,
})
export class CoursesPage implements OnInit {
  private readonly panel = inject(PanelService);
  readonly courses = signal<PanelCourse[]>([]);
  readonly count = signal(0);
  readonly page = signal(1);
  readonly error = signal('');

  ngOnInit(): void {
    this.load(1);
  }

  load(page: number): void {
    this.page.set(page);
    this.panel.courses(page).subscribe({
      next: (result) => {
        this.courses.set(result.results);
        this.count.set(result.count);
      },
      error: (error: unknown) => this.error.set(apiError(error, 'No se pudieron cargar.')),
    });
  }
}
