// Campo de Flujo — corrientes de partículas luminosas con estelas de cometa.
// Unas 420 partículas siguen un campo de flujo con tres grandes remolinos que se
// desplazan por la pantalla; cada una deja una estela de luz larga. Cada golpe
// las hace estallar hacia fuera desde el centro antes de que la corriente las
// vuelva a arrastrar; los graves aceleran la corriente y cada tercio de
// partículas brilla con su banda (graves, medios o agudos).
const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kTrail = 14;
  // La simulación avanza en pasos fijos de 1/60 s contados con el tiempo
  // absoluto: es idéntica a 30 y a 60 FPS y se dibuja interpolada.
  static constexpr double kHz = 60.0;
  static constexpr float kStep = float(1.0 / kHz);
  static constexpr int kRecordEvery = 2;  // una muestra de estela cada 1/30 s
  struct Particle { float x, y, px, py, vx, vy, life, size; int group; };
  std::vector<Particle> ps;
  std::vector<float> trail;  // anillo de posiciones: partícula * kTrail * 2
  int head = 0;
  int recordCount = 0;
  int64_t steps = -1;
  float frac = 0, pendingHit = 0;
  float w = 0, h = 0;
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  std::array<float, 3> groups{};
  float t = 0, hue = 0;
  Random rng{17};

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  void spawn(size_t i) {
    Particle& p = ps[i];
    p.x = rng.unit() * w;
    p.y = rng.unit() * h;
    p.px = p.x;
    p.py = p.y;
    p.vx = p.vy = 0;
    p.life = 2.5f + rng.unit() * 5.0f;
    for (int k = 0; k < kTrail; k++) {
      trail[(i * kTrail + k) * 2] = p.x;
      trail[(i * kTrail + k) * 2 + 1] = p.y;
    }
  }

  // Dirección del flujo: corriente sinusoidal más tres remolinos que se mueven.
  void field(float x, float y, float& fx, float& fy) const {
    float s = std::min(w, h);
    float u = (x - w * 0.5f) / s, v = (y - h * 0.5f) / s;
    float a = std::sin(u * 3.1f + t * 0.30f) * 1.6f + std::cos(v * 2.7f - t * 0.25f) * 1.6f +
              std::sin((u + v) * 1.9f + t * 0.17f) * 1.2f;
    fx = std::cos(a);
    fy = std::sin(a);
    for (int k = 0; k < 3; k++) {
      float cx = 0.33f * std::sin(t * 0.21f + float(k) * 2.1f) * (w / s);
      float cy = 0.42f * std::cos(t * 0.17f + float(k) * 1.7f) * (h / s);
      float du = u - cx, dv = v - cy;
      float d2 = du * du + dv * dv + 0.02f;
      float spin = (k % 2 == 0 ? 1.0f : -1.0f) * (0.09f + 0.10f * bass) / d2;
      fx += -dv * spin;
      fy += du * spin;
    }
    float len = std::sqrt(fx * fx + fy * fy) + 1e-4f;
    fx /= len;
    fy /= len;
  }

  void step(float flowSpeed, float speed) {
    float s = std::min(w, h);
    float hit = pendingHit;
    pendingHit = 0;
    t += kStep * speed * (0.25f + 0.9f * drive);
    const float k = 1.0f - std::exp(-kStep * 2.6f);
    float margin = s * 0.08f;
    for (size_t i = 0; i < ps.size(); i++) {
      Particle& p = ps[i];
      p.px = p.x;
      p.py = p.y;
      if (hit > 0) {
        // Estallido: empuje radial desde el centro de la pantalla.
        float dx = p.x - w * 0.5f, dy = p.y - h * 0.5f;
        float d = std::sqrt(dx * dx + dy * dy) + 1.0f;
        float push = s * (0.9f + 0.6f * rng.unit()) * hit;
        p.vx += dx / d * push;
        p.vy += dy / d * push;
      }
      float fx, fy;
      field(p.x, p.y, fx, fy);
      p.vx += (fx * flowSpeed * p.size - p.vx) * k;
      p.vy += (fy * flowSpeed * p.size - p.vy) * k;
      p.x += p.vx * kStep;
      p.y += p.vy * kStep;
      p.life -= kStep;
      if (p.life <= 0 || p.x < -margin || p.x > w + margin || p.y < -margin || p.y > h + margin) spawn(i);
    }
    if (++recordCount >= kRecordEvery) {
      recordCount = 0;
      for (size_t i = 0; i < ps.size(); i++) {
        trail[(i * kTrail + head) * 2] = ps[i].x;
        trail[(i * kTrail + head) * 2 + 1] = ps[i].y;
      }
      head = (head + 1) % kTrail;
    }
  }

 public:
  void reset(uint32_t seed) override {
    rng = Random(seed);
    ps.clear();
    trail.clear();
    w = h = 0;
    head = 0;
    recordCount = 0;
    steps = -1;
    frac = pendingHit = 0;
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    groups.fill(0);
    t = rng.unit() * 20.0f;
    hue = 0;
  }

  void update(const Frame& f) override {
    float dt = float(f.delta);
    if (f.width != w || f.height != h || ps.empty()) {
      w = f.width;
      h = f.height;
      int count = int(300.0f + 120.0f * std::clamp(f.detail, 0.25f, 2.0f));
      ps.assign(count, Particle{0, 0, 0, 0, 0, 0, 0, 1, 0});
      trail.assign(size_t(count) * kTrail * 2, 0.0f);
      for (int i = 0; i < count; i++) {
        ps[i].group = i % 3;
        ps[i].size = 0.7f + rng.unit() * 0.6f;
        spawn(size_t(i));
        ps[i].life *= rng.unit();
      }
    }
    const Music& m = f.music;
    bass = follow(bass, m.bass, 22.0f, 4.5f, dt);
    body = follow(body, m.body, 12.0f, 3.0f, dt);
    spark = follow(spark, m.spark, 30.0f, 7.0f, dt);
    energy = follow(energy, m.energy, 6.0f, 1.8f, dt);
    drive = follow(drive, m.active ? std::pow(std::clamp(m.energy, 0.0f, 1.0f), 0.8f) : 0.0f, 3.0f, 0.7f, dt);
    float lo = 0, mi = 0, hi = 0;
    for (int i = 0; i < 9; i++) lo = std::max(lo, m.smoothSpectrum[i]);
    for (int i = 9; i < 21; i++) mi = std::max(mi, m.smoothSpectrum[i]);
    for (int i = 21; i < 31; i++) hi = std::max(hi, m.smoothSpectrum[i]);
    groups[0] = follow(groups[0], lo, 20.0f, 4.0f, dt);
    groups[1] = follow(groups[1], mi, 20.0f, 4.0f, dt);
    groups[2] = follow(groups[2], hi, 20.0f, 4.0f, dt);

    float hit = 0, fl = 0;
    for (const auto& e : m.events[0]) hit = std::max(hit, e.strength);
    for (const auto& e : m.events[2]) hit = std::max(hit, e.strength * 0.85f);
    for (const auto& e : m.events[3]) fl = std::max(fl, e.strength);
    float onset = std::clamp((m.bass - slowBass - 0.15f) * 2.5f, 0.0f, 1.0f);
    slowBass = follow(slowBass, m.bass, 3.0f, 3.0f, dt);
    hit = std::min(std::max(hit, onset), 1.0f);
    if (hit > kick + 0.2f) pendingHit = std::max(pendingHit, hit);
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    hue += dt * (0.01f + 0.04f * energy);

    float flowSpeed = std::min(w, h) * f.speed * (0.19f + 0.28f * drive + 0.20f * bass);
    int64_t target = int64_t(std::floor(f.time * kHz + 1e-6));
    if (steps < 0 || target < steps || target - steps > 30) steps = target - 1;
    while (steps < target) {
      step(flowSpeed, f.speed);
      steps++;
    }
    frac = std::clamp(float(f.time * kHz - double(steps)), 0.0f, 1.0f);
  }

  void render(const Frame& f, Canvas& c) const override {
    float amp = f.intensity;
    float s = std::min(f.width, f.height);
    float px = s / 400.0f;
    c.material("flow", {0, 0, f.width, f.height},
               {t, bass * amp, kick * amp, energy, hue, f.glow,
                f.colors[0].r, f.colors[0].g, f.colors[0].b, f.colors[1].r, f.colors[1].g, f.colors[1].b,
                f.colors[2].r, f.colors[2].g, f.colors[2].b, f.colors[3].r, f.colors[3].g, f.colors[3].b});
    if (ps.empty()) return;
    auto alpha = [](float v) { return std::clamp(v, 0.0f, 1.0f); };
    for (int g = 0; g < 3; g++) {
      const Color& col = f.colors[1 + g];
      float gain = (0.85f + 1.0f * groups[g] + 0.6f * kick) * amp;
      Path tail, tip;
      std::vector<Vec2> heads;
      for (size_t i = 0; i < ps.size(); i++) {
        const Particle& p = ps[i];
        if (p.group != g) continue;
        float x = p.px + (p.x - p.px) * frac, y = p.py + (p.y - p.py) * frac;
        tail.moveTo(x, y);
        tip.moveTo(x, y);
        for (int k = 1; k <= kTrail; k++) {
          int slot = (head - k + kTrail) % kTrail;
          float tx = trail[(i * kTrail + slot) * 2], ty = trail[(i * kTrail + slot) * 2 + 1];
          tail.lineTo(tx, ty);
          if (k <= 3) tip.lineTo(tx, ty);
        }
        heads.push_back({x, y});
      }
      Paint glow;
      glow.blend = Blend::plus;
      glow.strokeCap = 1;
      glow.strokeJoin = 1;
      glow.strokeWidth = 8.0f * px;
      glow.color = {col.r, col.g, col.b, alpha(0.07f * gain * f.glow)};
      c.path(tail, glow);
      Paint core = glow;
      core.strokeWidth = 1.8f * px;
      core.color = {col.r, col.g, col.b, alpha(0.45f * gain)};
      c.path(tail, core);
      Paint bright = glow;
      bright.strokeWidth = 3.0f * px;
      bright.color = {(col.r + 1.0f) * 0.5f, (col.g + 1.0f) * 0.5f, (col.b + 1.0f) * 0.5f, alpha(0.55f * gain)};
      c.path(tip, bright);
      Paint dot;
      dot.blend = Blend::plus;
      float twinkle = 0.75f + 0.25f * std::sin(t * 9.0f + float(g) * 2.0f) * spark;
      dot.color = {(col.r + 1.0f) * 0.5f, (col.g + 1.0f) * 0.5f, (col.b + 1.0f) * 0.5f,
                   alpha((0.6f + 0.4f * groups[g] + 0.3f * kick) * twinkle)};
      c.points(heads, (2.2f + 1.6f * groups[g] * amp + 1.2f * kick * amp) * px, dot);
    }
  }
};
''';

const shaderSources = <String, String>{
  'flow': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // tiempo del campo, graves, golpe, energía
uniform vec2 uB;   // tono, glow
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

float fbm(vec2 p) {
  float s = 0.0;
  float a = 0.5;
  for (int i = 0; i < 3; i++) {
    s += a * noise(p);
    p = mat2(1.6, 1.2, -1.2, 1.6) * p;
    a *= 0.5;
  }
  return s / 0.875;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  float t = uA.x;
  // Humo de color que fluye en la misma dirección general que las partículas.
  float a = sin(p.x * 3.1 + t * 0.3) * 1.6 + cos(p.y * 2.7 - t * 0.25) * 1.6;
  vec2 flow = vec2(cos(a), sin(a));
  float smoke = fbm(p * 2.0 + flow * 0.35 + vec2(t * 0.05, -t * 0.04));
  float mixer = fbm(p * 1.2 - vec2(t * 0.03, 0.0) + 3.0);
  vec3 tint = mix(mix(uC1, uC2, smoothstep(0.3, 0.7, mixer)), uC3, smoothstep(0.65, 0.9, mixer) * 0.5);
  vec3 col = uC0 + tint * smoothstep(0.45, 0.9, smoke) * (0.05 + 0.08 * uA.w + 0.12 * uA.z + 0.06 * uA.y) * uB.y;
  col *= 1.0 - 0.4 * smoothstep(0.5, 1.3, length(p * vec2(0.9, 0.65)));
  col += (hash12(frag) - 0.5) / 255.0;
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
