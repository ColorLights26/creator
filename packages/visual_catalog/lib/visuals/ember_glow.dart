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
  float seed = mod(f.seedLow + f.seedHigh, 65535.0) * 0.019;
  float px = 1.0 / max(f.size.y, 1.0);
  vec3 col = mix(f.color0.rgb * 0.50, f.color0.rgb * 0.22, smoothstep(0.25, 1.0, uv.y));
  float rise = t * (0.85 + 0.95 * f.flow) + seed;
  float n = fbm4(vec2(p.x * (5.0 * f.detail) + seed, uv.y * 3.0 - rise));
  n = pow(clamp(n * 1.52 - 0.06, 0.0, 1.0), 1.8);
  float lift = uv.y / (0.33 + 0.15 * f.bass + 0.02 * f.energy);
  float heat = clamp(n * 1.90 - lift * 1.06 + 0.30, 0.0, 1.25);
  heat *= 0.52 + 0.48 * smoothstep(-0.03, 0.10, uv.y);
  vec3 fireCol = mix(f.color1.rgb, f.color2.rgb, clamp(heat * 1.45, 0.0, 1.0));
  fireCol = mix(fireCol, f.color3.rgb, pow(clamp(heat * 1.45 - 0.80, 0.0, 1.0), 1.7));
  col += fireCol * heat * (0.85 + 0.40 * f.energy + 0.30 * f.pulse);
  float bed = exp(-(1.0 - uv.y) * 5.0);
  float pockets = pow(clamp(vnoise(vec2(p.x * (6.5 * f.detail) + seed, t * 0.35)) * 1.45 - 0.30, 0.0, 1.0), 2.2);
  col += mix(f.color1.rgb, f.color2.rgb, pockets) * bed * (0.34 + 0.42 * f.bass) * (0.35 + 0.85 * pockets);
  for (int i = 0; i < 3; i++) {
    float k = float(i);
    float cols = 7.0 + k * 6.0;
    vec2 gp = vec2(p.x * cols + seed * 7.0 + k * 19.0,
                   (uv.y + t * (0.09 + 0.07 * k) * (1.0 + 0.5 * f.flow)) * (cols * 0.60));
    gp.x += 0.6 * sin(t * 0.5 + k * 2.0 + uv.y * 5.0);
    vec2 cell = floor(gp);
    vec2 h = hash23(cell + k * 41.0);
    float on = step(0.72, h.y);
    vec2 pos = cell + 0.25 + 0.50 * h;
    vec2 dd = gp - pos;
    float d2 = dot(dd, dd);
    float flick = pow(0.5 + 0.5 * sin(t * (1.8 + 2.6 * h.x) + h.y * 6.2831853), 2.2);
    float ember = on * exp(-d2 * (620.0 - k * 120.0)) * flick * (0.40 + 1.20 * f.spark);
    vec3 emberCol = mix(f.color3.rgb, f.color2.rgb, smoothstep(1.0, 0.30, uv.y));
    col += emberCol * ember * 0.72 * (0.7 + 0.5 * f.bass);
  }
  col = grade(col * f.intensity);
  col += (hash13(uv * f.size + seed) - 0.5) * 0.008;
  float vig = clamp(1.08 - dot(p, p) * 0.34, 0.42, 1.0);
  return vec4(col * vig, 1.0);
}
''';
