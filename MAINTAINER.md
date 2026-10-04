> Para: mantener Creator y aprobar visuales en Color Lights. Lee esta guía si eres responsable de la integración o del motor.

# Mantenimiento e integración

Para crear un visual con una IA, sigue el [README principal](README.md).
Esta guía corresponde al responsable de la app; el colaborador puede completar
su trabajo sin ejecutar comandos de aprobación ni abrir Color Lights.

El alcance verificado y los gates físicos pendientes están en [VERIFICATION.md](VERIFICATION.md).

## Herramientas y archivos

La versión verificada es Flutter **3.44.5 stable**. Para iOS se necesita macOS,
Xcode y CocoaPods; el destino mínimo es iOS 15. Los paquetes declaran Dart >=3.7
y el SDK gráfico Flutter >=3.29; esos límites no certifican el proyecto nativo
completo en versiones anteriores.

La plantilla incorpora el contrato de respuesta para la IA: el colaborador
sólo añade una descripción creativa. Esto orienta al modelo, no garantiza que
obedezca. Antes de importar archivos de autor, `compile_visuals.dart` aplica la
misma validación de envoltorio Dart que la revisión de entrada a la app, desde
`scene_compositor/lib/src/creator_source_admission.dart`. Rechaza declaraciones
extra y formatos ajenos con el nombre del archivo; no ejecuta una respuesta
rechazada. Después se verifican metadata, recursos y compilación para la
plataforma. La revisión nativa ejecuta el programa en otro proceso con timeout,
ASan y UBSan; esto detecta errores, pero no es un sandbox ni una certificación térmica.
Los errores de validación de la generación no reemplazan parcialmente los
assets runtime. El fallo sigue bloqueando el build: corregir y volver a ejecutar.

El archivo creativo declara `const nativeSource`, un programa C++17 con
`Visual : Scene`: `reset(seed)`, `update(frame)` y `render(frame, canvas) const`.
Cada reproducción posee su instancia. El SDK prepara tiempo, controles, señales,
imágenes y materiales; el visual no necesita sensores ni servicios de la app.
Un mapa opcional `shaderSources` permite materiales GLSL completos compilados
por el compilador real de Flutter. El primer uniform es `vec2 uSize`; después,
float/vec2/vec3/vec4 y sampler2D. Las coordenadas son píxeles locales, las imágenes
se enlazan por clave y el material devuelve RGBA premultiplicado. No hay acceso
al fotograma anterior ni compute shaders.

`const metadata = CreatorVisualMetadata(...)` vive en el compañero. Los visuales
anteriores con `shaderSource` y `paintVisual` siguen funcionando. Se aceptan
hasta 256 pares y `_metadata.dart` queda reservado para metadata. La plantilla
se genera del bloque AUTHOR API de `scene_program_native/src/creator_scene.hpp`
y `templates/visual_template_body.cpp`; `generate_template.dart --check` y CI
comprueban la referencia y la compilación del ejemplo.

Para imágenes, guardar PNG/JPG/WebP en `visual_catalog/assets/images/` y declarar
`images: {'planet': 'assets/images/planet.png'}` en metadata. `canvas.image` y los
samplers usan esa clave. Se conservan los bytes y hashes en la aprobación;
los recursos se cargan por sesión, con límites por imagen y memoria total.

En metadata, `purposes`, `moods` y `concepts` clasifican el visual; `credits`
conserva autor, licencia y origen. Los controles `intensity`, `speed` y `glow`
admiten 0–2; `detail`, 0.25–2. Mantener cuatro colores ARGB. La publicación es
una etiqueta editorial: ninguna de sus opciones concede aprobación.

## Modificadores

Un visual nativo declara sus propios ajustes y variaciones en el archivo del
código, antes de `nativeSource`. Los escribe la IA (la plantilla lo pide
siempre) y el colaborador pega un solo archivo:

