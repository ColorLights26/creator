// Destellos Anamórficos — las rayas de luz de las lentes de cine.
// Las lentes anamórficas convierten cada luz fuerte en una raya horizontal
// larga: blanca en el centro y de un azul intenso hacia las puntas. Además
// dejan fantasmas azules y naranjas: reflejos ovalados o hexagonales, con
// los bordes irisados por la aberración cromática, alineados en la recta que
// une la luz con el centro de la imagen, y un aro cálido alrededor. Este visual no tiene
// fondo: se pone encima de cualquier otro y le añade luces que flotan,
// barridos de luz que cruzan la pantalla y estrellas que estallan.
// Música: con Golpes, cada golpe hace estallar una luz (destello, estrella
// de ocho puntas y una onda naranja que se abre) y uno de cada dos lanza un
// barrido de luz de lado a lado; todas las rayas se alargan con el golpe.
// Con Graves, la luz principal respira: crece, su raya se engrosa y sus
// fantasmas y su aro se encienden con los graves. Con Brillos, los agudos
// hacen centellear las luces y encienden destellos de cuatro puntas por
// toda la pantalla. Sin música las luces derivan y cada pocos segundos un
// barrido cruza la imagen.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // FORMA: el tipo de lente.
  CreatorModifier.choice(
    'lente',
    'Lente',
    options: ['Anamórfica', 'Estrella', 'Arco'],
  ),
  // MOVIMIENTO: luces que flotan, que pasan de lado a lado o que orbitan.
  CreatorModifier.choice(
    'recorrido',
    'Recorrido',
    options: ['Deriva', 'Barrido', 'Órbita'],
  ),
  // MÚSICA
  CreatorModifier.choice(
    'pulso',
    'Pulso',
    options: ['Golpes', 'Graves', 'Brillos'],
  ),
  // ATMÓSFERA: fantasmas y aro de la lente, de una lente limpia a una vieja.
  CreatorModifier.slider('reflejos', 'Reflejos', min: 0, max: 1, value: .6),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Ciencia Ficción', {
    'lente': 'Anamórfica',
    'recorrido': 'Barrido',
    'pulso': 'Golpes',
    'reflejos': .9,
    'speed': 1.3,
  }),
  CreatorVariation('Cristal Estelar', {
    'lente': 'Estrella',
    'recorrido': 'Órbita',
    'pulso': 'Brillos',
    'reflejos': .3,
  }),
];

