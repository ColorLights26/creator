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
float vnoise(vec2 p) {
  vec2 i = floor(p);
  vec2 u = fract(p);
  u = u * u * u * (u * (u * 6.0 - 15.0) + 10.0);
  float a = hash13(i);
  float b = hash13(i + vec2(1.0, 0.0));
  float c = hash13(i + vec2(0.0, 1.0));
  float d = hash13(i + vec2(1.0, 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
float fbm4(vec2 p) {
  float v = 0.0;
  float a = 0.5;
  for (int i = 0; i < 4; i++) {
    v += a * vnoise(p);
    p = mat2(0.8, 0.6, -0.6, 0.8) * p * 2.02 + vec2(3.1, 7.7);
    a *= 0.5;
  }
  return v;
}
vec3 grade(vec3 c) {
  c = max(c, vec3(0.0));
  c = (c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14);
  return clamp(c, 0.0, 1.0);
}
mat2 rot2o(float a) {
  float c = cos(a);
  float s = sin(a);
  return mat2(c, -s, s, c);
}
vec4 paintVisual(vec2 uv, CreatorFrame f) {
  float aspect = f.size.x / max(f.size.y, 1.0);
  vec2 p = vec2((uv.x - 0.5) * aspect, uv.y - 0.5);
  float t = f.time * f.speed;
  float seed = mod(f.seedLow + f.seedHigh, 65535.0) * 0.011;
  float px = 1.0 / max(f.size.y, 1.0);
  vec3 col = mix(vec3(0.006, 0.008, 0.018), vec3(0.014, 0.020, 0.042), smoothstep(0.0, 1.0, uv.y));
  col += f.color1.rgb * fbm4(p * 1.7 + vec2(seed, -t * 0.006)) * 0.040;
  for (int i = 0; i < 2; i++) {
    float k = float(i);
    vec2 gp = vec2(p.x, uv.y) * (17.0 + k * 15.0) + vec2(seed * 7.0 + k * 29.0, k * 13.0);
    vec2 cell = floor(gp);
    vec2 h = hash23(cell + k * 5.0);
    float on = step(0.962 - 0.020 * k, h.x);
    vec2 pos = cell + 0.25 + 0.5 * h;
    float tw = 0.65 + 0.35 * sin(t * (0.4 + 1.2 * h.y) + h.x * 6.2831853);
    vec2 dd = gp - pos;
    float d = sqrt(dot(dd, dd));
    float r0 = 0.028 + 0.022 * h.y;
    float core = 1.0 - smoothstep(r0 - px * 1.5, r0 + px * 1.5, d);
    col += vec3(0.78, 0.85, 1.0) * (core * on * tw * 0.22);
  }
  float breathe = 0.90 + 0.10 * sin(t * 0.5 + seed);
  float d0 = length(p);
  float star = exp(-d0 * d0 * 300.0);
  float core0 = 1.0 - smoothstep(0.014 - px, 0.014 + px, d0);
  col += mix(f.color2.rgb, vec3(1.0), 0.60) * (star * 0.26 + core0 * 0.85) * breathe;
  col += f.color2.rgb * exp(-d0 * 5.0) * 0.05;
  for (int i = 0; i < 3; i++) {
    float k = float(i);
    vec2 h = hash23(vec2(k * 3.1 + seed, k * 7.7 + 2.0));
    float R = 0.155 + 0.070 * (k + 0.15 * h.x);
    float tiltY = 0.60 + 0.12 * h.x;
    float rotA = (h.y - 0.5) * 0.9;
    float dirS = mix(1.0, -1.0, step(0.5, fract(h.x * 7.3)));
    float spd = (0.10 + 0.04 * k) * (1.0 + 0.18 * h.y) * dirS;
    float ang = h.y * 6.2831853 + t * spd;
    vec2 q = rot2o(-rotA) * p;
    vec2 e = vec2(q.x, q.y / tiltY);
    float de = abs(length(e) - R);
    float lineA = 1.0 - smoothstep(px * 0.6, px * 2.0, de);
    col += f.color1.rgb * lineA * 0.055 * (0.75 + 0.25 * sin(t * 0.3 + k * 2.0));
    vec2 local = vec2(cos(ang) * R, sin(ang) * R * tiltY);
    vec2 cpos = rot2o(rotA) * local;
    vec2 rel = p - cpos;
    float db = length(rel);
    float body = 1.0 - smoothstep(0.0092 - px, 0.0092 + px, db);
    float glowB = exp(-db * 55.0);
    vec3 ink = mix(f.color2.rgb, f.color3.rgb, k * 0.5);
    col += ink * (body * 0.95 + glowB * 0.26);
    vec2 tangent = rot2o(rotA) * normalize(vec2(-sin(ang) * R, cos(ang) * R * tiltY));
    float behind = -dot(rel, tangent);
    float side = dot(rel, vec2(-tangent.y, tangent.x));
    float trail = exp(-max(behind, 0.0) * 95.0) * exp(-side * side * 5200.0);
    col += ink * trail * 0.20;
  }
  col = grade(col * f.intensity);
  col += (hash13(uv * f.size + seed) - 0.5) * 0.006;
  float vig = clamp(1.05 - dot(p, p) * 0.18, 0.6, 1.0);
  return vec4(col * vig, 1.0);
}
''';
