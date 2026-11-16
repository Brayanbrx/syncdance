import { Routes } from '@angular/router';

import { adminGuard } from './core/auth/admin.guard';

export const routes: Routes = [
  {
    path: '',
    pathMatch: 'full',
    title: 'SyncDance: aprende a bailar con tu teléfono',
    loadComponent: () => import('./features/landing/landing.page').then((m) => m.LandingPage),
  },
  {
    path: 'cuenta/recuperar',
    title: 'Recuperar contraseña | SyncDance',
    loadComponent: () =>
      import('./features/account/forgot-password.page').then((m) => m.ForgotPasswordPage),
  },
  {
    path: 'cuenta/restablecer',
    title: 'Contraseña nueva | SyncDance',
    loadComponent: () =>
      import('./features/account/reset-password.page').then((m) => m.ResetPasswordPage),
  },
  {
    path: 'cuenta/borrar',
    title: 'Borrar tu cuenta | SyncDance',
    loadComponent: () =>
      import('./features/account/delete-account.page').then((m) => m.DeleteAccountPage),
  },
  {
    path: 'panel/ingresar',
    title: 'Ingresar al panel | SyncDance',
    loadComponent: () => import('./features/panel/panel-login.page').then((m) => m.PanelLoginPage),
  },
  {
    path: 'panel',
    canActivate: [adminGuard],
    loadComponent: () =>
      import('./features/panel/panel-shell.component').then((m) => m.PanelShellComponent),
    children: [
      {
        path: '',
        title: 'Resumen | Panel SyncDance',
        loadComponent: () => import('./features/panel/summary.page').then((m) => m.SummaryPage),
      },
      {
        path: 'usuarios',
        title: 'Usuarios | Panel SyncDance',
        loadComponent: () => import('./features/panel/users.page').then((m) => m.UsersPage),
      },
      {
        path: 'rutinas',
        title: 'Rutinas | Panel SyncDance',
        loadComponent: () => import('./features/panel/routines.page').then((m) => m.RoutinesPage),
      },
      {
        path: 'cursos',
        title: 'Cursos | Panel SyncDance',
        loadComponent: () => import('./features/panel/courses.page').then((m) => m.CoursesPage),
      },
      {
        path: 'app',
        title: 'App Android | Panel SyncDance',
        loadComponent: () => import('./features/panel/releases.page').then((m) => m.ReleasesPage),
      },
    ],
  },
  { path: '**', redirectTo: '' },
];
