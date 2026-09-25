> Para: mantener Creator y aprobar visuales en Color Lights. Lee esta guía si eres responsable de la integración o del motor.

# Mantenimiento e integración

Para crear un visual con una IA, sigue el [README principal](README.md).
Esta guía corresponde al responsable de la app; el colaborador puede completar
su trabajo sin ejecutar comandos de aprobación ni abrir Color Lights.

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
rechazada. Después se verifican metadata, restricciones del shader y compilación
para la plataforma. No es una certificación estética, térmica ni un sandbox GPU.
Los errores de validación de la generación no reemplazan parcialmente los
assets runtime. El fallo sigue bloqueando el build: corregir y volver a ejecutar.

El par de autoría mantiene `const shaderSource` en el archivo de código y
`const metadata = CreatorVisualMetadata(...)` en el archivo de datos. El dibujo
es GLSL portable dentro de Dart; no es un widget Flutter arbitrario. Los archivos
se relacionan por nombre, sin imports entre ellos ni registro manual. Se aceptan
hasta 64 pares y `_metadata.dart` queda reservado para la metadata.

En metadata, `purposes`, `moods` y `concepts` clasifican el visual; `credits`
conserva autor, licencia y origen. Los controles `intensity`, `speed` y `glow`
admiten 0–2; `detail`, 0.25–2. Mantener cuatro colores ARGB. La publicación es
una etiqueta editorial: ninguna de sus opciones concede aprobación.

## Miniaturas

La miniatura automática usa un fotograma del visual en un tiempo fijo. Se genera
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

La demo incluida está identificada como **sintética**. Usa el contrato binario
real de 520 bytes, pero no es una grabación del sensor. No se entrega una captura
real ni audio. Para probar una captura existente, coloca `signals.bin` y
`timeline.json` juntos en `studio/recordings/<nombre>/` y vuelve a ejecutar el
build. El replay conserva valores, orden, semilla y seriales; al repetir un loop
reinicia el estado del visual. La programación de cada dispositivo puede
introducir diferencias de presentación.

iOS utiliza el mismo compositor SceneSurface/Metal que la aplicación. Android
ejecuta el mismo código portable mediante el runtime `FragmentProgram` acotado
del SDK. El presupuesto es 30 FPS y la ejecución se pausa con el lifecycle.
Android limita el lado mayor del target a 1024 píxeles; iOS conserva los límites
del compositor compartido. Esto controla recursos, pero no garantiza que
cualquier shader sea ligero. La temperatura, batería y estabilidad sostenida
se validan en dispositivos físicos.

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

La validación comprueba el par seleccionado, la metadata, el shader combinado
con los aprobados y su compilación Metal/GLES/GLES3/Vulkan; también renderiza
el candidato con Metal en la Mac. Requiere macOS, Xcode y el Dart de Flutter.
La aprobación se hace mediante comandos; no hay un botón «Aprobar» en Studio.
Devuelve una revisión exacta y el comando `approve … --revision … --reviewed`.
El responsable lo ejecuta **después de revisar aspecto, transparencia, música
y rendimiento físico**. Compilar no decide si un visual es bueno.

La aprobación guarda código, metadata y miniatura en
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

Esa prueba compila los shaders reales y examina sus píxeles. No equivale a una
prueba térmica ni garantiza igualdad de píxeles entre iOS y Android.
