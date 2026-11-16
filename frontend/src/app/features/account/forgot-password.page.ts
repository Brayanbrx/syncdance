import { HttpClient } from '@angular/common/http';
import { ChangeDetectionStrategy, Component, inject, signal } from '@angular/core';
import { FormBuilder, ReactiveFormsModule, Validators } from '@angular/forms';
import { RouterLink } from '@angular/router';

import { environment } from '../../../environments/environment';
import { apiError } from '../../core/api.models';
import { AccountFrameComponent } from './account-frame.component';

@Component({
  selector: 'sd-forgot-password',
  imports: [ReactiveFormsModule, RouterLink, AccountFrameComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <sd-account-frame>
      <h1>Recuperar tu contraseña</h1>
      @if (sent()) {
        <p class="notice" role="status">{{ sent() }}</p>
        <p class="muted">
          El enlace vale por 2 horas y sirve una sola vez. Si no llega en unos minutos, revisa la
          carpeta de spam.
        </p>
        <a routerLink="/">Volver al inicio</a>
      } @else {
        <p class="muted">
          Escribe el correo de tu cuenta de SyncDance y te enviaremos un enlace para elegir una
          contraseña nueva. El correo también te recuerda tu nombre de usuario.
        </p>
        <form [formGroup]="form" (ngSubmit)="submit()">
          <label>
            Correo
            <input formControlName="email" type="email" autocomplete="email" required />
          </label>
          @if (error()) {
            <p class="alert" role="alert">{{ error() }}</p>
          }
          <button class="button" type="submit" [disabled]="form.invalid || busy()">
            {{ busy() ? 'Enviando…' : 'Enviar enlace' }}
          </button>
        </form>
      }
    </sd-account-frame>
  `,
  styles: `
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
  `,
})
export class ForgotPasswordPage {
  private readonly http = inject(HttpClient);

  readonly form = inject(FormBuilder).nonNullable.group({
    email: ['', [Validators.required, Validators.email]],
  });
  readonly busy = signal(false);
  readonly sent = signal('');
  readonly error = signal('');

  submit(): void {
    this.busy.set(true);
    this.error.set('');
    this.http
      .post<{ detail: string }>(
        `${environment.apiBaseUrl}/auth/password-reset/`,
        this.form.getRawValue(),
      )
      .subscribe({
        next: (answer) => {
          this.busy.set(false);
          this.sent.set(answer.detail);
        },
        error: (error: unknown) => {
          this.busy.set(false);
          this.error.set(
            (error as { status?: number }).status === 429
              ? 'Ya se pidieron varios enlaces para este correo. Espera una hora y vuelve a intentar.'
              : apiError(error, 'No se pudo conectar con el servidor.'),
          );
        },
      });
  }
}
