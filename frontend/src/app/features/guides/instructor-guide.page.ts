import { ChangeDetectionStrategy, Component } from '@angular/core';
import { RouterLink } from '@angular/router';

import { GuideFrameComponent } from './guide-frame.component';

@Component({
  selector: 'sd-instructor-guide',
  imports: [RouterLink, GuideFrameComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <sd-guide-frame heading="Guía para instructores">
      <p class="lead">
        Sube tus coreografías, divídelas en pasos y mira en cuáles les cuesta más a tus alumnos.
      </p>

      <h2>Antes de empezar</h2>
      <ol>
        <li>
          <strong>Tu cuenta.</strong> La crea un administrador de SyncDance. Entra en
          <a routerLink="/ingresar">Ingresar</a>: te lleva a tu estudio.
        </li>
        <li>
          <strong>Tu curso.</strong> En «Administrar cursos», agrega un curso con su nombre. Te da
          un código para unirse: compártelo con tus alumnos junto con la
          <a routerLink="/guia/alumnos">guía para alumnos</a>.
        </li>
      </ol>

      <h2>Graba la coreografía</h2>
      <ul>
        <li>De frente a la cámara, de cuerpo entero y con la cámara fija.</li>
        <li>Buena luz y solo tú en la imagen, sin espejos ni gente atrás.</li>
        <li>Entre 5 segundos y 5 minutos; MP4, MOV, WEBM o MKV de hasta 200 MB.</li>
        <li>Con música propia, con licencia o libre de derechos.</li>
      </ul>

      <h2>De tu video a tus alumnos</h2>
      <ol>
        <li>
          <strong>Súbela.</strong> En el estudio, «Subir rutina». En un par de minutos queda
          procesada: el informe «Cómo se ve tu cuerpo en el video» marca los tramos donde no se te
          ve bien. Si son muchos, graba de nuevo esos tramos.
        </li>
        <li>
          <strong>Marca el compás y los pasos.</strong> En «Compás y pasos», reproduce el video y
          toca «Tiempo» (o la tecla T) en cada tiempo desde el primer 1. Después agrega cada paso
          donde empieza, con un nombre y un consejo breve. Una rutina de un minuto suele tener de 6
          a 10 pasos.
        </li>
        <li>
          <strong>Publícala en tu curso.</strong> Elige el curso, indica de dónde es la música y
          toca «Publicar». Tus alumnos la ven en «Mis cursos» de la app.
        </li>
        <li>
          <strong>Ponle una meta (opcional).</strong> En «Administrar cursos» puedes asignarla como
          tarea con un objetivo de estrellas y una fecha.
        </li>
      </ol>

      <h2>Sigue a tu curso</h2>
      <p>
        En «Mis cursos» del estudio, cada curso muestra dónde les cuesta: el último resultado de
        cada alumno en cada paso y, con 3 alumnos o más, los errores que más se repiten. Califica
        sus prácticas de 1 a 5 según tu criterio: solo tú lo ves y sirve para comprobar si la app
        coincide contigo. Si agregas un comentario, el alumno lo lee en la app.
      </p>

      <h2>Durante el piloto</h2>
      <ul>
        <li>
          Cada participante firma el
          <a routerLink="/piloto/consentimiento">consentimiento del piloto</a> (quien tenga menos de
          18 años, con su madre, padre o tutor).
        </li>
        <li>Publica al menos 3 rutinas en las 6 semanas.</li>
        <li>Califica unas 10 prácticas de tus alumnos a velocidad normal.</li>
        <li>Al final te pediremos una entrevista corta sobre tu experiencia.</li>
      </ul>
    </sd-guide-frame>
  `,
})
export class InstructorGuidePage {}
