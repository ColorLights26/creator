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
  vec2 flowV = vec2(t * 0.040, -t * 0.026) * (1.0 + 1.2 * f.flow);
  vec2 q = vec2(fbm4(p * 1.35 + flowV + seed),
                fbm4(p * 1.35 + vec2(4.7, 1.9) - flowV));
  vec2 w = p * (1.8 + 0.7 * f.detail) + 2.2 * q + seed;
  vec2 drift = vec2(t * 0.055, -t * 0.045);
  float e = 0.055;
  float h = fbm4(w + drift);
  float hx = fbm4(w + vec2(e, 0.0) + drift);
  float hy = fbm4(w + vec2(0.0, e) + drift);
  float gain = 7.0;
  vec3 n = normalize(vec3((h - hx) * gain, (h - hy) * gain, 1.0));
  vec3 L = normalize(vec3(-0.42, 0.58, 0.70));
  float diff = clamp(dot(n, L), 0.0, 1.0);
  vec3 V = vec3(0.0, 0.0, 1.0);
  vec3 Rv = reflect(-L, n);
  float spec = pow(clamp(dot(Rv, V), 0.0, 1.0), 34.0);
  float bands = 0.5 + 0.5 * sin(h * (7.5 + 2.0 * f.detail) + t * 0.32 + seed);
  float sheen = pow(diff, 2.2);
  vec3 col = mix(f.color0.rgb * 1.35, f.color1.rgb, diff * 0.75 + bands * 0.18);
  col = mix(col, f.color2.rgb, sheen * (0.52 + 0.30 * f.bass));
  float glintN = vnoise(p * (80.0 + 50.0 * f.detail) + vec2(0.0, t * 0.55) + seed);
  float glint = pow(clamp(glintN * 1.30 - 0.42, 0.0, 1.0), 7.0);
  col += f.color3.rgb * (glint * (0.30 + 1.30 * f.spark) * (0.30 + sheen) + spec * (0.38 + 0.55 * f.spark));
  col *= 0.94 + 0.14 * f.energy + 0.18 * f.pulse;
  col = grade(col * f.intensity);
  col += (hash13(uv * f.size + seed) - 0.5) * 0.007;
  float vig = clamp(1.12 - dot(p, p) * 0.42, 0.45, 1.02);
  return vec4(col * vig, 1.0);
}
''';
