import { ChangeDetectionStrategy, Component, inject } from '@angular/core';
import { Router, RouterLink, RouterLinkActive, RouterOutlet } from '@angular/router';

import { AuthService } from '../../core/auth/auth.service';

/** The instructor's studio: their routines, uploads and publication. */
@Component({
  selector: 'sd-studio-shell',
  imports: [RouterLink, RouterLinkActive, RouterOutlet],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <header class="bar">
      <a class="wordmark" routerLink="/estudio">SyncDance <span>estudio</span></a>
      <nav aria-label="Estudio">
        <a routerLink="/estudio" [routerLinkActiveOptions]="{ exact: true }" routerLinkActive="on"
          >Mis rutinas</a
        >
        <a routerLink="/estudio/nueva" routerLinkActive="on">Subir rutina</a>
        <a routerLink="/estudio/cursos" routerLinkActive="on">Mis cursos</a>
        <a href="/admin/coaching/course/">Administrar cursos</a>
        <a routerLink="/estudio/guia" routerLinkActive="on">Guía</a>
        @if (auth.isPlatformAdmin()) {
          <a routerLink="/panel">Panel</a>
        }
      </nav>
      <div class="who">
        <span>{{ auth.me()?.username }}</span>
        <button class="button button--quiet button--small" type="button" (click)="logout()">
          Salir
        </button>
      </div>
    </header>
    <main class="content">
      <router-outlet />
    </main>
  `,
  styles: `
    .bar {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      gap: 1rem 2rem;
      padding: 0.9rem clamp(1rem, 3vw, 2.5rem);
      background: var(--stage);
      color: #dfe3fb;
    }
    .wordmark {
      font: 800 var(--step-1) / 1 var(--display);
      font-stretch: 80%;
      color: var(--paper);
      text-decoration: none;
    }
    .wordmark span {
      color: var(--left);
    }
    nav {
      display: flex;
      flex-wrap: wrap;
      gap: 0.25rem;
    }
    nav a {
      padding: 0.45rem 0.75rem;
      border-radius: 8px;
      text-decoration: none;
      font-weight: 700;
    }
    nav a:hover {
      background: rgba(255, 255, 255, 0.08);
    }
    nav a.on {
      background: var(--paper);
      color: var(--ink);
    }
    .who {
      margin-left: auto;
      display: flex;
      align-items: center;
      gap: 0.75rem;
      font-size: var(--step--1);
    }
    .who .button {
      color: var(--paper);
      border-color: #8c91c4;
    }
    .content {
      width: min(100% - 2rem, 64rem);
      margin: 2rem auto 4rem;
    }
  `,
})
export class StudioShellComponent {
  readonly auth = inject(AuthService);
  private readonly router = inject(Router);

  logout(): void {
    this.auth.logout();
    this.router.navigateByUrl('/ingresar');
  }
}
