> Para: ejecutar el estudio y encontrar la guía de creación. Lee aquí si abriste studio como proyecto Flutter.

# Empieza aquí

**[Sigue la guía para crear tu primer visual](../README.md).** Incluye qué archivos
copiar, un mensaje listo para la IA y qué hacer cuando algo falla.

## Ejecutar esta aplicación

Con la terminal situada en esta carpeta `studio/`:

```sh
flutter pub get
flutter run
```

También puedes usar **Run** en tu editor. El proyecto está preparado para Android
e iOS; la versión probada es Flutter 3.44.5 stable. Para iOS necesitas una Mac
con Xcode y CocoaPods.

Conserva `packages/` y `templates/` junto a `studio/`. Si tu editor no muestra esas
carpetas, abre también la carpeta superior `creator/` para editar tus archivos.
Sigue ejecutando la aplicación desde `studio/`.

## Cada visual tiene dos archivos

Los guardas en [packages/visual_catalog/lib/visuals/](../packages/visual_catalog/lib/visuals/):

```text
olas.dart           → el dibujo que entrega la IA
olas_metadata.dart  → nombre, tipo, reacción musical y miniatura
```

Copia ambas plantillas de [templates/](../templates/) y renombra las copias.
Para pedir el dibujo, pega la plantilla en la IA y describe tu idea:
«Crea un fondo de olas azules que reaccionen a la música». La propia plantilla
incluye las instrucciones técnicas. El código que recibas reemplaza `olas.dart`.

Pon un `id` diferente a cada visual. Los tipos disponibles son fondo
(`CreatorRole.background`) y transparencia (`CreatorRole.overlay`); ambos pueden
usar música. La [guía completa](../README.md#4-ponle-nombre-y-elige-su-comportamiento)
explica exactamente qué líneas editar.

Guarda ambos archivos y usa **Stop → Run**. El visual se añade automáticamente
al estudio. Hot Reload y Hot Restart no bastan para estos cambios.

## Lo que ves al probar

Puedes empezar con Liquid Chrome, Spiral Galaxy, Midnight Highway y Golden
Particles. Los ejemplos anteriores siguen disponibles.
El visual ocupa toda la pantalla. Los controles están superpuestos en un panel
desplazable; en pantallas amplias, el panel queda a la derecha.
La Demo sintética recorre 32 segundos con partes suaves, subidas, una pausa y
golpes de distinta fuerza. Graves y agudos varían por separado. El estudio no escucha
el micrófono ni reproduce canciones.

## Cuando esté listo

Entrega los dos archivos y, si elegiste una miniatura propia, su imagen.
El responsable revisa y aprueba la versión antes de incorporarla a Color Lights.
Tu visual aparece automáticamente en **Creator**; su incorporación a la app
principal requiere esa aprobación y un nuevo build.

[Errores frecuentes](../README.md#si-algo-no-funciona) ·
[Guía del responsable](../MAINTAINER.md)
