import { DatePipe } from '@angular/common';
import { ChangeDetectionStrategy, Component, OnInit, inject, signal } from '@angular/core';
import { FormBuilder, FormsModule, ReactiveFormsModule, Validators } from '@angular/forms';

import { AuthService } from '../../core/auth/auth.service';
import { PanelUser, ROLE_LABELS, Role, apiError } from '../../core/api.models';
import { PanelService } from '../../core/panel.service';
import { PagerComponent } from '../../shared/pager.component';

@Component({
  selector: 'sd-users',
  imports: [DatePipe, FormsModule, ReactiveFormsModule, PagerComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="page-head">
      <div>
        <h1>Usuarios</h1>
        <p>
          Los estudiantes se registran desde la app. Aquí se crean instructores y administradores.
        </p>
      </div>
      <button class="button" type="button" (click)="creating.set(!creating())">
        {{ creating() ? 'Cerrar' : 'Crear cuenta' }}
      </button>
    </div>

    @if (creating()) {
      <form class="create" [formGroup]="form" (ngSubmit)="create()">
        <label>Usuario <input formControlName="username" autocomplete="off" /></label>
        <label>Correo <input formControlName="email" type="email" autocomplete="off" /></label>
        <label>Nombre <input formControlName="first_name" /></label>
        <label>Apellido <input formControlName="last_name" /></label>
        <label>
          Rol
          <select formControlName="role">
            @for (role of roles; track role) {
              <option [value]="role">{{ labels[role] }}</option>
            }
          </select>
        </label>
        <label>
          Contraseña inicial
          <input formControlName="password" type="password" autocomplete="new-password" />
          <span class="field-hint">Mínimo 8 caracteres, no solo números ni una común.</span>
        </label>
        <button class="button" type="submit" [disabled]="form.invalid || busy()">
          Crear cuenta
        </button>
      </form>
    }

    @if (message()) {
      <p class="notice" role="status">{{ message() }}</p>
    }
    @if (error()) {
      <p class="alert" role="alert">{{ error() }}</p>
    }

    <div class="filters">
      <label>
        Rol
        <select [(ngModel)]="role" (ngModelChange)="reload(1)">
          <option value="">Todos</option>
          @for (role of roles; track role) {
            <option [value]="role">{{ labels[role] }}</option>
          }
        </select>
      </label>
      <label>
        Estado
        <select [(ngModel)]="active" (ngModelChange)="reload(1)">
          <option value="">Todos</option>
          <option value="true">Activas</option>
          <option value="false">Desactivadas</option>
        </select>
      </label>
      <form class="search" (ngSubmit)="reload(1)">
        <label>
          Buscar
          <input
            [(ngModel)]="search"
            name="search"
            type="search"
            placeholder="Usuario, nombre o correo"
          />
        </label>
        <button class="button button--quiet" type="submit">Buscar</button>
      </form>
    </div>

    <div class="table-scroll">
      <table class="table">
        <thead>
          <tr>
            <th>Usuario</th>
            <th>Nombre</th>
            <th>Rol</th>
            <th>Acceso</th>
            <th>Último ingreso</th>
            <th>Alta</th>
            <th><span class="visually-hidden">Acciones</span></th>
          </tr>
        </thead>
        <tbody>
          @for (user of users(); track user.id) {
            <tr>
              <td>
                <strong>{{ user.username }}</strong>
                <br /><span class="muted">{{ user.email }}</span>
              </td>
              <td>{{ user.first_name }} {{ user.last_name }}</td>
              <td>
                @if (locked(user)) {
                  {{ labels[user.role] }}{{ user.is_superuser ? ' (superusuario)' : '' }}
                } @else {
                  <select
                    [attr.aria-label]="'Rol de ' + user.username"
                    [ngModel]="user.role"
                    (ngModelChange)="update(user, { role: $event })"
                  >
                    @for (role of roles; track role) {
                      <option [value]="role">{{ labels[role] }}</option>
                    }
                  </select>
                }
              </td>
              <td>
                @if (locked(user)) {
                  <span class="status status--ok">Activa</span>
                } @else {
                  <label class="toggle">
                    <input
                      type="checkbox"
                      [checked]="user.is_active"
                      (change)="update(user, { is_active: !user.is_active })"
                    />
                    {{ user.is_active ? 'Activa' : 'Desactivada' }}
                  </label>
                }
              </td>
              <td>{{ user.last_login ? (user.last_login | date: 'd MMM y, HH:mm') : 'Nunca' }}</td>
              <td>{{ user.date_joined | date: 'd MMM y' }}</td>
              <td>
                @if (resetting() === user.id) {
                  <form class="reset" (ngSubmit)="resetPassword(user)">
                    <input
                      [(ngModel)]="newPassword"
                      name="password"
                      type="password"
                      autocomplete="new-password"
                      [attr.aria-label]="'Nueva contraseña de ' + user.username"
                      placeholder="Nueva contraseña"
                    />
                    <button class="button button--small" type="submit">Guardar</button>
                    <button
                      class="button button--quiet button--small"
                      type="button"
                      (click)="resetting.set(null)"
                    >
                      Cancelar
                    </button>
                  </form>
                } @else if (!user.is_superuser) {
                  <button
                    class="button button--quiet button--small"
                    type="button"
                    (click)="startReset(user)"
                  >
                    Cambiar contraseña
                  </button>
                }
              </td>
            </tr>
          } @empty {
            <tr>
              <td colspan="7">Ninguna cuenta coincide con estos filtros.</td>
            </tr>
          }
        </tbody>
      </table>
    </div>
    <sd-pager [count]="count()" [page]="page()" (pageChange)="reload($event)" />
  `,
  styles: `
    .create {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(14rem, 1fr));
      gap: 1rem;
      align-items: end;
      background: var(--paper);
      border: 1px solid var(--line);
      border-radius: 12px;
      padding: 1.25rem;
      margin-bottom: 1.5rem;
    }
    .search {
      display: flex;
      gap: 0.5rem;
      align-items: end;
    }
    .muted {
      color: var(--muted);
    }
    .toggle {
      display: flex;
      align-items: center;
      gap: 0.4rem;
      font-weight: 400;
    }
    .reset {
      display: flex;
      flex-wrap: wrap;
      gap: 0.4rem;
    }
    .reset input {
      width: 11rem;
    }
  `,
})
export class UsersPage implements OnInit {
  private readonly panel = inject(PanelService);
  readonly auth = inject(AuthService);

  readonly roles: Role[] = ['STUDENT', 'INSTRUCTOR', 'ADMIN'];
  readonly labels = ROLE_LABELS;
  readonly users = signal<PanelUser[]>([]);
  readonly count = signal(0);
  readonly page = signal(1);
  readonly busy = signal(false);
  readonly creating = signal(false);
  readonly resetting = signal<number | null>(null);
  readonly message = signal('');
  readonly error = signal('');
  role: Role | '' = '';
  active: '' | 'true' | 'false' = '';
  search = '';
  newPassword = '';

  readonly form = inject(FormBuilder).nonNullable.group({
    username: ['', Validators.required],
    email: ['', [Validators.required, Validators.email]],
    first_name: [''],
    last_name: [''],
    role: ['INSTRUCTOR' as Role, Validators.required],
    password: ['', [Validators.required, Validators.minLength(8)]],
  });

  ngOnInit(): void {
    this.reload(1);
  }

  /** Your own account and superusers (for non-superusers) are read-only here. */
  locked(user: PanelUser): boolean {
    return user.id === this.auth.me()?.id || user.is_superuser;
  }

  reload(page: number): void {
    this.page.set(page);
    this.panel
      .users({ page, role: this.role, active: this.active, search: this.search })
      .subscribe({
        next: (result) => {
          this.users.set(result.results);
          this.count.set(result.count);
        },
        error: (error: unknown) => this.error.set(apiError(error, 'No se pudo cargar la lista.')),
      });
  }

  update(user: PanelUser, changes: Partial<PanelUser>): void {
    this.message.set('');
    this.error.set('');
    this.panel.updateUser(user.id, changes).subscribe({
      next: (saved) => {
        this.users.update((list) => list.map((u) => (u.id === saved.id ? saved : u)));
        this.message.set(`Cuenta ${saved.username} actualizada.`);
      },
      error: (error: unknown) => {
        this.error.set(apiError(error, 'No se pudo guardar el cambio.'));
        this.reload(this.page()); // undo the optimistic control state
      },
    });
  }

  startReset(user: PanelUser): void {
    this.newPassword = '';
    this.resetting.set(user.id);
  }

  resetPassword(user: PanelUser): void {
    this.error.set('');
    this.panel.setPassword(user.id, this.newPassword).subscribe({
      next: () => {
        this.resetting.set(null);
        this.message.set(`Contraseña de ${user.username} cambiada. Compártela en persona.`);
      },
      error: (error: unknown) =>
        this.error.set(apiError(error, 'No se pudo cambiar la contraseña.')),
    });
  }

  create(): void {
    this.busy.set(true);
    this.error.set('');
    this.panel.createUser(this.form.getRawValue()).subscribe({
      next: (user) => {
        this.busy.set(false);
        this.creating.set(false);
        this.form.reset();
        this.message.set(`Cuenta ${user.username} creada como ${ROLE_LABELS[user.role]}.`);
        this.reload(1);
      },
      error: (error: unknown) => {
        this.busy.set(false);
        this.error.set(apiError(error, 'No se pudo crear la cuenta.'));
      },
    });
  }
}
