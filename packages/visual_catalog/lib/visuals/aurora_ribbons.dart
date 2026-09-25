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
vec4 paintVisual(vec2 uv, CreatorFrame f) {
  float aspect = f.size.x / max(f.size.y, 1.0);
  vec2 p = vec2((uv.x - 0.5) * aspect, uv.y);
  float t = f.time * f.speed;
  float seed = mod(f.seedLow + f.seedHigh, 65535.0) * 0.013;
  float px = 1.0 / max(f.size.y, 1.0);
  vec3 col = mix(vec3(0.010, 0.015, 0.036), vec3(0.003, 0.005, 0.016), smoothstep(0.0, 1.0, uv.y));
  col += f.color1.rgb * fbm4(vec2(p.x * 0.9 + seed, uv.y * 1.4 - t * 0.008)) * 0.030;
  for (int i = 0; i < 2; i++) {
    float k = float(i);
    vec2 gp = vec2(p.x, uv.y) * (15.0 + k * 13.0) + vec2(seed * 9.0 + k * 31.0, k * 17.0);
    gp.y += t * (0.005 + 0.004 * k);
    vec2 cell = floor(gp);
    vec2 h = hash23(cell + k * 7.0);
    float on = step(0.958 - 0.022 * k, h.x);
    vec2 pos = cell + 0.25 + 0.5 * h;
    float tw = 0.6 + 0.4 * sin(t * (0.6 + 1.6 * h.y) + h.x * 6.2831853);
    vec2 dd = gp - pos;
    float d = sqrt(dot(dd, dd));
    float r0 = (0.030 + 0.024 * h.y) * (1.0 + 0.5 * f.spark);
    float core = 1.0 - smoothstep(r0 - px * 1.5, r0 + px * 1.5, d);
    col += vec3(0.74, 0.82, 1.0) * (core * on * tw * (0.28 + 0.22 * k)) * (0.7 + 0.6 * f.glow);
  }
  for (int i = 0; i < 3; i++) {
    float k = float(i);
    float base = 0.62 + 0.09 * k;
    float drift = t * (0.026 + 0.011 * k) + seed + k * 3.7;
    float warp = fbm4(vec2(p.x * (1.4 + 0.5 * k) + drift * (1.7 + 0.5 * k), drift * 0.6 + k * 5.0));
    float baseY = base + 0.11 * (warp - 0.5);
    float onoff = smoothstep(0.34, 0.62, fbm4(vec2(p.x * 1.15 + drift * 2.6 + k * 9.0, k * 4.1)));
    float above = uv.y - baseY;
    float fadeK = 4.6 + 1.4 * k;
    float body = exp(-max(above, 0.0) * fadeK) * step(0.0, above);
    float rim = exp(-abs(above) * 46.0);
    float rays = 0.60 + 0.40 * vnoise(vec2(p.x * (26.0 + 10.0 * k) + drift * 3.2, k * 3.0 + drift * 0.5));
    float curtain = onoff * rays * (rim * 0.85 + body * 0.30);
    float hMix = clamp(above * 3.2, 0.0, 1.0);
    vec3 ink = mix(f.color1.rgb, f.color2.rgb, hMix);
    ink = mix(ink, f.color3.rgb, pow(hMix, 2.5) * 0.55);
    col += ink * curtain * (0.30 + 0.26 * f.bass) * (0.80 + 0.34 * f.energy + 0.20 * f.pulse);
  }
  float ground = smoothstep(0.055, -0.01, uv.y);
  col = mix(col, vec3(0.004, 0.007, 0.014), ground * 0.85);
  col = grade(col * f.intensity);
  col += (hash13(uv * f.size + seed) - 0.5) * 0.007;
  float vig = clamp(1.06 - dot(p, p) * 0.20, 0.55, 1.0);
  return vec4(col * vig, 1.0);
}
''';
