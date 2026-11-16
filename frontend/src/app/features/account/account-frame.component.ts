import { ChangeDetectionStrategy, Component } from '@angular/core';
import { RouterLink } from '@angular/router';

/** Narrow column with the wordmark: the public account pages (password, deletion). */
@Component({
  selector: 'sd-account-frame',
  imports: [RouterLink],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <main class="frame">
      <a class="wordmark" routerLink="/">SyncDance</a>
      <ng-content />
    </main>
  `,
  styles: `
    .frame {
      width: min(100% - 2rem, 28rem);
      margin: 12vh auto 4rem;
    }
    .wordmark {
      display: inline-block;
      margin-bottom: 2rem;
      font: 800 var(--step-2) / 1 var(--display);
      font-stretch: 80%;
      text-decoration: none;
    }
  `,
})
export class AccountFrameComponent {}
