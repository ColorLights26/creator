// Espiral de Dominós — una cadena de fichas que cae vista desde arriba.
// Cientos de fichas de colores colocadas en espiral, en tres espirales que
// se enroscan o en anillos concéntricos. Una ola las tumba una tras otra:
// desde arriba, una ficha en pie es una raya fina y, al caer, se convierte
// en un rectángulo de color, así la ola va pintando el dibujo de arcoíris.
// Cuando cae la última, la cadena se rebobina y todas se levantan de nuevo
// para el siguiente dibujo. La energía acelera la ola, cada golpe le da un
// empujón y los graves avivan los colores.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.choice('patron', 'Dibujo', options: ['Auto', 'Espiral', 'Triple espiral', 'Anillos']),
  CreatorModifier.slider('velocidad', 'Velocidad', min: .3, max: 2.5, value: 1),
  CreatorModifier.choice('colores', 'Colores', options: ['Arcoíris', 'Fuego', 'Paleta']),
  CreatorModifier.toggle('sombra', 'Sombras', value: true),
];

const nativeSource = r'''
class Visual final : public Scene {
  struct Domino { float x, y, dx, dy, hue; int chain, index; };
  struct Chain { float delay; int count; };
  enum Phase { kTopple, kHold, kRise, kRest };
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double g = 0, phaseTime = 0, total = 1;
  int phase = kTopple, pattern = -1, autoPattern = 0;
  float aspect = 2.0f;
  std::vector<Domino> dominoes;
  std::vector<Chain> chains;

  static constexpr float kSpacing = 0.03f;
  static constexpr float kSpeed = 70.0f;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  void addSpiral(float rOut, float rIn, float turns, float offset, float delay) {
    int chain = int(chains.size());
    float b = (rOut - rIn) / (turns * 6.2831853f);
    float theta = 0;
    int idx = 0;
    while (true) {
      float r = rOut - b * theta;
      if (r < rIn) break;
      float a = theta + offset;
      float x = r * std::cos(a), y = r * std::sin(a);
      // Dirección de avance: tangente de la espiral hacia dentro.
      float tx = -b * std::cos(a) - r * std::sin(a), ty = -b * std::sin(a) + r * std::cos(a);
      float tl = std::sqrt(tx * tx + ty * ty) + 1e-6f;
      dominoes.push_back({x, y, tx / tl, ty / tl, 0.0f, chain, idx++});
      theta += kSpacing / std::max(r, 0.02f);
    }
    chains.push_back({delay, idx});
  }

  void addRing(float r, float delay) {
    // Dos medias vueltas que salen del mismo punto en sentidos opuestos.
    for (int side = 0; side < 2; side++) {
      int chain = int(chains.size());
      int count = int(3.14159265f * r / kSpacing);
      for (int i = 0; i < count; i++) {
        float a = -1.5707963f + (side == 0 ? 1.0f : -1.0f) * float(i) / float(count) * 3.14159265f;
        float x = r * std::cos(a), y = r * std::sin(a);
        float s = side == 0 ? 1.0f : -1.0f;
        dominoes.push_back({x, y, -std::sin(a) * s, std::cos(a) * s, 0.0f, chain, i});
      }
      chains.push_back({delay, count});
    }
  }

  void build(int which) {
    pattern = which;
    dominoes.clear();
    chains.clear();
    float rOut = 0.46f;
    if (which == 0) {
      addSpiral(rOut, 0.05f, 5.0f, 0.0f, 0.0f);
    } else if (which == 1) {
      for (int k = 0; k < 3; k++) addSpiral(rOut, 0.07f, 1.8f, 6.2831853f * float(k) / 3.0f, 0.0f);
    } else {
      for (int k = 0; k < 7; k++) addRing(0.06f + 0.065f * float(k), 0.35f * float(k));
    }
    // Color a lo largo del recorrido de cada cadena.
    for (auto& d : dominoes) {
      const Chain& ch = chains[size_t(d.chain)];
      d.hue = (float(d.index) / float(std::max(ch.count - 1, 1)) + float(d.chain % 3) * 0.04f);
    }
    total = 0;
    for (const auto& ch : chains) total = std::max(total, double(ch.delay) + double(ch.count) / double(kSpeed));
    total += 0.4;
  }

 public:
  void reset(uint32_t seed) override {
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    g = 0;
    phaseTime = 0;
    phase = kTopple;
    pattern = -1;
    autoPattern = int(seed % 3u);
    dominoes.reserve(4000);
    chains.reserve(32);
  }

  void update(const Frame& f) override {
    auto m = modifiers(f);
    float dt = float(f.delta);
    const Music& mu = f.music;
    bass = follow(bass, mu.bass, 22.0f, 4.5f, dt);
    body = follow(body, mu.body, 12.0f, 3.0f, dt);
    spark = follow(spark, mu.spark, 30.0f, 7.0f, dt);
    energy = follow(energy, mu.energy, 6.0f, 1.8f, dt);
    drive = follow(drive, mu.active ? std::pow(std::clamp(mu.energy, 0.0f, 1.0f), 0.8f) : 0.0f, 3.0f, 0.7f, dt);

    float hit = 0, fl = 0;
    for (const auto& e : mu.events[0]) hit = std::max(hit, e.strength);
    for (const auto& e : mu.events[2]) hit = std::max(hit, e.strength * 0.85f);
    for (const auto& e : mu.events[3]) fl = std::max(fl, e.strength);
    float onset = std::clamp((mu.bass - slowBass - 0.15f) * 2.5f, 0.0f, 1.0f);
    slowBass = follow(slowBass, mu.bass, 3.0f, 3.0f, dt);
    hit = std::min(std::max(hit, onset), 1.0f);
    bool beat = hit > kick + 0.2f;
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    aspect = f.height / std::max(std::min(f.width, f.height), 1.0f);

    int wanted = m.patron == 0 ? autoPattern : m.patron - 1;
    if (wanted != pattern) {
      build(wanted);
      g = 0;
      phase = kTopple;
      phaseTime = 0;
    }
    double rate = f.delta * f.speed * m.velocidad * (1.0 + 1.2 * drive) + (beat && phase == kTopple ? 0.08 * double(hit) : 0.0);
    phaseTime += rate;
    for (int guard = 0; guard < 4; guard++) {
      if (phase == kTopple) {
        g = std::min(phaseTime, total);
        if (phaseTime < total) break;
        phaseTime -= total;
        phase = kHold;
      } else if (phase == kHold) {
        if (phaseTime < 1.2) break;
        phaseTime -= 1.2;
        phase = kRise;
      } else if (phase == kRise) {
        // Se rebobina al doble de velocidad.
        g = std::max(0.0, total - phaseTime * 2.0);
        if (g > 0.0) break;
        phaseTime -= total / 2.0;
        phase = kRest;
      } else {
        if (phaseTime < 0.8) break;
        phaseTime -= 0.8;
        phase = kTopple;
        g = 0;
        if (m.patron == 0) {
          autoPattern = (autoPattern + 1) % 3;
          build(autoPattern);
        }
      }
    }
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    float amp = f.intensity;
    const Color& bg = f.colors[0];
    c.rect({0, 0, f.width, f.height}, Paint::radial({f.width * 0.5f, f.height * 0.5f}, std::max(f.width, f.height) * 0.7f,
                                                   {Color{std::min(1.0f, bg.r + 0.06f), std::min(1.0f, bg.g + 0.05f), std::min(1.0f, bg.b + 0.07f), 1.0f},
                                                    Color{bg.r, bg.g, bg.b, 1.0f}}));
    float side = std::min(f.width, f.height) * 1.0f;
    float px = side / 400.0f;
    Vec2 center{f.width * 0.5f, f.height * 0.5f};
    const float L = 0.024f, T = 0.006f, W = 0.02f;
    const int buckets = 12;
    std::array<Path, buckets> fallen, standing;
    Path shadow;
    for (const auto& d : dominoes) {
      const Chain& ch = chains[size_t(d.chain)];
      float front = float((g - double(ch.delay)) * double(kSpeed));
      float tilt = std::clamp((front - float(d.index)) / 2.5f, 0.0f, 1.0f);
      float s = std::sin(tilt * 1.5707963f * 0.92f);
      float len = T + (L - T) * s;
      float bx = d.x - d.dx * T * 0.5f, by = d.y - d.dy * T * 0.5f;
      float ex = bx + d.dx * len, ey = by + d.dy * len;
      float nx = -d.dy * W * 0.5f, ny = d.dx * W * 0.5f;
      auto P = [&](float x, float y) { return Vec2{center.x + x * side, center.y + y * side}; };
      Vec2 p0 = P(bx + nx, by + ny), p1 = P(ex + nx, ey + ny), p2 = P(ex - nx, ey - ny), p3 = P(bx - nx, by - ny);
      int b = std::min(buckets - 1, int(d.hue * float(buckets)));
      Path& dst = tilt > 0.5f ? fallen[size_t(b)] : standing[size_t(b)];
      dst.moveTo(p0.x, p0.y).lineTo(p1.x, p1.y).lineTo(p2.x, p2.y).lineTo(p3.x, p3.y).close();
      if (m.sombra) {
        float o = (1.0f + 2.5f * (1.0f - s)) * px;
        shadow.moveTo(p0.x + o, p0.y + o * 1.4f).lineTo(p1.x + o, p1.y + o * 1.4f).lineTo(p2.x + o, p2.y + o * 1.4f).lineTo(p3.x + o, p3.y + o * 1.4f).close();
      }
    }
    if (m.sombra) {
      Paint sp;
      sp.color = Color{0, 0, 0, 0.45f};
      c.path(shadow, sp);
    }
    for (int b = 0; b < buckets; b++) {
      float t = (float(b) + 0.5f) / float(buckets);
      Color col;
      if (m.colores == 1) {
        const Color& a = f.colors[1];
        const Color& e = f.colors[3];
        col = Color{a.r + (e.r - a.r) * t, a.g + (e.g - a.g) * t, a.b + (e.b - a.b) * t, 1.0f};
      } else if (m.colores == 2) {
        std::array<Color, 3> pal = {f.colors[1], f.colors[2], f.colors[3]};
        col = pal[size_t(b % 3)];
      } else {
        float h = t * 0.85f;
        col = Color{std::clamp(std::fabs(h * 6.0f - 3.0f) - 1.0f, 0.0f, 1.0f), std::clamp(2.0f - std::fabs(h * 6.0f - 2.0f), 0.0f, 1.0f),
                    std::clamp(2.0f - std::fabs(h * 6.0f - 4.0f), 0.0f, 1.0f), 1.0f};
      }
      float lit = (0.85f + 0.25f * bass + 0.2f * kick) * amp;
      Paint fp;
      fp.color = Color{std::min(1.0f, col.r * lit), std::min(1.0f, col.g * lit), std::min(1.0f, col.b * lit), 1.0f};
      c.path(fallen[size_t(b)], fp);
      Paint sp;
      sp.color = Color{std::min(1.0f, col.r * 0.6f + 0.35f), std::min(1.0f, col.g * 0.6f + 0.35f), std::min(1.0f, col.b * 0.6f + 0.35f), 1.0f};
      c.path(standing[size_t(b)], sp);
    }
    (void)aspect;
    if (flash > 0.01f) {
      Paint fl;
      fl.blend = Blend::plus;
      fl.color = f.colors[2].opacity(std::clamp(flash * 0.05f * amp, 0.0f, 1.0f));
      c.rect({0, 0, f.width, f.height}, fl);
    }
  }
};
''';
