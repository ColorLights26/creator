import 'dart:io';

/// The example's settings and looks: the body reads them with glide(f).
const _exampleModifiers = '''// Ajustes propios de este visual: Studio los muestra en Ajustes.
const modifiers = [
  // FORMA
  CreatorModifier.steps('brazos', 'Brazos', min: 2, max: 8, value: 4),
  // MÚSICA: cómo se ve el ritmo.
  CreatorModifier.choice(
    'pulso',
    'Pulso',
    options: ['Graves', 'Golpes', 'Brillos'],
  ),
  // ATMÓSFERA
  CreatorModifier.slider('estela', 'Estela', min: 0, max: 1, value: .35),
  // MODO: cambia la estructura.
  CreatorModifier.toggle('espejo', 'Espejo'),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Tormenta', {
    'brazos': 8,
    'pulso': 'Golpes',
    'estela': .9,
    'espejo': true,
    'speed': 1.4,
  }),
  CreatorVariation('Calma', {
    'brazos': 2,
    'pulso': 'Graves',
    'estela': .1,
    'speed': .5,
  }),
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
          .trim()
          // The SDK allows Random in update, but the 30/60 FPS rule of the
          // template does not: the reference says what the rules say.
          .replaceAll(
            'call during reset/update, never render',
            'call only during reset (30/60 FPS rule)',
          );
  final body =
      File(
        '${root.path}/templates/visual_template_body.cpp',
      ).readAsStringSync().trim();
  final result =
      '''// PARA FRANCO: copia TODO este archivo a tu IA y describe el visual que quieres.
