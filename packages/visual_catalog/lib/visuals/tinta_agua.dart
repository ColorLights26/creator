// Tinta en Agua — nubes de tinta que caen y se abren en cámara lenta.
// Una gota de tinta que entra en el agua no se mezcla enseguida: baja como un
// hongo, con un anillo que se enrosca en el borde, deja un hilo detrás y se
// deshace en nubes y volutas. Aquí caen gotas de tinta roja, naranja y ámbar
// en agua oscura, iluminadas desde arriba, y cada golpe de la música suelta
// una gota nueva. Los graves hacen que las nubes se hinchen y la corriente
// las arrastra hacia los lados.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // FORMA: cómo cae la tinta.
  CreatorModifier.choice(
    'gotas',
    'Caída',
    options: ['Hongo', 'Lluvia', 'Columna'],
  ),
  // MOVIMIENTO: de agua quieta y suave a remolinos caóticos.
  CreatorModifier.slider('turbulencia', 'Turbulencia', min: 0, max: 1, value: .45),
  // MÚSICA
  CreatorModifier.choice(
    'pulso',
    'Pulso',
    options: ['Golpes', 'Graves', 'Corriente'],
  ),
  // ATMÓSFERA: la luz que atraviesa la tinta por detrás.
  CreatorModifier.slider('contraluz', 'Contraluz', min: 0, max: 1, value: .4),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Tormenta de Tinta', {
    'gotas': 'Lluvia',
    'turbulencia': 1,
    'pulso': 'Golpes',
  }),
  CreatorVariation('Humo Lento', {
    'gotas': 'Columna',
    'turbulencia': .2,
    'contraluz': 1,
    'speed': .6,
  }),
];

