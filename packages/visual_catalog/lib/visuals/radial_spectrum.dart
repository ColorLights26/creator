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
float hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.x, p.y, p.x) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}
vec2 hash22(vec2 p) {
  vec3 p3 = fract(vec3(p.x, p.y, p.x) * vec3(0.1031, 0.1030, 0.0973));
  p3 += dot(p3, p3.yzx + 33.33);
  return fract(vec2((p3.x + p3.y) * p3.z, (p3.x + p3.z) * p3.y));
}
vec4 paintVisual(vec2 uv, CreatorFrame f) {
  float aspect = f.size.x / max(f.size.y, 1.0);
  vec2 p = vec2((uv.x - 0.5) * aspect, uv.y - 0.5);
  float r = length(p) + 0.0001;
  float ang = acos(clamp(p.x / r, -1.0, 1.0));
  if (p.y < 0.0) {
    ang = 6.2831853 - ang;
  }
  float t = f.time * f.speed;
  float seed = mod(f.seedLow + f.seedHigh, 65535.0);
  float n = floor(40.0 + 40.0 * f.detail);
  float ac = ang / 6.2831853 * n;
  float ai = floor(ac);
  float af = fract(ac);
  vec2 h = hash22(vec2(ai, seed * 0.37));
  float kick = exp(-f.phase * 3.2);
  float wave = 0.5 + 0.5 * sin(t * 0.9 + ai * 1.7 + h.y * 6.2831853);
  float wB = 0.5 + 0.5 * sin((ai / n) * 12.56637 + t * 0.5);
  float wM = 0.5 + 0.5 * cos((ai / n) * 18.84956 - t * 0.37);
  float wH = 0.5 + 0.5 * sin((ai / n) * 31.41593 + t * 0.61);
  float spec = (f.bass * wB + f.body * wM + f.spark * wH) / max(wB + wM + wH, 0.35);
  float flowMod = 0.10 * f.flow * sin(t * 1.3 + h.x * 6.2831853);
  float level = clamp(0.10 + wave * 0.07 + spec * (0.52 + 0.30 * kick) + flowMod, 0.05, 1.0);
  float r0 = 0.145;
  float len = level * 0.26;
  float barWin = smoothstep(0.02, 0.18, af) * smoothstep(0.98, 0.82, af);
  float rr = r - r0;
  float tip = 1.0 - smoothstep(len * 0.82, len, rr);
  float bar = barWin * smoothstep(-0.010, 0.002, rr) * tip;
  float glowTip = exp(-max(rr - len, 0.0) * 30.0) * barWin * (0.12 + 0.25 * level);
  vec3 barCol = mix(f.color1.rgb, f.color2.rgb, clamp(level * 1.3, 0.0, 1.0));
  barCol = mix(barCol, f.color3.rgb, pow(clamp(level * 1.5 - 0.65, 0.0, 1.0), 1.6));
  vec3 col = mix(f.color0.rgb * 0.85, f.color0.rgb * 0.4, smoothstep(0.0, 0.55, r));
  col += barCol * bar * (0.55 + 0.60 * f.energy + 0.30 * kick * f.bass);
  col += barCol * glowTip * f.glow;
  float rd2 = r - r0;
  col += f.color1.rgb * exp(-rd2 * rd2 * 5200.0) * 0.20 * (0.5 + 0.5 * f.glow);
  col += f.color2.rgb * exp(-r * 6.5) * (0.10 + 0.25 * f.bass * kick);
  float vig = clamp(1.08 - dot(p, p) * 0.30, 0.40, 1.0);
  return vec4(col * vig * f.intensity, 1.0);
}
''';