```dart
import 'package:scene_compositor/authoring.dart';

const modifiers = [
  CreatorModifier.steps('brazos', 'Brazos', min: 2, max: 8, value: 4),
  CreatorModifier.choice('pulso', 'Pulso', options: ['Graves', 'Golpes', 'Brillos']),
  CreatorModifier.slider('estela', 'Estela', min: 0, max: 1, value: .35),
  CreatorModifier.toggle('espejo', 'Espejo'),
];
const variations = [
  CreatorVariation('Tormenta', {'brazos': 8, 'pulso': 'Golpes', 'speed': 1.4}),
];
```

En C++: `auto m = modifiers(f)` para decidir (tipado y acotado) y
`auto g = glide(f)` para transformarse (decimales que se deslizan, toggle
0..1, `g.pulso.weight(i)` para fundir opciones).

- **Admisión** (`creator_source_admission.dart`): sólo literales, en cualquier
  orden y una vez cada bloque. Fuera de los textos admite las palabras del
  constructor, números (también `1e-3`, `0x10`, `1_000`), `true`/`false`; sin
  `;` ni `$` en los textos. El import es obligatorio con un bloque y se rechaza
  sin ninguno. Nada se ejecuta al descubrir archivos.
- **Validación** (`creator_visual_definition.dart`, `creator_variation.dart`):
  sólo `nativeSource`; máximo 8 modificadores y 4 variaciones; id
  `^[a-z][a-z0-9_]{0,23}$`, único y fuera de `creatorReservedModifierIds`
  (básicos, `colors`, `music`, `glide`, `color0..3`, palabras y macros de C++);
  rangos dentro de ±100000, `steps` con hasta 1000 pasos; `choice` con 2 a 8
  opciones; valores iniciales y de variaciones en rango; una variación debe
  diferir del original y se nombra el choice por el texto de su opción.
- **Cable**: un float por modificador, en orden de declaración. `cp_configure`
  acepta 20 floats (valores iniciales) o 20+N. ABI 1, sin tocar el SDK.
- **Transiciones (`glide`)**: sólo para visuales con modificadores,
  `native_compiler.dart` genera `CreatorGlideScene_`, que envuelve al `Visual`
  del autor y suaviza los valores (constante de 0,25 s; choice con fundido de
  0,45 s). Instantáneo al crear, al reiniciar, en pausa (render sin update) y
  con movimiento reducido. Para los demás, `creator_programs.inc` sale byte a
  byte igual.
- **Contrato**: el hash nativo cuenta `creatorGlideRuntime` y sólo
  id/tipo/rango/valor (los textos no recompilan). Una huella del C++ generado
  (`_glideGolden` en `creator_visual_definition_test.dart`) obliga a subir
  `creatorGlideRuntime` si cambia el generador. El manifest está congelado:
  `modifiers` sólo si hay y con las claves exactas que acepta Swift (prueba
  espejo); lo que es sólo de interfaz (variaciones) va en `toMetadata`.
- **Revisión al compilar** (`creator_lint.dart`, sólo en
  `build_catalog_assets.dart` y en la aprobación, nunca en el teléfono): cada
  id debe aparecer en el C++ fuera de comentarios y textos (cualquier uso
  cuenta; el barrido decide si cambia algo); nada de `f.modifiers[…]`; ningún
  nombre visible que repita un básico. La admisión revisa la forma exacta de
  `const variations` para que un mapa mal escrito no rompa todo el catálogo.
- **Barrido nativo** (`authored_probe.cpp` con `creator_probe_cases.inc`,
  generado sólo para pruebas): con la música sintética «fuerte» (empieza donde
  hay música, golpes a fuerza 1 y un destello en cada pulso), 3 s comparando
  todos los cuadros: mínimo, máximo, cada opción y estado, todos al
  mínimo/máximo, 8 combinaciones, cada variación, un cambio en vivo y la regla
  de 30/60 FPS con valores no iniciales. Un visual con `reactivity: none` se
  barre sin música, como lo toca la app. Revienta o presupuesto: falla. «No
  cambia nada»: aviso en CI para los borradores (falla si es la plantilla o un
  visual de prueba) y error en la aprobación (`--strict-modifiers`). Todos los
  visuales se revisan aunque uno falle; los topes de tiempo crecen con el
  catálogo.
