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
float fbm4(vec2 p) {
  float v = 0.0;
  float a = 0.5;
  for (int i = 0; i < 4; i++) {
    v += a * vnoise(p);
    p = mat2(0.8, 0.6, -0.6, 0.8) * p * 2.02 + vec2(3.1, 7.7);
    a *= 0.5;
  }
  return v;
}
vec3 grade(vec3 c) {
  c = max(c, vec3(0.0));
  c = (c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14);
  return clamp(c, 0.0, 1.0);
}
vec4 paintVisual(vec2 uv, CreatorFrame f) {
  float aspect = f.size.x / max(f.size.y, 1.0);
  vec2 p = vec2((uv.x - 0.5) * aspect, uv.y);
  float t = f.time * f.speed;
  float seed = mod(f.seedLow + f.seedHigh, 65535.0) * 0.011;
  float px = 1.0 / max(f.size.y, 1.0);
  float horizon = 0.46;
  float drive = 0.88 + 0.34 * f.energy + 0.26 * f.pulse;
  float skyMask = smoothstep(1.0, horizon, uv.y);
  vec3 col = mix(f.color0.rgb * 0.16, f.color0.rgb, skyMask);
  col += f.color2.rgb * pow(skyMask, 3.2) * 0.10 * f.glow;
  for (int i = 0; i < 2; i++) {
    float k = float(i);
    vec2 gp = vec2(p.x, uv.y) * (13.0 + k * 11.0) + vec2(seed * 3.1 + k * 7.3, k * 5.9);
    vec2 cell = floor(gp);
    vec2 h = hash23(cell + k * 17.0);
    float on = step(0.955 - 0.02 * k, h.x);
    vec2 pos = cell + 0.25 + 0.5 * h;
    float tw = 0.55 + 0.45 * sin(t * (0.9 + 1.8 * h.y) + h.x * 6.2831853);
    vec2 dd = gp - pos;
    float d = sqrt(dot(dd, dd));
    float r0 = 0.026 + 0.020 * h.y;
    float core = 1.0 - smoothstep(r0 - px * 1.5, r0 + px * 1.5, d);
    col += vec3(0.82, 0.87, 1.0) * core * on * tw * (0.22 + 0.14 * k) * (0.35 + 0.85 * f.spark);
  }
  vec2 sp = vec2(p.x * 1.06, uv.y - (horizon - 0.115));
  float sd = length(sp) - 0.185;
  float disc = 1.0 - smoothstep(-px * 1.2, px * 1.2, sd);
  float stripes = fract(sp.y * 22.0 - t * 0.05 + seed);
  float band = smoothstep(0.02, -0.05, sp.y);
  float gap = mix(1.0, smoothstep(0.30, 0.55, stripes), band);
  disc *= gap;
  vec3 sun = mix(f.color1.rgb, f.color3.rgb, smoothstep(0.20, -0.17, sp.y));
  float halo = exp(-max(sd, 0.0) * 11.0) * 0.30 * f.glow;
  col += sun * disc * (0.95 + 0.30 * f.bass) * drive;
  col += sun * halo;
  for (int i = 0; i < 2; i++) {
    float k = float(i);
    float scale = 2.6 + k * 2.4;
    float ridge = fbm4(vec2(p.x * scale + seed * 3.0 + k * 11.0, k * 4.7));
    float skyline = horizon - 0.006 - ridge * 0.040 * (1.0 - 0.45 * k);
    float m = smoothstep(skyline - px * 1.6, skyline + px * 1.6, uv.y);
    vec3 mCol = mix(f.color0.rgb * 0.50, f.color0.rgb * 0.28, k);
    mCol += sun * exp(-abs(uv.y - skyline) * 90.0) * 0.10 * (1.0 - k * 0.5);
    col = mix(col, mCol, m);
  }
  float ground = smoothstep(horizon - px, horizon + px, uv.y);
  float gz = max(uv.y - horizon, 0.0016);
  float persp = 0.60 / gz;
  vec3 groundCol = f.color0.rgb * 0.40;
  float rowCoord = persp * 0.80 + t * (1.0 + 1.1 * f.flow) + seed * 2.0;
  float rowFr = abs(fract(rowCoord) - 0.5);
  float rowPix = 0.80 * 0.60 / max(gz * gz * f.size.y, 1.0);
  float rowLine = exp(-rowFr * rowFr / max(2.2 * rowPix * rowPix, 0.000001));
  float vx = p.x * persp * 1.30;
  float vFr = abs(fract(vx + 0.5) - 0.5);
  float vPix = 1.30 * 0.60 / max(gz * f.size.x, 1.0);
  float vLine = exp(-vFr * vFr / max(2.2 * vPix * vPix, 0.000001));
  float gridFade = smoothstep(0.0, 0.04, gz) * (0.30 + 0.70 * smoothstep(horizon, 0.92, uv.y));
  vec3 gridCol = mix(f.color3.rgb, f.color1.rgb, 0.30 + 0.30 * smoothstep(horizon, 1.0, uv.y));
  float grid = (rowLine * 1.15 + vLine * 0.95) * gridFade * (0.50 + 0.50 * f.bass) * (0.48 + 0.62 * f.glow);
  col = mix(col, groundCol + gridCol * grid * drive, ground);
  float hb = (uv.y - horizon) * 30.0;
  col += gridCol * exp(-hb * hb) * 0.16 * (0.5 + 0.5 * f.glow);
  col = grade(col * f.intensity);
  col += (hash13(uv * f.size + seed) - 0.5) * 0.007;
  float vig = clamp(1.05 - dot(p, p) * 0.24, 0.45, 1.0);
  return vec4(col * vig, 1.0);
}
''';
