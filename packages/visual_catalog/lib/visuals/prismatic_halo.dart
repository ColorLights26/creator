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
  float seed = mod(f.seedLow + f.seedHigh, 65535.0) * 0.017;
  float px = 1.0 / max(f.size.y, 1.0);
  float base = 0.30 + 0.005 * sin(t * 0.55 + seed) + 0.014 * f.bass + 0.020 * f.pulse;
  float disp = 0.0032 + 0.0016 * f.body + px * 0.6;
  float sig = 0.0034 + px * 0.9;
  float shimmer = 0.74 + 0.16 * sin(ang * 5.0 + t * 0.7 + seed)
                + 0.10 * sin(ang * 9.0 - t * 1.1 + seed * 2.0);
  shimmer = clamp(shimmer + 0.25 * f.spark, 0.0, 1.15);
  float dR = abs(r - base - disp);
  float dG = abs(r - base);
  float dB = abs(r - base + disp);
  float coreR = exp(-dR * dR / (2.0 * sig * sig));
  float coreG = exp(-dG * dG / (2.0 * sig * sig));
  float coreB = exp(-dB * dB / (2.0 * sig * sig));
  vec3 ink = vec3(1.0, 0.36, 0.50) * coreR
           + vec3(0.46, 1.0, 0.64) * coreG
           + vec3(0.40, 0.72, 1.0) * coreB;
  ink *= 0.32 * shimmer;
  float bloom = exp(-abs(r - base) * 30.0) * 0.16 * f.glow * shimmer;
  vec3 tint = mix(f.color1.rgb, f.color2.rgb, 0.5 + 0.5 * sin(ang * 2.0 + t * 0.4));
  vec3 col = ink + tint * bloom;
  float alpha = clamp(dot(vec3(coreR, coreG, coreB), vec3(0.36)) * shimmer + bloom * 1.6, 0.0, 1.0);
  alpha *= f.intensity * (0.9 + 0.2 * f.pulse);
  return vec4(col * f.intensity, clamp(alpha, 0.0, 0.92));
}
''';
