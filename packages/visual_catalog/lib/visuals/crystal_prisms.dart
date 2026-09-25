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
vec2 hash22(vec2 p) {
  vec3 p3 = fract(vec3(p.x, p.y, p.x) * vec3(0.1031, 0.1030, 0.0973));
  p3 += dot(p3, p3.yzx + 33.33);
  return fract(vec2((p3.x + p3.y) * p3.z, (p3.x + p3.z) * p3.y));
}
mat2 rot2(float a) {
  float c = cos(a);
  float s = sin(a);
  return mat2(c, -s, s, c);
}
vec4 paintVisual(vec2 uv, CreatorFrame f) {
  float aspect = f.size.x / max(f.size.y, 1.0);
  vec2 p = vec2((uv.x - 0.5) * aspect, uv.y - 0.5);
  float t = f.time * f.speed;
  float seed = mod(f.seedLow + f.seedHigh, 65535.0);
  vec3 acc = vec3(0.0);
  float aAcc = 0.0;
  for (int i = 0; i < 5; i++) {
    float k = float(i);
    vec2 h = hash22(vec2(k * 7.7 + seed * 0.11, k * 3.3 + 1.0));
    float orbR = 0.10 + 0.15 * h.y;
    float orbA = t * (0.08 + 0.07 * h.x) * (1.0 + 0.6 * f.flow) + h.x * 6.2831853;
    float orbB = t * (0.06 + 0.05 * h.y) + h.y * 6.2831853;
    vec2 c = vec2(cos(orbA) * orbR * min(aspect * 1.05, 1.3), sin(orbB) * orbR * 0.85);
    float spin = t * (0.30 + 0.45 * h.y) * (1.0 + 0.4 * f.flow) + h.x * 6.2831853 + k;
    vec2 lp = rot2(spin) * (p - c);
    float s = (0.05 + 0.055 * h.x) * (1.0 + 0.18 * f.bass);
    float shape = 0.9 + 0.18 * sin(k * 2.1 + t * 0.35 + seed);
    float d = (abs(lp.x) * 0.60 + abs(lp.y) * 1.0) / shape - s;
    d *= 0.85;
    float fill = smoothstep(0.004, -0.004, d);
    float facet = 0.5 + 0.5 * sin(lp.x * (40.0 + 14.0 * h.y) + lp.y * 26.0 + k * 3.1 + t * 0.10);
    vec2 nl = lp / max(length(lp), 0.0001);
    float sheen = pow(clamp(0.5 + 0.5 * dot(vec2(0.55, 0.83), nl), 0.0, 1.0), 3.0);
    float eR = exp(-abs(d + 0.005) * 150.0);
    float eG = exp(-abs(d) * 160.0);
    float eB = exp(-abs(d - 0.005) * 150.0);
    float kick = 0.55 + 0.30 * f.pulse + 0.15 * f.bass;
    acc += vec3(1.0, 0.30, 0.52) * eR * 0.38 * kick;
    acc += vec3(1.0) * eG * 0.55 * kick * (0.7 + 0.6 * facet);
    acc += vec3(0.32, 0.78, 1.0) * eB * 0.38 * kick;
    vec3 glass = mix(f.color1.rgb, f.color2.rgb, facet);
    glass = mix(glass, f.color3.rgb, sheen * 0.55);
    acc += glass * fill * (0.10 + 0.20 * sheen + 0.06 * facet);
    aAcc += fill * (0.13 + 0.20 * sheen + 0.05 * facet) * (0.75 + 0.5 * f.glow);
    aAcc += (eR + eG + eB) * 0.42 * kick;
    float ty = s * shape * 1.12;
    float tdx = lp.x;
    float tdy = abs(lp.y) - ty;
    float td2 = tdx * tdx + tdy * tdy;
    float glint = exp(-td2 * 5200.0) * (0.25 + 0.75 * f.spark);
    acc += vec3(1.0, 0.95, 0.85) * glint * 0.5;
    aAcc += glint * 0.30;
  }
  return vec4(acc * f.intensity, clamp(aAcc * (0.55 + 0.45 * f.glow), 0.0, 0.9));
}
''';