// Pega su respuesta completa en tu archivo .dart. Metadata en el archivo compañero.
// Guarda y usa Stop → Run. No necesitas registrar nada ni tocar el motor.
// Sus modificadores y variaciones aparecen en Studio, en Ajustes, para probarlos.
//
// PARA LA IA: entrega únicamente este archivo Dart completo, sin Markdown.
// Conserva las instrucciones y la referencia; reemplaza modifiers, variations y
// nativeSource por los de tu escena. Conserva el import: lo necesitan.
// nativeSource es C++17: define class Visual final : public Scene.
// Puedes crear algoritmos, structs, vectores, estado persistente, partículas,
// curvas y funciones auxiliares. La instancia es independiente por reproducción.
// No pongas includes dentro del string: el motor ya incluye algorithm, array,
// cmath, cstdint, initializer_list, memory, stdexcept, string y vector.
// reset(seed) inicializa toda la memoria; update(frame) mueve la simulación;
// render(frame,canvas) const sólo dibuja. No uses globals mutables, relojes del sistema,
// timers, sensores, red, archivos, hilos ni servicios de la app.
// Frame.time/delta son segundos activos, con pausa y delta acotado por el motor.
// Usa delta para velocidades; Random(seed) sólo en reset.
//
// 30 Y 60 FPS (Creator lo comprueba): sin música, el dibujo debe ser el mismo a
// 30 y a 60 FPS. Lleva un reloj propio en update (reloj += f.delta * f.speed) y
// acumula fases exactas con él. Para partículas, reserva un grupo fijo en reset
// y calcula cada una con una fórmula de ese reloj (edad = fmod(reloj + desfase,
// vida); posición = inicio + vel * edad): renacen por ciclo, sin Random en update
// y sin crear ni borrar por cuadro. Para ráfagas con cada golpe, guarda en update
// un anillo fijo de ranuras {inicio = reloj, fuerza} y dibuja cada chispa en
// render con (reloj - inicio). No integres en posiciones valores suavizados por
// cuadro (x += suave * delta). Evita pow, sqrt o log de valores que puedan ser
// negativos o cero.
//
// MÚSICA QUE SE VE: la energía (f.music.energy, bass) respira lento; los eventos
// (f.music.events) dan golpes cortos que se apagan. Un golpe fuerte debe verse a
// simple vista: un destello, una ráfaga, un cambio de forma o de movimiento. Lo
// que se limita es el tamaño y el brillo: con intensity 2 y música fuerte,
// crece como mucho un 25%, deja ~30% de oscuridad y no apiles capas aditivas ni
// rampas de color hasta el blanco. Sin música, el visual vive con su propio
// movimiento.
// Music.events ya está deduplicado. Si music.active=false, sus señales son cero.
// Apagar música no borra partículas existentes. No inventes golpes desde bpm.
// width/height son píxeles lógicos, origen arriba izquierda, y hacia abajo.
// Color usa RGBA recto. Un fondo debe cubrir el lienzo; un overlay conserva alpha.
// Agrupa partículas con Canvas.points. saveLayer aplica opacidad al grupo completo.
// Balancea save/saveLayer con restore. clip intersecta recortes anidados.
// Path.fillRule=FillRule::evenOdd permite huecos. Blend: sourceOver, plus, screen.
// El motor posee cadencia/calidad/recursos: 30 FPS por defecto; pedir 60 no lo fuerza.
// 60 FPS solo si cabe en 4 ms de GPU y 2 ms de CPU por cuadro; si no, 30
// (framesPerSecond en la metadata). El dibujo debe ser el mismo a 30 y a 60.
// Acota memoria y trabajo según tu escena. No existe un máximo artificial de 8 bucles.
//
// PASADAS (Creator las cuenta): el teléfono pinta cada cuadro en pasadas y
// cada una ocupa memoria hasta terminar el cuadro. Es una pasada de pantalla
// completa: cada points(); cada tramo seguido de figuras (path, rect, circle)
// con la misma Blend; y, por cada clip activo, una más en cada tramo, points(),
// imagen o material. Cada material es una pasada del tamaño de su rectángulo.
// save, restore, saveLayer, transform/translate/rotate/scale, clip y cambiar
// de Blend cortan el tramo de figuras. Límite duro, con los ajustes iniciales y
// música fuerte: 28 pasadas por cuadro en el iPad (900x1296 px) y 35 en el
// iPhone (664x1440 px); con más, la imagen se congela y la revisión falla. Con
// todos los ajustes al máximo o en una variación, más de 28 en el iPad es un
// aviso: corrígelo también. Apunta a menos de 10. Recetas:
// - agrupa por mezcla: todas las figuras sourceOver seguidas, luego las plus;
// - un lote de puntos: todas las partículas de un color en un solo points();
// - transforma en C++: calcula tú las coordenadas (rotar, escalar) en vez de
//   save/translate/rotate/restore por figura;
// - sin recorte por celda: nada de clip dentro de un bucle.
// Las pasadas no son bucles: dentro de un tramo o de un lote dibuja todas las
// figuras y puntos que tu escena necesite.
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
// MODIFICADORES (SIEMPRE): declara de 3 a 5, cada uno de una familia distinta:
//   FORMA: cantidad, simetría, figura, estructura.
//   MOVIMIENTO: el carácter (fluido, nervioso, orbital), nunca la velocidad; que
//     se note también en una imagen fija (la forma del camino, la estela).
//   MÚSICA (obligatorio si reactivity no es none; con none no lo declares,
//     no cambiaría nada): qué parte del visual reacciona. En un choice como
//     'Pulso': Graves / Golpes / Brillos, cada opción mueve algo distinto (los
//     graves inflan la forma, los golpes lanzan ráfagas, los brillos centellean);
//     no la misma reacción con otra fuente.
//   ATMÓSFERA: estela, bruma, profundidad, textura.
//   MODO: un interruptor que cambia la estructura (Espejo, Contorno).
// Cada uno debe cambiar el visual a simple vista: su mínimo y su máximo deben
// parecer dos visuales distintos y los dos bonitos, también con detail 2,
// intensity 2 y música fuerte. Si sólo cambia un detalle pequeño, quítalo.
// No repitas los básicos (intensidad, velocidad, detalle, brillo) ni la paleta:
// Creator rechaza el visual. Un interruptor sólo para un modo que cambia la
// estructura (Espejo, Contorno), nunca para encender un adorno.
// Van en const modifiers, antes de nativeSource. El valor inicial de un choice
// es su primera opción (o value: con el índice). Tipos:
//   CreatorModifier.slider('id', 'Nombre', min: .5, max: 2, value: 1)    decimal
//   CreatorModifier.steps('id', 'Nombre', min: 3, max: 12, value: 6)     entero
//   CreatorModifier.toggle('id', 'Nombre', value: true)                  sí / no
//   CreatorModifier.choice('id', 'Nombre', options: ['A', 'B', 'C'])     opción
// En C++: auto m = modifiers(f); para decidir (float, int, bool o el índice).
//   auto g = glide(f); para transformarse: el motor ya suaviza cada cambio.
//   g.<slider> y g.<steps> son decimales que se deslizan (5.4 brazos: mezcla 5
//   y 6); g.<toggle> va de 0 a 1 (úsalo como opacidad o como la parte de los
//   elementos que cambian); g.<choice>.weight(i) es
//   el peso de la opción i y los pesos suman 1: mezcla las opciones con ellos.
//   No escribas tu propio suavizado de los ajustes.
// Calcula el aspecto en render (así se ve en pausa); update sólo acumula
// movimiento. Reserva el máximo en reset; nunca reserves memoria ni reinicies
// al cambiar un ajuste. Para materiales, pasa los valores y pesos como floats.
// Al fundir dos opciones, reparte los elementos entre ambas en vez de dibujar
// dos pasadas completas. Límites por cuadro: 28 pasadas (35 en el iPhone),
// 32768 puntos por lote y 1 MiB de comandos; colores y opacidades entre 0 y 1
// (usa std::clamp).
// id: letras a-z sin acentos ni ñ, números y _; empieza por letra; hasta 24.
//   Es el nombre en C++: no uses intensity, speed, detail, glow, colors,
//   palette, music, time, delta, width, height, seed, modifiers, glide ni
//   palabras de C++ (double, float, auto, static, default, new, union...).
//   No leas f.modifiers[...] ni declares nada llamado modifiers, glide o Creator*.
// Nombre visible en español, hasta 24 caracteres; opciones hasta 20; máximo 8.
// Rangos dentro de ±100000; steps admite hasta 1000 pasos entre min y max.
//
// VARIACIONES (SIEMPRE): 2 o 3 en const variations, después de modifiers:
//   CreatorVariation('Tormenta', {'brazos': 8, 'pulso': 'Golpes', 'speed': 1.4})
// Cada una debe parecer otro visual. Claves: los ids de tus modificadores o
// intensity, speed, detail y glow. Un choice va con el texto de su opción y un
// toggle con true o false. Nombre de hasta 20 caracteres, distinto de 'Original'.
//
// Creator prueba cada mínimo, máximo, opción y variación con música: un ajuste
// que no cambia nada o que falla impide la aprobación.
// ANTES DE ENTREGAR, comprueba: 3 a 5 ajustes de familias distintas y uno
// musical (si reacciona); cada id se lee en el C++; ninguno repite un básico; extremos seguros
// con detail 2; 2 o 3 variaciones; el movimiento es igual a 30 y 60 FPS;
// 28 pasadas por cuadro como máximo con los ajustes iniciales (límite duro) y
// también con todos al máximo y en cada variación (si no, Creator avisa); cuenta
// points(), materiales, tramos de figuras por Blend y recortes; 60 FPS solo si
// cabe en 4 ms de GPU y 2 ms de CPU por cuadro.
//
// MATERIALES OPCIONALES: añade, después de nativeSource,
// const shaderSources = <String, String>{
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
