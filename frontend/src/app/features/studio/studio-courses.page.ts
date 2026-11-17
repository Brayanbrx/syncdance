import { ChangeDetectionStrategy, Component, OnInit, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';

import { StudioCourse, apiError } from '../../core/api.models';
import { StudioService } from '../../core/studio.service';

@Component({
  selector: 'sd-studio-courses',
  imports: [RouterLink],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="page-head">
      <div>
        <h1>Mis cursos</h1>
        <p>
          Mira en qué pasos les cuesta más a tus alumnos y califica sus prácticas. Los cursos se
          crean en <a href="/admin/coaching/course/add/">Administrar cursos</a>.
        </p>
      </div>
    </div>

    @if (error()) {
      <p class="alert" role="alert">{{ error() }}</p>
    }

    @if (loaded() && !courses().length) {
      <p>Todavía no tienes cursos.</p>
    }
    <ul class="list">
      @for (course of courses(); track course.id) {
        <li>
          <a [routerLink]="['/estudio/cursos', course.id]">
            <strong>{{ course.name }}</strong>
            <span class="muted">
              {{ course.students }} {{ course.students === 1 ? 'alumno' : 'alumnos' }} · código
              {{ course.join_code }}
            </span>
          </a>
        </li>
      }
    </ul>
  `,
  styles: `
    .list {
      list-style: none;
      padding: 0;
      margin: 1.5rem 0 0;
      display: grid;
      gap: 0.5rem;
    }
    li a {
      display: grid;
      gap: 0.15rem;
      padding: 0.9rem 1.1rem;
      background: var(--paper);
      border: 1px solid var(--line);
      border-radius: 12px;
      text-decoration: none;
    }
    .muted {
      color: var(--muted);
      font-size: var(--step--1);
    }
  `,
})
export class StudioCoursesPage implements OnInit {
  private readonly studio = inject(StudioService);
  readonly courses = signal<StudioCourse[]>([]);
  readonly loaded = signal(false);
  readonly error = signal('');

  ngOnInit(): void {
    this.studio.courses().subscribe({
      next: (courses) => {
        this.courses.set(courses);
        this.loaded.set(true);
      },
      error: (error: unknown) => this.error.set(apiError(error, 'No se pudieron cargar.')),
    });
  }
}
