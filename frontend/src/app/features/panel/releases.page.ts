import { DatePipe } from '@angular/common';
import { HttpEventType } from '@angular/common/http';
import { ChangeDetectionStrategy, Component, OnInit, inject, signal } from '@angular/core';
import { FormBuilder, ReactiveFormsModule, Validators } from '@angular/forms';

import { PanelRelease, apiError, formatSize } from '../../core/api.models';
import { PanelService } from '../../core/panel.service';

@Component({
  selector: 'sd-releases',
  imports: [DatePipe, ReactiveFormsModule],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="page-head">
      <div>
        <h1>App Android</h1>
        <p>
          La landing ofrece la versión publicada con el código más alto. Genera el APK con
          <code>flutter build apk --release</code> y súbelo aquí.
        </p>
      </div>
    </div>

    <form class="upload" [formGroup]="form" (ngSubmit)="upload()">
      <label>
        Versión
        <input formControlName="version_name" placeholder="1.0.0" />
      </label>
      <label>
        Código de versión
        <input formControlName="version_code" type="number" min="1" placeholder="1" />
        <span class="field-hint">El número tras el «+» en pubspec.yaml.</span>
      </label>
      <label>
        Android mínimo
        <input formControlName="min_android" />
      </label>
      <label class="wide">
        Novedades
        <textarea formControlName="notes" rows="2" maxlength="2000"></textarea>
      </label>
      <label class="wide">
        Archivo APK
        <input type="file" accept=".apk" (change)="pick($event)" />
      </label>
      <label class="check">
        <input type="checkbox" formControlName="is_published" />
        Publicar en la landing al subir
      </label>
      <div class="wide actions">
        <button
          class="button"
          type="submit"
          [disabled]="form.invalid || !file() || progress() !== null"
        >
          Subir versión
        </button>
        @if (progress() !== null) {
          <progress [value]="progress()" max="100" aria-label="Progreso de la subida"></progress>
          <span>{{ progress() }} %</span>
        }
      </div>
    </form>

    @if (message()) {
      <p class="notice" role="status">{{ message() }}</p>
    }
    @if (error()) {
      <p class="alert" role="alert">{{ error() }}</p>
    }

    <div class="table-scroll">
      <table class="table">
        <thead>
          <tr>
            <th>Versión</th>
            <th class="num">Código</th>
            <th class="num">Tamaño</th>
            <th>En la landing</th>
            <th>Subida</th>
            <th><span class="visually-hidden">Acciones</span></th>
          </tr>
        </thead>
        <tbody>
          @for (release of releases(); track release.id) {
            <tr>
              <td>
                <strong>{{ release.version_name }}</strong>
                @if (release.notes) {
                  <br /><span class="muted">{{ release.notes }}</span>
                }
                <br /><code class="hash" [title]="release.sha256"
                  >{{ release.sha256.slice(0, 16) }}…</code
                >
              </td>
              <td class="num">{{ release.version_code }}</td>
              <td class="num">{{ size(release.size_bytes) }}</td>
              <td>
                <label class="check">
                  <input
                    type="checkbox"
                    [checked]="release.is_published"
                    (change)="publish(release, !release.is_published)"
                    [attr.aria-label]="'Publicar la versión ' + release.version_name"
                  />
                  {{ release.is_published ? 'Publicada' : 'Sin publicar' }}
                </label>
              </td>
              <td>
                {{ release.created_at | date: 'd MMM y, HH:mm' }}
                @if (release.uploaded_by) {
                  <br /><span class="muted">por {{ release.uploaded_by }}</span>
                }
              </td>
              <td>
                @if (!release.is_published) {
                  <button
                    class="button button--danger button--small"
                    type="button"
                    (click)="remove(release)"
                  >
                    Borrar
                  </button>
                }
              </td>
            </tr>
          } @empty {
            <tr>
              <td colspan="6">Todavía no se subió ningún APK.</td>
            </tr>
          }
        </tbody>
      </table>
    </div>
  `,
  styles: `
    .upload {
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: 1rem;
      background: var(--paper);
      border: 1px solid var(--line);
      border-radius: 12px;
      padding: 1.25rem;
      margin-bottom: 1.5rem;
    }
    .wide {
      grid-column: 1 / -1;
    }
    .check {
      display: flex;
      align-items: center;
      gap: 0.5rem;
      font-weight: 400;
    }
    .actions {
      display: flex;
      align-items: center;
      gap: 1rem;
    }
    progress {
      width: min(20rem, 100%);
    }
    .muted {
      color: var(--muted);
    }
    .hash {
      font-size: 0.75rem;
      color: var(--muted);
    }
    @media (max-width: 48rem) {
      .upload {
        grid-template-columns: 1fr;
      }
    }
  `,
})
export class ReleasesPage implements OnInit {
  private readonly panel = inject(PanelService);
  readonly releases = signal<PanelRelease[]>([]);
  readonly file = signal<File | null>(null);
  readonly progress = signal<number | null>(null);
  readonly message = signal('');
  readonly error = signal('');
  readonly size = formatSize;

  readonly form = inject(FormBuilder).nonNullable.group({
    version_name: ['', Validators.required],
    version_code: [1, [Validators.required, Validators.min(1)]],
    min_android: ['7.0', Validators.required],
    notes: [''],
    is_published: [true],
  });

  ngOnInit(): void {
    this.load();
  }

  load(): void {
    this.panel.releases().subscribe({
      next: (page) => {
        this.releases.set(page.results);
        const next = Math.max(0, ...page.results.map((r) => r.version_code)) + 1;
        if (!this.form.dirty) this.form.patchValue({ version_code: next });
      },
      error: (error: unknown) => this.error.set(apiError(error, 'No se pudieron cargar.')),
    });
  }

  pick(event: Event): void {
    const input = event.target as HTMLInputElement;
    this.file.set(input.files?.[0] ?? null);
  }

  upload(): void {
    const file = this.file();
    if (!file) return;
    const values = this.form.getRawValue();
    const data = new FormData();
    data.append('version_name', values.version_name.trim());
    data.append('version_code', String(values.version_code));
    data.append('min_android', values.min_android.trim());
    data.append('notes', values.notes.trim());
    data.append('is_published', String(values.is_published));
    data.append('apk', file, file.name);
    this.error.set('');
    this.message.set('');
    this.progress.set(0);
    this.panel.uploadRelease(data).subscribe({
      next: (event) => {
        if (event.type === HttpEventType.UploadProgress && event.total) {
          this.progress.set(Math.round((100 * event.loaded) / event.total));
        } else if (event.type === HttpEventType.Response && event.body) {
          this.progress.set(null);
          this.message.set(
            event.body.is_published
              ? `Versión ${event.body.version_name} subida y publicada en la landing.`
              : `Versión ${event.body.version_name} subida sin publicar.`,
          );
          this.form.reset();
          this.file.set(null);
          this.load();
        }
      },
      error: (error: unknown) => {
        this.progress.set(null);
        this.error.set(apiError(error, 'No se pudo subir el APK.'));
      },
    });
  }

  publish(release: PanelRelease, isPublished: boolean): void {
    this.error.set('');
    this.panel.updateRelease(release.id, { is_published: isPublished }).subscribe({
      next: (saved) => {
        this.releases.update((list) => list.map((r) => (r.id === saved.id ? saved : r)));
        this.message.set(
          isPublished
            ? `Versión ${saved.version_name} publicada.`
            : `Versión ${saved.version_name} retirada de la landing.`,
        );
      },
      error: (error: unknown) => {
        this.error.set(apiError(error, 'No se pudo cambiar la publicación.'));
        this.load();
      },
    });
  }

  remove(release: PanelRelease): void {
    if (
      !confirm(`¿Borrar la versión ${release.version_name}? El archivo se elimina del servidor.`)
    ) {
      return;
    }
    this.panel.deleteRelease(release.id).subscribe({
      next: () => {
        this.message.set(`Versión ${release.version_name} borrada.`);
        this.load();
      },
      error: (error: unknown) => this.error.set(apiError(error, 'No se pudo borrar.')),
    });
  }
}
