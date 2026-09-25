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
  float seed = mod(f.seedLow + f.seedHigh, 65535.0) * 0.011;
  float px = 1.0 / max(f.size.y, 1.0);
  vec3 acc = vec3(0.0);
  float aAcc = 0.0;
  for (int i = 0; i < 4; i++) {
    float k = float(i);
    float scale = 4.0 + k * 3.6;
    vec2 gp = vec2(p.x, uv.y) * scale;
    gp.y += t * (0.10 + 0.06 * k) * (1.0 + 0.7 * f.flow);
    gp.x += seed + 0.45 * sin(t * 0.18 + k * 2.3 + uv.y * 1.5) + k * 13.7;
    vec2 cell = floor(gp);
    vec2 h = hash23(cell + k * 31.0);
    float on = step(h.y, 0.70 - 0.05 * k);
    vec2 pos = cell + 0.25 + 0.50 * h;
    vec2 dv = gp - pos;
    float d2 = dot(dv, dv);
    float twRaw = 0.5 + 0.5 * sin(t * (0.6 + 2.1 * h.y) + h.x * 6.2831853);
    float eased = twRaw * twRaw * (3.0 - 2.0 * twRaw);
    float tw = 0.10 + 0.90 * pow(clamp(eased + 0.30 * f.spark - 0.14, 0.0, 1.0), 1.6);
    vec3 tint = mix(f.color1.rgb, f.color2.rgb, h.x);
    float big = step(1.5, k);
    float small = 1.0 - big;
    float rad = (0.10 + 0.08 * h.x) * (1.0 + 0.25 * f.bass);
    float core = exp(-d2 / max(rad * rad, 0.0001)) * small;
    float disc = 1.0 - smoothstep(0.55, 0.62, sqrt(d2)) * big;
    float halo = exp(-sqrt(d2) * (7.0 + k * 2.5)) * 0.30 * small;
    float fx = exp(-abs(dv.x) * 120.0) * exp(-abs(dv.y) * 16.0)
             + exp(-abs(dv.y) * 120.0) * exp(-abs(dv.x) * 16.0);
    float flare = fx * step(2.5, k) * 0.38;
    float bodyA = core + halo * tw * (0.35 + 0.65 * f.glow) + flare * tw;
    float discA = disc * big * (0.045 + 0.035 * tw) * (0.6 + 0.4 * f.glow);
    vec3 discTint = mix(f.color1.rgb, f.color2.rgb, 0.6 + 0.3 * h.y);
    acc += (tint * bodyA + discTint * discA) * f.intensity
         * (0.60 + 0.50 * f.bass + 0.40 * f.pulse * tw);
    aAcc += (bodyA * (0.34 - 0.05 * k) + discA * 0.8) * (0.55 + 0.45 * f.glow);
  }
  return vec4(acc, clamp(aAcc, 0.0, 0.82));
}
''';
