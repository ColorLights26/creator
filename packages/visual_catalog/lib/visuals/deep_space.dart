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
  float seed = mod(f.seedLow + f.seedHigh, 65535.0) * 0.017;
  float px = 1.0 / max(f.size.y, 1.0);
  vec3 col = mix(f.color0.rgb * 0.45, f.color0.rgb * 1.15, smoothstep(0.0, 1.0, uv.y));
  vec2 w = vec2(t * 0.010 + seed, -t * 0.007) * (1.0 + f.flow * 0.7);
  float n1 = fbm4(p * 2.1 + w + seed);
  float n2 = fbm4(p * 3.0 - w * 1.25 + 1.9 * n1 + 4.7);
  float neb1 = pow(clamp(n1 * 1.62 - 0.40, 0.0, 1.0), 1.8);
  float neb2 = pow(clamp(n2 * 1.55 - 0.46, 0.0, 1.0), 2.1);
  col += f.color1.rgb * neb1 * (0.30 + 0.30 * f.bass);
  col += f.color2.rgb * neb2 * (0.26 + 0.24 * f.body);
  float dust = pow(clamp(fbm4(p * 4.2 + n2 * 1.6 - w + 9.1), 0.0, 1.0), 2.3);
  col *= 1.0 - 0.42 * dust;
  for (int i = 0; i < 3; i++) {
    float k = float(i);
    vec2 gp = vec2(p.x, uv.y) * (11.0 + k * 10.0) + vec2(seed * 2.3 + k * 9.7, k * 4.3)
            - vec2(0.0, t * (0.030 + 0.018 * k));
    vec2 cell = floor(gp);
    vec2 h = hash23(cell + k * 23.0);
    float on = step(0.935 - 0.025 * k, h.x);
    vec2 pos = cell + 0.30 + 0.40 * h;
    float tw = 0.55 + 0.45 * sin(t * (0.9 + 2.2 * h.y) + h.x * 6.2831853);
    vec2 dd = gp - pos;
    float d = sqrt(dot(dd, dd));
    float r0 = (0.020 + 0.030 * h.y) * (1.0 + 0.45 * f.spark);
    float core = 1.0 - smoothstep(r0 - px * 1.4, r0 + px * 1.4, d);
    float flare = exp(-dd.y * dd.y * 900.0) * exp(-abs(dd.x) * 220.0) * step(0.985, h.x) * 0.35;
    col += vec3(0.80, 0.86, 1.0) * (core + flare) * on * tw * 0.40 * (0.55 + 0.65 * f.glow);
  }
  float ct = floor(t / 11.0 + seed);
  float cs = fract(t / 11.0 + seed);
  vec2 sh = hash23(vec2(ct * 3.7, ct * 1.9) + seed);
  float life = smoothstep(0.0, 0.14, cs) * smoothstep(0.42, 0.16, cs);
  if (life > 0.001) {
    vec2 head = vec2(mix(-0.25, 0.55, sh.x) + cs * mix(0.65, 0.95, sh.y),
                     mix(0.05, 0.38, sh.y) + cs * mix(0.22, 0.50, sh.x));
    vec2 q2 = vec2(p.x, uv.y) - head;
    float along = dot(q2, vec2(0.82, 0.57));
    float perp2 = dot(q2, vec2(-0.57, 0.82));
    float tail = exp(-max(-along, 0.0) * 16.0) * 0.55 + exp(-max(along, 0.0) * 60.0);
    float shoot = life * exp(-perp2 * perp2 * 3200.0) * tail;
    col += vec3(0.95, 0.97, 1.0) * clamp(shoot, 0.0, 1.0) * 0.7;
  }
  col = grade(col * f.intensity);
  col += (hash13(uv * f.size + seed) - 0.5) * 0.008;
  float vig = clamp(1.06 - dot(p, p) * 0.30, 0.5, 1.0);
  return vec4(col * vig, 1.0);
}
''';
