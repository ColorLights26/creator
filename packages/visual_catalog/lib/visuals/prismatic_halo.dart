import 'package:scene_compositor/authoring.dart';

// VISUAL TEMPLATE — copia ESTE ARCHIVO COMPLETO a tu IA.
// Pide: "Crea [tu idea] conservando la API y las reglas de esta plantilla.
// Devuelve este archivo completo, listo para pegar, sin modificar el motor."
//
// Guarda un archivo .dart por visual en packages/visual_catalog/lib/visuals/.
// Conserva la declaración const visual. Cada archivo aparece automáticamente
// al volver a ejecutar la app; no edites imports ni registros. Máximo 64 visuales.
// Usa un ID único: minúsculas, números y guiones bajos, comenzando por letra.
// Guarda y ejecuta de nuevo: un shader nuevo requiere RECOMPILAR, no hot reload.
//
// Esto es Dart para declarar el catálogo y GLSL portable dentro de
// shaderSource. El kit usa SceneSurface/Metal en iOS y FragmentProgram en Android.
// No crear widgets, Canvas, CustomPainter, timers, sensores ni reproductores.
// No imports adicionales, paquetes, archivos, texturas, includes ni entrypoints.
// Puedes escribir funciones auxiliares y esta función obligatoria:
//   vec4 paintVisual(vec2 uv, CreatorFrame f)
// uv: 0..1. Devuelve RGBA recto 0..1 (el motor premultiplica alpha).
// role.background: alpha1. role.overlay: puede tener transparencia.
//
// Usa float/int/vec2/vec3/vec4/mat2/mat3/mat4 y funciones matemáticas
// comunes GLSL (sin uint, bool, structs propios, globals, inout ni pointers).
// atan admite solo un argumento. No uses funciones de textura/derivadas.
// CreatorFrame (ya lo declara el motor; NO lo vuelvas a declarar):
//   vec2 size;             // resolución efectiva en píxeles
//   float time;              // segundos activos; pausa y Reduced Motion nativos
//   float seedLow, seedHigh;  // mitades exactas de16bits de la semilla32bits
//   float energy;            // energía canónica dinámica
//   float bass, body, spark, flow; // canales musicales canónicos 0..1
//   float pulse;             // fuerza de evento nuevo, una presentación
//   float phase, bpm;        // fase de beat0..1 y tempo, 0 si no disponible
//   float intensity, speed, detail, glow; // controles declarados abajo
//   vec4 color0, color1, color2, color3; // paleta RGBA normalizada
//
// Datos ya procesados por el motor: no normalizar otra vez ni inventar beats.
// none: audio cero; music: siempre reactivo; optional: permite activar/desactivar.
// En silencio/no disponible los valores musicales son cero. Debe seguir bonito.
// time avanza aunque no haya música: úsalo para el movimiento de ambiente.
// No se entrega PCM, micrófono ni servicios de la app a este archivo.
//
// Presupuesto: 30FPS. Mantén bucles pequeños y constantes (ideal <=8 pasos),
// evita raymarching volumétrico, recursión, grandes kernels y flashes de pantalla.
// detail debe cambiar densidad, no multiplicar trabajo sin límite.
// El motor limita cadencia/resolución y pausa al salir. Eso no garantiza que
// cualquier shader sea barato: validar el coste en un iPhone antes de integrar.
//
// CreatorControls: intensity/speed/glow 0..2, detail0.25..2.
// colors: exactamente cuatro enteros ARGB. seed:0..4294967295.
// Usa solo CreatorVisualDefinition, CreatorRole, CreatorReactivity,
// CreatorControls, CreatorCredits, CreatorThumbnailSpec, CreatorPublication
// y strings GLSL. Conserva la declaración const visual.

// description/purposes/moods/concepts describen la intención del visual.
// credits registra autoría/licencia/origen. publication.draft aparece en el
// estudio y app debug; published habilita su inclusión en producción.
// La miniatura se congela en thumbnail.timeSeconds, sin reloj ni micrófono.
// Opcional: assetPath en assets/thumbnails/ y assetPackage: visual_catalog.

const visual = CreatorVisualDefinition(
  id: 'prismatic_halo',
  name: 'Halo · capa de luz',
  publication: CreatorPublication.draft,
  description:
      'Un halo de luz transparente que acompaña los acentos musicales.',
  purposes: ['visualizer', 'party'],
  moods: ['dreamy', 'energetic'],
  concepts: ['halo', 'prism', 'light'],
  credits: CreatorCredits(
    author: 'Chic Apps',
    license: 'Proprietary',
    source: 'Visual Studio examples',
  ),
  thumbnail: CreatorThumbnailSpec(timeSeconds: 3),
  role: CreatorRole.overlay,
  reactivity: CreatorReactivity.optional,
  colors: [0xff040712, 0xff49eadc, 0xffb17dff, 0xffffcddd],
  controls: CreatorControls(speed: .5, glow: .8),
  shaderSource: r'''
vec4 paintVisual(vec2 uv, CreatorFrame f) {
  vec2 p = (uv - 0.5) * vec2(f.size.x / max(f.size.y, 1.0), 1.0);
  float radius = 0.27 + 0.015 * sin(f.time * f.speed) + 0.025 * f.bass;
  float distance = abs(length(p) - radius);
  float beam = exp(-distance * distance * 17000.0);
  float halo = exp(-distance * 24.0) * 0.25 * f.glow;
  float alpha = clamp((beam * 0.62 + halo) * f.intensity * (0.8 + 0.2 * f.pulse), 0.0, 1.0);
  vec3 ink = mix(f.color1.rgb, f.color2.rgb, 0.5 + 0.5 * sin(p.x * 7.0 + f.time * 0.2));
  return vec4(ink, alpha);
}
''',
);
