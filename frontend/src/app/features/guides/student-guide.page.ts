import { ChangeDetectionStrategy, Component } from '@angular/core';
import { RouterLink } from '@angular/router';

import { GuideFrameComponent } from './guide-frame.component';

@Component({
  selector: 'sd-student-guide',
  imports: [RouterLink, GuideFrameComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <sd-guide-frame heading="Cómo empezar a bailar con SyncDance">
      <p class="lead">
        La app te muestra la coreografía de tu instructor y, con la cámara, te dice en qué pasos te
        acercas y en cuáles todavía no.
      </p>

      <h2>La primera vez</h2>
      <ol>
        <li>
          <strong>Instala la app.</strong> Desde tu teléfono Android abre la
          <a routerLink="/">página de SyncDance</a> y toca «Descargar para Android». Si el teléfono
          pregunta, permite instalar apps desde el navegador.
        </li>
        <li>
          <strong>Crea tu cuenta.</strong> En la app toca «Crear cuenta». Si tienes menos de 18
          años, hazlo con permiso de tu madre, padre o tutor.
        </li>
        <li>
          <strong>Únete a tu curso.</strong> En «Mis cursos», escribe en «Código del curso» el
          código que te dio tu instructor y toca «Unirme».
        </li>
      </ol>

      <h2>Cada vez que practiques</h2>
      <ol>
        <li>
          <strong>Prepara el lugar.</strong> Apoya el teléfono de pie, a 2 o 3 metros, con buena luz
          y espacio libre alrededor. Solo tú debes aparecer en la imagen.
        </li>
        <li>
          <strong>Elige la rutina.</strong> En «Mis cursos», toca el botón para bailar la rutina. La
          primera vez se descarga el video: mejor con wifi.
        </li>
        <li>
          <strong>Ubícate.</strong> La app te indica cómo moverte hasta verte de cuerpo entero.
          Cuando te ve bien, empieza sola la cuenta regresiva: no hace falta tocar el teléfono.
        </li>
        <li>
          <strong>Baila y mira tu resultado.</strong> Cada movimiento recibe una calificación y al
          final ves tus estrellas.
        </li>
      </ol>

      <h2>Aprende un paso a la vez</h2>
      <p>
        Si tu instructor marcó los pasos, entra en «Rutinas», abre la rutina guardada y toca «Abrir
        maestro»: ahí aparece «Pasos de la rutina». «Practicar» repite ese paso en bucle, más lento,
        con las cuentas en pantalla («5, 6, 7, 8»). Cuando te salga, súbelo a velocidad normal.
      </p>

      <h2>Tu progreso</h2>
      <p>
        Tus prácticas se envían solas cuando hay internet. Tu instructor ve cómo te va en cada paso
        y puede dejarte observaciones: las encuentras en «Mis cursos».
      </p>

      <h2>Tu imagen no sale del teléfono</h2>
      <p>
        La cámara se analiza dentro del teléfono. Al servidor llegan solo los resultados de cada
        práctica, nunca fotos ni video. Más detalles en la
        <a routerLink="/privacidad">política de privacidad</a>.
      </p>
    </sd-guide-frame>
  `,
})
export class StudentGuidePage {}
