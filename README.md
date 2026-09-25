# Color Lights Creator

Un estudio Flutter independiente para crear visuales de Color Lights con un
par de archivos por efecto: código y metadata. Copia la plantilla a una IA, pega su respuesta y vuelve a
ejecutar el estudio: el catálogo se prepara automáticamente.

## Empezar

Usa Flutter **3.44.5 stable** —la versión verificada para este estudio— y sus
herramientas de Android o iOS. Para iOS necesitas macOS, Xcode y CocoaPods; el
destino mínimo es iOS 15. Los paquetes declaran Dart >=3.7 y el SDK gráfico
Flutter >=3.29; esos límites no certifican el proyecto nativo completo en
versiones antiguas.

```sh
git clone git@github.com:ColorLights26/creator.git
cd creator/studio
flutter pub get
flutter run
```

Abre `studio/` como proyecto Flutter. Conserva `packages/` y `templates/` a su
lado. No necesitas el monorepo, Firebase, cuentas de servicios ni permisos de
micrófono.

## Crear un visual

1. Copia las dos plantillas a `packages/visual_catalog/lib/visuals/`, renombrándolas `olas.dart` y `olas_metadata.dart`.
2. Envía [templates/visual_template.dart](templates/visual_template.dart) a la IA. Describe el efecto y pide conservar `const shaderSource`, `paintVisual` y las restricciones.
3. Pega el código completo devuelto en `olas.dart`.
4. Edita `olas_metadata.dart`: ID único, nombre, rol, reactividad, colores, controles, categorías, créditos, miniatura y publicación.
5. Detén la ejecución anterior y pulsa **Run**. El visual aparece en la lista.

```text
packages/visual_catalog/lib/visuals/
  olas.dart              ← const shaderSource: código del dibujo
  olas_metadata.dart     ← const metadata: datos y configuración
  fuego.dart
  fuego_metadata.dart
```

El generador empareja los archivos por nombre. Cada metadata declara
`const metadata = CreatorVisualMetadata(...)`; no incluye código gráfico.
No hay imports entre los dos archivos ni registro manual. Si falta cualquiera
del par, la validación indica su nombre. Se admiten hasta 64 pares completos.
El sufijo `_metadata.dart` está reservado para metadata.

El dibujo usa GLSL portable dentro del string Dart `shaderSource`, con
`vec4 paintVisual(vec2 uv, CreatorFrame f)`. Un shader nuevo requiere recompilar;
hot reload no empaqueta el programa. Las plantillas fuera de `lib/visuals/` no
se incluyen en el catálogo.

El estudio incluye Aurora Ribbons, Quiet Orbits y el overlay Prismatic Halo.

## Aspecto, música y miniatura

| Propiedad | Uso |
| --- | --- |
| `role: background` | Fondo de la escena; devuelve alpha 1. |
| `role: overlay` | Capa que puede dejar ver el fondo mediante alpha. |
| `reactivity: none` | Movimiento ambiental; las entradas musicales son cero. |
| `reactivity: music` | Reacción musical activa, con reposo cuando no hay señal autorizada. |
| `reactivity: optional` | Permite activar o desactivar la reacción. |
| `purposes`, `moods`, `concepts` | Categorías que describen la intención del visual. |
| `credits` | Autor, licencia y origen del trabajo. |
| `publication: draft` | Disponible en el estudio y en la integración debug. |
| `publication: published` | Elegible para la integración en builds de producción después de revisarlo. |

Los controles `intensity`, `speed` y `glow` admiten 0–2; `detail`, 0.25–2. El
efecto recibe tiempo, paleta, semilla y señales musicales ya preparadas. No abre
sensores ni define otro detector de beats.

La miniatura predeterminada es un fotograma del mismo shader en un tiempo fijo:

```dart
thumbnail: CreatorThumbnailSpec(timeSeconds: 3),
```

Se genera una vez y se conserva en una caché acotada; las tarjetas no mantienen
una animación ni un micrófono. Para usar una imagen propia, añádela a
`packages/visual_catalog/assets/thumbnails/` y declárala:

```dart
thumbnail: CreatorThumbnailSpec(
  assetPath: 'assets/thumbnails/mi_visual.png',
  assetPackage: 'visual_catalog',
),
```

Esta imagen es un recurso opcional adicional al archivo creativo.

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
El estudio y el adaptador de Color Lights consumen el mismo paquete
`visual_catalog`: los borradores se incluyen en debug; los publicados pueden
incluirse en release. Cambiar la marca a `published` no sustituye la revisión
visual y de rendimiento.

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
| `packages/visual_catalog/` | Archivos creativos, metadatos y programas bundled compartidos. |
| `packages/scene_compositor/` | Compositor, render, recursos y miniaturas. |
| `packages/scene_compositor_host/` | Registro nativo exclusivo del estudio en iOS. |
| `packages/visual_contract/` | Codec y replay; Dart puro, sin sensores. |

Las fases nativas iOS/Android ejecutan `studio/tool/compile_visuals.dart` antes
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