const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kPlumes = 6;
  float bass = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: sin música es idéntico a 30 y 60 FPS.
  double flow = 0, sinceIdle = 0, sinceDrop = 10;
  std::array<float, kPlumes> px{}, psize{}, pcolor{};
  std::array<double, kPlumes> pbirth{};
  int nextPlume = 0;
  uint32_t drops = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }
  static float hashU(uint32_t x) {
    x ^= x >> 16; x *= 0x7feb352dU; x ^= x >> 15; x *= 0x846ca68bU; x ^= x >> 16;
    return float(x & 0xffffffu) / 16777216.0f;
  }
  static int slots(float detail) { return std::clamp(int(std::lround(3.0f + 1.5f * detail)), 3, kPlumes); }
  // Suelta una gota; carry es el tiempo que ya pasó desde que cayó.
  void drop(float strength, double carry, int limit) {
    const uint32_t k = drops++;
    const int slot = nextPlume % limit;
    px[size_t(slot)] = (hashU(k * 2654435761u + 5u) - 0.5f) * 0.76f;
    psize[size_t(slot)] = (0.8f + 0.5f * hashU(k * 2246822519u + 9u)) * strength;
    pcolor[size_t(slot)] = float(k % 3u);
    pbirth[size_t(slot)] = flow - carry;
    nextPlume = (slot + 1) % limit;
  }

 public:
  void reset(uint32_t seed) override {
    bass = energy = slowBass = kick = flash = drive = 0;
    flow = 0;
    sinceIdle = 0;
    sinceDrop = 10;
    px.fill(0.0f);
    psize.fill(1.0f);
    pcolor.fill(0.0f);
    pbirth.fill(-1000.0);
    nextPlume = 0;
    drops = seed * 3u;
    // Unas gotas ya en el agua para no empezar vacío.
    for (int i = 0; i < 3; i++) drop(1.0f, 1.0 + 2.2 * double(i), kPlumes);
  }

  void update(const Frame& f) override {
    auto m = modifiers(f);
    const float dt = float(f.delta);
    const Music& mu = f.music;
    bass = follow(bass, mu.bass, 22.0f, 4.5f, dt);
    energy = follow(energy, mu.energy, 6.0f, 1.8f, dt);
    drive = follow(drive, mu.active ? std::pow(std::clamp(mu.energy, 0.0f, 1.0f), 0.8f) : 0.0f, 3.0f, 0.7f, dt);
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
    const double step = f.delta * f.speed;
    flow += step;
    sinceDrop += f.delta;
    const int limit = slots(f.detail);
    // Golpes: cada golpe suelta una gota, más grande cuanto más fuerte.
    if (m.pulso == 0 && fresh && sinceDrop > 0.3) {
      drop(0.8f + 0.6f * hit * f.intensity, 0.0, limit);
      sinceDrop = 0;
    }
    // A su ritmo cae una gota; en Lluvia, el doble.
    double period = m.gotas == 1 ? 0.9 : 1.8;
    if (mu.active && m.pulso == 0) period *= 3.0;
    sinceIdle += step;
    while (sinceIdle >= period) {
      sinceIdle -= period;
      drop(1.0f, sinceIdle, limit);
    }
  }

  void render(const Frame& f, Canvas& c) const override {
    auto g = glide(f);
    const float amp = f.intensity;
    const float side = std::min(f.width, f.height);
    std::vector<float> u;
    u.reserve(64);
    const float current = g.pulso.weight(2) * std::min((energy + drive) * amp, 1.2f);
    u.insert(u.end(), {float(std::fmod(flow, 1000.0)), std::min(bass * amp, 1.5f) * g.pulso.weight(1), std::min(kick * amp, 1.0f), current});
    u.insert(u.end(), {g.gotas.weight(0), g.gotas.weight(1), g.gotas.weight(2), std::clamp(g.turbulencia, 0.0f, 1.0f)});
    u.insert(u.end(), {std::clamp(g.contraluz, 0.0f, 1.0f), f.glow, std::min(flash * amp, 1.0f), 0.5f * f.height / side});
    for (int i = 0; i < kPlumes; i++) {
      const float age = float(std::min(flow - pbirth[size_t(i)], 1000.0));
      u.insert(u.end(), {px[size_t(i)], age, psize[size_t(i)], pcolor[size_t(i)]});
    }
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[size_t(i)].r, f.colors[size_t(i)].g, f.colors[size_t(i)].b});
    c.material("ink_water", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'ink_water': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // tiempo, graves, golpe, corriente
uniform vec4 uB;   // pesos de caída: hongo, lluvia, columna; turbulencia
uniform vec4 uE;   // contraluz, glow, destello, media altura
uniform vec4 uP0;  // gotas: x, edad, tamaño, color
uniform vec4 uP1;
uniform vec4 uP2;
uniform vec4 uP3;
uniform vec4 uP4;
uniform vec4 uP5;
uniform vec3 uC0;
uniform vec3 uC1;
uniform vec3 uC2;
uniform vec3 uC3;
out vec4 fragColor;

float hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
             mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm2(vec2 p) {
  return (noise(p) * 0.65 + noise(p * 2.07 + vec2(3.1, 1.7)) * 0.35);
}

vec3 inkColor(float sel) {
  return sel < 0.5 ? uC1 : (sel < 1.5 ? uC2 : uC3);
}

// Densidad de una gota: capuchón de hongo con su anillo, cúpula e hilo.
float plume(vec2 p, vec4 P, vec2 warp, float halfH) {
  float age = P.y;
  if (age < 0.0 || age > 40.0) return 0.0;
  float fallK = uB.x * 1.0 + uB.y * 1.5 + uB.z * 0.8;
  float headK = uB.x * 1.0 + uB.y * 0.45 + uB.z * 0.55;
  float stemK = uB.x * 0.55 + uB.y * 0.15 + uB.z * 1.3;
  float top = -halfH - 0.03;
  float fall = (0.85 * (1.0 - exp(-age / 2.4)) + 0.06 * age) * fallK;
  vec2 head = vec2(P.x, top + 0.05 + fall);
  float R = P.z * headK * (0.05 + 0.13 * (1.0 - exp(-age / 1.5)) + 0.012 * age) * (1.0 + 0.15 * uA.y);
  float turb = (0.2 + 0.7 * uB.w) * (0.3 + 0.7 * min(age / 3.0, 1.0)) * (1.0 + 0.4 * uA.y);
  // Lejos de la gota no hay tinta: se descarta sin calcular más.
  float reach = R * 1.6 + turb * (0.05 + R * 1.6) * 0.8 + 0.02;
  if (abs(p.x - P.x) > reach || p.y > head.y + reach) return 0.0;
  vec2 pw = p + warp * turb * (0.05 + R * 1.6);
  vec2 q = (pw - head) / R;
  vec2 l = q - vec2(0.62, -0.05);
  vec2 r = q - vec2(-0.62, -0.05);
  float lobes = exp(-dot(l, l) / 0.08) + exp(-dot(r, r) / 0.08);
  float dome = exp(-(q.x * q.x / 0.6 + (q.y - 0.2) * (q.y - 0.2) / 0.16));
  float d = max(lobes, 0.7 * dome);
  // El hilo que une la gota con el punto donde entró.
  float stemW = R * 0.14 + 0.004;
  float dx = (pw.x - P.x) / stemW;
  float stem = exp(-dx * dx) * smoothstep(top, top + 0.08, pw.y) *
               (1.0 - smoothstep(head.y - R * 0.8, head.y - R * 0.2, pw.y)) * stemK * exp(-age / 6.0);
  d = max(d, stem);
  return d * smoothstep(0.0, 0.25, age) * exp(-age / 11.0);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  float t = uA.x;
  float halfH = uE.w;
  // Corriente: el agua arrastra la tinta hacia los lados, más al fondo.
  p.x -= uA.w * 0.14 * sin(p.y * 2.2 + t * 0.45) * (p.y + halfH);
  vec2 warp = vec2(fbm2(p * 1.8 + vec2(0.0, -t * 0.12)), fbm2(p * 1.8 + vec2(5.2, -t * 0.1))) - 0.5;
  // Una segunda capa de remolinos más finos, con un solo ruido.
  float fineW = noise(p * 4.5 + warp * 1.5 + vec2(t * 0.05, -t * 0.06)) - 0.5;
  warp += vec2(fineW, -fineW * 0.8) * 0.6;
  float d0 = plume(p, uP0, warp, halfH);
  float d1 = plume(p, uP1, warp, halfH);
  float d2 = plume(p, uP2, warp, halfH);
  float d3 = plume(p, uP3, warp, halfH);
  float d4 = plume(p, uP4, warp, halfH);
  float d5 = plume(p, uP5, warp, halfH);
  float D = d0 + d1 + d2 + d3 + d4 + d5;
  vec3 acc = d0 * inkColor(uP0.w) + d1 * inkColor(uP1.w) + d2 * inkColor(uP2.w) +
             d3 * inkColor(uP3.w) + d4 * inkColor(uP4.w) + d5 * inkColor(uP5.w);
  vec3 ink = acc / max(D, 1e-4);
  // Volutas finas dentro de la nube (sólo donde hay tinta).
  float det = D > 0.01 ? fbm2(p * 7.0 + warp * 2.5 + vec2(0.0, -t * 0.2)) : 0.5;
  // Filamentos: hilos finos donde el ruido cruza su punto medio.
  float ridge = 1.0 - abs(2.0 * det - 1.0);
  float dens = D * (0.3 + 1.2 * det) + ridge * ridge * smoothstep(0.03, 0.25, D) * 0.5;
  // Agua oscura iluminada desde arriba.
  vec3 col = uC0 + uC3 * 0.04 * (1.0 - smoothstep(-halfH, halfH, p.y));
  // Bordes nítidos, como la tinta de verdad.
  float cover = smoothstep(0.08, 0.5, dens);
  // Lo fino deja pasar la luz; lo espeso se oscurece.
  vec3 lit = ink * (0.75 + 0.55 * exp(-dens * 0.8)) * (0.8 + 0.4 * ridge);
  col = mix(col, lit, cover);
  col += ink * uE.x * uE.y * 0.3 * (1.0 - exp(-D * 0.6));
  col *= 1.0 + 0.15 * uA.z + 0.08 * uE.z;
  col *= 1.0 - 0.3 * smoothstep(0.6, 1.4, length(p * vec2(0.9, 0.65)));
  float peak = max(col.r, max(col.g, col.b));
  if (peak > 0.9) col *= (0.9 + 0.1 * (peak - 0.9) / (peak - 0.8)) / peak;
  col += (hash12(frag) - 0.5) / 255.0;
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
