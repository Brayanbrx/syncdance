import { ChangeDetectionStrategy, Component, computed, inject } from '@angular/core';
import { RouterLink } from '@angular/router';

import { LegalFrameComponent, LegalInfoService } from './legal-frame.component';

@Component({
  selector: 'sd-privacy',
  imports: [RouterLink, LegalFrameComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <sd-legal-frame heading="Política de privacidad">
      <p>
        SyncDance es una app de Android para aprender a bailar: compara tu postura con la de un
        maestro usando la cámara del teléfono. Aquí explicamos qué datos usamos y para qué.
      </p>

      <h2>Quién es responsable</h2>
      <p>
        {{ controller() }} es responsable de tus datos.
        @if (contact(); as email) {
          Para cualquier consulta sobre ellos escribe a <a [href]="'mailto:' + email">{{ email }}</a
          >.
        } @else {
          El correo de contacto se publicará aquí antes del lanzamiento.
        }
      </p>

      <h2>La cámara</h2>
      <p>
        La app usa la cámara solo mientras practicas. El análisis de tu postura ocurre dentro de tu
        teléfono: ni imágenes, ni video, ni los puntos de tu cuerpo salen del teléfono o se guardan
        en nuestros servidores. La app no graba tu práctica.
      </p>

      <h2>Qué datos guardamos</h2>
      <ul>
        <li>
          <strong>Tu cuenta:</strong> usuario, correo, nombre y apellido si los das, y tu contraseña
          cifrada (nadie puede leerla).
        </li>
        <li>
          <strong>Resúmenes de tus prácticas:</strong> rutina, fecha, duración, velocidad, puntajes
          por tramo, por paso y por parte del cuerpo, los avisos que más recibiste, cuántas veces
          intentaste ubicarte frente a la cámara y, en el modo juego, tus estrellas y
          calificaciones. Se suben cuando hay conexión.
        </li>
        <li>
          <strong>Tus cursos:</strong> a qué cursos te uniste y las observaciones que te escribe tu
          instructor.
        </li>
        <li>
          <strong>Registros técnicos del servidor:</strong> dirección IP, fecha y página pedida,
          para seguridad y para resolver fallas.
        </li>
        <li>
          <strong>Informes de fallas de la app:</strong> si la app falla, envía el tipo de error, en
          qué parte del código ocurrió y las versiones de la app y del sistema. No incluyen tu
          cuenta, imágenes ni datos de tu cuerpo.
        </li>
        <li>Qué versión de estos textos aceptaste y cuándo.</li>
      </ul>

      <h2>Para qué los usamos</h2>
      <ul>
        <li>Darte acceso a tu cuenta y guardar tu progreso.</li>
        <li>Mostrar a tu instructor cómo avanzas en sus cursos.</li>
        <li>Enviarte el enlace para recuperar tu contraseña.</li>
        <li>Proteger el servicio y resolver fallas.</li>
      </ul>
      <p>No vendemos tus datos ni los usamos para publicidad.</p>

      <h2>Quién los ve</h2>
      <ul>
        <li>Tú.</li>
        <li>
          Los instructores de los cursos a los que te uniste: tu progreso, tus prácticas y tus
          puntajes. Si sales de un curso, ese instructor deja de verlos.
        </li>
        <li>Las personas que administran la plataforma, solo para operarla y darte soporte.</li>
        <li>
          Los proveedores que operan el servidor y el correo por nuestra cuenta, que no pueden
          usarlos para otros fines.
        </li>
      </ul>

      <h2>Cuánto tiempo los guardamos</h2>
      <p>
        Mientras tengas tu cuenta. Al borrarla eliminamos tu cuenta, tus prácticas y tus
        inscripciones; las copias de seguridad se renuevan y en unas dos semanas tampoco quedan en
        ellas. Las prácticas guardadas en tu teléfono se borran con la cuenta o al desinstalar la
        app.
      </p>

      <h2>Tus derechos</h2>
      <p>
        Puedes ver tu progreso en la app, pedirnos que corrijamos tus datos y borrar tu cuenta
        cuando quieras, desde <strong>Mi cuenta</strong> en la app o en
        <a routerLink="/cuenta/borrar">esta página</a>.
      </p>

      <h2>Menores de edad</h2>
      <p>
        Si tienes menos de 18 años necesitas el permiso de tu madre, padre o tutor para usar
        SyncDance.
      </p>

      <h2>Seguridad</h2>
      <p>
        Las conexiones van cifradas (HTTPS), las contraseñas se guardan cifradas, al cambiar la
        contraseña se cierran las sesiones abiertas y hacemos copias de seguridad diarias.
      </p>

      <h2>Cambios</h2>
      <p>Si cambiamos esta política publicaremos aquí la nueva versión con su fecha.</p>
    </sd-legal-frame>
  `,
})
export class PrivacyPage {
  private readonly legal = inject(LegalInfoService);
  readonly controller = computed(() => this.legal.info()?.controller ?? 'El equipo de SyncDance');
  readonly contact = computed(() => this.legal.info()?.contact_email ?? '');
}
