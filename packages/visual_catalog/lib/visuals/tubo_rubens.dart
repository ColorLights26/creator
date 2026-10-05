// Tubo de Rubens — el sonido dibujado con fuego.
// Un tubo lleno de gas con una fila de agujeros y un altavoz en un extremo:
// el sonido forma ondas dentro del tubo y la presión sube y baja por zonas,
// así cada llama crece o se encoge según dónde cae la onda. Es un
// ecualizador de fuego real. Aquí las llamas dibujan ondas estacionarias,
// el espectro de la canción o una onda que viaja; cada golpe cambia el modo
// de la onda y aviva todas las llamas, y el calor hace temblar el aire.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // FORMA: qué dibujan las alturas de las llamas.
  CreatorModifier.choice(
    'onda',
    'Onda',
    options: ['Estacionaria', 'Espectro', 'Viajera'],
  ),
  // MOVIMIENTO: llamas quietas o que bailan y se agitan.
  CreatorModifier.slider('llama', 'Agitación', min: 0, max: 1, value: .5),
  // MÚSICA
  CreatorModifier.choice(
    'pulso',
    'Pulso',
    options: ['Graves', 'Golpes', 'Tono'],
  ),
  // ATMÓSFERA: el aire caliente que tiembla y el resplandor.
  CreatorModifier.slider('calor', 'Calor', min: 0, max: 1, value: .5),
  // MODO: suelo de espejo bajo el tubo.
  CreatorModifier.toggle('reflejo', 'Suelo de espejo', value: true),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Ecualizador', {
    'onda': 'Espectro',
    'pulso': 'Graves',
    'reflejo': true,
  }),
  CreatorVariation('Laboratorio', {
    'onda': 'Estacionaria',
    'pulso': 'Tono',
    'llama': .1,
    'reflejo': false,
    'calor': .2,
  }),
];

