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
vec3 grade(vec3 c) {
  c = max(c, vec3(0.0));
  c = (c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14);
  return clamp(c, 0.0, 1.0);
}
vec4 paintVisual(vec2 uv, CreatorFrame f) {
  float aspect = f.size.x / max(f.size.y, 1.0);
  vec2 p = vec2((uv.x - 0.5) * aspect, uv.y);
  float t = f.time * f.speed * 0.75;
  float seed = mod(f.seedLow + f.seedHigh, 65535.0) * 0.017;
  vec2 q = p * (2.4 + 1.3 * f.detail) + seed;
  float ca = 0.0;
  vec2 wv = vec2(0.0);
  for (int i = 0; i < 3; i++) {
    float k = float(i) + 1.0;
    wv = vec2(sin(q.y * 5.7 * k + t * (0.50 + 0.20 * k) + wv.x * 1.2 + seed),
              sin(q.x * 5.0 * k - t * (0.42 + 0.18 * k) + wv.y * 1.2));
    ca += 0.5 + 0.5 * sin(q.x * (3.1 + 1.6 * k) + wv.x * 2.2 + t * 0.6 * k)
              * sin(q.y * (4.1 - 0.8 * k) + wv.y * 2.0 - t * 0.5 * k);
  }
  ca /= 3.0;
  float fine = 0.5 + 0.5 * sin(q.x * 17.0 + sin(q.y * 13.0 - t * 0.8) + t * 0.9);
  float fil = pow(clamp(ca * 1.42 - 0.26, 0.0, 1.0), 5.2);
  fil += pow(clamp(ca * fine * 1.9 - 0.55, 0.0, 1.0), 4.0) * 0.45;
  float depth = smoothstep(0.0, 1.0, uv.y);
  vec3 col = mix(f.color1.rgb * 0.80, f.color0.rgb, depth);
  col += f.color2.rgb * fil * (0.22 + 0.55 * exp(-uv.y * 2.4));
  col += f.color1.rgb * pow(clamp(ca, 0.0, 1.0), 2.2) * 0.10 * (0.4 + 0.6 * (1.0 - depth));
  float bend = vnoise(vec2(p.x * 1.7 - t * 0.10, uv.y * 1.3)) * 2.0;
  float rays = pow(clamp(0.5 + 0.5 * sin(p.x * (5.0 + 2.0 * f.detail) + bend + t * 0.15 + seed), 0.0, 1.0), 4.5);
  col += mix(f.color2.rgb, f.color3.rgb, 0.4) * rays * exp(-uv.y * 2.9) * 0.15 * (0.4 + 0.6 * f.glow);
  float glintN = vnoise(p * (60.0 + 40.0 * f.detail) + vec2(t * 0.20, -t * 0.14) + seed);
  float glint = pow(clamp(glintN * 1.35 - 0.48, 0.0, 1.0), 8.0);
  col += f.color3.rgb * glint * exp(-uv.y * 3.4) * 0.20 * (0.5 + 0.5 * f.glow);
  col = grade(col * f.intensity);
  col += (hash13(uv * f.size + seed) - 0.5) * 0.007;
  float vig = clamp(1.10 - dot(p, p) * 0.38, 0.45, 1.0);
  return vec4(col * vig, 1.0);
}
''';
