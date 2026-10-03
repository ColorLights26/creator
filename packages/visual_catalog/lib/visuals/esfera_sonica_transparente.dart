// Esfera Sónica Transparente — esfera 3D de puntos de luz que se deforma con el espectro.
// Versión overlay: mismo movimiento y reacción a la música sin fondo opaco.
// Unos 2400 puntos repartidos en espiral de Fibonacci forman una esfera que
// gira; cada franja de latitud responde a una banda del espectro y empuja sus
// puntos hacia fuera como púas. Cada golpe la hace respirar y lanza un anillo;
// en el drop la esfera explota en una nube de partículas que gira y vuelve a
// formarse con un muelle amortiguado.
const nativeSource = r'''
class Visual final : public Scene {
  struct Dot { float x, y, z, seed; int band, group; };
  std::vector<Dot> dots;
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0, mids = 0;
  std::array<float, 31> spec{};
  // Fases en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double yaw = 0, tilt = 0, sinceBurst = 100;
  float explode = 0, explodeVel = 0, breath = 0, breathVel = 0;
  float ringR = 3.0f, ringAmp = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  static float hash(float n) {
    float x = std::sin(n) * 43758.5453f;
    return x - std::floor(x);
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    dots.clear();
    bass = body = spark = energy = slowBass = kick = flash = drive = mids = 0;
    spec.fill(0);
    yaw = rng.unit() * 6.2831853;
    tilt = rng.unit() * 6.2831853;
    sinceBurst = 100;
    explode = explodeVel = breath = breathVel = 0;
    ringR = 3.0f;
    ringAmp = 0;
  }

  void update(const Frame& f) override {
    float dt = float(f.delta);
    if (dots.empty()) {
      int count = int(2000.0f + 1000.0f * std::clamp(f.detail, 0.25f, 2.0f));
      dots.resize(count);
      const float golden = 2.39996323f;
      for (int i = 0; i < count; i++) {
        float y = 1.0f - 2.0f * (float(i) + 0.5f) / float(count);
        float r = std::sqrt(std::max(0.0f, 1.0f - y * y));
        float phi = float(i) * golden;
        Dot& d = dots[i];
        d.x = std::cos(phi) * r;
        d.y = y;
        d.z = std::sin(phi) * r;
        d.seed = hash(float(i) * 12.9898f + 3.1f);
        // El ecuador responde a los graves y los polos a los agudos.
        d.band = std::clamp(int(std::fabs(y) * 22.0f + d.seed * 9.0f), 0, 30);
        d.group = d.band < 8 ? 0 : (d.band < 18 ? 1 : 2);
      }
    }
    const Music& m = f.music;
    bass = follow(bass, m.bass, 22.0f, 4.5f, dt);
    body = follow(body, m.body, 12.0f, 3.0f, dt);
    spark = follow(spark, m.spark, 30.0f, 7.0f, dt);
    energy = follow(energy, m.energy, 6.0f, 1.8f, dt);
    drive = follow(drive, m.active ? std::pow(std::clamp(m.energy, 0.0f, 1.0f), 0.8f) : 0.0f, 3.0f, 0.7f, dt);
    float mi = 0;
    for (int i = 9; i < 21; i++) mi = std::max(mi, m.smoothSpectrum[i]);
    mids = follow(mids, mi, 12.0f, 3.0f, dt);
    for (int i = 0; i < 31; i++) spec[i] = follow(spec[i], m.smoothSpectrum[i], 25.0f, 5.0f, dt);

    float hit = 0, fl = 0;
    for (const auto& e : m.events[0]) hit = std::max(hit, e.strength);
    for (const auto& e : m.events[2]) hit = std::max(hit, e.strength * 0.85f);
    for (const auto& e : m.events[3]) fl = std::max(fl, e.strength);
    float onset = std::clamp((m.bass - slowBass - 0.15f) * 2.5f, 0.0f, 1.0f);
    slowBass = follow(slowBass, m.bass, 3.0f, 3.0f, dt);
    hit = std::min(std::max(hit, onset), 1.0f);
    sinceBurst += f.delta;
    if (hit > kick + 0.2f) {
      breathVel += 1.6f * hit;
      ringR = 0.0f;
      ringAmp = hit;
      // Drop: golpe fuerte con la música lanzada -> la esfera explota.
      if (hit > 0.7f && drive > 0.4f && sinceBurst > 6.0) {
        explodeVel += 4.5f * hit;
        sinceBurst = 0;
      }
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    // Muelles amortiguados: la explosión vuelve despacio y la respiración rápido.
    explodeVel += (-explode * 6.0f - explodeVel * 2.6f) * dt;
    explode += explodeVel * dt;
    breathVel += (-breath * 40.0f - breathVel * 7.0f) * dt;
    breath += breathVel * dt;
    ringR += dt * (0.8f + 0.5f * drive);
    ringAmp *= std::exp(-dt * 2.2f);

    yaw += f.delta * f.speed * (0.25 + 0.7 * drive + 0.9 * std::max(0.0f, explode));
    tilt += f.delta * f.speed * 0.13;
  }

  void render(const Frame& f, Canvas& c) const override {
    float amp = f.intensity;
    float s = std::min(f.width, f.height);
    float cx = f.width * 0.5f, cy = f.height * 0.5f;
    float R = 0.34f * s;
    std::vector<float> u;
    u.reserve(20);
    u.insert(u.end(), {float(std::fmod(yaw, 1000.0)), bass * amp, kick * amp, energy});
    u.insert(u.end(), {f.glow, ringR, ringAmp * amp, std::max(0.0f, explode)});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("sonic_core", {0, 0, f.width, f.height}, u);
    if (dots.empty()) return;

    float cyaw = float(std::cos(yaw)), syaw = float(std::sin(yaw));
    float pitch = 0.45f * float(std::sin(tilt));
    float cp = std::cos(pitch), sp = std::sin(pitch);
    float ex = std::max(-0.3f, explode);
    float wob = float(std::fmod(yaw * 3.0, 6.2831853));
    // Nueve grupos: tres profundidades por tres colores.
    std::array<std::vector<Vec2>, 9> bins;
    for (auto& b : bins) b.reserve(dots.size() / 4);
    for (const Dot& d : dots) {
      // Púas irregulares: cada punto responde con distinta fuerza a su banda.
      float spike = d.seed * d.seed;
      float v = spec[d.band] * (0.25f + 1.6f * spike);
      // Olas lentas que recorren la superficie aunque no haya música.
      float rad = 1.0f + 0.12f * breath + 0.42f * v * amp + 0.05f * std::sin(d.y * 7.0f + wob * 2.0f) +
                  0.025f * std::sin(d.seed * 40.0f + wob) +
                  ex * (0.35f + 1.6f * d.seed);
      // Giro alrededor del eje vertical y luego inclinación.
      float x = d.x * cyaw + d.z * syaw;
      float z = -d.x * syaw + d.z * cyaw;
      float y = d.y * cp - z * sp;
      z = d.y * sp + z * cp;
      // En la explosión la nube se retuerce alrededor del eje.
      float twist = ex * (d.seed - 0.5f) * 1.5f;
      float tx = x * std::cos(twist) - z * std::sin(twist);
      float tz = x * std::sin(twist) + z * std::cos(twist);
      float persp = 3.2f / (3.2f - tz * rad);
      float sx = cx + tx * rad * R * persp;
      float sy = cy + y * rad * R * persp;
      int depth = tz < -0.3f ? 0 : (tz < 0.35f ? 1 : 2);
      bins[depth * 3 + d.group].push_back({sx, sy});
    }
    float px = s / 400.0f;
    float gain = std::clamp((0.8f + 0.5f * bass + 0.5f * kick) * amp, 0.0f, 1.5f);
    const float sizes[3] = {1.0f, 1.5f, 2.1f};
    const float alphas[3] = {0.30f, 0.62f, 0.95f};
    for (int depth = 0; depth < 3; depth++) {
      for (int g = 0; g < 3; g++) {
        const auto& pts = bins[depth * 3 + g];
        if (pts.empty()) continue;
        const Color& col = f.colors[1 + g];
        Paint halo;
        halo.blend = Blend::plus;
        halo.color = {col.r, col.g, col.b, std::clamp(0.07f * alphas[depth] * gain * f.glow, 0.0f, 1.0f)};
        c.points(pts, sizes[depth] * 3.2f * px, halo);
        Paint core;
        core.blend = Blend::plus;
        core.color = {col.r, col.g, col.b, std::clamp(alphas[depth] * gain, 0.0f, 1.0f)};
        c.points(pts, (sizes[depth] + 0.4f * spark * amp) * px, core);
      }
    }
  }
};
''';

const shaderSources = <String, String>{
  'sonic_core': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // fase de giro, graves, golpe, energía
uniform vec4 uB;   // glow, radio y fuerza del anillo, explosión
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

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  float r = length(p);
  float bass = uA.y;
  float kick = uA.z;

  vec3 col = uC0;
  // Núcleo de energía dentro de la esfera y halo que la envuelve.
  col += uC1 * (0.004 + 0.010 * bass + 0.02 * kick) / (r * r + 0.02) * uB.x;
  col += uC1 * exp(-(r - 0.31) * (r - 0.31) * 60.0) * (0.03 + 0.05 * bass) * uB.x;
  // Anillo del golpe y fogonazo de la explosión.
  float ring = 0.31 + uB.y * 0.6;
  col += mix(uC1, uC3, 0.3) * uB.z * exp(-(r - ring) * (r - ring) * 900.0) * 0.8;
  col += mix(uC2, uC3, 0.5) * uB.w * 0.06 * smoothstep(1.0, 0.0, r);

  col *= 1.0 - 0.5 * smoothstep(0.4, 1.2, length(p * vec2(0.9, 0.65)));
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
