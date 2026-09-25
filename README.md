> Para: crear y probar visuales con una IA. Lee esta guía para hacer tu primer visual o añadir otro.

# Creator: crea tu primer visual

Aquí puedes crear fondos y efectos transparentes para Color Lights.
Tu trabajo es **copiar una plantilla, pedirle un dibujo a la IA, pegar el resultado
y ejecutarlo**. El proyecto ya se ocupa de mostrarlo y darle señales de prueba.

**Lo que crees aparece en Creator.** El responsable de Color Lights revisará
lo que entregues y decidirá qué incorpora a la app principal.

## 1. Abre y ejecuta el proyecto

Descarga el repositorio completo o clónalo. Conserva juntas estas carpetas:

```text
creator/
  studio/       ← la aplicación Flutter que ejecutas
  templates/    ← las dos plantillas que vas a copiar
  packages/     ← aquí guardarás tus visuales
```

Abre `studio/` como proyecto Flutter en tu editor. En una terminal situada
**dentro de `studio/`**, ejecuta:

```sh
flutter pub get
flutter run
```

Usa Android o iOS. La versión de Flutter probada es **3.44.5 stable**; iOS requiere
una Mac con Xcode y CocoaPods. Si tu editor ya tiene preparado el dispositivo,
también puedes usar su botón **Run**.

Deberías ver los ejemplos **Aurora Ribbons**, **Quiet Orbits** y **Prismatic Halo**.
Primero comprueba que estos funcionan; después crea el tuyo.

Si tu editor sólo muestra `studio/`, abre también la carpeta completa `creator/`
o usa el explorador de archivos para acceder a `templates/` y `packages/`.
La aplicación que ejecutas sigue estando en `studio/`.

## 2. Crea dos archivos para «Olas»

Copia estas dos plantillas a la [carpeta de visuales](packages/visual_catalog/lib/visuals/)
y cambia los nombres de las **copias**:

| Copia esta plantilla | Guarda la copia con este nombre |
| --- | --- |
| [visual_template.dart](templates/visual_template.dart) | `olas.dart` |
| [visual_template_metadata.dart](templates/visual_template_metadata.dart) | `olas_metadata.dart` |

Al terminar debes tener:

```text
packages/visual_catalog/lib/visuals/
  olas.dart
  olas_metadata.dart
```

**`olas.dart` contiene el dibujo. `olas_metadata.dart` contiene su ficha:**
el nombre, si es fondo o transparente, si reacciona a la música y su miniatura.
Ambos nombres empiezan por `olas` para que el proyecto sepa que van juntos.
Para los nombres de archivo usa minúsculas sin tildes, números y guiones bajos,
sin espacios y comenzando con una letra: por ejemplo, `lluvia_suave.dart`.

Las plantillas originales se quedan en `templates/` para crear más visuales.
Editar sólo una plantilla allí no añade nada a la lista.

## 3. Pídele el dibujo a la IA

Copia todo el contenido de [visual_template.dart](templates/visual_template.dart)
y pégalo en la conversación con tu IA. La plantilla ya incluye las instrucciones
sobre qué devolver y cómo trabajar dentro del proyecto. **Tú sólo describes
el efecto que quieres**, por ejemplo:

```text
Crea un fondo de olas azules suaves que reaccionen a la música.
```

Para una capa transparente puedes decir:

```text
Crea partículas doradas sobre fondo transparente que reaccionen a la música.
```

No necesitas escribir nombres de funciones ni instrucciones técnicas en tu
mensaje. Al pedir mejoras, vuelve a adjuntar la plantilla y el archivo actual,
y describe el cambio: «Haz las olas más lentas y de color violeta».

Copia **todo el código** que devuelva y reemplaza el contenido de `olas.dart`.
Si la IA lo muestra entre marcas como ` ```dart ` y ` ``` `, copia únicamente
el contenido de ese bloque, sin las marcas ni el texto explicativo.

## 4. Ponle nombre y elige su comportamiento

Abre `olas_metadata.dart`. Para tu primer visual cambia estas dos líneas:

```dart
id: 'olas',
name: 'Olas',
```

El `id` es una etiqueta interna: usa minúsculas sin tildes, números si los
necesitas y guiones bajos; comienza con una letra. Por ejemplo, `olas_azules`.
Debe ser distinto al de otros visuales. `name` es el nombre que verás en pantalla
y puede llevar espacios y tildes.

Después elige el tipo. La plantilla ya viene como fondo:

| Lo que quieres | Línea de la metadata |
| --- | --- |
| Un fondo que ocupa toda la escena | `role: CreatorRole.background,` |
| Un efecto que deja ver lo que hay detrás | `role: CreatorRole.overlay,` |

**Cambiar esta línea no borra el fondo del dibujo.** Para un efecto transparente,
pide a la IA «un efecto sobre fondo transparente». Así la descripción del
paso 3 y el tipo que elijas aquí se refieren a lo mismo.

Elige cómo usa la música:

