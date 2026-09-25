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
vec4 paintVisual(vec2 uv, CreatorFrame f) {
  float aspect = f.size.x / max(f.size.y, 1.0);
  vec2 p = vec2((uv.x - 0.5) * aspect, uv.y);
  float t = f.time * f.speed;
  float seed = mod(f.seedLow + f.seedHigh, 65535.0) * 0.013;
  float px = 1.0 / max(f.size.y, 1.0);
  vec3 acc = vec3(0.0);
  float aAcc = 0.0;
  for (int i = 0; i < 2; i++) {
    float k = float(i);
    float cols = (13.0 + k * 21.0) * f.detail;
    float cx = p.x * cols + k * 23.7 + seed * 5.0;
    float ci = floor(cx);
    float fx = fract(cx) - 0.5;
    vec2 h = hash23(vec2(ci, k * 47.0 + seed));
    float spd = 0.40 + 0.42 * h.y + 0.26 * f.flow + 0.20 * f.bass;
    float len = (0.10 + 0.12 * h.x) * (1.0 + k * 0.45);
    float head = fract(h.x * 11.3 + t * spd);
    float rel = uv.y - head;
    float inTrail = smoothstep(-len - 0.012, -len + 0.03, rel) * (1.0 - smoothstep(-0.015, 0.004, rel));
    float sigCell = max(0.20 - 0.05 * k, px * cols * 1.4);
    float lat = exp(-fx * fx / max(sigCell * sigCell, 0.0001));
    float along = clamp(-rel / max(len, 0.001), 0.0, 1.0);
    float fade = 1.0 - 0.72 * along;
    vec3 tint = mix(f.color1.rgb, f.color2.rgb, h.y);
    tint = mix(tint, f.color3.rgb, 0.28 + 0.22 * h.x);
    float a = inTrail * lat * fade * (0.62 - 0.16 * k) * (0.6 + 0.6 * f.spark + 0.3 * f.energy);
    float hx2 = fx * fx * 420.0;
    float hy2 = rel * rel * 800.0;
    a += exp(-(hx2 + hy2)) * 0.36 * (0.7 + 0.6 * f.spark);
    acc += tint * a;
    aAcc += a;
  }
  for (int j = 0; j < 2; j++) {
    float k = float(j);
    vec2 gp = vec2(p.x, uv.y) * 4.2 + vec2(seed * 3.0 + k * 11.0, -t * 0.05 - k * 0.02);
    vec2 cell = floor(gp);
    vec2 h = hash23(cell + k * 29.0 + seed);
    float on = step(0.42, h.x);
    vec2 pos = cell + 0.25 + 0.50 * h;
    vec2 dd = gp - pos;
    float d2 = dot(dd, dd);
    float bob = 0.5 + 0.5 * sin(t * (0.3 + 0.4 * h.y) + h.x * 6.2831853);
    float g = exp(-d2 * (24.0 - k * 7.0));
    vec3 tint = mix(f.color1.rgb, f.color2.rgb, h.y);
    float a = on * g * bob * (0.14 - 0.05 * k) * (0.7 + 0.5 * f.glow);
    acc += tint * a;
    aAcc += a;
  }
  return vec4(acc * f.intensity, clamp(aAcc * (0.62 + 0.38 * f.glow), 0.0, 0.90));
}
''';
