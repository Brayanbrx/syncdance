import { ChangeDetectionStrategy, Component, input } from '@angular/core';
import { RouterLink } from '@angular/router';

/** Reading column for the getting-started guides of the pilot. */
@Component({
  selector: 'sd-guide-frame',
  imports: [RouterLink],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <main class="guide">
      <a class="wordmark" routerLink="/">SyncDance</a>
      <h1>{{ heading() }}</h1>
      <ng-content />
      <nav class="more" aria-label="Guías">
        <a routerLink="/guia/alumnos">Guía para alumnos</a>
        <a routerLink="/guia/instructores">Guía para instructores</a>
        <a routerLink="/privacidad">Privacidad</a>
      </nav>
    </main>
  `,
  styles: `
    .guide {
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
    :host ::ng-deep h2 {
      font-size: var(--step-1);
      margin: 2rem 0 0.5rem;
    }
    :host ::ng-deep ol,
    :host ::ng-deep ul {
      padding-left: 1.3rem;
    }
    :host ::ng-deep li + li {
      margin-top: 0.6rem;
    }
    :host ::ng-deep .lead {
      font-size: var(--step-1);
      color: var(--ink-soft);
    }
    .more {
      display: flex;
      flex-wrap: wrap;
      gap: 0.5rem 1.5rem;
      margin-top: 3rem;
      font-size: var(--step--1);
    }
  `,
})
export class GuideFrameComponent {
  readonly heading = input.required<string>();
}
