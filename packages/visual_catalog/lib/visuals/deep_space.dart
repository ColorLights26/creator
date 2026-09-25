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
  float seed = mod(f.seedLow + f.seedHigh, 65535.0) * 0.017;
  vec3 col = mix(f.color0.rgb * 0.5, f.color0.rgb * 1.25, smoothstep(0.0, 1.0, uv.y));
  vec2 w = vec2(t * 0.012 + seed, -t * 0.009) * (1.0 + f.flow * 0.8);
  float n1 = fbm4(p * 2.4 + w + seed);
  float n2 = fbm4(p * 3.2 - w * 1.3 + 1.8 * n1 + 4.7);
  float neb1 = pow(clamp(n1 * 1.65 - 0.42, 0.0, 1.0), 1.7);
  float neb2 = pow(clamp(n2 * 1.5 - 0.45, 0.0, 1.0), 2.0);
  col += f.color1.rgb * neb1 * (0.36 + 0.38 * f.bass);
  col += f.color2.rgb * neb2 * (0.30 + 0.30 * f.body);
  float dust = pow(clamp(fbm4(p * 4.6 + n2 * 1.5 - w + 9.1), 0.0, 1.0), 2.2);
  col *= 1.0 - 0.38 * dust;
  for (int i = 0; i < 3; i++) {
    float k = float(i);
    vec2 gp = vec2(p.x, uv.y) * (10.0 + k * 10.0) + vec2(seed * 2.3 + k * 9.7, k * 4.3)
            - vec2(0.0, t * (0.035 + 0.02 * k));
    vec2 cell = floor(gp);
    vec2 h = hash22(cell + k * 23.0);
    float on = step(0.88 - 0.04 * k, h.x);
    vec2 pos = cell + 0.30 + 0.40 * h;
    vec2 dd = gp - pos;
    float d2 = dot(dd, dd);
    float tw = 0.5 + 0.5 * sin(t * (1.0 + 2.6 * h.y) + h.x * 6.2831853);
    float star = on * exp(-d2 * 620.0) * tw * (0.40 + 0.90 * f.spark);
    col += vec3(0.82, 0.88, 1.0) * star * 0.52 * (0.6 + 0.6 * f.glow);
  }
  float ct = floor(t / 9.0 + seed);
  float cx2 = fract(t / 9.0 + seed);
  vec2 sh = hash22(vec2(ct * 3.7, ct * 1.9) + seed);
  vec2 head = vec2(mix(-0.25, 0.60, sh.x) + cx2 * mix(0.70, 1.00, sh.y),
                   mix(0.02, 0.35, sh.y) + cx2 * mix(0.25, 0.55, sh.x));
  float life = smoothstep(0.0, 0.10, cx2) * smoothstep(0.50, 0.22, cx2);
  vec2 q2 = vec2(p.x, uv.y) - head;
  float along = dot(q2, vec2(0.82, 0.57));
  float perp2 = dot(q2, vec2(-0.57, 0.82));
  float tail = exp(-max(-along, 0.0) * 14.0) * 0.5 + exp(-max(along, 0.0) * 55.0);
  float shoot = life * exp(-perp2 * perp2 * 2600.0) * tail;
  col += vec3(1.0) * clamp(shoot, 0.0, 1.0) * 0.8;
  float vig = clamp(1.05 - dot(p, p) * 0.35, 0.45, 1.0);
  return vec4(col * vig * f.intensity, 1.0);
}
''';