const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kLights = 6;
  static constexpr int kBursts = 4;
  static constexpr int kSweeps = 2;
  float bass = 0, spark = 0, slowBass = 0, kick = 0, flash = 0;
  // Relojes en doble precisión: sin música el dibujo es igual a 30 y 60 FPS.
  // clock sigue a Velocidad; secs mide segundos para los golpes.
  double clock = 0, secs = 0;
  std::array<float, kLights> fx{}, fy{}, phx{}, phy{}, rowY{}, speedK{}, sizeK{}, orbitK{};
  // Estallidos: anillo fijo de ranuras {inicio, fuerza, luz}.
  std::array<double, kBursts> burstAt{};
  std::array<float, kBursts> burstPow{};
  std::array<int, kBursts> burstLight{};
  // Barridos lanzados por los golpes: {inicio, fuerza, altura, sentido}.
  std::array<double, kSweeps> sweepAt{};
  std::array<float, kSweeps> sweepPow{}, sweepY{}, sweepDir{};
  uint32_t beats = 0;
  int nextBurst = 0, nextSweep = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }
  static float hashU(uint32_t x) {
    x ^= x >> 16; x *= 0x7feb352dU; x ^= x >> 15; x *= 0x846ca68bU; x ^= x >> 16;
    return float(x & 0xffffffu) / 16777216.0f;
  }
  // Detalle: cuántas luces hay (3 a 6).
  static int lightCount(float detail) {
    return std::clamp(int(std::lround(2.0f + 2.0f * detail)), 1, kLights);
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = spark = slowBass = kick = flash = 0;
    clock = double(rng.unit()) * 40.0;
    secs = 0;
    for (int i = 0; i < kLights; i++) {
      const size_t s = size_t(i);
      fx[s] = 0.6f + 0.8f * rng.unit();
      fy[s] = 0.6f + 0.8f * rng.unit();
      phx[s] = rng.unit() * 6.2831853f;
      phy[s] = rng.unit() * 6.2831853f;
      rowY[s] = (float(i) + 0.5f) / float(kLights) * 1.5f - 0.75f + (rng.unit() - 0.5f) * 0.12f;
      speedK[s] = 0.6f + 0.8f * rng.unit();
      sizeK[s] = i == 0 ? 1.55f : 0.6f + 0.45f * rng.unit();
      orbitK[s] = i == 0 ? 0.55f : 0.35f + 0.65f * rng.unit();
    }
    burstAt.fill(-100.0);
    burstPow.fill(0.0f);
    burstLight.fill(0);
    sweepAt.fill(-100.0);
    sweepPow.fill(0.0f);
    sweepY.fill(0.0f);
    sweepDir.fill(1.0f);
    beats = seed;
    nextBurst = nextSweep = 0;
  }

  void update(const Frame& f) override {
    auto m = modifiers(f);
    const float dt = float(f.delta);
    const Music& mu = f.music;
    bass = follow(bass, mu.bass, 22.0f, 4.5f, dt);
    spark = follow(spark, mu.spark, 30.0f, 7.0f, dt);
    float hit = 0, fl = 0;
    for (const auto& e : mu.events[0]) hit = std::max(hit, e.strength);
    for (const auto& e : mu.events[2]) hit = std::max(hit, e.strength * 0.85f);
    for (const auto& e : mu.events[3]) fl = std::max(fl, e.strength);
    const float onset = std::clamp((mu.bass - slowBass - 0.15f) * 2.5f, 0.0f, 1.0f);
    slowBass = follow(slowBass, mu.bass, 3.0f, 3.0f, dt);
    hit = std::min(std::max(hit, onset), 1.0f);
    const bool fresh = hit > kick + 0.2f;
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    secs += f.delta;
    // Golpes: cada golpe hace estallar una luz y uno de cada dos lanza un
    // barrido. Sólo ocurre con música.
    if (fresh && m.pulso == 0) {
      const uint32_t k = beats++;
      const uint32_t n = uint32_t(lightCount(f.detail));
      const size_t b = size_t(nextBurst);
      burstAt[b] = secs;
      burstPow[b] = hit;
      burstLight[b] = int(k % n);
      nextBurst = (nextBurst + 1) % kBursts;
      if (k % 2u == 0u) {
        const size_t w = size_t(nextSweep);
        sweepAt[w] = secs;
        sweepPow[w] = hit;
        sweepY[w] = hashU(k * 2654435761u + 7u) * 2.0f - 1.0f;
        sweepDir[w] = (k / 2u) % 2u == 0u ? 1.0f : -1.0f;
        nextSweep = (nextSweep + 1) % kSweeps;
      }
    }
    clock += f.delta * f.speed;
  }

  void render(const Frame& f, Canvas& c) const override {
    auto g = glide(f);
    const float amp = f.intensity;
    const float side = std::min(f.width, f.height);
    const float halfW = 0.5f * f.width / side, halfH = 0.5f * f.height / side;
    const float t = float(std::fmod(clock, 10000.0));
    const float rt = float(std::fmod(secs, 1000.0));
    const float wDeriva = g.recorrido.weight(0), wBarrido = g.recorrido.weight(1), wOrbita = g.recorrido.weight(2);
    const float wGolpes = g.pulso.weight(0), wGraves = g.pulso.weight(1), wBrillos = g.pulso.weight(2);
    const int count = lightCount(f.detail);
    // Pulso: cada opción mueve algo distinto (todo vale 0 sin música).
    const float punch = wGolpes * std::min(kick * amp, 1.0f);
    const float graves = wGraves * std::min(bass * amp, 1.2f);
    const float brillos = wBrillos * std::min((spark + 0.4f * flash) * amp, 1.2f);
    std::vector<float> u;
    u.reserve(80);
    u.insert(u.end(), {t, std::clamp(f.glow, 0.0f, 2.0f), std::clamp(g.reflejos, 0.0f, 1.0f), rt});
    // Pesos de la lente y el centelleo de fondo (también en silencio).
    u.insert(u.end(), {g.lente.weight(0), g.lente.weight(1), g.lente.weight(2), 0.16f});
    std::array<float, kLights> lx{}, ly{};
    for (int i = 0; i < kLights; i++) {
      const size_t s = size_t(i);
      // Deriva: curvas de Lissajous lentas por toda la pantalla.
      const float dx = halfW * 0.72f * std::sin(t * 0.13f * fx[s] + phx[s]);
      const float dy = halfH * 0.72f * std::sin(t * 0.11f * fy[s] + phy[s]);
      // Barrido: cada luz cruza de lado a lado en su carril.
      const float run = float(std::fmod(double(t) * 0.06 * double(speedK[s]) + double(phx[s]) / 6.2831853, 1.0));
      const float bx = (run * 2.0f - 1.0f) * (halfW + 0.45f);
      const float by = rowY[s] * halfH;
      // Órbita: elipses alrededor del centro; los fantasmas giran al revés.
      const float ang = t * 0.2f * (0.6f + 0.4f * speedK[s]) + phx[s];
      const float ox = std::cos(ang) * halfW * 0.85f * orbitK[s];
      const float oy = std::sin(ang) * halfH * 0.6f * orbitK[s];
      lx[s] = wDeriva * dx + wBarrido * bx + wOrbita * ox;
      ly[s] = wDeriva * dy + wBarrido * by + wOrbita * oy;
      // Cada luz respira despacio por su cuenta.
      float I = (i == 0 ? 1.2f : 0.68f) + 0.22f * std::sin(t * 0.5f + float(i) * 1.7f);
      I *= 1.0f + 0.45f * punch;
      I *= 1.0f + (i == 0 ? 0.9f : 0.25f) * graves;
      I *= 1.0f + 0.8f * brillos * (0.5f + 0.5f * std::sin(rt * 23.0f + float(i) * 3.1f));
      if (i >= count) I = 0.0f;
      // Tamaño: la principal crece un 22 % con los graves; el golpe, un 12 %.
      const float size = sizeK[s] * (1.0f + (i == 0 ? 0.22f * graves : 0.0f) + 0.12f * punch);
      u.insert(u.end(), {lx[s], ly[s], std::clamp(I, 0.0f, 3.0f), size});
    }
    // Estallidos de los golpes: siguen a su luz y se apagan en ~1,5 s.
    for (int j = 0; j < kBursts; j++) {
      const size_t s = size_t(j);
      const float age = float(std::min(secs - burstAt[s], 100.0));
      const size_t li = size_t(burstLight[s] < count ? burstLight[s] : 0);
      const float power = age < 3.0f ? std::min(burstPow[s] * amp, 1.2f) * wGolpes : 0.0f;
      u.insert(u.end(), {lx[li], ly[li], std::max(age, 0.0f), power});
    }
    // Barrido de reposo: cada 7 s una luz cruza la pantalla (también en silencio).
    const double period = 7.0;
    const double lap = std::floor(clock / period);
    const float idle = float((clock - lap * period) / 1.9);
    const uint32_t li = uint32_t(int64_t(lap) & 0x7fffffff);
    {
      const float dir = hashU(li * 747796405u + 1u) < 0.5f ? 1.0f : -1.0f;
      const float y = (hashU(li * 2891336453u + 5u) * 2.0f - 1.0f) * 0.7f * halfH;
      const float x = dir * (-(halfW + 0.5f) + 2.0f * (halfW + 0.5f) * std::min(idle, 1.0f));
      const float power = idle < 1.0f ? 0.8f * std::sin(3.1415927f * idle) : 0.0f;
      u.insert(u.end(), {x, y, std::max(power, 0.0f), 1.0f});
    }
    // Barridos de los golpes: más rápidos y con la raya más larga.
    for (int j = 0; j < kSweeps; j++) {
      const size_t s = size_t(j);
      const float run = float(std::min(secs - sweepAt[s], 100.0)) / 0.95f;
      const float x = sweepDir[s] * (-(halfW + 0.5f) + 2.0f * (halfW + 0.5f) * std::clamp(run, 0.0f, 1.0f));
      const float power = run < 1.0f ? std::min(sweepPow[s] * amp, 1.2f) * wGolpes * std::sin(3.1415927f * std::max(run, 0.0f)) : 0.0f;
      u.insert(u.end(), {x, sweepY[s] * 0.75f * halfH, std::max(power, 0.0f), 1.35f});
    }
    u.insert(u.end(), {std::min(graves, 1.2f), brillos, punch, std::min(flash * amp, 1.0f) * wBrillos});
    for (int i = 1; i < 4; i++) u.insert(u.end(), {f.colors[size_t(i)].r, f.colors[size_t(i)].g, f.colors[size_t(i)].b});
    c.material("lens_flares", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'lens_flares': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // reloj, glow, reflejos, reloj real
uniform vec4 uB;   // lente: anamórfica, estrella, arco; centelleo de fondo
uniform vec4 uL0;  // luces: x, y, intensidad, tamaño
uniform vec4 uL1;
uniform vec4 uL2;
uniform vec4 uL3;
uniform vec4 uL4;
uniform vec4 uL5;
uniform vec4 uK0;  // estallidos: x, y, edad, fuerza
uniform vec4 uK1;
uniform vec4 uK2;
uniform vec4 uK3;
uniform vec4 uW0;  // barridos: x, y, fuerza, largo
uniform vec4 uW1;
uniform vec4 uW2;
uniform vec4 uM;   // graves, brillos, golpe, destello de agudos
uniform vec3 uC1;
uniform vec3 uC2;
uniform vec3 uC3;
out vec4 fragColor;

const float TAU = 6.2831853;

float hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

float gauss(float x, float w) {
  float k = x / w;
  return exp(-k * k);
}

// Degradado de la raya: núcleo blanco, azul claro y azul anamórfico intenso
// que se oscurece hacia las puntas.
vec3 streakTint(float t) {
  vec3 pale = mix(uC1, uC3, 0.45);
  vec3 c = mix(uC3, pale, smoothstep(0.0, 0.1, t));
  c = mix(c, uC1, smoothstep(0.1, 0.45, t));
  return mix(c, uC1 * 0.7, smoothstep(0.45, 1.0, t));
}

// Raya: una línea fina casi blanca, un cuerpo de color saturado y un brillo
// ancho y tenue; del centro a las puntas pasa de azul claro a azul intenso.
vec3 streak(float across, float along, float len, float thick) {
  // Lejos de la raya no aporta nada: se ahorra el cálculo.
  if (abs(across) > 0.18 * thick) return vec3(0.0);
  float t = along / (len * 1.5);
  float thin = gauss(across, 0.0036 * thick) * (exp(-along / len) + 0.3 * exp(-along / (len * 3.2)));
  float body = gauss(across, 0.013 * thick) * (exp(-along / (len * 0.8)) + 0.2 * exp(-along / (len * 3.0)));
  float wide = gauss(across, 0.05 * thick) * exp(-along / (len * 0.6));
  return streakTint(t) * thin + streakTint(t + 0.3) * body * 0.55 + uC1 * wide * 0.16;
}

// Fantasma de radio 1: óvalo (anamórfica), hexágono (estrella) o círculo
// (arco), con el borde suave y un aro algo más brillante.
float ghostShape(vec2 q) {
  float oval = length(q * vec2(1.5, 0.82));
  float hexa = max(abs(q.y), abs(q.x) * 0.8660254 + abs(q.y) * 0.5);
  float circ = length(q);
  float d = uB.x * oval + uB.y * hexa + uB.z * circ;
  float body = 1.0 - smoothstep(0.7, 1.0, d);
  return body * (0.16 + 0.84 * smoothstep(0.35, 0.93, d));
}

// Aberración cromática: el rojo sale más grande y el azul más pequeño.
vec3 ghost(vec2 p, vec2 at, float radius, vec3 tint) {
  vec2 q = (p - at) / radius;
  if (dot(q, q) > 2.6) return vec3(0.0);
  return tint * vec3(ghostShape(q * 0.93), ghostShape(q), ghostShape(q * 1.07));
}

// Cadena de fantasmas en la recta que une la luz con el centro.
vec3 ghosts(vec2 p, vec4 L) {
  float I = L.z * uA.z;
  if (I < 0.003) return vec3(0.0);
  vec2 c = L.xy;
  float s = L.w;
  vec3 acc = ghost(p, c * -0.42, 0.055 * s, uC1) * 0.34;
  acc += ghost(p, c * -0.85, 0.11 * s, mix(uC2, uC3, 0.25)) * 0.18;
  acc += ghost(p, c * 0.38, 0.03 * s, mix(uC2, uC3, 0.35)) * 0.45;
  acc += ghost(p, c * -1.35, 0.17 * s, uC2) * 0.1;
  acc += ghost(p, c * -0.18, 0.02 * s, mix(uC1, uC3, 0.5)) * 0.45;
  return acc * I;
}

// Aro de arcoíris alrededor del centro óptico.
vec3 halo(vec2 p, vec4 L, float boost) {
  float I = L.z * uA.z * (0.07 + 0.1 * boost);
  if (I < 0.003) return vec3(0.0);
  float R = 0.26 + 0.55 * length(L.xy);
  float r = length(p + L.xy * 0.15);
  float w = 0.008 + 0.01 * uB.z;
  vec3 ring = vec3(gauss(r - R * 1.035, w), gauss(r - R, w), gauss(r - R * 0.965, w));
  return ring * mix(uC3, uC2, 0.35) * I;
}

vec3 light(vec2 p, vec4 L, float thick, float lenK) {
  float I = L.z;
  if (I < 0.003) return vec3(0.0);
  float s = L.w;
  vec2 d = p - L.xy;
  float r2 = dot(d, d);
  float r = sqrt(r2);
  // Núcleo blanco y halo suave, sin bordes.
  vec3 col = uC3 * I * (1.3 * exp(-r2 / (0.00011 * s * s)) + 0.45 * exp(-r2 / (0.0011 * s * s)));
  col += mix(uC1, uC3, 0.3) * I * 0.2 * uA.y * exp(-r / (0.05 * s));
  // Brillo ovalado, más ancho que alto, como el de una lente anamórfica.
  col += uC1 * I * 0.16 * uA.y * exp(-length(d * vec2(0.4, 1.7)) / (0.06 * s));
  // Raya recta: larga en Anamórfica, más corta en Estrella.
  float straight = uB.x + uB.y;
  if (straight > 0.001) {
    float len = 0.3 * s * lenK * (uB.x + 0.45 * uB.y) / straight;
    float ax = abs(d.x);
    col += streak(d.y, ax, len, thick) * I * straight;
  }
  if (uB.y > 0.001) {
    // Estrella de difracción de seis puntas, alternando largas y cortas.
    float a = atan(d.y, d.x) * (6.0 / TAU) + 0.5;
    float off = abs(fract(a) - 0.5) * (TAU / 6.0);
    float longer = mod(floor(a), 2.0) < 0.5 ? 1.0 : 0.5;
    float spikes = gauss(r * off, 0.0026 * s * thick * (1.0 + 3.0 * r)) * exp(-r / (0.09 * s * longer * lenK));
    col += mix(uC3, uC1, smoothstep(0.0, 0.25, r)) * spikes * I * uB.y;
  }
  if (uB.z > 0.001) {
    // Arco: la raya sigue un círculo alrededor del centro de la imagen.
    float lr = length(L.xy);
    vec2 n = lr > 0.001 ? L.xy / lr : vec2(0.0, 1.0);
    float R = 0.32 + 0.7 * lr;
    vec2 e = p - (L.xy - n * R);
    float er = max(length(e), 0.0001);
    float along = acos(clamp(dot(e / er, n), -1.0, 1.0)) * R;
    float len = 0.2 * s * lenK;
    col += streak(er - R, along, len, thick) * I * uB.z;
  }
  return col;
}

// Estallido de un golpe: destello, estrella de ocho puntas, onda irisada que
// se abre y una raya horizontal muy larga.
vec3 burst(vec2 p, vec4 K) {
  if (K.w < 0.003) return vec3(0.0);
  vec2 d = p - K.xy;
  float r = length(d);
  if (r > 0.9 && abs(d.y) > 0.03) return vec3(0.0);
  float age = K.z;
  float grow = 1.0 - exp(-age * 3.2);
  float R = 0.03 + 0.36 * grow;
  float w = 0.006 + 0.024 * grow;
  vec3 ring = vec3(gauss(r - R * 1.05, w), gauss(r - R, w), gauss(r - R * 0.95, w));
  vec3 col = ring * mix(uC3, uC2, 0.55) * exp(-age * 2.6) * 0.6;
  float a = atan(d.y, d.x) * (8.0 / TAU) + 0.5;
  float off = abs(fract(a) - 0.5) * (TAU / 8.0);
  float longer = mod(floor(a), 2.0) < 0.5 ? 1.0 : 0.55;
  float spikes = gauss(r * off, 0.003 + 0.012 * r) * exp(-r / ((0.04 + 0.2 * grow) * longer)) * exp(-age * 2.0);
  col += mix(uC3, uC1, smoothstep(0.0, 0.2, r)) * spikes;
  col += uC3 * exp(-r * r / (0.0016 * (1.0 + age * 3.0))) * exp(-age * 4.0) * 1.4;
  col += streakTint(abs(d.x) / 1.2) * gauss(d.y, 0.0045) * exp(-abs(d.x) / 0.5) * exp(-age * 2.4) * 1.2;
  return col * K.w;
}

// Barrido: una luz rápida que cruza la pantalla con su raya y un brillo ancho.
vec3 sweep(vec2 p, vec4 W) {
  if (W.z < 0.003) return vec3(0.0);
  vec2 d = p - W.xy;
  if (abs(d.y) > 0.2) return vec3(0.0);
  float ax = abs(d.x);
  float len = 0.42 * W.w;
  float r2 = dot(d, d);
  float core = exp(-r2 / 0.0003) * 1.6 + exp(-r2 / 0.004) * 0.45;
  float band = gauss(d.y, 0.06) * exp(-ax / (len * 1.4)) * 0.22;
  return (uC3 * core + streak(d.y, ax, len, 1.0) + uC2 * band) * W.z;
}

// Destellos de cuatro puntas que centellean en celdas repartidas.
vec3 glints(vec2 p, float level, float time) {
  if (level < 0.003) return vec3(0.0);
  float cell = 0.12;
  vec2 id = floor(p / cell);
  float h = hash12(id + 17.0);
  if (h < 0.4) return vec3(0.0);
  vec2 at = (id + 0.3 + 0.4 * vec2(hash12(id + 3.1), hash12(id + 7.7))) * cell;
  vec2 d = p - at;
  float tw = max(sin(time * (2.5 + 5.0 * h) + h * 40.0), 0.0);
  tw = tw * tw * tw * tw;
  float star = exp(-dot(d, d) / 0.00004) +
               0.7 * (gauss(d.y, 0.0016) * exp(-abs(d.x) / 0.011) + gauss(d.x, 0.0016) * exp(-abs(d.y) / 0.011));
  vec3 tint = mix(mix(uC3, uC1, hash12(id + 9.0) * 0.7), uC2, step(0.72, hash12(id + 5.0)));
  return tint * star * tw * level;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  float graves = uM.x;
  float punch = uM.z;
  // Graves engruesan las rayas; el golpe las alarga.
  float thick = 1.0 + 1.1 * graves + 0.4 * punch;
  float lenK = 1.0 + 0.6 * punch + 0.25 * graves + 0.02 * sin(uA.x * 0.7);
  vec3 col = light(p, uL0, thick, lenK) + light(p, uL1, thick, lenK) + light(p, uL2, thick, lenK) +
             light(p, uL3, thick, lenK) + light(p, uL4, thick, lenK) + light(p, uL5, thick, lenK);
  col += ghosts(p, uL0) * (1.0 + 1.2 * graves) + ghosts(p, uL1) + ghosts(p, uL2);
  col += halo(p, uL0, graves);
  col += burst(p, uK0) + burst(p, uK1) + burst(p, uK2) + burst(p, uK3);
  col += sweep(p, uW0) + sweep(p, uW1) + sweep(p, uW2);
  // Los barridos también dejan su cadena de fantasmas al cruzar.
  col += ghosts(p, vec4(uW0.xy, uW0.z, 1.0)) + ghosts(p, vec4(uW1.xy, uW1.z, 1.2)) + ghosts(p, vec4(uW2.xy, uW2.z, 1.2));
  col += glints(p, uB.w + 1.5 * uM.y + 0.6 * uM.w, uA.w);
  // La luz intensa se vuelve blanca sin quemar.
  col = vec3(1.0) - exp(-col * 1.15);
  // Sin fondo: color premultiplicado y opacidad según el brillo; lo muy
  // tenue se desvanece del todo para no dejar velo.
  float veilPeak = max(col.r, max(col.g, col.b));
  float clearCut = smoothstep(0.0, 0.035, veilPeak);
  float alpha = clamp(veilPeak * 1.15, 0.0, 1.0) * clearCut;
  col = min(col * clearCut, vec3(alpha));
  fragColor = vec4(col, alpha);
}
""",
};
