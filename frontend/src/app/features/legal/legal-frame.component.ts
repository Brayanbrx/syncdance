import { HttpClient } from '@angular/common/http';
import { DatePipe } from '@angular/common';
import { ChangeDetectionStrategy, Component, Injectable, inject, input } from '@angular/core';
import { toSignal } from '@angular/core/rxjs-interop';
import { RouterLink } from '@angular/router';
import { catchError, of } from 'rxjs';

import { environment } from '../../../environments/environment';

export interface LegalInfo {
  controller: string;
  contact_email: string;
  terms_version: string;
}

/** Who is responsible for the data and the version in force (GET /api/auth/legal/). */
@Injectable({ providedIn: 'root' })
export class LegalInfoService {
  readonly info = toSignal(
    inject(HttpClient)
      .get<LegalInfo>(`${environment.apiBaseUrl}/auth/legal/`)
      .pipe(catchError(() => of(null))),
    { initialValue: null },
  );
}

/** Reading column for the privacy policy and the terms. */
@Component({
  selector: 'sd-legal-frame',
  imports: [DatePipe, RouterLink],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <main class="legal">
      <a class="wordmark" routerLink="/">SyncDance</a>
      <h1>{{ heading() }}</h1>
      @if (legal.info(); as info) {
        <p class="meta">Vigente desde el {{ info.terms_version | date: 'd MMMM y' }}.</p>
      }
      <ng-content />
      <p class="draft">
        Este texto es un borrador que se revisará con asesoría legal antes del lanzamiento público.
      </p>
      <nav class="more" aria-label="Textos legales">
        <a routerLink="/privacidad">Política de privacidad</a>
        <a routerLink="/terminos">Términos de uso</a>
        <a routerLink="/cuenta/borrar">Borrar mi cuenta</a>
      </nav>
    </main>
  `,
  styles: `
    .legal {
      width: min(100% - 2rem, 42rem);
      margin: 8vh auto 4rem;
      line-height: 1.6;
    }
    .wordmark {
      display: inline-block;
      margin-bottom: 2rem;
      font: 800 var(--step-2) / 1 var(--display);
      font-stretch: 80%;
      text-decoration: none;
    }
    .meta,
    .draft {
      color: var(--muted);
    }
    :host ::ng-deep h2 {
      font-size: var(--step-1);
      margin: 2rem 0 0.5rem;
    }
    :host ::ng-deep ul {
      padding-left: 1.2rem;
    }
    .draft {
      margin-top: 2.5rem;
      font-size: var(--step--1);
    }
    .more {
      display: flex;
      flex-wrap: wrap;
      gap: 0.5rem 1.5rem;
      margin-top: 1rem;
      padding-top: 1rem;
      border-top: 1px solid var(--line);
    }
  `,
})
export class LegalFrameComponent {
  readonly legal = inject(LegalInfoService);
  readonly heading = input.required<string>();
}
