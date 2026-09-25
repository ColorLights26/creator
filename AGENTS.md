# Creator: instrucciones para agentes

## Ámbito y arquitectura

Este repositorio debe poder clonarse y ejecutarse sin el monorepo Color Lights.
No añadas dependencias de `minibase`, `base`, `skeleton`, `metadata`,
`sharedkernel`, `appkernel` u otros checkouts externos.

- `studio/`: aplicación Flutter y herramientas de generación/exportación.
- `packages/visual_catalog/`: visuales y metadata del estudio; fuente de candidatos.
- `packages/scene_compositor/`: SDK gráfico; no posee sensores ni servicios de app.
- `packages/scene_program_native/`: SDK C++17 y ABI C, compartidos entre plataformas.
- `packages/scene_compositor_host/`: plugin iOS exclusivo del estudio; registra el SDK.
- `packages/visual_contract/`: codec/replay Dart puro; preserva el protocolo.
- `templates/visual_template.dart`: código completo para copiar a una IA.
- `templates/visual_template_metadata.dart`: metadata separada del visual.

El README principal y `studio/README.md` están dirigidos a colaboradores que
saben compilar Flutter y usar una IA. Conserva instrucciones concretas con un
ejemplo completo; la aprobación, arquitectura y comprobaciones avanzadas viven
en `MAINTAINER.md`. Las instrucciones técnicas para la IA viven dentro de la
plantilla; al colaborador sólo se le pide describir el efecto. La validación
previa del SDK debe seguir compartida entre Studio y la revisión de la app.
No mezcles los comandos del responsable de Color Lights con
los pasos necesarios para crear un visual en el estudio independiente.

Revisa el estado Git antes de editar y conserva cambios de otros colaboradores.
No publiques, hagas push ni cambies el estado de publicación de un visual sin
autorización para esa acción.

## Autoría

Para un visual normal, modifica su par de archivos en
`packages/visual_catalog/lib/visuals/`: `nombre.dart` declara `const nativeSource` y opcionalmente `const shaderSources`
y `nombre_metadata.dart` declara `const metadata = CreatorVisualMetadata(...)`.
El programa C++ implementa `Visual : Scene` con reset/update/render. Los visuales
anteriores con `shaderSource` y `paintVisual` siguen admitidos. El ID único y toda la configuración viven en
metadata. El generador une pares por nombre y rechaza compañeros ausentes. No agregues registros manuales,
widgets, sensores, timers o renderers independientes al archivo creativo.

Mantén explícitos `role`, `reactivity`, autoría y clasificación. Los nuevos
visuales son `draft` salvo instrucción expresa de publicación. Un overlay debe
conservar su transparencia y un visual no reactivo no debe adquirir audio.
Las miniaturas son imágenes fijas cacheadas o assets de `visual_catalog`;
nunca ejecutes un compositor continuo por tarjeta.

La app principal consume snapshots aprobados en su propio repositorio, nunca
el catálogo de borradores de Creator. `publication` es una etiqueta editorial,
no una autorización. No añadas aprobaciones ni cambies sus huellas para saltar
la revisión. La herramienta del responsable valida la versión exacta y exige
una aprobación explícita después de la revisión visual y energética.
La autoría normal no modifica el SDK ni el contrato compartidos; esos cambios
se revisan separadamente del catálogo.

No edites a mano los productos generados: `lib/src/registry.g.dart`,
`assets/creator_catalog.json`, `assets/catalog_metadata.json` y
`shaders/creator_programs.frag` del catálogo, ni `studio/assets/recordings.json`.
Regenera desde `studio/` con `dart run tool/compile_visuals.dart`. Los hooks
nativos lo hacen antes de empaquetar Flutter; mantén ese orden.

## Contratos que deben conservarse

- Usa el mismo programa C++ y los mismos materiales GLSL en ambas plataformas.
  Los materiales se compilan con impellerc real; no aplicarles las restricciones
  del traductor de los visuales antiguos. No agregar límites artificiales de bucles.
- La referencia de la plantilla se genera del SDK: `dart studio/tool/generate_template.dart`.
  Edita el bloque AUTHOR API de `creator_scene.hpp` o el ejemplo
  `templates/visual_template_body.cpp` y regenera; CI comprueba que no diverjan.
- iOS utiliza SceneSurface V1. Solo Studio depende del plugin
  `scene_compositor_host`: Flutter instala sus pods y lo registra una vez con
  `GeneratedPluginRegistrant`. El Podfile resuelve el pod `scene_compositor`
  local. `scene_compositor` permanece una biblioteca Flutter sin registro
  automático: producción conserva su propietario nativo existente.
- Los Swift de `packages/scene_compositor/ios/Classes/Runtime` son canónicos.
  La app productiva puede compilarlos mediante enlaces; no mantengas copias
  divergentes ni actives otra política de compositor como efecto secundario.
- El catálogo nativo se carga exclusivamente desde el asset bundled del
  paquete `visual_catalog`. Los documentos transportan IDs/controles, no código.
- Preserva el wire format de 520 bytes, los seriales, la semilla uint32 y los
  valores de las grabaciones. Reinicia el estado antes de un loop o seek atrás.
- Identifica siempre los fixtures sintéticos. Un archivo compatible no prueba
  que sus datos procedan de un sensor físico.
- Conserva cadencia, pausas, memoria acotada y propiedad de recursos. No afirmes
  ausencia de calentamiento a partir de tests o simuladores.

## Verificación

La versión verificada para el proyecto completo es Flutter 3.44.5. Sigue el
workflow Flutter del workspace cuando exista. En hosts Codex que exijan
`apprun`, autentica el directorio real de la tarea y selecciona el subproyecto
`studio`; nunca inventes identidad, título o simulador, ni ejecutes un segundo
runner manual.

Resuelve dependencias solamente si cambiaron o faltan. Después de una edición,
elige las comprobaciones afectadas:

```sh
# Desde studio/
dart run tool/compile_visuals.dart
flutter test --no-pub test/creator_studio_test.dart test/visual_registry_generator_test.dart test/android_shader_runtime_test.dart test/creator_thumbnail_test.dart

# Desde packages/scene_compositor/
dart run test/creator_visual_definition_test.dart
flutter test --no-pub test/creator_shader_frame_test.dart test/scene_compositor_controller_test.dart test/creator_catalog_metadata_test.dart

# Desde packages/visual_contract/
dart run test/contract_test.dart
```

Los tests de autoría y contrato son ejecutables Dart, no suites `flutter_test`.
Al cambiar native shader/state, usa también
`packages/scene_compositor/ios/Tests/check_creator_catalog.rb` con la ruta del
catálogo generado; necesita Metal real. Un problema de compilación gráfica debe
mostrarse como error, sin cambiar silenciosamente a otro renderer.

Al cambiar exportación o dependencias, exporta a otra carpeta y comprueba que
todas las rutas locales resuelven dentro del kit. No incluyas SDKs, cachés,
credenciales, rutas personales, `.git` ni enlaces hacia otro checkout.

Los programas nativos se prueban fuera de la app con timeout y ASan/UBSan mediante
`python3 packages/scene_program_native/test/check_native.py --generated studio/build/creator_native`.
No es un sandbox. `native_scene_pixels_test.dart` requiere una biblioteca de prueba
y CREATOR_TEST_LIBRARY/CREATOR_PIXEL_OUTPUT; ver `.github/workflows/check.yml`.