| Lo que quieres | Línea de la metadata |
| --- | --- |
| Activar o desactivar la reacción en el estudio | `reactivity: CreatorReactivity.optional,` |
| Que use las señales musicales cuando estén disponibles | `reactivity: CreatorReactivity.music,` |
| Que se mueva por sí solo, sin reaccionar a la música | `reactivity: CreatorReactivity.none,` |

Para empezar puedes conservar `.optional`. La IA debe haber usado las señales
de la plantilla para que el dibujo reaccione; la metadata por sí sola no crea
esa animación. **Tanto un fondo como una transparencia pueden ser reactivos.**

La miniatura se crea automáticamente a partir del dibujo. Conserva la línea
`thumbnail` de la plantilla para usarla. Si quieres una imagen propia, consulta
[miniaturas](MAINTAINER.md#miniaturas).

Actualiza `description` con una frase sobre tu efecto y `author` con tu nombre.
Puedes conservar inicialmente los colores y controles de la plantilla. Deja
`publication: CreatorPublication.draft`: significa «borrador» y no impide probarlo.

## 5. Guarda y vuelve a ejecutar

1. Guarda los dos archivos.
2. Detén la ejecución actual con **Stop**.
3. Vuelve a ejecutar `studio/` con **Run** o `flutter run` desde esa carpeta.
4. Busca **Olas** en la lista y selecciónalo.

**El proyecto añade el visual automáticamente.** No tienes que editar una lista.
Para estos cambios necesitas detener y volver a ejecutar: **Hot Reload y
Hot Restart no bastan** para recompilar el dibujo.

Si elegiste `.optional`, prueba el interruptor de reacción musical activado y
desactivado. La **Demo sintética** simula señales de música: el estudio no escucha
el micrófono ni reproduce una canción. Así puedes probar sin conectar sensores.

## 6. Para crear otro visual

Repite los pasos con otro nombre y otro `id`. Por ejemplo:

```text
olas.dart            + olas_metadata.dart       → id: 'olas'
fuego.dart           + fuego_metadata.dart      → id: 'fuego'
estrellas.dart       + estrellas_metadata.dart → id: 'estrellas'
```

Cada pareja es un visual independiente. Para mejorar Olas, edita su pareja
existente; para crear Fuego, añade otra pareja. Puedes conservar los ejemplos.

## Si algo no funciona

| Lo que ocurre | Qué revisar |
| --- | --- |
| Mi visual no aparece | Los dos archivos deben estar en `packages/visual_catalog/lib/visuals/`. Guarda, detén y vuelve a ejecutar `studio/`. |
| Dice que falta metadata o un compañero | Comprueba los nombres: `olas.dart` y `olas_metadata.dart`, en la misma carpeta. |
| Dice «ID duplicado» | Cambia el valor `id` de la nueva metadata. Cambiar sólo el nombre del archivo no cambia el ID. |
| Veo la versión anterior | Usa **Stop → Run**, no Hot Reload ni Hot Restart. |
| Elegí transparente, pero sigue mostrando un fondo negro | Pide a la IA transparencia real en el código del dibujo; revisa que la metadata use `.overlay`. |
| No reacciona a la música que pongo en mi habitación | El estudio usa señales de demostración y no escucha el micrófono. Prueba la Demo sintética y revisa la opción de reacción. |
| El código de la IA no compila | Copia el primer error completo, el contenido de tu visual y la plantilla a la IA. Usa el mensaje de abajo. |

```text
Corrige este error usando la plantilla. Te adjunto el error y el archivo actual.
```

**La IA puede equivocarse aunque reciba la plantilla.** Al ejecutar, Creator
comprueba el formato de lo que pegaste antes de incorporarlo: detecta, por
ejemplo, HTML, una app Flutter completa, código sin su envoltorio y las marcas
Markdown copiadas por error. El mensaje identifica el archivo. Después se
validan los datos y se compila el dibujo; cualquier error bloquea ese build.
Copia el error junto con la plantilla y el archivo para que la IA lo corrija.
Estas comprobaciones no deciden si el resultado es bonito o consume poca batería.

Si el error aparece antes de crear un visual, al ejecutar los ejemplos originales,
comparte ese error con el responsable del proyecto para revisar la instalación.

## 7. Entrega el resultado

Comparte tu pareja de archivos por el repositorio o envíasela al responsable.
Si añadiste una imagen para la miniatura, inclúyela también. Una captura o un vídeo
corto ayuda a mostrar qué resultado esperabas.

**Tu parte termina al crear, probar y entregar.** El responsable valida y aprueba
una versión; luego recompila Color Lights para incorporarla. Cambiar `draft` por
`published` o subir un archivo a GitHub no hace que aparezca en la app principal.

Si algo sale mal en un borrador, no sustituye la versión aprobada que ya tenga
Color Lights. Comenta cualquier tirón o calentamiento que notes al probar: que
compile correctamente no demuestra que el efecto sea ligero.

[Guía del responsable: aprobación, integración y detalles técnicos](MAINTAINER.md).
