import { DatePipe } from '@angular/common';
import {
  ChangeDetectionStrategy,
  Component,
  OnInit,
  computed,
  inject,
  signal,
} from '@angular/core';

import { PilotMetrics, apiError, percent } from '../../core/api.models';
import { PanelService } from '../../core/panel.service';

type Verdict = 'met' | 'below' | 'unknown';

/** The pilot's gate (E5), each figure against its provisional target. */
@Component({
  selector: 'sd-pilot',
  imports: [DatePipe],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="page-head">
      <div>
        <h1>Piloto</h1>
        <p>
          Las cifras que deciden si el producto sigue, cada una contra su meta provisional. Salen de
          las prácticas sincronizadas; «—» es sin datos. La disposición a pagar se mide en las
          entrevistas con los instructores.
        </p>
      </div>
    </div>

    @if (error()) {
      <p class="alert" role="alert">{{ error() }}</p>
    }

    @if (metrics(); as m) {
      <div class="gates">
        <section class="gate">
          <h2>Se ubican frente a la cámara</h2>
          <p class="figure">{{ percent(m.calibration.ratio) }}</p>
          <p>
            {{ m.calibration.calibrated }} de {{ m.calibration.attempts }} intentos lograron el
            encuadre. Meta: {{ percent(m.targets.calibration) }} o más.
          </p>
          <span class="status status--{{ tone(verdicts().calibration) }}">
            {{ label(verdicts().calibration) }}
          </span>
        </section>
        <section class="gate">
          <h2>La app coincide con el instructor</h2>
          <p class="figure">
            {{ m.concordance.spearman === null ? '—' : rho(m.concordance.spearman) }}
          </p>
          <p>
            Correlación de rangos en {{ m.concordance.pairs }} prácticas calificadas. Meta:
            {{ rho(m.targets.concordance) }} o más; hacen falta 5.
          </p>
          <span class="status status--{{ tone(verdicts().concordance) }}">
            {{ label(verdicts().concordance) }}
          </span>
        </section>
        <section class="gate">
          <h2>Siguen activos en la semana 4</h2>
          <p class="figure">{{ percent(m.retention_week4.ratio) }}</p>
          <p>
            {{ m.retention_week4.retained }} de {{ m.retention_week4.cohort }} alumnos que empezaron
            hace 4 semanas o más practicaron entre los días 21 y 28. Meta:
            {{ percent(m.targets.retention_week4) }} o más.
          </p>
          <span class="status status--{{ tone(verdicts().retention) }}">
            {{ label(verdicts().retention) }}
          </span>
        </section>
        <section class="gate">
          <h2>Rutinas publicadas por instructor</h2>
          @if (!m.instructors.length) {
            <p class="figure">—</p>
            <p>Todavía no hay instructores.</p>
          } @else {
            <ul class="instructors">
              @for (i of m.instructors; track i.username) {
                <li>
                  <span>{{ i.username }}</span>
                  <strong [class.met]="i.published >= m.targets.routines_per_instructor">
                    {{ i.published }}
                  </strong>
                </li>
              }
            </ul>
            <p>Meta: {{ m.targets.routines_per_instructor }} o más cada uno, sin ayuda.</p>
          }
          <span class="status status--{{ tone(verdicts().routines) }}">
            {{ label(verdicts().routines) }}
          </span>
        </section>
      </div>

      <section class="activity">
        <h2>Actividad por semana</h2>
        <div class="table-scroll">
          <table class="table">
            <thead>
              <tr>
                <th>Semana del</th>
                <th class="num">Alumnos activos</th>
                <th class="num">Prácticas evaluadas</th>
              </tr>
            </thead>
            <tbody>
              @for (week of weeksNewestFirst(); track week.week_start) {
                <tr>
                  <td>{{ week.week_start | date: 'd MMM y' }}</td>
                  <td class="num">{{ week.active_students }}</td>
                  <td class="num">{{ week.evaluated_practices }}</td>
                </tr>
              }
            </tbody>
          </table>
        </div>
      </section>
    }
  `,
  styles: `
    .gates {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(15rem, 1fr));
      gap: 1rem;
    }
    .gate,
    .activity {
      padding: 1.25rem;
      background: var(--paper);
      border: 1px solid var(--line);
      border-radius: 12px;
    }
    .activity {
      margin-top: 1.5rem;
    }
    h2 {
      font-size: var(--step-0);
      margin: 0 0 0.5rem;
    }
    .figure {
      margin: 0 0 0.5rem;
      font: 800 var(--step-3) / 1 var(--display);
      font-variant-numeric: tabular-nums;
    }
    .gate p:not(.figure) {
      color: var(--ink-soft);
      font-size: var(--step--1);
    }
    .instructors {
      list-style: none;
      padding: 0;
      margin: 0 0 0.5rem;
      display: grid;
      gap: 0.25rem;
    }
    .instructors li {
      display: flex;
      justify-content: space-between;
      border-bottom: 1px dashed var(--line);
      padding: 0.2rem 0;
    }
    .instructors strong.met {
      color: var(--ok);
    }
    .status--neutral {
      background: var(--floor);
      color: var(--ink-soft);
    }
    .num {
      text-align: right;
      font-variant-numeric: tabular-nums;
    }
  `,
})
export class PilotPage implements OnInit {
  private readonly panel = inject(PanelService);
  readonly percent = percent;
  readonly metrics = signal<PilotMetrics | null>(null);
  readonly error = signal('');

  readonly weeksNewestFirst = computed(() => [...(this.metrics()?.weeks ?? [])].reverse());

  readonly verdicts = computed(() => {
    const m = this.metrics();
    const against = (value: number | null | undefined, target: number): Verdict =>
      value === null || value === undefined ? 'unknown' : value >= target ? 'met' : 'below';
    return {
      calibration: against(m?.calibration.ratio, m?.targets.calibration ?? 1),
      concordance: against(m?.concordance.spearman, m?.targets.concordance ?? 1),
      retention: against(m?.retention_week4.ratio, m?.targets.retention_week4 ?? 1),
      routines: !m?.instructors.length
        ? ('unknown' as Verdict)
        : m.instructors.every((i) => i.published >= m.targets.routines_per_instructor)
          ? ('met' as Verdict)
          : ('below' as Verdict),
    };
  });

  ngOnInit(): void {
    this.panel.pilot().subscribe({
      next: (metrics) => this.metrics.set(metrics),
      error: (error: unknown) => this.error.set(apiError(error, 'No se pudieron cargar.')),
    });
  }

  rho(value: number): string {
    return value.toFixed(2).replace('.', ',');
  }

  tone(verdict: Verdict): string {
    return verdict === 'met' ? 'ok' : verdict === 'below' ? 'warn' : 'neutral';
  }

  label(verdict: Verdict): string {
    return verdict === 'met' ? 'Cumple' : verdict === 'below' ? 'Bajo la meta' : 'Sin datos';
  }
}
