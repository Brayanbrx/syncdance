import { ChangeDetectionStrategy, Component, inject } from '@angular/core';
import { Router, RouterLink, RouterLinkActive, RouterOutlet } from '@angular/router';

import { AuthService } from '../../core/auth/auth.service';

@Component({
  selector: 'sd-panel-shell',
  imports: [RouterLink, RouterLinkActive, RouterOutlet],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="shell">
      <aside class="side">
        <a class="wordmark" routerLink="/panel">SyncDance</a>
        <nav aria-label="Panel">
          <a routerLink="/panel" [routerLinkActiveOptions]="{ exact: true }" routerLinkActive="on"
            >Resumen</a
          >
          <a routerLink="/panel/usuarios" routerLinkActive="on">Usuarios</a>
          <a routerLink="/panel/rutinas" routerLinkActive="on">Rutinas</a>
          <a routerLink="/panel/revision" routerLinkActive="on">Revisión del catálogo</a>
          <a routerLink="/panel/piloto" routerLinkActive="on">Piloto</a>
          <a routerLink="/panel/cursos" routerLinkActive="on">Cursos</a>
          <a routerLink="/panel/app" routerLinkActive="on">App Android</a>
        </nav>
        <div class="extra">
          <a href="/admin/">Administración avanzada</a>
          <a routerLink="/">Ver la landing</a>
        </div>
        <div class="who">
          <span>{{ auth.me()?.username }}</span>
          <button class="button button--quiet button--small" type="button" (click)="logout()">
            Salir
          </button>
        </div>
      </aside>
      <main class="content">
        <router-outlet />
      </main>
    </div>
  `,
  styles: `
    .shell {
      display: grid;
      grid-template-columns: 15rem minmax(0, 1fr);
      min-height: 100vh;
    }
    .side {
      display: flex;
      flex-direction: column;
      gap: 2rem;
      padding: 1.5rem 1.25rem;
      background: var(--stage);
      color: #dfe3fb;
    }
    .wordmark {
      font: 800 var(--step-2) / 1 var(--display);
      font-stretch: 80%;
      color: var(--paper);
      text-decoration: none;
    }
    nav,
    .extra {
      display: grid;
      gap: 0.25rem;
    }
    nav a {
      padding: 0.55rem 0.75rem;
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
    .extra a {
      font-size: var(--step--1);
      padding: 0.25rem 0.75rem;
    }
    .who {
      margin-top: auto;
      display: grid;
      gap: 0.5rem;
      justify-items: start;
      font-size: var(--step--1);
    }
    .who .button {
      color: var(--paper);
      border-color: #8c91c4;
    }
    .who .button:hover {
      background: rgba(255, 255, 255, 0.08);
    }
    .content {
      padding: 2rem clamp(1rem, 3vw, 2.5rem) 4rem;
      min-width: 0;
    }
    @media (max-width: 48rem) {
      .shell {
        grid-template-columns: 1fr;
      }
      .side {
        gap: 1rem;
      }
      nav {
        grid-auto-flow: column;
        overflow-x: auto;
      }
      .who {
        margin-top: 0;
        grid-auto-flow: column;
        align-items: center;
      }
    }
  `,
})
export class PanelShellComponent {
  readonly auth = inject(AuthService);
  private readonly router = inject(Router);

  logout(): void {
    this.auth.logout();
    this.router.navigateByUrl('/ingresar');
  }
}
