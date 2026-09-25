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
// atan admite solo un argumento. No usa funciones de textura/derivadas.
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
float hash13(vec2 p) {
  vec3 q = fract(vec3(p.x, p.y, p.x) * 0.1031);
  q += dot(q, q.zyx + 31.32);
  return fract((q.x + q.y) * q.z);
}
vec2 hash23(vec2 p) {
  vec3 q = fract(vec3(p.x, p.y, p.x) * vec3(0.1031, 0.1030, 0.0973));
  q += dot(q, q.zyx + 31.32);
  return fract(vec2((q.x + q.y) * q.z, (q.x + q.z) * q.y));
}
vec3 grade(vec3 c) {
  c = max(c, vec3(0.0));
  c = (c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14);
  return clamp(c, 0.0, 1.0);
}
float barLevel(float ai, float n, float seed, float t, float bass, float body, float spark, float flow) {
  vec2 h = hash23(vec2(ai, seed * 0.37));
  float wB = 0.5 + 0.5 * sin((ai / n) * 12.56637 + t * 0.5);
  float wM = 0.5 + 0.5 * cos((ai / n) * 18.84956 - t * 0.37);
  float wH = 0.5 + 0.5 * sin((ai / n) * 31.41593 + t * 0.61);
  float wsum = max(wB + wM + wH, 0.35);
  float spec = (bass * wB + body * wM + spark * wH) / wsum;
  float wave = 0.5 + 0.5 * sin(t * 0.9 + ai * 1.7 + h.y * 6.2831853);
  return clamp(0.10 + wave * 0.06 + spec * 0.55 + 0.08 * flow * sin(t * 1.3 + h.x * 6.2831853), 0.05, 1.0);
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
  float px = 1.0 / max(f.size.y, 1.0);
  float n = floor(44.0 + 36.0 * f.detail);
  float ac = ang / 6.2831853 * n;
  float ai = floor(ac);
  float af = fract(ac);
  float kick = exp(-f.phase * 3.2);
  float lv = 0.0;
  float wsum = 0.0;
  for (int j = 0; j < 5; j++) {
    float o = float(j) - 2.0;
    float wgt = exp(-o * o * 0.5);
    lv += wgt * barLevel(ai + o, n, seed, t, f.bass, f.body, f.spark, f.flow);
    wsum += wgt;
  }
  lv /= wsum;
  float r0 = 0.150;
  float len = lv * 0.24 + 0.012;
  float halfW = 0.34;
  float barWin = smoothstep(0.02, 0.18, af) * (1.0 - smoothstep(0.82, 0.98, af));
  float rr = r - r0;
  float cap = len + px;
  float tipA = 1.0 - smoothstep(cap - px * 2.0, cap + px * 0.5, rr);
  float baseA = smoothstep(-0.010 - px, -0.010 + px, rr);
  float bar = barWin * baseA * tipA;
  float tipGlow = exp(-max(rr - len, 0.0) * 34.0) * barWin * (0.10 + 0.26 * lv);
  vec3 barCol = mix(f.color1.rgb, f.color2.rgb, clamp(lv * 1.35, 0.0, 1.0));
  barCol = mix(barCol, f.color3.rgb, pow(clamp(lv * 1.5 - 0.70, 0.0, 1.0), 1.5));
  vec3 col = mix(f.color0.rgb * 0.90, f.color0.rgb * 0.42, smoothstep(0.0, 0.55, r));
  col += barCol * bar * (0.55 + 0.55 * f.energy + 0.28 * kick * f.bass);
  col += barCol * tipGlow * f.glow;
  float rd = r - r0;
  col += f.color1.rgb * exp(-rd * rd * 5200.0) * 0.16 * (0.5 + 0.5 * f.glow);
  col += f.color2.rgb * exp(-r * 7.0) * (0.08 + 0.22 * f.bass * kick);
  float rippleR = r0 + 0.015 + f.phase * 0.30;
  float ripple = exp(-abs(r - rippleR) * 55.0) * (1.0 - f.phase) * kick;
  col += f.color2.rgb * ripple * 0.18;
  col = grade(col * f.intensity);
  col += (hash13(uv * f.size + seed) - 0.5) * 0.005;
  float vig = clamp(1.08 - dot(p, p) * 0.28, 0.45, 1.0);
  return vec4(col * vig, 1.0);
}
''';
