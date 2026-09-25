// CÓDIGO DEL VISUAL — copia este archivo completo a la IA.
// Pide el efecto conservando const shaderSource, paintVisual y estas reglas.
// Guarda la respuesta en packages/visual_catalog/lib/visuals/olas.dart.
// Sus datos van APARTE en olas_metadata.dart (const metadata).
// El generador empareja ambos nombres; no se importan uno al otro.
// Detén y ejecuta Run para compilar; hot reload no basta.
//
// Dart contiene el string GLSL; no añadir widgets, Canvas, timers, sensores,
// imports, dependencias, texturas, includes ni entrypoints distintos.
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

const shaderSource = r'''
vec4 paintVisual(vec2 uv, CreatorFrame f) {
vec2 p = uv - 0.5;
p.x *= f.size.x / max(f.size.y, 1.0);
float t = f.time * f.speed * 0.32;
float seed = mod(f.seedLow + f.seedHigh, 10000.0) * 0.001;
vec3 c = f.color0.rgb * (0.7 + 0.3 * uv.y);
for (int i = 0; i < 4; i++) {
  float k = float(i);
  float center = 0.14 * sin(p.x * (2.0 + k * 0.32) + t + seed + k)
               + 0.08 * cos(p.x * 5.0 * f.detail - t * 0.6 + k)
               + (k - 1.5) * 0.105;
  float d = abs(p.y - center);
  float width = 0.014 + 0.013 * f.bass;
  float core = exp(-d * d / (width * width));
  float halo = exp(-d * 12.0) * 0.13 * f.glow;
  vec3 ink = mix(f.color1.rgb, f.color2.rgb, k / 3.0);
  ink = mix(ink, f.color3.rgb, 0.15 * (0.5 + 0.5 * sin(t + p.x * 2.0 + k)));
  c += ink * (core * 0.30 + halo) * f.intensity * (0.75 + 0.3 * f.energy + 0.15 * f.pulse);
}
float vignette = clamp(1.0 - dot(p, p) * 0.65, 0.25, 1.0);
return vec4(c * vignette, 1.0);
}
''';
