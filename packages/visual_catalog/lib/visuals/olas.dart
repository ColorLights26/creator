// PARA EL CREADOR: copia este archivo completo a la IA y describe tu idea.
// Ejemplo: "Quiero un fondo de olas azules suaves que reaccionen a la música".
// No necesitas copiar ni explicar por separado las instrucciones técnicas.
//
// PARA LA IA — CONTRATO DE RESPUESTA:
// Este archivo es la plantilla completa de un visual para Creator.
// La petición del creador describe su aspecto; conserva este contrato técnico.
// Devuelve un único archivo Dart completo: este encabezado de instrucciones y
// const shaderSource = r'''...'''; con el dibujo solicitado dentro del string.
// Devuelve sólo el contenido del archivo, sin explicación ni marcas Markdown.
// No omitas partes con "...". No devuelvas HTML, main(), widgets ni un proyecto.
// Conserva este encabezado para que también acompañe las siguientes revisiones.
// La metadata existe en otro archivo: no la mezcles ni la incluyas en la respuesta.
// Si se pide un fondo, devuelve alpha 1; si se pide una capa transparente,
// las zonas vacías deben devolver alpha 0. Si no se indica tipo, usa un fondo.
// Usa las señales de CreatorFrame si se pide música; con todas a cero el efecto
// debe seguir siendo válido. No inventes APIs ni nombres de señales.
// Antes de responder, revisa formato completo, paintVisual, transparencia,
// compatibilidad de tipos y coste acotado según las reglas que siguen.
//
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
vec4 paintVisual(vec2 uv, CreatorFrame f) {
vec2 q = uv - 0.5;
vec2 p = q;
p.x *= max(f.size.x, 1.0) / max(f.size.y, 1.0);

float intensity = clamp(f.intensity, 0.0, 2.0);
float speed = clamp(f.speed, 0.0, 3.0);
float detail = clamp(f.detail, 0.0, 2.0);
float glow = clamp(f.glow, 0.0, 2.0);

float t = f.time * speed * 0.28;
float seed = mod(
f.seedLow * 0.0174533 + f.seedHigh * 0.0137137,
6.2831853
);

vec3 deepBlue = mix(
vec3(0.006, 0.022, 0.070),
f.color0.rgb * 0.35,
0.20
);
vec3 oceanBlue = mix(
vec3(0.018, 0.115, 0.290),
f.color1.rgb,
0.20
);
vec3 waveBlue = mix(
vec3(0.045, 0.310, 0.590),
f.color2.rgb,
0.22
);
vec3 lightBlue = mix(
vec3(0.240, 0.590, 0.820),
f.color3.rgb,
0.20
);

float depth = smoothstep(0.0, 1.0, uv.y);
vec3 c = mix(deepBlue, oceanBlue, 0.22 + 0.28 * depth);

vec2 lightPosition = vec2(
0.18 * sin(t * 0.23 + seed),
-0.12 + 0.06 * sin(t * 0.19 + seed * 0.71)
);
vec2 lightDistance = p - lightPosition;
float ambientLight = exp(-dot(lightDistance, lightDistance) * 1.65);
c += oceanBlue * ambientLight * 0.14;

float density = 1.70 + 0.60 * detail;
float amplitude = 0.075 + 0.055 * f.bass + 0.018 * f.energy;
float luminosity = 0.78 + 0.22 * f.energy;

for (int i = 0; i < 6; i++) {
float k = float(i);
float layer = k / 5.0;
float offset = seed + k * 0.92;

float primary = sin(
  p.x * density - t * (0.68 + 0.035 * k) + offset
);
float secondary = sin(
  p.x * (2.30 + 0.75 * detail)
  + t * 0.44
  + offset * 1.70
);

float center = (k - 2.5) * 0.17
  + p.x * 0.07
  + amplitude * primary
  + (0.032 + 0.014 * f.flow) * secondary;

float d = p.y - center;
float width = 0.067 + 0.006 * k + 0.020 * f.body;
float normalizedDistance = d / width;
float wave = exp(-normalizedDistance * normalizedDistance);

float crestDistance = (d + width * 0.30)
  / (0.024 + 0.009 * f.body);
float crest = exp(-crestDistance * crestDistance);

float faceLight = 1.0 - smoothstep(-width, width * 1.60, d);
vec3 ink = mix(oceanBlue, waveBlue, 0.28 + 0.60 * layer);
vec3 face = ink * (0.64 + 0.30 * faceLight);

float opacity = wave * (0.25 + 0.07 * f.energy) * intensity;
c = mix(c, face, opacity);

c += ink * wave
  * (0.065 + 0.035 * f.energy)
  * glow * intensity;

float reflection = 0.027 + 0.026 * f.spark + 0.008 * f.pulse;
c += lightBlue * crest * reflection
  * luminosity * glow * intensity;

}

float vignette = 1.0
- 0.26 * smoothstep(0.05, 0.50, dot(q, q));

return vec4(clamp(c * vignette, 0.0, 1.0), 1.0);
}
''';
