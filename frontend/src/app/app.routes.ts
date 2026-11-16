import { Routes } from '@angular/router';

import { adminGuard } from './core/auth/admin.guard';
import { studioGuard } from './core/auth/studio.guard';

export const routes: Routes = [
  {
    path: '',
    pathMatch: 'full',
    title: 'SyncDance: aprende a bailar con tu teléfono',
    loadComponent: () => import('./features/landing/landing.page').then((m) => m.LandingPage),
  },
  {
    path: 'privacidad',
    title: 'Política de privacidad | SyncDance',
    loadComponent: () => import('./features/legal/privacy.page').then((m) => m.PrivacyPage),
  },
  {
    path: 'terminos',
    title: 'Términos de uso | SyncDance',
    loadComponent: () => import('./features/legal/terms.page').then((m) => m.TermsPage),
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
    path: 'ingresar',
    title: 'Ingresar | SyncDance',
    loadComponent: () => import('./features/panel/panel-login.page').then((m) => m.PanelLoginPage),
  },
  // Old address of the login (bookmarks, earlier links); query params are kept.
  { path: 'panel/ingresar', redirectTo: 'ingresar' },
  {
    path: 'estudio',
    canActivate: [studioGuard],
    loadComponent: () =>
      import('./features/studio/studio-shell.component').then((m) => m.StudioShellComponent),
    children: [
      {
        path: '',
        title: 'Mis rutinas | Estudio SyncDance',
        loadComponent: () =>
          import('./features/studio/studio-routines.page').then((m) => m.StudioRoutinesPage),
      },
      {
        path: 'nueva',
        title: 'Subir rutina | Estudio SyncDance',
        loadComponent: () =>
          import('./features/studio/studio-new.page').then((m) => m.StudioNewPage),
      },
      {
        path: 'rutinas/:id',
        title: 'Rutina | Estudio SyncDance',
        loadComponent: () =>
          import('./features/studio/studio-routine.page').then((m) => m.StudioRoutinePage),
      },
    ],
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