- **En vivo**: `setModifiers` y `setPalette` en `SceneCompositorController`.
  Android escribe los floats y reconfigura sin reiniciar; iOS manda
  `updateDocument` (`controlIdentity` ignora `options`, así que no reinicia).
- **Paleta en vivo**: `color0..color3` (ARGB) en las opciones del documento
  reemplazan los colores y el relleno de fondo; sin esas claves, Swift y
  Android producen exactamente los colores del catálogo. Sólo visuales nativos.
- **Studio** (`studio/lib/studio/adjustments/`): sesión por visual durante la
  sesión de Studio, variaciones del autor y propias (`SharedPreferences`,
  `creator.variations.<id>`), Variar/Sorprender/Deshacer, paleta, semilla,
  comparar con el original y «Copiar para la IA». El voto es del original.
- **Voto**: la versión incluye los modificadores (sin textos) sólo si existen;
  las variaciones y la paleta no cuentan.
- **Color Lights**: `creator_review.dart` arma el visual con
  `creatorVisualExpression` (la misma que Studio), corre la revisión y el
  barrido estricto. La app todavía no muestra modificadores, variaciones ni
  paleta: cada visual se ve con sus valores iniciales.

## Miniaturas

La miniatura automática usa una instancia aislada: reproduce semilla y señales
a pasos conocidos en un isolate, y sólo dibuja el fotograma final. Se genera
una vez por configuración y se conserva en una caché acotada; las tarjetas no
mantienen una animación ni un micrófono. La plantilla selecciona 2,5 segundos.

Para una imagen propia, colocar el archivo en
`packages/visual_catalog/assets/thumbnails/` y configurar la metadata:

```dart
thumbnail: CreatorThumbnailSpec(
  assetPath: 'assets/thumbnails/olas.png',
  assetPackage: 'visual_catalog',
),
```

Se admiten PNG, JPG/JPEG y WebP. La aprobación conserva los bytes de la imagen
junto a esa versión del visual; el límite de admisión es 4 MB.

## Datos musicales y rendimiento

`CreatorReactivity.none` impide activar la reacción; `.music` impide desactivarla;
`.optional` ofrece el interruptor. El estado de render aplica estas reglas en
ambas plataformas. Los valores musicales quedan en cero al desactivar la
reacción o faltar autorización musical; el tiempo de ambiente es independiente.
Esto controla entradas futuras; las partículas existentes continúan por inercia.
Cambiar controles, reacción o tamaño conserva la instancia. Un reinicio o loop
de grabación restablece el estado. El programa debe usar las señales para reaccionar.

La demo incluida está identificada como **sintética**. Usa el contrato binario
real de 520 bytes, pero no es una grabación del sensor. No se entrega una captura
real ni audio. Para probar una captura existente, coloca `signals.bin` y
`timeline.json` juntos en `studio/recordings/<nombre>/` y vuelve a ejecutar el
build. El replay conserva valores, orden, semilla y seriales; al repetir un loop
reinicia el estado del visual. La programación de cada dispositivo puede
introducir diferencias de presentación.

iOS ejecuta el programa C++ desde la cola de SceneSurface V1, sin llamar a Dart
por fotograma; Android ejecuta el mismo programa por FFI y dibuja sus comandos
sobre Canvas/FragmentProgram. Se conservan el compositor y su propietario del
reloj. El valor predeterminado es 30 FPS; 60 es una solicitud, no una garantía.
El compositor iOS reduce cadencia con estado térmico o bajo consumo; Android
mantiene el perfil de calidad recibido y un target máximo de 1024 píxeles.
Los grupos de opacidad se componen como capas, y las partículas se dibujan por
lotes. No hay lectura de píxeles a CPU por fotograma durante la reproducción.

Studio expone PiP en iOS mediante la continuación nativa del compositor. Mientras
PiP mantiene la sesión, el programa nativo continúa sin ticker Dart; la demo
sintética sólo alimenta señales mientras Flutter está activo. El audio real de
producción conserva su autoridad existente. Una compilación o simulador no
certifica PiP en segundo plano, consumo ni temperatura: requieren hardware.

