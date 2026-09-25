import 'dart:io';

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
//
// PARA LA IA: entrega únicamente este archivo Dart completo, sin Markdown.
// Conserva las instrucciones y la referencia, reemplaza nativeSource por tu escena.
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
