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
  float seed = mod(f.seedLow + f.seedHigh, 65535.0) * 0.013;
  vec2 drift = vec2(t * 0.045, -t * 0.030) * (1.0 + 1.6 * f.flow);
  vec2 q = vec2(fbm4(p * 1.7 + drift + seed),
                fbm4(p * 1.7 + vec2(5.2, 1.3) - drift + seed));
  float freq = 1.5 + 0.9 * f.detail;
  vec2 r = vec2(fbm4(p * freq + 2.4 * q + vec2(1.7, 9.2) + vec2(t * 0.06, -t * 0.05)),
                fbm4(p * freq + 2.4 * q + vec2(8.3, 2.8) + vec2(-t * 0.04, t * 0.055)));
  float ridge = fbm4(p * (2.1 + f.detail * 0.4) + 3.0 * r + seed);
  float bands = 0.5 + 0.5 * sin((p.y * 3.4 + p.x * 1.2) * (0.8 + 0.6 * f.detail)
                + ridge * 7.0 + t * 0.4 + seed);
  float silk = pow(bands, 2.6);
  float sheen = pow(clamp(ridge * 1.5 - 0.42, 0.0, 1.0), 2.6);
  vec3 col = mix(f.color0.rgb, f.color0.rgb * 1.9, smoothstep(1.0, 0.0, uv.y));
  col = mix(col, f.color1.rgb, clamp(silk * 0.9, 0.0, 1.0));
  col = mix(col, f.color2.rgb, sheen * (0.50 + 0.35 * f.bass));
  float glintN = vnoise(p * (70.0 + 60.0 * f.detail) + vec2(0.0, t * 0.6) + seed);
  float glint = pow(clamp(glintN * 1.25 - 0.28, 0.0, 1.0), 8.0);
  col += f.color3.rgb * glint * (0.25 + 1.4 * f.spark) * (0.35 + sheen);
  col *= 0.90 + 0.18 * f.energy + 0.22 * f.pulse;
  float vig = clamp(1.15 - dot(p, p) * 0.5, 0.4, 1.05);
  return vec4(col * vig * f.intensity, 1.0);
}
''';
