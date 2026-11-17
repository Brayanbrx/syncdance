import { ChangeDetectionStrategy, Component, computed, inject } from '@angular/core';
import { RouterLink } from '@angular/router';

import { LegalInfoService } from '../legal/legal-frame.component';

/** Printable consent for the pilot participants; signed on paper. */
@Component({
  selector: 'sd-pilot-consent',
  imports: [RouterLink],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <main class="consent">
      <div class="screen-only">
        <a class="wordmark" routerLink="/">SyncDance</a>
        <button class="button" type="button" (click)="print()">Imprimir</button>
      </div>

      <h1>Consentimiento para participar en el piloto de SyncDance</h1>

      <h2>Qué es el piloto</h2>
      <p>
        Durante 6 semanas, tu curso usará SyncDance para aprender sus coreografías. Queremos saber
        si la app ayuda a aprender a bailar y qué hay que mejorar.
      </p>

      <h2>Qué harás</h2>
      <ul>
        <li>Practicar con la app cuando quieras, como parte de tu curso.</li>
        <li>Responder dos encuestas cortas, en la semana 2 y en la semana 6.</li>
        <li>Si eres instructor, una entrevista final de unos 30 minutos.</li>
      </ul>

      <h2>Qué datos usamos</h2>
      <p>
        Los resultados de tus prácticas (puntaje por paso, cuánto se te pudo medir, avisos que
        mostró la app e intentos de ubicarte frente a la cámara), tu curso y tus respuestas. La
        cámara se analiza dentro de tu teléfono: <strong>nunca recibimos fotos ni video</strong>. Tu
        instructor ve tus resultados.
      </p>

      <h2>Para qué</h2>
      <p>
        Para decidir si el producto sigue y para mejorarlo. Los informes muestran cifras del grupo,
        sin nombres.
      </p>

      <h2>Es voluntario</h2>
      <p>
        Puedes dejar el piloto cuando quieras, sin dar razones y sin consecuencias en tu curso.
        También puedes borrar tu cuenta y tus datos desde la app o en
        <span class="url">{{ origin }}/cuenta/borrar</span>.
      </p>

      <h2>Cuídate al bailar</h2>
      <p>
        Como en cualquier clase: calienta antes, deja espacio libre alrededor y detente si sientes
        dolor.
      </p>

      <h2>Contacto</h2>
      <p>
        Responsable: {{ controller() }}.
        @if (contact(); as email) {
          Consultas: {{ email }}.
        }
      </p>

      <section class="signatures">
        <p>
          <span class="box"></span> Leí este documento, pude hacer preguntas y acepto participar.
        </p>
        <div class="line"><span>Nombre del participante</span></div>
        <div class="row">
          <div class="line"><span>Firma</span></div>
          <div class="line"><span>Fecha</span></div>
        </div>
        <p class="minor">Si el participante tiene menos de 18 años:</p>
        <p><span class="box"></span> Como madre, padre o tutor, autorizo su participación.</p>
        <div class="line"><span>Nombre de la madre, padre o tutor</span></div>
        <div class="row">
          <div class="line"><span>Firma</span></div>
          <div class="line"><span>Fecha</span></div>
        </div>
      </section>

      <p class="draft">
        Borrador que se revisará con asesoría legal antes del lanzamiento público.
      </p>
    </main>
  `,
  styles: `
    .consent {
      width: min(100% - 2rem, 42rem);
      margin: 6vh auto 4rem;
      line-height: 1.55;
    }
    .screen-only {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 2rem;
    }
    .wordmark {
      font: 800 var(--step-2) / 1 var(--display);
      font-stretch: 80%;
      text-decoration: none;
    }
    h1 {
      font-size: var(--step-2);
    }
    h2 {
      font-size: var(--step-0);
      margin: 1.25rem 0 0.25rem;
    }
    ul {
      padding-left: 1.2rem;
    }
    .signatures {
      margin-top: 2rem;
      break-inside: avoid;
    }
    .box {
      display: inline-block;
      width: 0.9rem;
      height: 0.9rem;
      margin-right: 0.4rem;
      border: 1.5px solid var(--ink);
      vertical-align: -0.1rem;
    }
    .line {
      flex: 1;
      margin: 1.6rem 0 0.6rem;
      border-top: 1px solid var(--ink);
      font-size: var(--step--1);
      color: var(--ink-soft);
    }
    .row {
      display: flex;
      gap: 2rem;
    }
    .minor {
      margin-top: 1.5rem;
      font-weight: 700;
    }
    .draft {
      margin-top: 2rem;
      color: var(--muted);
      font-size: var(--step--1);
    }
    @media print {
      .screen-only {
        display: none;
      }
      .consent {
        width: 100%;
        margin: 0;
        font-size: 11pt;
      }
    }
  `,
})
export class PilotConsentPage {
  private readonly legal = inject(LegalInfoService);
  readonly origin = typeof location === 'undefined' ? '' : location.origin;
  readonly controller = computed(() => this.legal.info()?.controller ?? 'El equipo de SyncDance');
  readonly contact = computed(() => this.legal.info()?.contact_email || '');

  print(): void {
    window.print();
  }
}
