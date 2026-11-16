import { HttpClient } from '@angular/common/http';
import { ChangeDetectionStrategy, Component, inject, signal } from '@angular/core';
import { FormBuilder, ReactiveFormsModule, Validators } from '@angular/forms';
import { ActivatedRoute, RouterLink } from '@angular/router';

import { environment } from '../../../environments/environment';
import { apiError } from '../../core/api.models';
import { AccountFrameComponent } from './account-frame.component';

/** Opened from the reset email: /cuenta/restablecer?uid=…&token=… */
@Component({
  selector: 'sd-reset-password',
  imports: [ReactiveFormsModule, RouterLink, AccountFrameComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <sd-account-frame>
      <h1>Elegir una contraseña nueva</h1>
      @if (!uid || !token) {
        <p class="alert" role="alert">
          Este enlace está incompleto. Ábrelo tal como llegó en el correo o pide uno nuevo.
        </p>
        <a routerLink="/cuenta/recuperar">Pedir un enlace nuevo</a>
      } @else if (done()) {
        <p class="notice" role="status">{{ done() }}</p>
        <p class="muted">
          Por seguridad se cerraron las sesiones abiertas: vuelve a ingresar en la app con tu
          contraseña nueva.
        </p>
        <a routerLink="/">Volver al inicio</a>
      } @else {
        <form [formGroup]="form" (ngSubmit)="submit()">
          <label>
            Contraseña nueva
            <input formControlName="password" type="password" autocomplete="new-password" />
            <span class="field-hint">Mínimo 8 caracteres, no solo números ni una común.</span>
          </label>
          <label>
            Repítela
            <input formControlName="repeat" type="password" autocomplete="new-password" />
          </label>
          @if (error()) {
            <p class="alert" role="alert">
              {{ error() }}
              @if (expired()) {
                <a routerLink="/cuenta/recuperar">Pedir un enlace nuevo</a>
              }
            </p>
          }
          <button class="button" type="submit" [disabled]="form.invalid || busy()">
            {{ busy() ? 'Guardando…' : 'Guardar contraseña' }}
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
    }
    .button {
      justify-self: start;
    }
  `,
})
export class ResetPasswordPage {
  private readonly http = inject(HttpClient);
  private readonly params = inject(ActivatedRoute).snapshot.queryParamMap;

  readonly uid = this.params.get('uid') ?? '';
  readonly token = this.params.get('token') ?? '';
  readonly form = inject(FormBuilder).nonNullable.group({
    password: ['', [Validators.required, Validators.minLength(8)]],
    repeat: ['', Validators.required],
  });
  readonly busy = signal(false);
  readonly done = signal('');
  readonly error = signal('');
  readonly expired = signal(false);

  submit(): void {
    const { password, repeat } = this.form.getRawValue();
    this.expired.set(false);
    if (password !== repeat) {
      this.error.set('Las dos contraseñas no coinciden.');
      return;
    }
    this.busy.set(true);
    this.error.set('');
    this.http
      .post<{ detail: string }>(`${environment.apiBaseUrl}/auth/password-reset/confirm/`, {
        uid: this.uid,
        token: this.token,
        new_password: password,
      })
      .subscribe({
        next: (answer) => {
          this.busy.set(false);
          this.done.set(answer.detail);
        },
        error: (error: unknown) => {
          this.busy.set(false);
          const body = (error as { error?: Record<string, unknown> }).error;
          this.expired.set(!!body && typeof body === 'object' && 'token' in body);
          this.error.set(apiError(error, 'No se pudo conectar con el servidor.'));
        },
      });
  }
}
