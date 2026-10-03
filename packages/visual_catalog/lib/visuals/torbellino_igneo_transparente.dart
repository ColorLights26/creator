// Torbellino Ígneo Transparente — estelas de luz naranja que giran en espiral hacia el centro.
// Versión overlay: mismo movimiento y reacción a la música sin fondo opaco.
// Unas 420 partículas siguen un remolino único: giran más rápido cuanto más
// cerca están del núcleo y se van hundiendo en él mientras dejan estelas
// curvas. Cada golpe las lanza hacia fuera en una onda de choque y acelera el
// giro; los graves avivan el núcleo y cada tercio de partículas brilla con su
// banda (graves, medios o agudos).
const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kTrail = 16;
  static constexpr float kRecord = 1.0f / 32.0f;
  struct Particle { float x, y, vx, vy, life, size; int group; };
  std::vector<Particle> ps;
  std::vector<float> trail;  // anillo de posiciones: partícula * kTrail * 2
  int head = 0;
  float recordAcc = 0;
  float w = 0, h = 0;
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0, surge = 0;
  std::array<float, 3> groups{};
  float t = 0, spin = 0, ringR = 3.0f, ringAmp = 0;
  Random rng{23};

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  void spawn(size_t i) {
    Particle& p = ps[i];
    float s = std::min(w, h);
    float margin = s * 0.06f;
    p.x = -margin + rng.unit() * (w + 2.0f * margin);
    p.y = -margin + rng.unit() * (h + 2.0f * margin);
    p.vx = p.vy = 0;
    p.life = 2.5f + rng.unit() * 4.5f;
    for (int k = 0; k < kTrail; k++) {
      trail[(i * kTrail + k) * 2] = p.x;
      trail[(i * kTrail + k) * 2 + 1] = p.y;
    }
  }

  // Velocidad del remolino (en lados cortos por segundo): giro que se acelera
  // hacia el núcleo, hundimiento lento y una ondulación que forma brazos.
  void field(float x, float y, float& fx, float& fy) const {
    float s = std::min(w, h);
    float u = (x - w * 0.5f) / s, v = (y - h * 0.5f) / s;
    float r = std::sqrt(u * u + v * v) + 1e-3f;
    float tx = -v / r, ty = u / r;
    float rx = u / r, ry = v / r;
    float vt = 0.22f + 0.10f / (r + 0.10f);
    float vr = -(0.10f + 0.06f * r + 0.025f / (r + 0.05f));
    float wave = 0.18f * std::sin(r * 9.0f - t * 1.3f + 3.0f * std::atan2(v, u));
    float bx = tx * vt + rx * vr, by = ty * vt + ry * vr;
    float cw = std::cos(wave), sw = std::sin(wave);
    fx = bx * cw - by * sw;
    fy = bx * sw + by * cw;
  }

 public:
  void reset(uint32_t seed) override {
    rng = Random(seed);
    ps.clear();
    trail.clear();
    w = h = 0;
    head = 0;
    recordAcc = 0;
    bass = body = spark = energy = slowBass = kick = flash = drive = surge = 0;
    groups.fill(0);
    t = rng.unit() * 20.0f;
    spin = rng.unit() * 6.2831853f;
    ringR = 3.0f;
    ringAmp = 0;
  }

  void update(const Frame& f) override {
    float dt = float(f.delta);
    if (f.width != w || f.height != h || ps.empty()) {
      w = f.width;
      h = f.height;
      int count = int(300.0f + 120.0f * std::clamp(f.detail, 0.25f, 2.0f));
      ps.assign(count, Particle{0, 0, 0, 0, 0, 1, 0});
      trail.assign(size_t(count) * kTrail * 2, 0.0f);
      for (int i = 0; i < count; i++) {
        ps[i].group = i % 3;
        ps[i].size = 0.75f + rng.unit() * 0.5f;
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
    bool strike = hit > kick + 0.2f;
    if (strike) {
      surge = std::max(surge, hit);
      ringR = 0.0f;
      ringAmp = hit;
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    surge *= std::exp(-dt * 1.8f);
    ringR += dt * (0.9f + 0.5f * drive);
    ringAmp *= std::exp(-dt * 2.4f);

    float s = std::min(w, h);
    float flow = f.speed * (0.65f + 0.7f * drive + 0.45f * bass + 0.6f * surge);
    t += dt * f.speed * (0.4f + 0.8f * drive);
    spin += dt * flow * 0.8f;
    for (size_t i = 0; i < ps.size(); i++) {
      Particle& p = ps[i];
      float dx = p.x - w * 0.5f, dy = p.y - h * 0.5f;
      float d = std::sqrt(dx * dx + dy * dy) + 1.0f;
      if (strike) {
        // Onda de choque: las estelas salen disparadas hacia fuera.
        float push = s * (0.7f + 0.5f * rng.unit()) * hit;
        p.vx += dx / d * push;
        p.vy += dy / d * push;
      }
      // Las partículas siguen el remolino sin inercia (la inercia las expulsa
      // por fuerza centrífuga y vacía el centro); sólo el empujón del golpe
      // tiene inercia y se amortigua.
      float fx, fy;
      field(p.x, p.y, fx, fy);
      float decay = std::exp(-dt * 2.4f);
      p.vx *= decay;
      p.vy *= decay;
      p.x += (fx * s * flow * p.size + p.vx) * dt;
      p.y += (fy * s * flow * p.size + p.vy) * dt;
      p.life -= dt;
      float margin = s * 0.1f;
      bool sunk = d < s * 0.05f;
      if (p.life <= 0 || sunk || p.x < -margin || p.x > w + margin || p.y < -margin || p.y > h + margin) spawn(i);
    }
    // Las estelas se registran a intervalos fijos: mismo aspecto a 30 y 60 FPS.
    recordAcc += dt;
    int guard = 0;
    while (recordAcc >= kRecord && guard < 4) {
      recordAcc -= kRecord;
      for (size_t i = 0; i < ps.size(); i++) {
        trail[(i * kTrail + head) * 2] = ps[i].x;
        trail[(i * kTrail + head) * 2 + 1] = ps[i].y;
      }
      head = (head + 1) % kTrail;
      guard++;
    }
    if (guard == 4) recordAcc = 0;
  }

  void render(const Frame& f, Canvas& c) const override {
    float amp = f.intensity;
    float s = std::min(f.width, f.height);
    float px = s / 400.0f;
    std::vector<float> u;
    u.reserve(20);
    u.insert(u.end(), {t, bass * amp, kick * amp, energy});
    u.insert(u.end(), {spin, f.glow, ringR, ringAmp * amp});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("vortex", {0, 0, f.width, f.height}, u);
    if (ps.empty()) return;
    auto alpha = [](float v) { return std::clamp(v, 0.0f, 1.0f); };
    for (int g = 0; g < 3; g++) {
      const Color& col = f.colors[1 + g];
      // Puntas casi blancas pero cálidas: el naranja no vira a amarillo.
      Color hot = {col.r + (1.0f - col.r) * 0.45f, col.g + (0.82f - col.g) * 0.45f,
                   col.b + (0.55f - col.b) * 0.45f, 1.0f};
      float gain = (0.8f + 1.0f * groups[g] + 0.6f * kick) * amp;
      Path tail, tip;
      std::vector<Vec2> heads;
      for (size_t i = 0; i < ps.size(); i++) {
        const Particle& p = ps[i];
        if (p.group != g) continue;
        tail.moveTo(p.x, p.y);
        tip.moveTo(p.x, p.y);
        for (int k = 1; k <= kTrail; k++) {
          int slot = (head - k + kTrail) % kTrail;
          float tx = trail[(i * kTrail + slot) * 2], ty = trail[(i * kTrail + slot) * 2 + 1];
          tail.lineTo(tx, ty);
          if (k <= 3) tip.lineTo(tx, ty);
        }
        heads.push_back({p.x, p.y});
      }
      Paint glow;
      glow.blend = Blend::plus;
      glow.strokeCap = 1;
      glow.strokeJoin = 1;
      glow.strokeWidth = 9.0f * px;
      glow.color = {col.r, col.g, col.b, alpha(0.06f * gain * f.glow)};
      c.path(tail, glow);
      Paint core = glow;
      core.strokeWidth = 2.0f * px;
      core.color = {col.r, col.g, col.b, alpha(0.42f * gain)};
      c.path(tail, core);
      Paint bright = glow;
      bright.strokeWidth = 3.2f * px;
      bright.color = {hot.r, hot.g, hot.b, alpha(0.5f * gain)};
      c.path(tip, bright);
      Paint dot;
      dot.blend = Blend::plus;
      float twinkle = 0.75f + 0.25f * std::sin(t * 9.0f + float(g) * 2.0f) * spark;
      dot.color = {hot.r, hot.g, hot.b, alpha((0.6f + 0.4f * groups[g] + 0.3f * kick) * twinkle)};
      c.points(heads, (2.4f + 1.6f * groups[g] * amp + 1.2f * kick * amp) * px, dot);
    }
  }
};
''';

const shaderSources = <String, String>{
  'vortex': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // tiempo, graves, golpe, energía
uniform vec4 uB;   // fase de giro, glow, radio y fuerza de la onda de choque
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
  float r = length(p) + 0.0005;
  float kick = uA.z;
  float bass = uA.y;

  // Humo en espiral: el ruido se retuerce con el logaritmo del radio y gira
  // con las estelas, así forma brazos que se hunden en el núcleo.
  float th = uB.x - 1.7 * log(r);
  vec2 q = mat2(cos(th), sin(th), -sin(th), cos(th)) * p;
  float smoke = fbm(q * 2.4 + vec2(uA.x * 0.05, 0.0));
  float arms = 0.55 + 0.45 * cos(atan(q.y, q.x) * 2.0);
  vec3 tint = mix(uC1, uC2, smoothstep(0.35, 0.75, smoke));
  float haze = smoothstep(0.42, 0.9, smoke) * arms * smoothstep(1.3, 0.15, r);
  vec3 col = uC0 + tint * haze * (0.06 + 0.10 * uA.w + 0.16 * kick + 0.08 * bass) * uB.y;

  // Núcleo incandescente que late con los graves.
  float core = (0.0012 + 0.003 * bass + 0.006 * kick) / (r * r + 0.0025);
  col += mix(uC2, uC3, 0.5) * core * uB.y;
  // Onda de choque que sale del núcleo con cada golpe.
  col += mix(uC2, uC3, 0.4) * uB.w * exp(-(r - uB.z) * (r - uB.z) * 700.0) * 0.9;

  col *= 1.0 - 0.4 * smoothstep(0.5, 1.3, length(p * vec2(0.9, 0.65)));
  // Compresión que conserva el tono: el naranja intenso no se vuelve amarillo.
  float peak = max(col.r, max(col.g, col.b));
  if (peak > 0.75) {
    float e = (peak - 0.75) / 0.25;
    col *= (0.75 + 0.25 * e / (1.0 + e)) / peak;
  }
  // Fondo transparente: el color va premultiplicado y la opacidad sale del
  // brillo, así la luz se compone sobre lo que haya debajo.
  col = clamp(col, 0.0, 1.0);
  float alpha = clamp(max(col.r, max(col.g, col.b)) * 1.25, 0.0, 1.0);
  fragColor = vec4(col, alpha);
}
""",
};
