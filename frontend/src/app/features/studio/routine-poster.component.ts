import {
  ChangeDetectionStrategy,
  Component,
  DestroyRef,
  computed,
  inject,
  input,
  signal,
} from '@angular/core';
import { takeUntilDestroyed, toObservable } from '@angular/core/rxjs-interop';
import { catchError, of, switchMap } from 'rxjs';

import { StudioService } from '../../core/studio.service';

/**
 * Thumbnail of a processed routine version. The file needs the session, so
 * it is fetched as a blob and shown through an object URL, released on change.
 */
@Component({
  selector: 'sd-routine-poster',
  changeDetection: ChangeDetectionStrategy.OnPush,
  host: { '[class.natural]': "fit() === 'natural'" },
  template: `
    @if (url(); as src) {
      <img [src]="src" alt="" />
    }
  `,
  styles: `
    :host {
      display: block;
      overflow: hidden;
      border-radius: inherit;
      background: var(--line);
    }
    :host(:not(.natural)) {
      aspect-ratio: 1;
    }
    img {
      display: block;
      width: 100%;
    }
    :host(:not(.natural)) img {
      height: 100%;
      object-fit: cover;
    }
    :host(.natural) img {
      max-height: 24rem;
      object-fit: contain;
    }
  `,
})
export class RoutinePosterComponent {
  private readonly studio = inject(StudioService);

  readonly routine = input.required<number>();
  readonly version = input.required<number>();
  /** `cover` fills a square (lists); `natural` keeps the video's shape. */
  readonly fit = input<'cover' | 'natural'>('cover');
  readonly url = signal<string | null>(null);

  constructor() {
    const key = computed(() => ({ id: this.routine(), version: this.version() }));
    toObservable(key)
      .pipe(
        switchMap(({ id, version }) =>
          this.studio.poster(id, version).pipe(catchError(() => of(null))),
        ),
        takeUntilDestroyed(),
      )
      .subscribe((blob) => this.show(blob));
    inject(DestroyRef).onDestroy(() => this.show(null));
  }

  private show(blob: Blob | null): void {
    const previous = this.url();
    if (previous) URL.revokeObjectURL(previous);
    this.url.set(blob ? URL.createObjectURL(blob) : null);
  }
}
