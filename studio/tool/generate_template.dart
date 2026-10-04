import 'dart:io';

/// The example's settings: the body reads them with modifiers(f).
const _exampleModifiers = '''// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.steps('brazos', 'Brazos', min: 2, max: 6, value: 4),
  CreatorModifier.slider('giro', 'Giro', min: .2, max: 2, value: 1),
  CreatorModifier.toggle('nucleo', 'Núcleo brillante', value: true),
  CreatorModifier.choice(
    'estilo',
    'Estilo',
    options: ['Auto', 'Nítido', 'Nebuloso'],
  ),
];''';

void main(List<String> args) {
  final root = File.fromUri(Platform.script).parent.parent.parent;
  final header =
      File(
        '${root.path}/packages/scene_program_native/src/creator_scene.hpp',
      ).readAsStringSync();
  final api =
      header
          .split('// BEGIN AUTHOR API')
          .last
          .split('\n')
          .skip(1)
          .join('\n')
          .split('// END AUTHOR API')
          .first
          .trim();
  final body =
      File(
        '${root.path}/templates/visual_template_body.cpp',
      ).readAsStringSync().trim();
  final result =
      '''// PARA FRANCO: copia TODO este archivo a tu IA y describe el visual que quieres.
// Pega su respuesta completa en tu archivo .dart. Metadata en el archivo compañero.
// Guarda y usa Stop → Run. No necesitas registrar nada ni tocar el motor.
// Sus modificadores aparecen en Studio, en el botón Ajustes, para probarlos.
//
// PARA LA IA: entrega únicamente este archivo Dart completo, sin Markdown.
// Conserva las instrucciones y la referencia; reemplaza modifiers y nativeSource
// por los de tu escena. Conserva el import: lo necesitan los modificadores.
// nativeSource es C++17: define class Visual final : public Scene.
// Puedes crear algoritmos, structs, vectores, estado persistente, partículas,
// curvas y funciones auxiliares. La instancia es independiente por reproducción.
// No pongas includes dentro del string: el motor ya incluye algorithm, array,
// cmath, cstdint, initializer_list, memory, stdexcept, string y vector.
// reset(seed) inicializa toda la memoria; update(frame) mueve la simulación;
// render(frame,canvas) const sólo dibuja. No uses globals mutables, relojes,
// timers, sensores, red, archivos, hilos ni servicios de la app.
// Frame.time/delta son segundos activos, con pausa y delta acotado por el motor.
// Usa delta para velocidades; Random(seed) para inicialización reproducible.
// Music.events ya está deduplicado. Si music.active=false, sus señales son cero.
// Apagar música no borra partículas existentes. No inventes golpes desde bpm.
// width/height son píxeles lógicos, origen arriba izquierda, y hacia abajo.
// Color usa RGBA recto. Un fondo debe cubrir el lienzo; un overlay conserva alpha.
// Agrupa partículas con Canvas.points. saveLayer aplica opacidad al grupo completo.
// Balancea save/saveLayer con restore. clip intersecta recortes anidados.
// Path.fillRule=FillRule::evenOdd permite huecos. Blend: sourceOver, plus, screen.
// El motor posee cadencia/calidad/recursos: 30 FPS por defecto; pedir 60 no lo fuerza.
// Acota memoria y trabajo según tu escena. No existe un máximo artificial de 8 bucles.
// El código nativo se valida antes de aprobarse; esa validación NO es un sandbox.
//
// AJUSTES BÁSICOS: todo visual los tiene y Studio los muestra. Úsalos siempre.
// f.intensity: cuánto reacciona a la música; multiplica la respuesta al audio.
// f.speed: ritmo del movimiento. Acumúlalo con delta (fase += f.delta*f.speed);
//   nunca uses f.time*f.speed: al mover el ajuste, el dibujo saltaría.
// f.detail (0.25 a 2): densidad. Reserva el máximo en reset y dibuja una parte.
// f.glow: halo, niebla o resplandor.
// f.colors: paleta de la metadata. colors[0] es el fondo; colors[1..3], los
//   acentos. No escribas colores fijos en el código: así la paleta se cambia.
//
// MODIFICADORES (SIEMPRE): declara de 2 a 6 ajustes propios que cambien de
// verdad el visual: cantidad, simetría, forma, figura, estilo, estela, zoom...
// Van en const modifiers, antes de nativeSource. Tipos:
//   CreatorModifier.slider('id', 'Nombre', min: .5, max: 2, value: 1)    decimal
//   CreatorModifier.steps('id', 'Nombre', min: 3, max: 12, value: 6)     entero
//   CreatorModifier.toggle('id', 'Nombre', value: true)                  sí / no
//   CreatorModifier.choice('id', 'Nombre', options: ['Auto', 'A', 'B'])  opción
// En C++: auto m = modifiers(f); y usa m.id (choice da el índice: 0, 1, 2...).
// Léelos en update y render; reset no recibe el frame.
// id: letras a-z sin acentos ni ñ, números y _; empieza por letra; hasta 24.
//   Es el nombre en C++: no uses intensity, speed, detail, glow, colors,
//   palette, music, time, delta, width, height, seed, modifiers ni palabras
//   de C++ (double, float, auto, static, default, new, union...).
// Nombre visible en español, hasta 24 caracteres; opciones hasta 20; máximo 8.
// Rangos dentro de ±100000; steps admite hasta 1000 pasos entre min y max.
// value es el aspecto inicial; el rango, sólo valores que se sigan viendo bien.
// Si el visual cambia solo (figuras, simetrías, modos), pon 'Auto' primero.
// Cambiar un modificador debe verse suave y en vivo: no reinicies ni reserves
// memoria al cambiarlo; para cantidades, reserva el máximo en reset.
//
// MATERIALES OPCIONALES: añade const shaderSources = <String, String>{
//   'material': r\"\"\"#version 460 core
// #include <flutter/runtime_effect.glsl>
// uniform vec2 uSize;
// uniform float uTime;
// out vec4 fragColor;
// void main() {
//   vec2 uv=FlutterFragCoord().xy/uSize;
//   fragColor=vec4(uv,0.5+0.5*sin(uTime),1.0);
// }
// \"\"\", };
// Dibuja con canvas.material(\"material\", {0,0,f.width,f.height}, {float(f.time)}).
// uSize siempre primero; después float/vec2/vec3/vec4 y sampler2D, sin arrays.
// Material produce RGBA premultiplicado. Sus coordenadas son locales al rectángulo.
// Para aplicarlo a una forma: save(), clip(path), material(...), restore().
// Texturas se nombran en metadata.images: {'foto':'assets/images/foto.png'}.
// canvas.image(\"foto\", rect) dibuja la imagen ya preparada. Los samplers del
// material reciben esas claves en orden: material(\"x\", rect, floats, {\"foto\"}).
// No hay acceso al fotograma anterior, shaders de cómputo ni motor 3D.
//
// REFERENCIA REAL DEL SDK (generada; no redeclarar estas clases):
${api.split('\n').map((line) => '// $line').join('\n')}

import 'package:scene_compositor/authoring.dart';

$_exampleModifiers

const nativeSource = r\"\"\"
$body
\"\"\";
''';
  final target = File('${root.path}/templates/visual_template.dart');
  if (args.contains('--check')) {
    if (!target.existsSync() || target.readAsStringSync() != result) {
      stderr.writeln(
        'La plantilla está desactualizada. Ejecuta tool/generate_template.dart.',
      );
      exitCode = 1;
    }
  } else {
    target.writeAsStringSync(result);
  }
}
