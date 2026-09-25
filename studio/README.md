# Visual Studio

Abre esta carpeta `studio/` como proyecto Flutter. Conserva `packages/` y
`templates/` a su lado, dentro del repositorio Creator.

## Dónde pegar lo que devuelve la IA

1. Copia **todo** `../templates/visual_template.dart` a la IA y describe tu idea.
2. Pide que devuelva el archivo completo conservando `const visual` y las reglas.
3. Guarda esa respuesta en
   `../packages/visual_catalog/lib/visuals/mi_visual.dart`.
4. Cambia `id` y `name`. Cada visual debe tener un ID único.
5. Guarda, detén el estudio y pulsa **Run**. El nuevo visual aparece en
   **Tus visuales**. No basta con hot reload.

Para crear otro visual, añade otro archivo a esa misma carpeta. No reemplaces
los anteriores ni edites listas, imports o registros generados. El archivo de
`templates/` es el molde: editarlo allí no lo añade al catálogo.

## Código y metadata: el mismo archivo

Dentro de `const visual = CreatorVisualDefinition(...)`:

- `shaderSource: r''' ... '''` contiene el dibujo, dentro de `paintVisual`.
  Es GLSL portable, encapsulado en un archivo Dart; la IA debe respetar la
  plantilla, no entregar un widget Flutter o CustomPainter independiente.
- `id`, `name`, `description`, `purposes`, `moods`, `concepts` y `credits`
  contienen la metadata.
- `role: CreatorRole.background` indica fondo (es el valor predeterminado).
  `CreatorRole.overlay` permite transparencia; el shader debe devolver alpha
  menor que 1 en las zonas que dejen ver el fondo.
- `reactivity` puede ser `CreatorReactivity.none`, `.music` u `.optional`.
- `thumbnail: CreatorThumbnailSpec(timeSeconds: 2.5)` genera una miniatura fija
  automáticamente. Para una imagen propia, consulta el README raíz.
- `publication: CreatorPublication.draft` conserva el visual como borrador.

## Validar

**Run hace las comprobaciones automáticamente.** Revisa IDs duplicados,
metadata mal formada, límites, miniaturas propias inexistentes y parte de las
restricciones gráficas. La compilación gráfica y la vista previa detectan
problemas adicionales del shader. Corrige el error antes de continuar.

Para comprobar estructura y regenerar el catálogo sin abrir el estudio,
ejecuta desde esta carpeta:

```sh
dart run tool/compile_visuals.dart
```

Si termina correctamente, muestra por ejemplo:
`Visual Studio: 3 visuales, 0 grabaciones.`
Este paso no certifica compilación GPU en ambas plataformas ni rendimiento.
Después ejecuta el estudio, selecciona el visual y comprueba su aspecto,
transparencia, pausa y reacción con la demo sintética. Para validar temperatura
y consumo, usa dispositivos físicos.

## Cuándo aparece en Color Lights

El estudio lo lista después de un nuevo build. La app Color Lights también lo
incorpora después de sincronizar este repositorio y compilar: los borradores
aparecen en debug y los marcados `published` en release. Guardar un archivo o
hacer push no actualiza una app instalada.

[Guía completa del repositorio](../README.md), con señales, miniaturas propias,
exportación, plataformas y límites.
