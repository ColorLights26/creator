# Visual Studio

Proyecto Flutter independiente para crear visuales de Color Lights en iOS y
Android. Mantén `creator/` y `packages/` juntos; no necesita el resto del monorepo.

## Tu flujo

1. Abre `creator` en tu IDE Flutter y resuelve las dependencias. Para iOS
   necesitas una Mac con Xcode y CocoaPods.
2. Copia todo `lib/visual_template.dart` a tu IA y describe el visual.
3. Pega el archivo devuelto, conservando la función `createVisuals()`.
4. Guarda, detén la app y pulsa Run. Los visuales aparecen solos en la lista.

Un shader nuevo requiere volver a ejecutar el build; hot reload no basta.
La plantilla explica toda la API: Dart declara el catálogo y GLSL portable
produce los efectos. No hay que modificar registros, sensores, widgets o assets.
Incluye una aurora opcionalmente reactiva y unas órbitas sin reacción musical.

## Señales y rendimiento

La demo incluida es **sintética**, con el contrato binario real del compositor.
No imita todas las situaciones de un sensor. Las capturas `signals.bin` y
`timeline.json` van en una carpeta dentro de `recordings/`; el siguiente build
las ofrece sin alterar valores, semilla o seriales. No incluye ni reproduce audio.

iOS usa SceneSurface/Metal compartido con la app; Android ejecuta el mismo código
con FragmentProgram. El presupuesto es 30 FPS con pausa por lifecycle. Android
limita el lado mayor a 1024 píxeles con un target GPU y un frame en preparación.
La precisión puede variar entre GPUs y un shader caro todavía puede calentar:
comprueba consumo sostenido en hardware real antes de integrar.

## Entrega

Devuelve `lib/visual_template.dart`. El catálogo automático es el del estudio;
publicar en Color Lights requiere integración y validación. El manifiesto remoto
no puede entregar código ejecutable nuevo.

`dart run tool/export_kit.dart` crea el zip en `../dist/` con este proyecto y sus
dos paquetes. No depende de minibase, base, skeleton, metadata ni sharedkernel.

- `lib/visual_template.dart`: único archivo creativo.
- `lib/studio/`: controles y replay encapsulados.
- `../packages/scene_compositor`: render y vida de las sesiones.
- `../packages/visual_contract`: señales canónicas y lector de capturas.
- `tool/compile_visuals.dart`: generación automática al ejecutar iOS/Android.
