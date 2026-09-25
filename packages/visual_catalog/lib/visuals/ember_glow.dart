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
float vnoise(vec2 p) {
  vec2 i = floor(p);
  vec2 u = fract(p);
  u = u * u * (3.0 - 2.0 * u);
  return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
             mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm4(vec2 p) {
  float v = 0.0;
  float a = 0.5;
  for (int i = 0; i < 4; i++) {
    v += a * vnoise(p);
    p = p * 2.03 + vec2(11.7, 5.3);
    a *= 0.5;
  }
  return v;
}
vec4 paintVisual(vec2 uv, CreatorFrame f) {
  float aspect = f.size.x / max(f.size.y, 1.0);
  vec2 p = vec2((uv.x - 0.5) * aspect, uv.y);
  float t = f.time * f.speed;
  float seed = mod(f.seedLow + f.seedHigh, 65535.0) * 0.019;
  float rise = t * (0.9 + 1.0 * f.flow) + seed;
  float n = fbm4(vec2(p.x * (5.5 * f.detail) + seed, uv.y * 3.2 - rise));
  n = pow(clamp(n * 1.55 - 0.08, 0.0, 1.0), 1.9);
  float lift = uv.y / (0.34 + 0.15 * f.bass);
  float heat = clamp(n * 1.85 - lift * 1.05 + 0.30, 0.0, 1.25);
  heat *= 0.50 + 0.50 * smoothstep(-0.03, 0.10, uv.y);
  vec3 fireCol = f.color1.rgb;
  fireCol = mix(fireCol, f.color2.rgb, clamp(heat * 1.55, 0.0, 1.0));
  fireCol = mix(fireCol, f.color3.rgb, pow(clamp(heat * 1.5 - 0.85, 0.0, 1.0), 1.6));
  vec3 col = mix(f.color0.rgb * 0.55, f.color0.rgb * 0.25, smoothstep(0.25, 1.0, uv.y));
  col += fireCol * heat * (0.85 + 0.40 * f.energy + 0.30 * f.pulse);
  float bed = exp(-(1.0 - uv.y) * 5.5);
  float bedNoise = fbm4(vec2(p.x * (5.0 * f.detail) + seed, rise * 1.2));
  col += mix(f.color1.rgb, f.color2.rgb, bedNoise) * bed * (0.30 + 0.30 * f.bass) * (0.55 + 0.45 * bedNoise);
  for (int i = 0; i < 3; i++) {
    float k = float(i);
    float cols = 6.0 + k * 5.0;
    vec2 gp = vec2(p.x * cols + seed * 7.0 + k * 19.0,
                   (uv.y + t * (0.10 + 0.08 * k) * (1.0 + 0.5 * f.flow)) * (cols * 0.62));
    gp.x += 0.5 * sin(t * 0.5 + k * 2.0 + uv.y * 4.0);
    vec2 cell = floor(gp);
    vec2 h = hash22(cell + k * 41.0);
    float on = step(0.30, h.y);
    vec2 pos = cell + 0.25 + 0.50 * h;
    vec2 dd = gp - pos;
    float d2 = dot(dd, dd);
    float flick = pow(0.5 + 0.5 * sin(t * (2.0 + 3.0 * h.x) + h.y * 6.2831853), 2.0);
    float ember = on * exp(-d2 * (700.0 - k * 140.0)) * flick * (0.45 + 1.25 * f.spark);
    vec3 emberCol = mix(f.color3.rgb, f.color2.rgb, smoothstep(1.0, 0.30, uv.y));
    col += emberCol * ember * 0.75 * (0.7 + 0.5 * f.bass);
  }
  float vig = clamp(1.10 - dot(p, p) * 0.40, 0.40, 1.0);
  return vec4(col * vig * f.intensity, 1.0);
}
''';
