import { ChangeDetectionStrategy, Component, computed, inject } from '@angular/core';
import { RouterLink } from '@angular/router';

import { LegalFrameComponent, LegalInfoService } from './legal-frame.component';

@Component({
  selector: 'sd-terms',
  imports: [RouterLink, LegalFrameComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <sd-legal-frame heading="Términos de uso">
      <h2>Qué es SyncDance</h2>
      <p>
        Una app para practicar baile: compara tu postura con la de un maestro y te da sugerencias.
        Está en etapa de piloto, así que algunas funciones pueden cambiar o fallar.
      </p>

      <h2>Tu cuenta</h2>
      <p>
        Usa datos verdaderos y no compartas tu contraseña: lo que se haga con tu cuenta es tu
        responsabilidad. Si tienes menos de 18 años, necesitas el permiso de tu madre, padre o
        tutor.
      </p>

      <h2>Practica con cuidado</h2>
      <p>
        Baila en un espacio despejado, con el teléfono firme, y detente si sientes dolor o mareo.
        SyncDance no es un servicio médico ni de fisioterapia: si tienes una lesión o una condición
        de salud, consulta a un profesional antes de practicar.
      </p>

      <h2>Puntajes y sugerencias</h2>
      <p>
        Los puntajes, las estrellas y los avisos son estimaciones automáticas a partir de la cámara.
        Pueden equivocarse con poca luz, ropa muy holgada o si no se te ve de cuerpo entero. Úsalos
        como guía, no como la evaluación de un profesor.
      </p>

      <h2>Contenido de los instructores</h2>
      <p>
        Cada instructor es responsable de las rutinas y los videos que publica, y de tener permiso
        para usar su música y su coreografía. No publiques contenido de otras personas sin su
        autorización. Podemos retirar contenido que infrinja derechos o estos términos.
      </p>

      <h2>Uso permitido</h2>
      <p>
        No intentes entrar a cuentas ajenas, sobrecargar el servicio ni copiar las rutinas para
        usarlas fuera de SyncDance.
      </p>

      <h2>Baja y suspensión</h2>
      <p>
        Puedes <a routerLink="/cuenta/borrar">borrar tu cuenta</a> cuando quieras. Podemos suspender
        las cuentas que no cumplan estos términos.
      </p>

      <h2>Privacidad</h2>
      <p>
        Cómo usamos tus datos se explica en la
        <a routerLink="/privacidad">política de privacidad</a>.
      </p>

      <h2>Cambios y contacto</h2>
      <p>
        Publicaremos aquí cada nueva versión con su fecha.
        @if (contact(); as email) {
          Para consultas escribe a <a [href]="'mailto:' + email">{{ email }}</a
          >.
        }
      </p>
    </sd-legal-frame>
  `,
})
export class TermsPage {
  private readonly legal = inject(LegalInfoService);
  readonly contact = computed(() => this.legal.info()?.contact_email ?? '');
}
