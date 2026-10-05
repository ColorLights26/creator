// Destellos Anamórficos — las rayas de luz de las lentes de cine.
// Las lentes anamórficas convierten cada luz fuerte en una raya horizontal
// larga y azulada, con reflejos ovalados que cruzan la imagen: el sello de
// la ciencia ficción en el cine. Este visual no tiene fondo: se pone encima
// de cualquier otro y le añade luces que pasan con sus rayas, estrellas de
// difracción o arcos. Con Golpes, cada golpe aviva todas las luces y hace
// estallar dos de ellas, que crecen, alargan sus rayas, encienden un
// resplandor a su alrededor y se apagan despacio; con Graves, la luz
// principal se infla con un halo mayor y las rayas se engrosan; con Brillos,
// los agudos hacen centellear las luces, chisporrotear las rayas y soltar un
// polvo de chispas alrededor de cada luz.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // FORMA: el tipo de destello de la lente.
  CreatorModifier.choice(
    'lente',
    'Lente',
    options: ['Anamórfica', 'Estrella', 'Arco'],
  ),
  // MOVIMIENTO: luces que flotan, que cruzan la pantalla o que se quedan.
  CreatorModifier.choice(
    'recorrido',
    'Recorrido',
    options: ['Deriva', 'Barrido', 'Fijas'],
  ),
  // MÚSICA
  CreatorModifier.choice(
    'pulso',
    'Pulso',
    options: ['Golpes', 'Graves', 'Brillos'],
  ),
  // ATMÓSFERA: el halo de neblina alrededor de cada luz.
  CreatorModifier.slider('neblina', 'Neblina', min: 0, max: 1, value: .35),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Ciencia Ficción', {
    'lente': 'Anamórfica',
    'recorrido': 'Barrido',
    'pulso': 'Golpes',
  }),
  CreatorVariation('Estrellas', {
    'lente': 'Estrella',
    'recorrido': 'Fijas',
    'pulso': 'Brillos',
    'neblina': .8,
  }),
];