### Panel de rendimiento

El panel de arriba a la izquierda (`studio/lib/performance/`) muestrea cada
segundo. Cada número es una diferencia entre dos lecturas de la misma sesión de
superficie: al cambiar de visual, pista o tamaño, la ventana se descarta.

- **CPU app**: `clock_gettime` del proceso por FFI
  (`scene_compositor/lib/src/cpu_clock.dart`; Darwin usa los ids 12/16 y
  Linux/Android 2/3). Cuenta todo el proceso: UI, raster y cola nativa.
- **Del visual**: CPU reproduciendo menos CPU en pausa. Solo cuenta como pausa la
  del usuario con el visual ya cargado, nunca la carga. Las ventanas que cambian
  de estado no se comparan.
- **iOS**: una sonda nativa por segundo (`startPerformanceProbe` /
  `stopPerformanceProbe`) da promedio, p95 y tirones (cuadros que pasan 1,1× el
  presupuesto). Los FPS salen de `publishedFrameCount` y `sampleTimeSeconds` de
  `activeSurfaceForScene`. El C++, el target y la temperatura salen de
  `creatorPrograms`, que solo llenan los programas nativos. El tiempo de cuadro
  incluye la espera de la GPU porque el render es síncrono (`waitUntilCompleted`),
  así que no se separa CPU de GPU. Las claves `gpu*` de esa respuesta solo miden
  la copia final de Core Image: no son la GPU del visual y el panel no las usa.
- **Android**: CPU del hilo Dart por cuadro (simulación C++ por FFI, comandos y
  grabación del Canvas), con `clock_gettime` del hilo. El raster y la GPU no
  entran. La GPU no se puede medir desde la app (Impeller; `toImage` no espera a
  la GPU); para eso están Android GPU Inspector o Perfetto.
- La contabilidad de Android está apagada por defecto
  (`AndroidCreatorSession.measureCost`): Color Lights usa la misma sesión sin
  coste extra; solo el estudio la enciende con `measureRenderCost`.
- Debug infla todo (Dart JIT, Swift sin optimizar) y el panel lo avisa. Para
  medir: `flutter run --profile` en hardware.
- Pendiente de decisión: separar CPU y GPU por cuadro en iOS requiere tocar el
  runtime Swift que también usa Color Lights.

## Votación del equipo

Las notas del 1 al 10 viven en Chic Team (proyecto `chic-ads`), no en el repo.
El estudio llama por HTTPS a `/api/creator-review` con una clave personal
(`clr_…`); no usa Firebase ni cuentas. Las claves se crean y revocan en
`chic-ads.web.app/team` → Color Lights → **Evaluación**, donde está también el
ranking y la exportación a CSV. Revocar una clave conserva sus votos.

- Cada voto corresponde a un visual y a su **versión**:
  `studio/lib/team_review/visual_revision.dart` calcula una huella del código,
  los materiales, las imágenes y los parámetros de render (incluidos los
  modificadores, si tiene). El nombre y la descripción no cuentan.
- Las notas del equipo de una versión se ocultan hasta que la persona vota.
- El voto se elige y luego se **confirma**. Cambiarlo es una **función oculta**
  a propósito: hay que mantener el voto presionado 3 segundos
  (`hiddenVoteChangeHold` en `team_rating_panel.dart`). Ningún texto lo anuncia,
  la guía de colaboradores no lo menciona y un toque o una pulsación larga normal
  no hacen nada. El gesto deselecciona el voto y la nota nueva lo reemplaza al
  confirmarla (`POST /ratings` con `change: true`; sin esa marca el servidor
  responde `vote-final`). El voto anterior vale hasta esa confirmación y el
  comentario se conserva. Quien cambia ya vio las notas del equipo: es una
  corrección, no un voto a ciegas. El responsable también puede borrar un voto en
  Chic Team → Evaluación → ↺ («Reiniciar voto»).
