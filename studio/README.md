# Visual Studio

Abre esta carpeta `studio/` como proyecto Flutter. Conserva `packages/` y
`templates/` a su lado dentro del repositorio Creator.

## Dos archivos por visual

Copia las dos plantillas de `../templates/` a
`../packages/visual_catalog/lib/visuals/` y renómbralas con el mismo prefijo:

```text
olas.dart           ← código del dibujo: const shaderSource
olas_metadata.dart  ← nombre, ID, tipo, reactividad, miniatura: const metadata
```

Envía `visual_template.dart` completo a la IA. Pega su respuesta en `olas.dart`
y edita los datos de `olas_metadata.dart`. Ambos archivos son independientes;
el generador los relaciona por nombre. No tienen que importarse entre ellos.

En el archivo de código, conserva `const shaderSource = r'''...''';` y la función
`paintVisual`. El dibujo es GLSL portable dentro del archivo Dart.

En la metadata, conserva `const metadata = CreatorVisualMetadata(...)`:

- `id`, `name`, `description`, `purposes`, `moods`, `concepts` y `credits`.
- `role: CreatorRole.background` para fondo o `CreatorRole.overlay` para
  transparencia. El shader debe devolver alpha menor que 1 donde corresponda.
- `reactivity`: `CreatorReactivity.none`, `.music` u `.optional`.
- `colors`, `controls` y `seed`: parámetros del dibujo.
- `thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5)`: miniatura fija automática.
- `publication: CreatorPublication.draft`: borrador para pruebas.

Para otro visual, añade otro par con un ID único. No edites listas ni registros.
Editar las plantillas dentro de `templates/` no añade visuales al catálogo.

## Aparición automática y validación

Guarda ambos archivos, detén el estudio y pulsa **Run**. El nuevo visual aparece
en **Tus visuales**. Hot reload no basta para empaquetar shaders.

Run valida automáticamente que cada archivo tenga su compañero, los IDs,
rangos, metadata, miniaturas propias y restricciones del shader. Después compila
y carga el programa gráfico. Corrige los errores antes de continuar.

Para el chequeo previo desde esta carpeta, sin abrir la app:

```sh
dart run tool/compile_visuals.dart
```

Al completar muestra, por ejemplo, `Visual Studio: 3 visuales, 0 grabaciones.`
Esta comprobación no certifica apariencia, compilación GPU en ambas plataformas
ni temperatura. Revisa la vista previa, la reacción y el consumo físico.

## Cómo llega a Color Lights

Creator y Color Lights usan el mismo paquete `visual_catalog`. En este workspace
ya está conectado a la lista de fondos y transparencias de la app principal.

1. El colaborador guarda y comparte el par de archivos por Git.
2. Sincronizas el checkout `creator` que usa Color Lights.
3. Compilas Color Lights: sus hooks regeneran el catálogo automáticamente.
4. Los borradores aparecen en debug; `published` permite su aparición en release.

Si editas directamente el checkout `creator` de este monorepo, el segundo paso
ya está hecho. No debes copiar código a `minibase` ni registrar visuales uno a uno.
Run del estudio actualiza el estudio; para ver cambios en Color Lights debes
recompilar Color Lights. Las apps ya instaladas por usuarios requieren una nueva
versión distribuida.

[Guía completa](../README.md).
