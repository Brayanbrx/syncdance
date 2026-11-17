import { HttpEventType } from '@angular/common/http';
import {
  ChangeDetectionStrategy,
  Component,
  DestroyRef,
  effect,
  inject,
  input,
  signal,
  untracked,
} from '@angular/core';
import { Subscription } from 'rxjs';

import { RoutineMediaService } from '../core/routine-media.service';
import { RoutinePosterComponent } from './routine-poster.component';

/**
 * The poster of a version and, on request, the same video students download.
 * It is fetched only when asked for: it can weigh several megabytes.
 */
@Component({
  selector: 'sd-routine-preview',
  imports: [RoutinePosterComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @if (url(); as src) {
      @if (audio()) {
        <audio [src]="src" controls autoplay></audio>
      } @else {
        <video [src]="src" controls autoplay playsinline></video>
      }
    } @else {
      @if (poster()) {
        <sd-routine-poster fit="natural" [routine]="routine()" [version]="version()" />
      }
      <button class="button" type="button" [disabled]="loading() !== null" (click)="watch()">
        @if (loading() === null) {
          {{ audio() ? 'Escuchar' : 'Ver video' }}
        } @else {
          Cargando {{ loading() }} %
        }
      </button>
    }
    @if (failed()) {
      <p class="alert" role="alert">
        No se pudo cargar {{ audio() ? 'el audio' : 'el video' }}. Inténtalo de nuevo.
      </p>
    }
  `,
  styles: `
    :host {
      display: grid;
      justify-items: start;
      gap: 0.75rem;
    }
    sd-routine-poster,
    video,
    audio {
      max-width: min(100%, 28rem);
      border-radius: 12px;
    }
    audio {
      width: 28rem;
    }
    video {
      display: block;
      max-height: 24rem;
      background: var(--ink);
    }
  `,
})
export class RoutinePreviewComponent {
  private readonly media = inject(RoutineMediaService);

  readonly routine = input.required<number>();
  readonly version = input.required<number>();
  /** Whether the version has a poster to show before the video. */
  readonly poster = input(false);
  /** A singing routine: its file is the voice students sing with. */
  readonly audio = input(false);

  readonly url = signal<string | null>(null);
  readonly loading = signal<number | null>(null);
  readonly failed = signal(false);
  private download?: Subscription;

  constructor() {
    // A new version (the video was replaced) drops the old preview.
    effect(() => {
      this.routine();
      this.version();
      untracked(() => this.reset());
    });
    inject(DestroyRef).onDestroy(() => this.reset());
  }

  watch(): void {
    this.failed.set(false);
    this.loading.set(0);
    this.download = this.media.video(this.routine(), this.version()).subscribe({
      next: (event) => {
        if (event.type === HttpEventType.DownloadProgress && event.total) {
          this.loading.set(Math.round((100 * event.loaded) / event.total));
        } else if (event.type === HttpEventType.Response && event.body) {
          this.url.set(URL.createObjectURL(event.body));
          this.loading.set(null);
        }
      },
      error: () => {
        this.loading.set(null);
        this.failed.set(true);
      },
    });
  }

  private reset(): void {
    this.download?.unsubscribe();
    this.download = undefined;
    const url = this.url();
    if (url) URL.revokeObjectURL(url);
    this.url.set(null);
    this.loading.set(null);
  }
}
