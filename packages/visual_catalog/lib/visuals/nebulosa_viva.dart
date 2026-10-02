// Nebulosa Viva — nube de gas interestelar iluminada por una estrella joven.
// Capas de gas con deformación de dominio, filamentos brillantes y polvo
// oscuro en paralaje. Cada golpe enciende la estrella y lanza una onda de
// choque que curva la luz al atravesar el gas; los graves avivan el brillo y
// el espectro desplaza el color entre cálido y frío.
const nativeSource = r'''
class Visual final : public Scene {
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0, warm = 0, cool = 0;
  float phase = 0, drift = 0, push = 0;
  std::array<float, 4> shocks{};  // radio, amplitud, radio, amplitud

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = warm = cool = 0;
    phase = rng.unit() * 30.0f;
    drift = rng.unit() * 20.0f;
    push = 0;
    shocks = {6.0f, 0.0f, 6.0f, 0.0f};
  }

  void update(const Frame& f) override {
    float dt = float(f.delta);
    const Music& m = f.music;
    bass = follow(bass, m.bass, 20.0f, 4.0f, dt);
    body = follow(body, m.body, 12.0f, 3.0f, dt);
    spark = follow(spark, m.spark, 30.0f, 7.0f, dt);
    energy = follow(energy, m.energy, 6.0f, 1.8f, dt);
    drive = follow(drive, m.active ? std::pow(std::clamp(m.energy, 0.0f, 1.0f), 0.8f) : 0.0f, 3.0f, 0.7f, dt);
    float low = 0, high = 0;
    for (int i = 0; i < 10; i++) low = std::max(low, m.smoothSpectrum[i]);
    for (int i = 18; i < 31; i++) high = std::max(high, m.smoothSpectrum[i]);
    warm = follow(warm, low, 10.0f, 2.5f, dt);
    cool = follow(cool, high, 10.0f, 2.5f, dt);

    float hit = 0, fl = 0;
    for (const auto& e : m.events[0]) hit = std::max(hit, e.strength);
    for (const auto& e : m.events[2]) hit = std::max(hit, e.strength * 0.85f);
    for (const auto& e : m.events[3]) fl = std::max(fl, e.strength);
    float onset = std::clamp((m.bass - slowBass - 0.15f) * 2.5f, 0.0f, 1.0f);
    slowBass = follow(slowBass, m.bass, 3.0f, 3.0f, dt);
    hit = std::min(std::max(hit, onset), 1.0f);
    if (hit > kick + 0.2f) {
      shocks[2] = shocks[0];
      shocks[3] = shocks[1];
      shocks[0] = 0.0f;
      shocks[1] = hit;
    }
    kick = std::max(kick * std::exp(-dt * 4.5f), hit);
    flash = std::max(flash * std::exp(-dt * 7.0f), std::min(fl, 1.0f));
    for (int i = 0; i < 4; i += 2) {
      shocks[i] += dt * 0.85f;
      shocks[i + 1] *= std::exp(-dt * 1.3f);
    }

    phase += dt * f.speed * (0.10f + 0.6f * drive + 0.5f * kick);
    drift += dt * f.speed * (0.02f + 0.08f * drive);
    push = follow(push, kick, 12.0f, 2.5f, dt);
  }

  void render(const Frame& f, Canvas& c) const override {
    float amp = f.intensity;
    std::vector<float> u;
    u.reserve(32);
    u.insert(u.end(), {phase, bass * amp, kick * amp, energy});
    u.insert(u.end(), {shocks[0], shocks[1] * amp, shocks[2], shocks[3] * amp});
    u.insert(u.end(), {warm, cool, spark * amp, f.glow});
    u.insert(u.end(), {drift, push * amp, flash, f.detail});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("nebula", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'nebula': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // tiempo, graves, golpe, energía
uniform vec4 uS;   // ondas de choque: radio, amplitud, radio, amplitud
uniform vec4 uT;   // cálido, frío, agudos, glow
uniform vec4 uX;   // deriva, empuje, destello, detalle
uniform vec3 uC0;
uniform vec3 uC1;
uniform vec3 uC2;
uniform vec3 uC3;
out vec4 fragColor;

// Campana gaussiana segura: pow() con base negativa no está definido en GLSL.
float gauss(float x) {
  return exp(-x * x);
}

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

float fbm(vec2 p) {
  float s = 0.0;
  float a = 0.5;
  for (int i = 0; i < 5; i++) {
    s += a * noise(p);
    p = mat2(1.6, 1.2, -1.2, 1.6) * p + vec2(1.3, -0.7);
    a *= 0.5;
  }
  return s;
}

float fbmLow(vec2 p) {
  float s = 0.0;
  float a = 0.5;
  for (int i = 0; i < 3; i++) {
    s += a * noise(p);
    p = mat2(1.6, 1.2, -1.2, 1.6) * p + vec2(1.3, -0.7);
    a *= 0.5;
  }
  return s / 0.875 * 0.97;
}

// Ruido de crestas: filamentos finos y brillantes.
float ridged(vec2 p) {
  float s = 0.0;
  float a = 0.55;
  for (int i = 0; i < 4; i++) {
    float n = 1.0 - abs(noise(p) * 2.0 - 1.0);
    s += a * n * n;
    p = mat2(1.7, 1.1, -1.1, 1.7) * p + vec2(-2.1, 0.4);
    a *= 0.5;
  }
  return s;
}

float stars(vec2 uv, float scale, float threshold) {
  vec2 g = uv * scale;
  vec2 id = floor(g);
  vec2 f = fract(g) - 0.5;
  float h = hash12(id);
  vec2 o = vec2(hash12(id + 3.1), hash12(id + 7.7)) - 0.5;
  float d = length(f - o * 0.7);
  float tw = 0.55 + 0.45 * sin(uA.x * (3.0 + 6.0 * uT.z) + h * 40.0);
  return smoothstep(0.09, 0.0, d) * step(threshold, h) * tw;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 uv = (frag - 0.5 * uSize) / scale;
  uv.y = -uv.y;
  float t = uA.x;
  float kick = uA.z;

  // Empuje de cámara con el golpe y onda de choque que curva la luz.
  uv /= 1.0 + 0.10 * uX.y;
  vec2 core = vec2(0.06, 0.04);
  vec2 rel = uv - core;
  float r = length(rel);
  float shock = uS.y * gauss((r - uS.x) * 9.0) + uS.w * gauss((r - uS.z) * 9.0);
  vec2 lens = rel / max(r, 0.001) * shock * 0.035;
  vec2 p = uv + lens;

  vec2 drift = vec2(uX.x * 0.6, uX.x * 0.25);
  vec2 q = p * 1.35 + drift;
  vec2 w = vec2(fbmLow(q + vec2(0.0, t * 0.04)), fbmLow(q + vec2(5.2, -t * 0.03)));
  w = (w - 0.5) * (1.4 + 0.45 * uA.y);
  float gas = fbm(q * 1.1 + w);
  float fil = ridged(q * 1.9 + w * 1.6 + vec2(t * 0.02, 0.0));
  float dust = smoothstep(0.50, 0.72, fbmLow(q * 1.6 + w * 0.8 + vec2(11.0, 3.0)));
  vec2 nearQ = p * 2.6 + drift * 1.8 + w * 0.5;
  float wisps = fbmLow(nearQ + vec2(t * 0.05, 0.0));

  // Color de emisión: dos gases que se mezclan, desplazados por el espectro.
  float mixer = smoothstep(0.25, 0.75, w.x * 0.5 + 0.5 + 0.35 * (uT.y - uT.x));
  vec3 emit = mix(uC1, uC2, mixer);
  float coreLight = (0.08 + 0.18 * uA.y + 0.9 * kick) / (0.015 + r * r * 5.0);
  float density = pow(clamp(gas * 1.35 - 0.25, 0.0, 1.0), 2.2);
  vec3 neb = emit * density * (0.45 + 0.22 * uA.y + 0.1 * uA.w);
  neb += mix(emit, uC3, 0.2) * pow(fil, 3.0) * density * (0.6 + 0.7 * uT.z + 0.15 * uA.y);
  neb *= 1.0 + coreLight * 0.25;
  neb += mix(emit, uC3, 0.5) * shock * density * 1.8;
  neb += uC2 * pow(clamp(wisps * 1.4 - 0.45, 0.0, 1.0), 2.0) * (0.12 + 0.25 * uA.y);

  vec3 col = uC0;
  float st = stars(p + drift * 0.2, 80.0, 0.975) + stars(p + drift * 0.5 + 7.0, 34.0, 0.988) * 1.6;
  col += vec3(0.9, 0.93, 1.0) * st * (1.0 - dust * 0.9) * (0.7 + 0.8 * uT.z);
  col += neb * (1.0 - 0.85 * dust) * uT.w;
  // Estrella joven en el núcleo con destello en cruz.
  float star = (0.0022 + 0.008 * kick + 0.002 * uA.y) / (r * r + 0.0008);
  float spikes = (0.0006 + 0.004 * kick) / (abs(rel.x * rel.y) * 30.0 + 0.0006) * exp(-r * 6.0);
  col += uC3 * (star + spikes) * (1.0 - 0.5 * dust);
  col += mix(uC2, uC3, 0.5) * uX.z * 0.08;

  col *= 1.0 - 0.4 * smoothstep(0.45, 1.25, length(uv * vec2(0.9, 0.7)));
  // Realce de croma: el gas conserva su color en los momentos intensos.
  float luma = dot(col, vec3(0.299, 0.587, 0.114));
  col = max(mix(vec3(luma), col, 1.35), 0.0);
  col = clamp((col * (2.51 * col + 0.03)) / (col * (2.43 * col + 0.59) + 0.14), 0.0, 1.0);
  col = pow(col, vec3(0.4545));
  col += (hash12(frag) - 0.5) / 255.0;
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
