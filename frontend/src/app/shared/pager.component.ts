import { ChangeDetectionStrategy, Component, computed, input, output } from '@angular/core';

/** Previous/next over DRF pages (20 rows each). */
@Component({
  selector: 'sd-pager',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @if (pages() > 1) {
      <nav class="pager" aria-label="Páginas">
        <button
          class="button button--quiet button--small"
          type="button"
          [disabled]="page() <= 1"
          (click)="pageChange.emit(page() - 1)"
        >
          Anterior
        </button>
        <span>Página {{ page() }} de {{ pages() }}</span>
        <button
          class="button button--quiet button--small"
          type="button"
          [disabled]="page() >= pages()"
          (click)="pageChange.emit(page() + 1)"
        >
          Siguiente
        </button>
      </nav>
    }
  `,
  styles: `
    .pager {
      display: flex;
      align-items: center;
      gap: 1rem;
      margin-top: 1rem;
      font-size: var(--step--1);
    }
  `,
})
export class PagerComponent {
  readonly count = input.required<number>();
  readonly page = input.required<number>();
  readonly pageSize = input(20);
  readonly pageChange = output<number>();
  readonly pages = computed(() => Math.max(1, Math.ceil(this.count() / this.pageSize())));
}
