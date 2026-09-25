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
  float drive = 0.85 + 0.40 * f.energy + 0.30 * f.pulse + 0.20 * f.bass;
  float horizon = 0.46;
  float skyMask = smoothstep(1.0, horizon, uv.y);
  vec3 sky = mix(f.color0.rgb * 0.22, f.color0.rgb, skyMask);
  sky += f.color2.rgb * pow(skyMask, 3.0) * 0.16 * f.glow;
  for (int i = 0; i < 2; i++) {
    float k = float(i);
    vec2 gp = vec2(p.x, uv.y) * (11.0 + k * 9.0) + vec2(seed * 3.1 + k * 7.3, k * 5.9);
    gp.y += t * (0.06 + 0.05 * k);
    vec2 cell = floor(gp);
    vec2 h = hash22(cell + k * 17.0);
    float on = step(0.86 - 0.05 * k, h.x);
    vec2 pos = cell + 0.25 + 0.5 * h;
    vec2 dd = gp - pos;
    float d2 = dot(dd, dd);
    float tw = 0.45 + 0.55 * sin(t * (1.2 + 2.4 * h.y) + h.x * 6.2831853);
    float star = on * exp(-d2 * 700.0) * tw * (0.35 + 0.85 * f.spark);
    sky += vec3(0.85, 0.90, 1.0) * star * skyMask * 0.30;
  }
  vec2 sp = vec2(p.x * 1.06, uv.y - (horizon - 0.155));
  float sd = length(sp) - 0.245;
  float disc = smoothstep(0.010, -0.010, sd);
  float stripes = fract(sp.y * 21.0 - t * 0.05 + seed);
  float gap = mix(1.0, smoothstep(0.28, 0.52, stripes), smoothstep(-0.02, 0.16, sp.y));
  disc *= gap;
  vec3 sun = mix(f.color1.rgb, f.color2.rgb, smoothstep(-0.24, 0.24, sp.y));
  float halo = exp(-max(sd, 0.0) * 7.0) * 0.40 * f.glow;
  vec3 col = sky + sun * disc * (0.85 + 0.35 * f.bass) * drive + sun * halo;
  float ground = smoothstep(horizon - 0.0025, horizon + 0.0025, uv.y);
  float gz = max(uv.y - horizon, 0.0018);
  float persp = 0.62 / gz;
  vec3 groundCol = f.color0.rgb * 0.42;
  float rowCoord = persp * 0.85 + t * (1.1 + 1.2 * f.flow) + seed * 2.0;
  float rowFr = abs(fract(rowCoord) - 0.5);
  float rowPix = 0.85 * 0.62 / max(gz * gz * f.size.y, 1.0);
  float rowLine = exp(-rowFr * rowFr / max(2.2 * rowPix * rowPix, 0.000001));
  float vx = p.x * persp * 1.35;
  float vFr = abs(fract(vx + 0.5) - 0.5);
  float vPix = 1.35 * 0.62 / max(gz * f.size.x, 1.0);
  float vLine = exp(-vFr * vFr / max(2.2 * vPix * vPix, 0.000001));
  float gridFade = smoothstep(0.0, 0.045, gz) * (0.35 + 0.65 * smoothstep(horizon, 0.95, uv.y));
  vec3 gridCol = mix(f.color3.rgb, f.color1.rgb, 0.25 + 0.30 * smoothstep(horizon, 1.0, uv.y));
  float grid = (rowLine + vLine * 0.85) * gridFade * (0.55 + 0.45 * f.bass) * (0.40 + 0.60 * f.glow);
  col = mix(col, groundCol + gridCol * grid * drive, ground);
  float hb = (uv.y - horizon) * 26.0;
  col += gridCol * exp(-hb * hb) * 0.22 * (0.5 + f.glow * 0.5);
  float vig = clamp(1.0 - dot(p, p) * 0.28, 0.35, 1.0);
  return vec4(col * vig * f.intensity, 1.0);
}
''';
