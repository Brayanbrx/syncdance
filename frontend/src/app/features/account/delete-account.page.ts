import { HttpBackend, HttpClient, HttpHeaders } from '@angular/common/http';
import { ChangeDetectionStrategy, Component, inject, signal } from '@angular/core';
import { FormBuilder, ReactiveFormsModule, Validators } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { switchMap } from 'rxjs';

import { environment } from '../../../environments/environment';
import { apiError } from '../../core/api.models';
import { AccountFrameComponent } from './account-frame.component';

/**
 * Public page to delete an account (Google Play asks for one besides the app).
 *
 * It signs in with the account typed here and deletes exactly that one. The
 * client skips the interceptors: they would put the panel's own token on the
 * request and delete whoever is signed in to the panel instead.
 */
@Component({
  selector: 'sd-delete-account',
  imports: [ReactiveFormsModule, RouterLink, AccountFrameComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <sd-account-frame>
      <h1>Borrar tu cuenta</h1>
      @if (done()) {
        <p class="notice" role="status">
          La cuenta {{ done() }} se borró. Puedes desinstalar la app; si quedaron prácticas
          guardadas en el teléfono, se borran con ella.
        </p>
        <a routerLink="/">Volver al inicio</a>
      } @else {
        <p>También puedes hacerlo desde la app, en <strong>Mi cuenta</strong>.</p>
        <h2>Qué se borra</h2>
        <ul>
          <li>Tu cuenta: usuario, nombre y correo.</li>
          <li>
            Tus prácticas sincronizadas, con sus puntajes y las observaciones de tu instructor.
          </li>
          <li>Tu inscripción en los cursos.</li>
        </ul>
        <p class="muted">
          No se puede deshacer. Los instructores con cursos o rutinas a cargo deben pedir antes a un
          administrador que los transfiera.
        </p>

        <form [formGroup]="form" (ngSubmit)="submit()">
          <label>
            Usuario
            <input formControlName="username" autocomplete="username" />
          </label>
          <label>
            Contraseña
            <input formControlName="password" type="password" autocomplete="current-password" />
          </label>
          <label class="check">
            <input formControlName="understood" type="checkbox" />
            Entiendo que mi cuenta y mis prácticas se borran para siempre.
          </label>
          @if (error()) {
            <p class="alert" role="alert">{{ error() }}</p>
          }
          <button class="button button--danger" type="submit" [disabled]="form.invalid || busy()">
            {{ busy() ? 'Borrando…' : 'Borrar mi cuenta' }}
          </button>
        </form>
      }
    </sd-account-frame>
  `,
  styles: `
    h2 {
      font-size: var(--step-1);
      margin-top: 1.5rem;
    }
    ul {
      padding-left: 1.2rem;
    }
    .muted {
      color: var(--muted);
    }
    form {
      display: grid;
      gap: 1rem;
      margin-top: 1.5rem;
    }
    .check {
      display: flex;
      gap: 0.6rem;
      align-items: flex-start;
      font-weight: 400;
    }
    .check input {
      width: auto;
      margin-top: 0.3rem;
    }
    .button {
      justify-self: start;
    }
  `,
})
export class DeleteAccountPage {
  private readonly raw = new HttpClient(inject(HttpBackend));
  private readonly api = environment.apiBaseUrl;

  readonly form = inject(FormBuilder).nonNullable.group({
    username: ['', Validators.required],
    password: ['', Validators.required],
    understood: [false, Validators.requiredTrue],
  });
  readonly busy = signal(false);
  readonly done = signal('');
  readonly error = signal('');

  submit(): void {
    const { username, password } = this.form.getRawValue();
    this.busy.set(true);
    this.error.set('');
    let step: 'login' | 'delete' = 'login';
    this.raw
      .post<{ access: string }>(`${this.api}/auth/login/`, { username, password })
      .pipe(
        switchMap(({ access }) => {
          step = 'delete';
          return this.raw.post(
            `${this.api}/auth/me/delete/`,
            { password },
            { headers: new HttpHeaders({ Authorization: `Bearer ${access}` }) },
          );
        }),
      )
      .subscribe({
        next: () => {
          this.busy.set(false);
          this.done.set(username);
          this.form.reset();
        },
        error: (error: unknown) => {
          this.busy.set(false);
          const status = (error as { status?: number }).status;
          this.error.set(
            step === 'login' && status === 401
              ? 'Usuario o contraseña incorrectos.'
              : status === 429
                ? 'Demasiados intentos. Espera un momento y vuelve a intentar.'
                : apiError(error, 'No se pudo conectar con el servidor.'),
          );
        },
      });
  }
}
