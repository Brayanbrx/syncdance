# Fase 5 · Pasos 1–2 — indicaciones geométricas y resaltado

Implementado el 2026-10-02. En **Practicar con cámara**, después de calibrar y
reproducir el maestro, se muestra como máximo una tarjeta de corrección.
Funciona localmente, sin LLM, red, audio ni vibración.

## Evidencia y catálogo

`PoseMatch.referenceSample` conserva la muestra exacta elegida por la comparación
conjunta. `FeedbackRules` (`geometric-feedback-v2`, antes v1) compara esa muestra con las
features del mismo frame del alumno, sin suavizado de presentación. Solo se
invoca cuando hay un match completo y el quality gate/calibración permiten medir.
No calcula otro alineamiento temporal ni usa una muestra distinta para aconsejar.

Cada candidato contiene código, región, métrica, magnitud, umbral, severidad
(magnitud/umbral) y mensaje. Los umbrales iniciales requieren validación física:

| Métrica | Entrada | Acción según diferencia con el maestro |
| --- | --- | --- |
| Ángulo de cada codo/rodilla | 20° | Extender o flexionar la articulación del lado indicado |
| Altura de cada muñeca desde las caderas | 0.25 largos de torso | Subir o bajar la mano del lado indicado |
| Separación horizontal entre tobillos | 0.30 largos de torso | Separar o acercar los pies |
| Diferencia de inclinación proyectada del torso | 15° | Ajustar la inclinación para seguir al maestro |

Se conservan los lados anatómicos aunque la preview esté espejada. La coordenada
vertical crece hacia abajo: una muñeca más baja que la referencia solicita subir
la mano. Las indicaciones describen geometría 2D relativa al maestro, no diagnósticos
ni restricciones biomecánicas. No se deduce la inclinación 3D de estas medidas.

## Paso 2 — torso y articulaciones resaltadas

Se mide la dirección del vector centro de caderas → centro de hombros mediante
`atan2(x, -y)` en coordenadas corporales. La diferencia maestro menos alumno se
envuelve a ±180° antes de tomar su magnitud; no se convierte un cruce 179°/−179°
en un error de 358°. Los vectores degenerados no generan corrección de torso.
Dos torsos con la misma inclinación no reciben un aviso aunque no estén verticales.
El signo separa los códigos `torso_clockwise`/`torso_counterclockwise` para reiniciar
persistencia ante cambio de dirección; ambos comparten región y cooldown.
El texto no prescribe izquierda/derecha anatómica ni movimiento hacia delante/atrás:
la pose proyectada no certifica frontalidad ni inclinación 3D.

Cada aviso lleva un conjunto inmutable de puntos: hombro/codo/muñeca para un
codo; cadera/rodilla/tobillo para una rodilla; muñeca para altura de mano;
ambos tobillos para separación; hombros y caderas para torso. Solo el aviso
activo aporta resaltado. Los aros amarillos con contorno oscuro no sustituyen
los colores anatómicos del esqueleto y usan exactamente su proyección y espejo.
Se omiten puntos fuera de imagen, ausentes o de confianza inferior a 0.5.
La pantalla añade el requisito de quality gate/calibración vigente. El texto y
los aros desaparecen juntos cuando el aviso se retira, aunque la pose no cambie.
Si el esqueleto está oculto por encuadre incompatible, tampoco aparecen los aros;
el mensaje textual puede seguir orientando sin inventar una transformación visual.

## Persistencia, prioridad y descanso

`LiveFeedback` requiere que cada error alcance el umbral durante al menos 400 ms,
con cuatro muestras distintas y huecos de captura de como máximo 250 ms.
Los timestamps duplicados o atrasados no suman evidencia. Un hueco mayor reinicia
la persistencia. El tiempo de captura mide evidencia; un reloj monotónico local
controla visualización y cooldown incluso tras reiniciar la cámara o saltar video.

Entre candidatos elegibles gana la mayor severidad; un empate se resuelve por
código para mantener resultados deterministas. Un aviso activo no se reemplaza
por otro mientras conserve evidencia. Para evitar parpadeo cerca del umbral,
permanece hasta que su magnitud cae por debajo del 60 % del umbral de entrada,
desaparece o cambia la dirección de la diferencia.

La duración objetivo de una tarjeta es 1200 ms, revisada en cada nueva muestra.
Entre inicios de tarjetas hay al menos 1500 ms. Tras retirar un aviso, su región
descansa otros 1500 ms, también para un aviso contrario (mano y codo comparten
región del brazo). La pausa, salto, buffering, pérdida de calidad, recalibración,
cambio de cámara/orientación o expiración del score retiran la tarjeta y borran
evidencia pendiente. A los 250 ms sin score nuevo se retira cualquier aviso;
no se deja una corrección obsoleta a la espera de otra inferencia.
Las interrupciones conservan el cooldown. Una nueva práctica/referencia comienza
con otro controlador. Desde Fase 6, paso 1, cada aviso nuevo también alimenta un
conteo agregado por código en el resumen local, sin guardar frames ni poses.

## Validación y límites

144 pruebas Flutter aprobadas; análisis estático y formato sin incidencias.
APK Android debug compilado; no se instaló ni validó en el teléfono.
Las pruebas verifican signos/lados, geometría de manos/pies, referencia temporal
común, persistencia, prioridad, histéresis, cooldown, gaps y timestamps duplicados.
El widget integrado calibra, reproduce, acumula evidencia, muestra una corrección
y la retira al pausar. La suite usa cámara/reproductor simulados.
El paso 2 añade pruebas de inclinación relativa, cruce ±180°, conjuntos inmutables,
proyección espejada de aros, omisión de puntos inválidos y retirada conjunta de
texto/resaltado. Las pruebas de dibujo inspeccionan coordenadas, color y forma.

Pendiente en teléfono: contrastar cada mensaje con un maestro controlado, cambiar
de ejecución correcta a incorrecta, cruzar umbrales lentamente y comprobar la
estabilidad de lectura. Probar pausa/salto/background, pérdida de pose y cámara
con video simultáneos. Registrar latencia y falsos avisos antes de ajustar umbrales.

Este paso no completa la validación de Fase 5. Adelanto/atraso requiere una métrica temporal
validada: el offset del matcher no se presenta como error de ritmo. El resumen
ya conserva avisos frecuentes e historial local desde Fase 6, paso 1;
ver `../history/README.md`, que también describe la sincronización. La
validación física de Fases 1–6 sigue pendiente.

Prueba física adicional: seguir una inclinación igual a la del maestro, inclinar
en sentidos distintos y volver a coincidir. Verificar que los aros señalen el
lado anatómico correcto en la preview frontal y que se retiren al pausar,
perder encuadre o cambiar de orientación. No aprobar alineación por pruebas sintéticas.