- La barra **Pruébalo con** (encima del voto) cambia de pista o pasa a silencio
  con un toque; reemplaza al selector escondido de «Señal de audio».
- El estado sale **solo del promedio** y con **al menos 2 votos**
  (`teamMinimumVotes`): ≥ 7 Aprobado, 5–6,9 «Descarte pero tiene potencial al
  mejorar», < 5 Descarte total; con un solo voto queda «Faltan votos». Los
  umbrales viven en `team_ranking.dart`; el servidor de `chic-ads` repite el
  mínimo y el corte de 5 para marcar los descartes que la persona aún no ve.
- La cola **Faltan N** omite lo que el equipo ya dejó en Descarte total. Si el
  autor cambia el dibujo, es otra versión y vuelve a la cola.
- El ranking (`team_ranking.dart` y `team_ranking_screen.dart`) tiene una fila
  por visual del catálogo actual: lista en el celular y tabla por persona en
  pantallas anchas.
- Ya no hay curaduría local: Studio no tiene botones «Aprobar/Descartar» ni
  `creator_curation_review.json` (su historial queda en git). Tu única decisión
  es meter un visual en Color Lights con `creator_review.dart`, y solo para los
  que el equipo dejó en Aprobado.
- Para probar contra otro servidor:
  `flutter run --dart-define=CREATOR_REVIEW_URL=<url>/api/creator-review`.

## Entregar y actualizar la app

Comparte los dos archivos del visual y, si existe, su miniatura propia mediante Git.
Todo aparece automáticamente en **Creator**. Color Lights utiliza un catálogo
separado con copias de las versiones aprobadas por el responsable de la app.
Los borradores no entran en la app principal, ni siquiera en debug. Un borrador
roto tampoco participa en su compilación.

En el workspace de Color Lights, el responsable ejecuta desde `minibase/`:

```sh
dart run tool/creator_review.dart list
dart run tool/creator_review.dart validate olas
```

La validación comprueba el par seleccionado, la metadata, recursos y el shader combinado
con los aprobados y su compilación Metal/GLES/GLES3/Vulkan; también renderiza
el candidato con Metal en la Mac. Requiere macOS, Xcode y el Dart de Flutter.
Los programas C++ pasan también ASan/UBSan y replay determinista en proceso
separado. Para escenas con estado se comparan historias equivalentes con música,
sin música y con reacción apagada desde el inicio; no se exige borrar partículas
al apagarla a mitad de reproducción. Para los shaders anteriores se comparan
píxeles manteniendo fijo el tiempo: tres instantes y dos
intensidades sintéticas del contrato real. Comprueba música, silencio, señal no
disponible y apagado opcional. Un visual `.none` debe conservar la misma imagen;
uno `.music` u `.optional` debe demostrar algún cambio con música y conservar
el resultado ambiental cuando la señal no está autorizada. Si no demuestra
reacción, bloquea la aprobación con un mensaje para corregir el dibujo o
declararlo ambiental. El recibo exige `reactivityProbed`; los recibos antiguos
requieren repetir `validate`. Las versiones ya aprobadas no se modifican.
Estas muestras no certifican todas las canciones, controles o condiciones,
ni la calidad perceptual de la reacción.

La aprobación se hace mediante comandos, para los visuales que el equipo dejó
en Aprobado en el ranking de Studio. `validate` devuelve una revisión exacta y el comando `approve … --revision … --reviewed`.
El responsable lo ejecuta **después de revisar aspecto, transparencia, música
y rendimiento físico**. Compilar no decide si un visual es bueno.

La aprobación guarda código, metadata, materiales, imágenes y miniatura en
`metadata/creator_catalog/approved/`, fuera de este repositorio. Al recompilar
Color Lights aparece automáticamente en fondos o transparencias según `role`.
Si el colaborador cambia algo después, queda pendiente otra revisión; la app
conserva la versión aprobada. `revoke <id>` retira una aprobación en el siguiente
build. Cambiar `publication` nunca sustituye estos pasos.

