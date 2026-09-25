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
vec4 paintVisual(vec2 uv, CreatorFrame f) {
  float aspect = f.size.x / max(f.size.y, 1.0);
  vec2 p = vec2((uv.x - 0.5) * aspect, uv.y);
  float t = f.time * f.speed * 0.8;
  float seed = mod(f.seedLow + f.seedHigh, 65535.0) * 0.017;
  vec2 q = p * (2.6 + 1.4 * f.detail) + seed;
  float ca = 0.0;
  vec2 wv = vec2(0.0);
  for (int i = 0; i < 3; i++) {
    float k = float(i) + 1.0;
    wv = vec2(sin(q.y * 5.9 * k + t * (0.50 + 0.20 * k) + wv.x * 1.2 + seed),
              sin(q.x * 5.1 * k - t * (0.42 + 0.18 * k) + wv.y * 1.2));
    ca += 0.5 + 0.5 * sin(q.x * (3.0 + 1.6 * k) + wv.x * 2.2 + t * 0.6 * k)
              * sin(q.y * (4.2 - 0.8 * k) + wv.y * 2.0 - t * 0.5 * k);
  }
  ca /= 3.0;
  float fil = pow(clamp(ca * 1.45 - 0.30, 0.0, 1.0), 5.0);
  float depth = smoothstep(0.0, 1.0, uv.y);
  vec3 col = mix(f.color1.rgb * 0.75, f.color0.rgb, depth);
  col += f.color2.rgb * fil * (0.26 + 0.62 * exp(-uv.y * 2.6));
  col += f.color1.rgb * pow(clamp(ca, 0.0, 1.0), 2.0) * 0.14 * (0.4 + 0.6 * (1.0 - depth));
  float bend = vnoise(vec2(p.x * 1.8 - t * 0.11, uv.y * 1.4)) * 1.8;
  float rays = pow(clamp(0.5 + 0.5 * sin(p.x * (5.5 + 2.0 * f.detail) + bend + t * 0.16 + seed), 0.0, 1.0), 4.0);
  col += mix(f.color2.rgb, f.color3.rgb, 0.4) * rays * exp(-uv.y * 3.1) * 0.20 * (0.4 + 0.6 * f.glow);
  vec2 gp = vec2(p.x, uv.y) * 13.0 + vec2(seed * 5.0, -t * 0.12);
  vec2 cell = floor(gp);
  vec2 h = hash22(cell + 7.7);
  float on = step(0.90, h.x);
  vec2 pos = cell + 0.30 + 0.40 * h;
  float tw = 0.5 + 0.5 * sin(t * (0.8 + 1.6 * h.y) + h.x * 6.2831853);
  vec2 dd = gp - pos;
  float d2 = dot(dd, dd);
  col += f.color3.rgb * on * exp(-d2 * 420.0) * tw * 0.16 * (0.5 + 0.5 * f.glow);
  float vig = clamp(1.12 - dot(p, p) * 0.42, 0.42, 1.0);
  return vec4(col * vig * f.intensity, 1.0);
}
''';
