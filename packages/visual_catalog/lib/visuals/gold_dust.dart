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
vec4 paintVisual(vec2 uv, CreatorFrame f) {
  float aspect = f.size.x / max(f.size.y, 1.0);
  vec2 p = vec2((uv.x - 0.5) * aspect, uv.y);
  float t = f.time * f.speed;
  float seed = mod(f.seedLow + f.seedHigh, 65535.0) * 0.011;
  vec3 acc = vec3(0.0);
  float aAcc = 0.0;
  for (int i = 0; i < 4; i++) {
    float k = float(i);
    float scale = 4.5 + k * 3.5;
    vec2 gp = vec2(p.x, uv.y) * scale;
    gp.y += t * (0.10 + 0.06 * k) * (1.0 + 0.7 * f.flow);
    gp.x += seed + 0.4 * sin(t * 0.20 + k * 2.3) + k * 13.7;
    vec2 cell = floor(gp);
    vec2 h = hash22(cell + k * 31.0);
    float on = step(h.y, 0.72 - 0.06 * k);
    vec2 pos = cell + 0.25 + 0.50 * h;
    vec2 dv = gp - pos;
    float d2 = dot(dv, dv);
    float tw = 0.5 + 0.5 * sin(t * (0.7 + 2.4 * h.y) + h.x * 6.2831853);
    tw = pow(clamp(tw + 0.35 * f.spark - 0.18, 0.0, 1.0), 1.5 + 2.0 * h.x);
    float rad = (0.16 + 0.10 * h.x) * (1.0 + 0.25 * f.bass);
    float core = exp(-d2 / (rad * rad));
    float halo = exp(-sqrt(d2) * (9.0 + k * 3.0)) * 0.35;
    float fx = exp(-abs(dv.x) * 90.0) * exp(-abs(dv.y) * 12.0)
             + exp(-abs(dv.y) * 90.0) * exp(-abs(dv.x) * 12.0);
    float flare = fx * step(2.5, k) * 0.30;
    vec3 tint = mix(f.color1.rgb, f.color2.rgb, h.x);
    tint = mix(tint, f.color3.rgb, pow(core, 3.0) * 0.7);
    float a = on * (core * (0.30 + 0.45 * tw) + halo * tw * (0.4 + 0.6 * f.glow) + flare * tw)
            * (0.34 - 0.05 * k) * f.intensity * (0.65 + 0.5 * f.bass + 0.45 * f.pulse * tw);
    acc += tint * a;
    aAcc += a;
  }
  return vec4(acc, clamp(aAcc * (0.55 + 0.45 * f.glow), 0.0, 0.80));
}
''';