Una versión aprobada conserva su ID y su tipo (fondo o transparencia) para no
romper escenas guardadas. Si quieres otro tipo, crea otro par con un ID nuevo.

La colaboración sobre visuales se limita a `packages/visual_catalog/` y las
plantillas; los cambios al compositor y al contrato compartidos requieren su
propia revisión. El almacén de aprobaciones debe permanecer bajo control del
responsable de Color Lights. Una huella detecta cambios, no reemplaza permisos
del repositorio ni constituye una firma.

La aplicación debe sincronizar este repositorio y compilar nuevamente. Un
commit o push no modifica una app ya instalada, y el manifiesto remoto nunca
transporta shaders nuevos ni código ejecutable.

Para entregar una copia portable sin Git, desde `studio/` ejecuta:

```sh
dart run tool/export_kit.dart
```

Genera una carpeta y un zip en `dist/`, sin cachés ni configuración de la
máquina. Abre `studio/` dentro de la copia y ejecuta `flutter pub get`.

## Estructura y comprobaciones

| Ruta | Responsabilidad |
| --- | --- |
| `studio/` | Aplicación, controles y selección de señales. |
| `templates/visual_template.dart` | Plantilla de código que se copia a la IA. |
| `templates/visual_template_metadata.dart` | Plantilla separada de datos y configuración. |
| `packages/visual_catalog/` | Archivos creativos, metadata y catálogo completo del estudio. |
| `packages/scene_program_native/` | Programa C++ compartido, ABI y validación de comandos. |
| `packages/scene_compositor/` | Compositor, render, recursos y miniaturas. |
| `packages/scene_compositor_host/` | Registro nativo exclusivo del estudio en iOS. |
| `packages/visual_contract/` | Codec y replay; Dart puro, sin sensores. |

Las fases nativas iOS/Android de Studio ejecutan `studio/tool/compile_visuals.dart` antes
de empaquetar los assets. Primero descubre archivos y genera el registro; luego
valida y genera JSON/shaders. La app carga los assets empaquetados, evitando que
un registro Dart antiguo compita con la generación del build.

Para comprobar tus archivos sin abrir el estudio, ejecuta desde `studio/`:

```sh
dart run tool/compile_visuals.dart
```

Revisa pares incompletos, estructura, IDs, rangos y restricciones del catálogo y muestra cuántos
visuales encontró. **Run ejecuta este mismo paso automáticamente**, además de
compilar los assets; la vista previa comprueba la carga del programa. Editar
`templates/visual_template.dart` no registra un visual: guarda la respuesta de
la IA en `packages/visual_catalog/lib/visuals/olas.dart`, acompañada de
`olas_metadata.dart`. Dibujo y metadata se mantienen separados; el generador
los une para producir el contrato que ya consume Color Lights. Compilar correctamente no certifica rendimiento sostenido.

CI comprueba generación reproducible, contratos y tests Flutter. Para revisar
el catálogo en una Mac con Metal disponible:

```sh
ruby packages/scene_compositor/ios/Tests/check_creator_catalog.rb \
  packages/visual_catalog/assets/creator_catalog.json
```

Esa prueba compila los shaders reales, examina sus píxeles y ejecuta las mismas
comparaciones de reacción. No equivale a una
prueba térmica ni garantiza igualdad de píxeles entre iOS y Android.

Para verificar escenas completas con Metal:

```sh
python3 packages/scene_program_native/test/check_native.py --generated studio/build/creator_native
python3 packages/scene_compositor/ios/Tests/check_creator_scenes.py --generated studio/build/creator_native --catalog packages/visual_catalog/assets/creator_catalog.json --output /tmp/creator-metal
```

La preparación tiene un lock por aplicación y reemplazo atómico de cada archivo.
El registro compilado y el catálogo comprueban hashes antes de reproducir;
una discrepancia es un error visible, no una sustitución por una versión anterior.
Las salidas C++ viven en `build/creator_native/<configuración>` de cada aplicación;
las herramientas manuales usan la raíz `build/creator_native`. No compartir
ese directorio entre aplicaciones ni copiar binarios generados a mano.
