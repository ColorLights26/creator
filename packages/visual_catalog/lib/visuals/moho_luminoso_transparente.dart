// Moho Luminoso Transparente — red de venas de luz que crece como un moho mucilaginoso.
// Versión overlay: mismo movimiento y reacción a la música sin fondo opaco.
// Miles de agentes dejan un rastro y siguen el rastro de los demás (el modelo
// Physarum): solos forman una red de venas que se ramifica y se reorganiza.
// Tres especies con sentidos distintos tejen redes superpuestas en rojo,
// ámbar y blanco cálido. Cada golpe suelta una explosión de filamentos desde
// el centro, los graves aceleran a los agentes y la energía engorda el rastro.
const nativeSource = r'''
class Visual final : public Scene {
  // La red avanza en pasos fijos de 1/30 s contados con el tiempo absoluto:
  // es idéntica a 30 y a 60 FPS y los agentes se dibujan interpolados.
  static constexpr double kHz = 30.0;
  static constexpr float kTau = 6.2831853f;
  // Cada agente guarda su dirección como vector: los giros y los sensores son
  // rotaciones fijas, así no hay trigonometría por agente en cada paso.
  struct Agent { float x, y, px, py, dx, dy; int species; };
  std::vector<Agent> agents;
  std::vector<float> trail, scratch;
  int gw = 0, gh = 0;
  float w = 0, h = 0;
  int64_t steps = -1;
  float frac = 0, pendingBurst = 0;
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  Random rng{61};

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  float sense(float x, float y) const {
    int ix = int(x), iy = int(y);
    // Fuera de la rejilla el rastro es negativo: los agentes se apartan del borde.
    if (x < 0 || y < 0 || ix >= gw || iy >= gh) return -1.0f;
    return trail[size_t(iy * gw + ix)];
  }

  static void rotate(float& x, float& y, float c, float s) {
    float nx = x * c - y * s;
    y = x * s + y * c;
    x = nx;
  }

  void step() {
    // Parámetros del modelo de Jeff Jones por especie: ángulo y distancia de
    // los sensores y giro.
    static const float sensorAngle[3] = {0.39f, 0.45f, 0.35f};
    static const float sensorDist[3] = {5.0f, 6.0f, 4.0f};
    static const float turnAngle[3] = {0.78f, 0.85f, 0.65f};
    float sc[3], ss[3], tc[3], ts[3];
    for (int k = 0; k < 3; k++) {
      sc[k] = std::cos(sensorAngle[k]);
      ss[k] = std::sin(sensorAngle[k]);
      tc[k] = std::cos(turnAngle[k]);
      ts[k] = std::sin(turnAngle[k]);
    }
    float speed = 0.8f + 0.8f * bass + 0.45f * drive;
    float deposit = 1.0f + 1.2f * energy;
    float burst = pendingBurst;
    pendingBurst = 0;
    float cx = float(gw) * 0.5f, cy = float(gh) * 0.5f;
    for (Agent& ag : agents) {
      ag.px = ag.x;
      ag.py = ag.y;
      // Una pequeña parte renace al azar en cada paso: la red nunca se
      // reduce a un solo hilo y sigue ramificándose.
      if (rng.unit() < 0.003f) {
        ag.x = ag.px = 1.0f + rng.unit() * float(gw - 2);
        ag.y = ag.py = 1.0f + rng.unit() * float(gh - 2);
      }
      if (burst > 0 && rng.unit() < 0.25f * burst) {
        // Estallido: el agente renace junto al centro mirando hacia fuera.
        float vx = rng.unit() - 0.5f, vy = rng.unit() - 0.5f;
        float l = std::sqrt(vx * vx + vy * vy) + 1e-4f;
        ag.dx = vx / l;
        ag.dy = vy / l;
        ag.x = ag.px = cx + ag.dx * 2.0f;
        ag.y = ag.py = cy + ag.dy * 2.0f;
      }
      int s = ag.species;
      float sd = sensorDist[s];
      float lx = ag.dx, ly = ag.dy, rx = ag.dx, ry = ag.dy;
      rotate(lx, ly, sc[s], ss[s]);
      rotate(rx, ry, sc[s], -ss[s]);
      float f = sense(ag.x + ag.dx * sd, ag.y + ag.dy * sd);
      float l = sense(ag.x + lx * sd, ag.y + ly * sd);
      float r = sense(ag.x + rx * sd, ag.y + ry * sd);
      if (f >= l && f >= r) {
      } else if (f < l && f < r) {
        rotate(ag.dx, ag.dy, tc[s], rng.unit() < 0.5f ? ts[s] : -ts[s]);
      } else if (l > r) {
        rotate(ag.dx, ag.dy, tc[s], ts[s]);
      } else {
        rotate(ag.dx, ag.dy, tc[s], -ts[s]);
      }
      ag.x += ag.dx * speed;
      ag.y += ag.dy * speed;
      if (ag.x < 1.0f || ag.x > float(gw) - 1.01f) {
        ag.x = std::clamp(ag.x, 1.0f, float(gw) - 1.01f);
        ag.dx = -ag.dx;
      }
      if (ag.y < 1.0f || ag.y > float(gh) - 1.01f) {
        ag.y = std::clamp(ag.y, 1.0f, float(gh) - 1.01f);
        ag.dy = -ag.dy;
      }
      trail[size_t(int(ag.y) * gw + int(ag.x))] += deposit;
    }
    // Difusión y evaporación del rastro (media 3 x 3 y pérdida del 10 %), con
    // un tope bajo para que ningún hilo acapare a todos los agentes.
    for (int y = 0; y < gh; y++) {
      int y0 = std::max(0, y - 1), y1 = std::min(gh - 1, y + 1);
      for (int x = 0; x < gw; x++) {
        int x0 = std::max(0, x - 1), x1 = std::min(gw - 1, x + 1);
        float sum = 0;
        for (int yy = y0; yy <= y1; yy++)
          for (int xx = x0; xx <= x1; xx++) sum += trail[size_t(yy * gw + xx)];
        float n = float((y1 - y0 + 1) * (x1 - x0 + 1));
        scratch[size_t(y * gw + x)] = std::min(sum / n * 0.9f, 2.0f);
      }
    }
    trail.swap(scratch);
  }

 public:
  void reset(uint32_t seed) override {
    rng = Random(seed);
    agents.clear();
    trail.clear();
    scratch.clear();
    gw = gh = 0;
    w = h = 0;
    steps = -1;
    frac = pendingBurst = 0;
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
  }

  void update(const Frame& f) override {
    float dt = float(f.delta);
    if (f.width != w || f.height != h || agents.empty()) {
      w = f.width;
      h = f.height;
      gw = int(90.0f + 30.0f * std::clamp(f.detail, 0.25f, 2.0f));
      gh = std::max(16, int(float(gw) * h / std::max(1.0f, w)));
      trail.assign(size_t(gw * gh), 0.0f);
      scratch.assign(size_t(gw * gh), 0.0f);
      int count = int(float(gw * gh) * 0.3f);
      agents.resize(size_t(count));
      for (int i = 0; i < count; i++) {
        Agent& ag = agents[size_t(i)];
        ag.x = ag.px = 1.0f + rng.unit() * float(gw - 2);
        ag.y = ag.py = 1.0f + rng.unit() * float(gh - 2);
        float a = rng.unit() * kTau;
        ag.dx = std::cos(a);
        ag.dy = std::sin(a);
        ag.species = i % 3;
      }
      // Arranque con la red ya formada.
      for (int k = 0; k < 60; k++) step();
      for (Agent& ag : agents) {
        ag.px = ag.x;
        ag.py = ag.y;
      }
    }
    const Music& m = f.music;
    bass = follow(bass, m.bass, 22.0f, 4.5f, dt);
    body = follow(body, m.body, 12.0f, 3.0f, dt);
    spark = follow(spark, m.spark, 30.0f, 7.0f, dt);
    energy = follow(energy, m.energy, 6.0f, 1.8f, dt);
    drive = follow(drive, m.active ? std::pow(std::clamp(m.energy, 0.0f, 1.0f), 0.8f) : 0.0f, 3.0f, 0.7f, dt);

    float hit = 0, fl = 0;
    for (const auto& e : m.events[0]) hit = std::max(hit, e.strength);
    for (const auto& e : m.events[2]) hit = std::max(hit, e.strength * 0.85f);
    for (const auto& e : m.events[3]) fl = std::max(fl, e.strength);
    float onset = std::clamp((m.bass - slowBass - 0.15f) * 2.5f, 0.0f, 1.0f);
    slowBass = follow(slowBass, m.bass, 3.0f, 3.0f, dt);
    hit = std::min(std::max(hit, onset), 1.0f);
    if (hit > kick + 0.2f) pendingBurst = std::max(pendingBurst, hit);
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));

    int64_t target = int64_t(std::floor(f.time * kHz + 1e-6));
    if (steps < 0 || target < steps || target - steps > 8) steps = target - 1;
    while (steps < target) {
      step();
      steps++;
    }
    frac = std::clamp(float(f.time * kHz - double(steps)), 0.0f, 1.0f);
  }

  void render(const Frame& f, Canvas& c) const override {
    float amp = f.intensity;
    std::vector<float> u;
    u.reserve(20);
    u.insert(u.end(), {bass * amp, kick * amp, energy, f.glow});
    u.insert(u.end(), {spark * amp, flash * amp, 0.0f, 0.0f});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("moho_dark", {0, 0, f.width, f.height}, u);
    if (agents.empty()) return;
    float sx = f.width / float(gw), sy = f.height / float(gh);
    std::array<std::vector<Vec2>, 3> groups;
    for (auto& g : groups) g.reserve(agents.size() / 3 + 1);
    for (const Agent& ag : agents) {
      float x = ag.px + (ag.x - ag.px) * frac, y = ag.py + (ag.y - ag.py) * frac;
      groups[size_t(ag.species)].push_back({x * sx, y * sy});
    }
    float px = std::min(f.width, f.height) / 400.0f;
    float gain = std::clamp((0.85f + 0.5f * bass + 0.6f * kick) * amp, 0.0f, 1.6f);
    for (int g = 0; g < 3; g++) {
      const Color& col = f.colors[1 + g];
      Paint halo;
      halo.blend = Blend::plus;
      halo.color = {col.r, col.g, col.b, std::clamp(0.03f * gain * f.glow, 0.0f, 1.0f)};
      c.points(groups[size_t(g)], 3.5f * px, halo);
      Paint core;
      core.blend = Blend::plus;
      core.color = {col.r, col.g, col.b, std::clamp((g == 2 ? 0.16f : 0.24f) * gain, 0.0f, 1.0f)};
      c.points(groups[size_t(g)], (0.9f + 0.4f * spark * amp) * px, core);
    }
  }
};
''';

const shaderSources = <String, String>{
  'moho_dark': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // graves, golpe, energía, glow
uniform vec4 uB;   // agudos, destello
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
  // Penumbra rojiza y fogonazo del estallido en el centro.
  vec3 col = uC0 + uC1 * exp(-dot(p, p) * 2.0) * (0.03 + 0.03 * uA.x + 0.12 * uA.y) * uA.w;
  col *= 1.0 - 0.45 * smoothstep(0.5, 1.4, length(p * vec2(0.9, 0.65)));
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
