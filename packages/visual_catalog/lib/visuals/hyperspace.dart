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
  vec2 p = vec2((uv.x - 0.5) * aspect, uv.y - 0.5);
  float r = length(p) + 0.0001;
  vec2 dir = p / r;
  float ang = acos(clamp(dir.x, -1.0, 1.0));
  if (dir.y < 0.0) {
    ang = 6.2831853 - ang;
  }
  float t = f.time * f.speed;
  float seed = mod(f.seedLow + f.seedHigh, 65535.0) * 0.007;
  float px = 1.0 / max(f.size.y, 1.0);
  float warp = t * 0.55 + seed + 0.28 * f.flow + 0.20 * f.bass;
  vec3 col = f.color0.rgb * (0.80 - 0.40 * clamp(r, 0.0, 1.0));
  float n = fbm4(dir * 2.0 + vec2(seed, r * 2.6 - warp * 0.7));
  col += f.color2.rgb * pow(clamp(n * 1.45 - 0.48, 0.0, 1.0), 2.3) * 0.30;
  for (int i = 0; i < 3; i++) {
    float k = float(i);
    float ci = 26.0 + k * 20.0;
    float ac = ang / 6.2831853 * ci;
    float ai = floor(ac);
    float af = fract(ac);
    vec2 h = hash23(vec2(ai + k * 57.0, k * 13.7 + seed * 3.0));
    float dAng = abs(af - 0.5 - (h.x - 0.5) * 0.60);
    float z = fract(h.y * 7.31 + warp * (0.50 + 0.28 * k));
    float rr = 0.02 + 1.50 * z * z;
    float sw = 0.030 + 0.26 * z;
    float aw = max(0.045 + 0.09 * z, px * 1.4 * ci / 6.2831853 / max(r, 0.03));
    float dr = (r - rr) / sw;
    float streak = exp(-dAng * dAng / (aw * aw)) * exp(-dr * dr);
    vec3 tint = mix(f.color1.rgb, f.color2.rgb, h.x);
    tint = mix(tint, f.color3.rgb, z * z * 0.60);
    float head = pow(clamp(z, 0.0, 1.0), 5.0);
    col += tint * streak * smoothstep(0.02, 0.20, z) * (0.32 + 0.62 * z)
         * (0.52 + 0.70 * f.energy + 0.28 * f.pulse);
    col += vec3(1.0) * streak * head * 0.25 * (0.4 + 0.8 * f.spark);
  }
  col += mix(f.color2.rgb, f.color3.rgb, 0.4) * exp(-r * (8.0 - 2.2 * f.bass))
       * (0.30 + 0.45 * f.bass + 0.30 * f.pulse);
  col = grade(col * f.intensity);
  col += (hash13(uv * f.size + seed) - 0.5) * 0.006;
  float vig = clamp(1.08 - dot(p, p) * 0.26, 0.40, 1.0);
  return vec4(col * vig, 1.0);
}
''';
