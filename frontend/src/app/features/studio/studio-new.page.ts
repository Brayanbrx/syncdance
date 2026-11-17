import { HttpEventType } from '@angular/common/http';
import { ChangeDetectionStrategy, Component, inject, signal } from '@angular/core';
import { toSignal } from '@angular/core/rxjs-interop';
import { FormBuilder, ReactiveFormsModule, Validators } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';

import {
  DIFFICULTY_LABELS,
  Difficulty,
  RoutineKind,
  apiError,
  formatSize,
} from '../../core/api.models';
import { StudioService } from '../../core/studio.service';

const MAX_BYTES = 200 * 1024 * 1024;
const VIDEO = ['.mp4', '.mov', '.m4v', '.webm', '.mkv'];
/** Singing: the instructor's voice alone, as audio or video. */
const VOICE = [...VIDEO, '.m4a', '.mp3', '.wav', '.aac', '.ogg', '.flac'];
const VIDEO_ACCEPT = 'video/mp4,video/quicktime,video/webm,video/x-matroska,.mkv';
const VOICE_ACCEPT = `audio/*,${VIDEO_ACCEPT}`;

@Component({
  selector: 'sd-studio-new',
  imports: [ReactiveFormsModule, RouterLink],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <h1>Subir rutina</h1>
    <div class="layout">
      <form [formGroup]="form" (ngSubmit)="submit()">
        <fieldset class="kind">
          <legend>¿Qué vas a enseñar?</legend>
          <label class="choice">
            <input type="radio" formControlName="kind" value="DANCE" (change)="video.set(null)" />
            Baile: subes un video y tus alumnos copian tus movimientos
          </label>
          <label class="choice">
            <input type="radio" formControlName="kind" value="SING" (change)="video.set(null)" />
            Canto: subes tu voz y tus alumnos cantan la melodía con audífonos
          </label>
        </fieldset>
        <label>
          Nombre
          <input formControlName="name" maxlength="150" required />
        </label>
        <div class="row">
          <label>
            Nivel
            <select formControlName="difficulty">
              @for (level of levels; track level) {
                <option [value]="level">{{ labels[level] }}</option>
              }
            </select>
          </label>
          <label>
            Estilo
            <input
              formControlName="style"
              maxlength="40"
              [placeholder]="singing() ? 'Pop, coro, vocalización…' : 'Urbano, K-pop, fitness…'"
            />
          </label>
        </div>
        <label>
          Descripción
          <textarea formControlName="description" rows="3"></textarea>
          <span class="field-hint">Qué se aprende y para quién es. La ven tus alumnos.</span>
        </label>
        <label>
          {{ singing() ? 'Tu voz, sola' : 'Video de la coreografía' }}
          <input
            type="file"
            [accept]="singing() ? voiceAccept : videoAccept"
            (change)="pick($event)"
            [disabled]="busy()"
          />
          <span class="field-hint">
            @if (singing()) {
              Audio (M4A, MP3, WAV) o video, de 5 segundos a 5 minutos, hasta 200 MB.
            } @else {
              MP4, MOV, WEBM o MKV, de 5 segundos a 5 minutos, hasta 200 MB.
            }
            @if (video(); as file) {
              Elegido: {{ file.name }} ({{ size(file.size) }}).
            }
          </span>
        </label>

        @if (error()) {
          <p class="alert" role="alert">{{ error() }}</p>
        }
        @if (progress() !== null) {
          <div class="progress" role="status">
            <div class="bar"><span [style.width.%]="progress()"></span></div>
            {{ progress() === 100 ? 'Revisando el archivo…' : 'Subiendo ' + progress() + ' %' }}
          </div>
        }
        <div class="actions">
          <button class="button" type="submit" [disabled]="form.invalid || !video() || busy()">
            Subir y procesar
          </button>
          <a routerLink="/estudio">Cancelar</a>
        </div>
      </form>

      <aside class="tips">
        <h2>Para que corrija bien</h2>
        @if (singing()) {
          <ul>
            <li>Solo tu voz: sin pista, piano ni coro de fondo.</li>
            <li>En un lugar callado, a un palmo del micrófono.</li>
            <li>Canta como quieres que lo canten: tus alumnos siguen tu voz.</li>
            <li>Una canción propia, con licencia o libre de derechos.</li>
          </ul>
          <p>
            SyncDance saca la melodía de tu voz y te avisa si oye música o ruido detrás. Tus alumnos
            escuchan tu voz y ven en vivo si su nota está arriba o abajo.
          </p>
        } @else {
          <ul>
            <li>De frente a la cámara y de cuerpo entero, de la cabeza a los pies.</li>
            <li>Solo tú en el cuadro: nadie pasando por detrás.</li>
            <li>Buena luz y ropa que deje ver codos y rodillas.</li>
            <li>Con la música que usarás en clase: propia, con licencia o libre.</li>
          </ul>
          <p>
            Después de subirlo, SyncDance analiza el video y te muestra en qué tramos no se te ve
            bien. Recién entonces lo publicas en tus cursos.
          </p>
        }
      </aside>
    </div>
  `,
  styles: `
    .layout {
      display: grid;
      grid-template-columns: minmax(0, 1fr) 18rem;
      gap: 2.5rem;
      align-items: start;
    }
    form {
      display: grid;
      gap: 1.1rem;
    }
    .kind {
      display: grid;
      gap: 0.5rem;
      border: 1.5px solid var(--line);
      border-radius: 10px;
      padding: 0.75rem 1rem;
    }
    .choice {
      display: flex;
      gap: 0.6rem;
      align-items: baseline;
      font-weight: normal;
    }
    .row {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 1rem;
    }
    textarea {
      font: inherit;
      padding: 0.6rem 0.75rem;
      border: 1.5px solid var(--line);
      border-radius: 10px;
    }
    .actions {
      display: flex;
      align-items: center;
      gap: 1.25rem;
    }
    .progress {
      display: grid;
      gap: 0.4rem;
      font-size: var(--step--1);
    }
    .bar {
      height: 0.6rem;
      border-radius: 99px;
      background: var(--floor);
      overflow: hidden;
    }
    .bar span {
      display: block;
      height: 100%;
      background: var(--right);
      transition: width 0.2s;
    }
    .tips {
      padding: 1.25rem;
      background: var(--paper);
      border: 1px solid var(--line);
      border-radius: 12px;
      font-size: var(--step--1);
    }
    .tips h2 {
      font-size: var(--step-0);
      margin: 0 0 0.5rem;
    }
    .tips ul {
      padding-left: 1.1rem;
      display: grid;
      gap: 0.35rem;
    }
    @media (max-width: 52rem) {
      .layout,
      .row {
        grid-template-columns: 1fr;
      }
    }
  `,
})
export class StudioNewPage {
  private readonly studio = inject(StudioService);
  private readonly router = inject(Router);

  readonly levels: Difficulty[] = ['BEGINNER', 'INTERMEDIATE', 'ADVANCED'];
  readonly labels = DIFFICULTY_LABELS;
  readonly size = formatSize;
  readonly videoAccept = VIDEO_ACCEPT;
  readonly voiceAccept = VOICE_ACCEPT;
  readonly form = inject(FormBuilder).nonNullable.group({
    kind: ['DANCE' as RoutineKind],
    name: ['', [Validators.required, Validators.maxLength(150)]],
    difficulty: ['BEGINNER' as Difficulty],
    style: [''],
    description: [''],
  });
  private readonly kind = toSignal(this.form.controls.kind.valueChanges, {
    initialValue: this.form.controls.kind.value,
  });
  readonly singing = () => this.kind() === 'SING';
  readonly video = signal<File | null>(null);
  readonly busy = signal(false);
  readonly progress = signal<number | null>(null);
  readonly error = signal('');

  pick(event: Event): void {
    const file = (event.target as HTMLInputElement).files?.[0] ?? null;
    this.error.set('');
    this.video.set(null);
    if (!file) return;
    const extension = file.name.slice(file.name.lastIndexOf('.')).toLowerCase();
    if (this.singing() && !VOICE.includes(extension)) {
      this.error.set('Elige tu voz como audio (M4A, MP3, WAV) o video (MP4, MOV).');
    } else if (!this.singing() && !VIDEO.includes(extension)) {
      this.error.set('Elige un video MP4, MOV, WEBM o MKV.');
    } else if (file.size > MAX_BYTES) {
      this.error.set('El archivo pesa más de 200 MB.');
    } else {
      this.video.set(file);
    }
  }

  submit(): void {
    const video = this.video();
    if (!video) return;
    this.busy.set(true);
    this.error.set('');
    this.progress.set(0);
    this.studio.create(this.form.getRawValue(), video).subscribe({
      next: (event) => {
        if (event.type === HttpEventType.UploadProgress && event.total) {
          this.progress.set(Math.round((100 * event.loaded) / event.total));
        } else if (event.type === HttpEventType.Response && event.body) {
          this.router.navigate(['/estudio/rutinas', event.body.id]);
        }
      },
      error: (error: unknown) => {
        this.busy.set(false);
        this.progress.set(null);
        this.error.set(apiError(error, 'No se pudo subir el archivo. Revisa tu conexión.'));
      },
    });
  }
}
