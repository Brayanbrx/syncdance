import { HttpClient } from '@angular/common/http';
import { ChangeDetectionStrategy, Component, OnInit, inject, signal } from '@angular/core';
import { FormBuilder, ReactiveFormsModule, Validators } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';

import { environment } from '../../../environments/environment';
import { apiError } from '../../core/api.models';
import { AuthService } from '../../core/auth/auth.service';

@Component({
  selector: 'sd-panel-login',
  imports: [ReactiveFormsModule, RouterLink],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <main class="login">
      <a class="wordmark" routerLink="/">SyncDance</a>
      <h1>Panel de administración</h1>
      <p class="muted">Para quienes administran la plataforma.</p>

      @if (expired) {
        <p class="notice" role="status">Tu sesión terminó. Vuelve a ingresar.</p>
      }
      @if (noAccess()) {
        <p class="alert" role="alert">
          Esta cuenta no administra la plataforma. Si eres instructor, gestiona tus cursos en el
          <a href="/admin/">panel del instructor</a>.
        </p>
      }

      @if (devSeed()) {
        <div class="dev" role="note">
          <p>
            Servidor de desarrollo: entra con la semilla, usuario <strong>admin</strong> y
            contraseña <strong>admin</strong>.
          </p>
          <button class="button button--quiet button--small" type="button" (click)="useSeed()">
            Usar la cuenta de desarrollo
          </button>
        </div>
      }

      <form [formGroup]="form" (ngSubmit)="submit()">
        <label>
          Usuario
          <input formControlName="username" autocomplete="username" required />
        </label>
        <label>
          Contraseña
          <input formControlName="password" type="password" autocomplete="current-password" />
        </label>
        @if (error()) {
          <p class="alert" role="alert">{{ error() }}</p>
        }
        <button class="button" type="submit" [disabled]="form.invalid || busy()">
          {{ busy() ? 'Ingresando…' : 'Ingresar' }}
        </button>
      </form>
      <p class="forgot"><a routerLink="/cuenta/recuperar">¿Olvidaste tu contraseña?</a></p>
    </main>
  `,
  styles: `
    .login {
      width: min(100% - 2rem, 26rem);
      margin: 12vh auto 4rem;
    }
    .wordmark {
      font: 800 var(--step-2) / 1 var(--display);
      font-stretch: 80%;
      text-decoration: none;
    }
    h1 {
      font-size: var(--step-3);
      margin-top: 2rem;
    }
    .muted {
      color: var(--muted);
    }
    form {
      display: grid;
      gap: 1rem;
      margin-top: 1.5rem;
    }
    .button {
      justify-self: start;
    }
    .dev {
      border: 1.5px dashed var(--ink-soft);
      border-radius: 12px;
      padding: 0.9rem 1rem;
      margin-top: 1rem;
    }
    .dev p {
      margin: 0 0 0.6rem;
    }
    .forgot {
      margin-top: 1.25rem;
    }
  `,
})
export class PanelLoginPage implements OnInit {
  private readonly http = inject(HttpClient);
  private readonly auth = inject(AuthService);
  private readonly router = inject(Router);
  private readonly params = inject(ActivatedRoute).snapshot.queryParamMap;

  readonly expired = this.params.has('expirada');
  readonly noAccess = signal(this.params.has('sinacceso'));
  readonly busy = signal(false);
  /** The backend runs with DEBUG: the admin / admin seed exists. */
  readonly devSeed = signal(false);
  readonly error = signal('');
  readonly form = inject(FormBuilder).nonNullable.group({
    username: ['', Validators.required],
    password: ['', Validators.required],
  });

  ngOnInit(): void {
    this.http.get<{ environment?: string }>(`${environment.apiBaseUrl}/health/`).subscribe({
      next: (health) => this.devSeed.set(health.environment === 'development'),
      error: () => undefined,
    });
  }

  useSeed(): void {
    this.form.setValue({ username: 'admin', password: 'admin' });
  }

  submit(): void {
    const { username, password } = this.form.getRawValue();
    this.busy.set(true);
    this.error.set('');
    this.noAccess.set(false);
    this.auth.login(username, password).subscribe({
      next: (me) => {
        this.busy.set(false);
        if (me.is_platform_admin) {
          this.router.navigateByUrl('/panel');
        } else {
          this.auth.logout();
          this.noAccess.set(true);
        }
      },
      error: (error: unknown) => {
        this.busy.set(false);
        const status = (error as { status?: number }).status;
        this.error.set(
          status === 401
            ? 'Usuario o contraseña incorrectos.'
            : status === 429
              ? 'Demasiados intentos. Espera un minuto y vuelve a intentar.'
              : apiError(error, 'No se pudo conectar con el servidor.'),
        );
      },
    });
  }
}