const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kLights = 6;
  float bass = 0, spark = 0, slowBass = 0;
  float kick = 0, flash = 0;
  // Reloj en doble precisión: sin música es idéntico a 30 y 60 FPS.
  double clock = 0;
  std::array<float, kLights> fx{}, fy{}, phx{}, phy{}, rowY{}, baseX{}, baseY{}, speedK{}, sizeK{}, burst{};
  uint32_t beats = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }
  static float hashU(uint32_t x) {
    x ^= x >> 16; x *= 0x7feb352dU; x ^= x >> 15; x *= 0x846ca68bU; x ^= x >> 16;
    return float(x & 0xffffffu) / 16777216.0f;
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = spark = slowBass = kick = flash = 0;
    clock = double(rng.unit()) * 40.0;
    for (int i = 0; i < kLights; i++) {
      fx[size_t(i)] = 0.6f + 0.8f * rng.unit();
      fy[size_t(i)] = 0.6f + 0.8f * rng.unit();
      phx[size_t(i)] = rng.unit() * 6.28f;
      phy[size_t(i)] = rng.unit() * 6.28f;
      rowY[size_t(i)] = (float(i) + 0.5f) / float(kLights) * 1.4f - 0.7f + (rng.unit() - 0.5f) * 0.1f;
      baseX[size_t(i)] = (rng.unit() - 0.5f) * 0.7f;
      baseY[size_t(i)] = (rng.unit() - 0.5f) * 1.3f;
      speedK[size_t(i)] = 0.6f + 0.8f * rng.unit();
      sizeK[size_t(i)] = i == 0 ? 1.4f : 0.6f + 0.6f * rng.unit();
    }
    burst.fill(0.0f);
    beats = seed;
  }

  void update(const Frame& f) override {
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
    // Los estallidos se apagan despacio: duran casi el doble.
    for (auto& b : burst) b *= std::exp(-dt * 2.2f);
    // Cada golpe hace estallar dos luces distintas, siempre entre las visibles.
    if (hit > kick + 0.2f) {
      const uint32_t k = beats++;
      const uint32_t n = uint32_t(std::clamp(int(std::lround(2.0f + 2.0f * f.detail)), 1, kLights));
      const uint32_t a = k % n;
      const uint32_t b = (a + 1u + (k * 7u + 3u) % (n > 1u ? n - 1u : 1u)) % n;
      burst[size_t(a)] = std::max(burst[size_t(a)], hit);
      burst[size_t(b)] = std::max(burst[size_t(b)], hit * 0.85f);
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    clock += f.delta * f.speed;
  }

  void render(const Frame& f, Canvas& c) const override {
    auto g = glide(f);
    const float amp = f.intensity;
    const float side = std::min(f.width, f.height);
    const float halfW = 0.5f * f.width / side, halfH = 0.5f * f.height / side;
    const float t = float(std::fmod(clock, 10000.0));
    const float wDeriva = g.recorrido.weight(0), wBarrido = g.recorrido.weight(1), wFijas = g.recorrido.weight(2);
    const float wGolpes = g.pulso.weight(0), wGraves = g.pulso.weight(1), wBrillos = g.pulso.weight(2);
    // Detalle: cuántas luces hay.
    const int count = std::clamp(int(std::lround(2.0f + 2.0f * f.detail)), 1, kLights);
    std::vector<float> u;
    u.reserve(56);
    u.insert(u.end(), {t, f.glow, std::clamp(g.neblina, 0.0f, 1.0f), std::min(flash * amp, 1.0f)});
    u.insert(u.end(), {g.lente.weight(0), g.lente.weight(1), g.lente.weight(2), halfW});
    // Golpes: todas las luces se avivan con el golpe y las que estallan
    // encienden un resplandor alrededor (el material lo dibuja).
    const float punch = std::min(kick * amp, 1.0f) * wGolpes;
    const float gravesAll = std::min(bass * amp, 1.0f) * wGraves;
    std::array<float, kLights> bloom{};
    for (int i = 0; i < kLights; i++) {
      const size_t s = size_t(i);
      const float dx = halfW * 0.8f * std::sin(t * 0.13f * fx[s] + phx[s]);
      const float dy = halfH * 0.8f * std::sin(t * 0.11f * fy[s] + phy[s]);
      const float sweep = float(std::fmod(double(t) * 0.07 * double(speedK[s]) + double(phx[s]), 1.0));
      const float bx = (sweep * 2.0f - 1.0f) * (halfW + 0.4f);
      const float fxp = baseX[s] + 0.01f * std::sin(t * 0.7f + phy[s]);
      const float fyp = baseY[s] + 0.01f * std::cos(t * 0.6f + phx[s]);
      const float x = wDeriva * dx + wBarrido * bx + wFijas * fxp;
      const float y = wDeriva * dy + wBarrido * rowY[s] * halfH + wFijas * fyp;
      float I = 0.5f + 0.2f * std::sin(t * 0.5f + float(i) * 1.7f);
      // Golpes: la luz que estalla brilla mucho más y crece; el golpe aviva
      // además todas las luces (+100 % en el golpe).
      const float pop = std::min(burst[s] * amp, 1.0f) * wGolpes;
      I += wGolpes * burst[s] * amp * 2.0f;
      I += 0.55f * punch;
      // Graves: la principal se infla y las demás respiran con los graves.
      const float graves = std::min(bass * amp, 1.0f) * wGraves;
      if (i == 0) I *= 1.0f + wGraves * (std::min(bass * amp, 1.2f) * 1.1f - 0.2f);
      else I *= 1.0f + 0.5f * graves;
      // Brillos: centelleo fuerte con los agudos.
      I *= 1.0f + wBrillos * (std::min(spark * amp, 1.0f) * 2.0f * (0.5f + 0.5f * std::sin(t * 23.0f + float(i) * 3.1f)) - 0.3f);
      if (i >= count) I = 0.0f;
      // Pop de tamaño: 20 % en el golpe; la principal respira 15 % con graves.
      const float grow = 1.0f + 0.2f * pop + (i == 0 ? 0.15f * graves : 0.0f);
      u.insert(u.end(), {x, y, std::clamp(I, 0.0f, 2.0f), sizeK[s] * grow});
      // Resplandor local: fuerte en la luz que estalla, suave en las demás,
      // y la principal también con los graves.
      bloom[s] = std::clamp(pop + 0.35f * punch + (i == 0 ? 0.6f * graves : 0.0f), 0.0f, 1.0f);
    }
    for (int i = 1; i < 4; i++) u.insert(u.end(), {f.colors[size_t(i)].r, f.colors[size_t(i)].g, f.colors[size_t(i)].b});
    // Resplandor de cada luz, graves y agudos para el material.
    u.insert(u.end(), {bloom[0], bloom[1], bloom[2], bloom[3]});
    u.insert(u.end(), {bloom[4], bloom[5], gravesAll, std::min(spark * amp, 1.0f) * wBrillos});
    c.material("lens_flares", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'lens_flares': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // tiempo, glow, neblina, destello
uniform vec4 uB;   // pesos de lente: anamórfica, estrella, arco; medio ancho
uniform vec4 uL0;  // luces: x, y, intensidad, tamaño
uniform vec4 uL1;
uniform vec4 uL2;
uniform vec4 uL3;
uniform vec4 uL4;
uniform vec4 uL5;
uniform vec3 uC1;
uniform vec3 uC2;
uniform vec3 uC3;
uniform vec4 uG0;  // resplandor de las luces 0..3 (golpes y graves)
uniform vec4 uG1;  // resplandor de las luces 4 y 5, graves, agudos
out vec4 fragColor;

float sq(float x) {
  return x * x;
}

float hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

vec3 flare(vec2 p, vec4 L, float bloom, float glit, float glitX) {
  float I = L.z;
  if (I < 0.002) return vec3(0.0);
  float s = L.w;
  vec2 d = p - L.xy;
  float r2 = dot(d, d);
  float core = I * exp(-r2 / (0.00025 * s * s));
  float glow = I * 0.0003 * s / (r2 + 0.0003 * s) * uA.y;
  float streak = 0.0;
  if (uB.x > 0.001) {
    // La raya anamórfica: muy fina y muy larga, con otra más suave debajo.
    streak += uB.x * I * (exp(-abs(d.y) / (0.0035 * s)) * exp(-abs(d.x) / (0.55 * s)) +
                          0.35 * exp(-abs(d.y) / (0.012 * s)) * exp(-abs(d.x) / (0.22 * s)));
  }
  if (uB.y > 0.001) {
    vec2 r45 = vec2(d.x + d.y, d.x - d.y) * 0.7071;
    streak += uB.y * I * (exp(-abs(d.y) / (0.003 * s)) * exp(-abs(d.x) / (0.2 * s)) +
                          exp(-abs(d.x) / (0.003 * s)) * exp(-abs(d.y) / (0.2 * s)) +
                          0.5 * exp(-abs(r45.y) / (0.003 * s)) * exp(-abs(r45.x) / (0.12 * s)) +
                          0.5 * exp(-abs(r45.x) / (0.003 * s)) * exp(-abs(r45.y) / (0.12 * s)));
  }
  if (uB.z > 0.001) {
    // Arco: la raya se curva alrededor del centro de la imagen.
    float lr = length(L.xy) + 0.001;
    float da = abs(atan(p.y, p.x) - atan(L.y, L.x));
    da = min(da, 6.2831853 - da);
    streak += uB.z * I * exp(-abs(length(p) - lr) / (0.004 * s)) * exp(-da * lr / (0.35 * s));
  }
  // Reflejos ovalados en la línea que cruza el centro.
  float ghosts = 0.0;
  for (int k = 0; k < 3; k++) {
    float gk = k == 0 ? -0.45 : (k == 1 ? -0.95 : 0.55);
    vec2 e = (p - L.xy * gk) / vec2(0.04 * s, 0.024 * s);
    float r = length(e);
    ghosts += I * (0.06 * exp(-r * r) + 0.05 * exp(-sq((r - 1.0) / 0.12)));
  }
  float haze = I * uA.z * 0.18 * exp(-sqrt(r2) / 0.08);
  vec3 base = uC3 * (core + glow * 0.6) + uC1 * (streak + haze) + uC2 * ghosts;
  // Música: todo esto vale cero sin música.
  if (bloom + uG1.z + uG1.w < 0.0005) return base;
  float Ic = min(I, 1.2);
  // Golpes: rayas que se alargan con el estallido. Graves: rayas más gruesas.
  float extraStreak = 0.0;
  if (uB.x > 0.001) {
    extraStreak += uB.x * (bloom * 0.7 * exp(-abs(d.y) / (0.005 * s)) * exp(-abs(d.x) / (1.1 * s)) +
                           uG1.z * 0.6 * exp(-abs(d.y) / (0.0085 * s)) * exp(-abs(d.x) / (0.5 * s)));
  }
  if (uB.y > 0.001) {
    extraStreak += uB.y * (bloom * 0.7 + uG1.z * 0.6) *
                   (exp(-abs(d.y) / (0.006 * s)) * exp(-abs(d.x) / (0.4 * s)) +
                    exp(-abs(d.x) / (0.006 * s)) * exp(-abs(d.y) / (0.4 * s)));
  }
  if (uB.z > 0.001) {
    float lr = length(L.xy) + 0.001;
    float da = abs(atan(p.y, p.x) - atan(L.y, L.x));
    da = min(da, 6.2831853 - da);
    extraStreak += uB.z * (bloom * 0.7 + uG1.z * 0.6) * exp(-abs(length(p) - lr) / (0.008 * s)) * exp(-da * lr / (0.6 * s));
  }
  vec3 extra = uC1 * Ic * extraStreak;
  // Golpes: resplandor aditivo local alrededor de la luz que estalla.
  extra += mix(uC1, uC3, 0.35) * bloom * 0.38 * uA.y * exp(-r2 / (0.05 * s * s));
  // Graves: el halo crece un 80 %.
  extra += uC3 * glow * 0.48 * uG1.z;
  // Agudos: las rayas chisporrotean y un polvo de chispas rodea cada luz.
  extra += uC1 * streak * uG1.w * 1.4 * glitX;
  extra += uC3 * uG1.w * glit * min(I, 1.0) * 0.9 * exp(-sqrt(r2) / (0.12 * s));
  return base + extra;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  // Chispas de los agudos: celdas diminutas que cambian 14 veces por segundo.
  float glit = step(0.88, hash12(floor(frag * 0.34) + floor(uA.x * 14.0)));
  float glitX = step(0.55, hash12(vec2(floor(p.x * 90.0), floor(uA.x * 14.0) + 3.0)));
  vec3 col = flare(p, uL0, uG0.x, glit, glitX) + flare(p, uL1, uG0.y, glit, glitX) + flare(p, uL2, uG0.z, glit, glitX) +
             flare(p, uL3, uG0.w, glit, glitX) + flare(p, uL4, uG1.x, glit, glitX) + flare(p, uL5, uG1.y, glit, glitX);
  col *= 1.0 + 0.2 * uA.w;
  // Sin fondo: la luz se mezcla con lo que hay debajo.
  col = col / (1.0 + max(col.r, max(col.g, col.b)) * 0.35);
  // Fondo transparente: color premultiplicado y opacidad según el brillo; la
  // luz muy tenue se vuelve transparente del todo para no dejar velo.
  col = clamp(col, 0.0, 1.0);
  float veilPeak = max(col.r, max(col.g, col.b));
  float clearCut = smoothstep(0.04, 0.12, veilPeak);
  col *= clearCut;
  float alpha = clamp(veilPeak * 1.25, 0.0, 1.0) * clearCut;
  fragColor = vec4(col, alpha);
}
""",
};