const nativeSource = r'''
class Visual final : public Scene {
  float bass = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, mode = 3.0f, modeTarget = 3.0f, centroid = 0.3f;
  // Reloj en doble precisión: sin música es idéntico a 30 y 60 FPS.
  double clock = 0;
  std::array<float, 32> spec{};
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
    bass = energy = slowBass = kick = flash = 0;
    mode = modeTarget = 3.0f;
    centroid = 0.3f;
    clock = 0;
    spec.fill(0.0f);
    beats = seed;
  }

  void update(const Frame& f) override {
    auto m = modifiers(f);
    const float dt = float(f.delta);
    const Music& mu = f.music;
    bass = follow(bass, mu.bass, 22.0f, 4.5f, dt);
    energy = follow(energy, mu.energy, 6.0f, 1.8f, dt);
    float hit = 0, fl = 0;
    for (const auto& e : mu.events[0]) hit = std::max(hit, e.strength);
    for (const auto& e : mu.events[2]) hit = std::max(hit, e.strength * 0.85f);
    for (const auto& e : mu.events[3]) fl = std::max(fl, e.strength);
    const float onset = std::clamp((mu.bass - slowBass - 0.15f) * 2.5f, 0.0f, 1.0f);
    slowBass = follow(slowBass, mu.bass, 3.0f, 3.0f, dt);
    hit = std::min(std::max(hit, onset), 1.0f);
    // Golpes: cada golpe salta a otro modo de la onda.
    if (hit > kick + 0.2f && m.pulso == 1) modeTarget = 2.0f + float(int(hashU(beats++ * 2654435761u) * 6.0f));
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    for (int i = 0; i < 31; i++) spec[size_t(i)] = mu.smoothSpectrum[size_t(i)];
    spec[31] = spec[30];
    // Tono: el modo sigue a lo agudo o grave que suena la música.
    float sum = 0, weighted = 0;
    for (int i = 0; i < 31; i++) {
      sum += mu.smoothSpectrum[size_t(i)];
      weighted += mu.smoothSpectrum[size_t(i)] * float(i);
    }
    if (sum > 0.05f) centroid = follow(centroid, weighted / sum / 30.0f, 4.0f, 4.0f, dt);
    if (m.pulso == 2 && mu.active) modeTarget = 1.5f + centroid * 9.0f;
    mode = follow(mode, modeTarget, 6.0f, 6.0f, dt);
    clock += f.delta * f.speed;
  }

  void render(const Frame& f, Canvas& c) const override {
    auto g = glide(f);
    const float amp = f.intensity;
    const float side = std::min(f.width, f.height);
    const float t = float(std::fmod(clock, 1000.0));
    // Sin música el modo pasea solo de 2 a 5 medias ondas.
    const bool live = f.music.active;
    const float idleMode = 3.5f + 1.5f * std::sin(t * 0.09f);
    const float m = live ? mode : idleMode;
    float A = 0.3f + 0.12f * std::min(energy * amp, 1.0f);
    A *= 1.0f + g.pulso.weight(0) * (std::min(bass * amp, 1.2f) * 0.9f - 0.3f) * (live ? 1.0f : 0.0f);
    std::vector<float> u;
    u.reserve(80);
    u.insert(u.end(), {t, 0.5f * f.height / side, std::min(kick * amp, 1.0f) * (0.4f + 0.6f * g.pulso.weight(1)), live ? 1.0f : 0.0f});
    // Detalle: cuántos agujeros tiene el tubo.
    u.insert(u.end(), {m, t * 0.3f, A, std::round(24.0f + 16.0f * f.detail)});
    u.insert(u.end(), {g.onda.weight(0), g.onda.weight(1), g.onda.weight(2), std::clamp(g.llama, 0.0f, 1.0f)});
    u.insert(u.end(), {std::clamp(g.calor, 0.0f, 1.0f), std::clamp(g.reflejo, 0.0f, 1.0f), f.glow, std::min(flash * amp, 1.0f)});
    for (int i = 0; i < 32; i++) u.push_back(std::min(spec[size_t(i)] * amp, 1.2f));
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[size_t(i)].r, f.colors[size_t(i)].g, f.colors[size_t(i)].b});
    c.material("rubens_tube", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'rubens_tube': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // tiempo, media altura, golpe, con música
uniform vec4 uB;   // modo, fase, amplitud, agujeros
uniform vec4 uW;   // pesos de onda: estacionaria, espectro, viajera; agitación
uniform vec4 uE;   // calor, reflejo, glow, destello
uniform vec4 uS0;  // espectro de la música en 32 valores
uniform vec4 uS1;
uniform vec4 uS2;
uniform vec4 uS3;
uniform vec4 uS4;
uniform vec4 uS5;
uniform vec4 uS6;
uniform vec4 uS7;
uniform vec3 uC0;
uniform vec3 uC1;
uniform vec3 uC2;
uniform vec3 uC3;
out vec4 fragColor;

const float TUBE_Y = 0.22;
const float TUBE_R = 0.028;
const float LEFT = -0.42;
const float RIGHT = 0.46;

float hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

float specIdx(float i) {
  float k = floor(i / 4.0);
  float c = i - k * 4.0;
  vec4 v = k < 0.5 ? uS0 : (k < 1.5 ? uS1 : (k < 2.5 ? uS2 : (k < 3.5 ? uS3 : (k < 4.5 ? uS4 : (k < 5.5 ? uS5 : (k < 6.5 ? uS6 : uS7))))));
  return c < 0.5 ? v.x : (c < 1.5 ? v.y : (c < 2.5 ? v.z : v.w));
}

float specAt(float x) {
  float fi = clamp(x, 0.0, 1.0) * 30.0;
  float i0 = floor(fi);
  float i1 = min(i0 + 1.0, 31.0);
  float a = specIdx(i0);
  float b = specIdx(i1);
  return mix(a, b, fi - i0);
}

// Altura de la llama en la posición x del tubo (0..1).
float flameHeight(float x, float t) {
  // Sólo se calcula la onda que pesa en la mezcla.
  float h = 0.0;
  if (uW.x > 0.001) h += uW.x * pow(abs(sin(3.14159265 * uB.x * x + uB.y)), 1.3);
  if (uW.y > 0.001) h += uW.y * (specAt(x) * 1.4 + 0.08);
  if (uW.z > 0.001) h += uW.z * (0.5 + 0.5 * sin(6.2831853 * (2.5 * x - t * 0.8)));
  return 0.025 + uB.z * h + uA.z * 0.08;
}

// Las llamas de los agujeros cercanos a p.
vec3 flames(vec2 p, float t) {
  float N = uB.w;
  float spacing = (RIGHT - LEFT) / N;
  float tx = (p.x - LEFT) / (RIGHT - LEFT);
  float idx = floor(tx * N);
  float yTop = TUBE_Y - TUBE_R;
  vec3 acc = vec3(0.0);
  // Por debajo del tubo o muy por encima de la llama más alta no hay fuego.
  float maxH = 0.03 + uB.z * 1.5 + uA.z * 0.08;
  if (p.y > yTop + 0.01 || yTop - p.y > maxH * 1.7 || p.x < LEFT - 0.05 || p.x > RIGHT + 0.05) return acc;
  for (int k = -1; k <= 1; k++) {
    float i = idx + float(k);
    if (i < 0.0 || i > N - 1.0) continue;
    float xn = (i + 0.5) / N;
    float xi = LEFT + xn * (RIGHT - LEFT);
    float H = flameHeight(xn, t);
    float hN = (yTop - p.y) / H;
    if (hN < -0.05 || hN > 1.6) continue;
    float wob = uW.w * 0.022 * hN * sin(hN * 7.0 - t * 12.0 + i * 1.7) + 0.006 * hN * sin(t * 23.0 + i * 3.1);
    float dx = abs(p.x - xi - wob);
    float w0 = spacing * 1.05;
    float wp = w0 * (0.45 + 1.6 * clamp(hN, 0.0, 1.0)) * pow(max(1.0 - hN, 0.0), 0.75) + 0.0015;
    float inside = smoothstep(wp, wp * 0.25, dx) * step(0.0, hN);
    float core = smoothstep(wp * 0.55, 0.0, dx) * clamp(1.0 - hN, 0.0, 1.0);
    vec3 c = mix(uC1, uC2, smoothstep(0.05, 0.3, hN));
    c = mix(c, uC3, core * 0.8);
    acc += c * inside * (0.8 + 0.4 * core);
    acc += uC2 * exp(-dx / (wp * 2.5 + 0.01)) * exp(-max(hN, 0.0) * 2.0) * 0.1 * uE.z * step(0.0, hN);
  }
  return acc;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  float t = uA.x;
  // Calor: el aire sobre las llamas tiembla.
  vec2 q = p;
  q.x += uE.x * 0.006 * sin(p.y * 55.0 + t * 7.0) * smoothstep(TUBE_Y, TUBE_Y - 0.5, p.y);
  vec3 col = uC0 + uC2 * 0.1 * exp(-abs(p.y - TUBE_Y + 0.2) * 3.0) * (0.5 + uE.x);
  col += flames(q, t);
  // El tubo de metal, con la luz de las llamas encima.
  float v = (p.y - TUBE_Y) / TUBE_R;
  if (abs(v) < 1.0 && p.x > LEFT - 0.01 && p.x < RIGHT + 0.01) {
    float shade = 0.2 + 0.7 * pow(1.0 - abs(v + 0.35) / 1.35, 2.0);
    vec3 metal = mix(uC0 * 2.0 + vec3(0.04), mix(uC3, vec3(1.0), 0.5) * 0.55, shade);
    metal += uC2 * 0.3 * smoothstep(0.2, -1.0, v);
    float holes = smoothstep(0.35, 0.2, abs(fract((p.x - LEFT) / (RIGHT - LEFT) * uB.w) - 0.5)) * smoothstep(-0.55, -0.95, v);
    col = mix(metal, uC0, holes * 0.8);
  }
  // El altavoz en el extremo izquierdo.
  vec2 sp = p - vec2(LEFT - 0.03, TUBE_Y);
  if (abs(sp.x) < 0.035 && abs(sp.y) < 0.06) {
    float cone = length(sp / vec2(0.03, 0.05));
    col = mix(uC0 * 2.5 + vec3(0.03), uC1 * 0.25, smoothstep(1.0, 0.3, cone) * (0.6 + 0.4 * sin(t * 40.0) * uA.w));
  }
  // Suelo de espejo: las llamas reflejadas y onduladas.
  float floorY = TUBE_Y + 0.07;
  if (uE.y > 0.001 && p.y > floorY) {
    vec2 r = vec2(p.x + 0.004 * sin(p.y * 80.0 + t * 3.0), 2.0 * floorY - p.y);
    float fade = exp(-(p.y - floorY) * 4.0);
    col += flames(r, t) * 0.35 * uE.y * fade;
  }
  col *= 1.0 + 0.12 * uE.w;
  col *= 1.0 - 0.3 * smoothstep(0.7, 1.5, length(p * vec2(0.9, 0.65)));
  float peak = max(col.r, max(col.g, col.b));
  if (peak > 0.9) col *= (0.9 + 0.1 * (peak - 0.9) / (peak - 0.8)) / peak;
  col += (hash12(frag) - 0.5) / 255.0;
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
