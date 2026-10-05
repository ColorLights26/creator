// Espiral de Dominós Transparente — una cadena de fichas que cae vista desde arriba.
// Versión overlay: mismo movimiento y reacción a la música sin fondo opaco.
// Cientos de fichas de colores colocadas en espiral, en tres espirales que
// se enroscan o en anillos concéntricos. Una ola las tumba una tras otra:
// desde arriba, una ficha en pie es una raya fina y, al caer, se convierte
// en un rectángulo de color, así la ola va pintando el dibujo de arcoíris.
// Cuando cae la última, la cadena se rebobina y todas se levantan de nuevo
// para el siguiente dibujo. Recorrido decide por dónde empieza la ola: desde
// el principio de cada cadena, al revés o desde los dos extremos a la vez
// hasta encontrarse. Estela de luz deja encendida sólo la cabeza de la ola y
// apaga poco a poco las fichas que cayeron antes, como un cometa que recorre
// el dibujo. El arcoíris empieza en el tono del primer acento de la paleta.
// La energía acelera la ola, cada golpe le da un empujón y los graves avivan
// los colores.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.choice('patron', 'Dibujo', options: ['Auto', 'Espiral', 'Triple espiral', 'Anillos']),
  // MOVIMIENTO: el camino de la ola por cada cadena.
  CreatorModifier.choice('recorrido', 'Recorrido', options: ['Directo', 'Al revés', 'Dos frentes']),
  // ATMÓSFERA: de todo el dibujo encendido a un cometa que lo recorre.
  CreatorModifier.slider('estela', 'Estela de luz', min: 0, max: 1, value: 0),
  CreatorModifier.toggle('sombra', 'Sombras', value: true),
];

const nativeSource = r'''
class Visual final : public Scene {
  // mix reparte las fichas entre dos recorridos mientras uno se funde en otro.
  struct Domino { float x, y, dx, dy, hue, mix; int chain, index; };
  struct Chain { float delay; int count; };
  enum Phase { kTopple, kHold, kRise, kRest };
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double g = 0, phaseTime = 0, total = 1;
  // Duración de la caída con cada recorrido (directo, al revés, dos frentes).
  std::array<double, 3> totals{1, 1, 1};
  float maxDelay = 0;
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
      dominoes.push_back({x, y, tx / tl, ty / tl, 0.0f, 0.0f, chain, idx++});
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
        dominoes.push_back({x, y, -std::sin(a) * s, std::cos(a) * s, 0.0f, 0.0f, chain, i});
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
      uint32_t h = uint32_t(d.chain) * 2654435761u ^ uint32_t(d.index) * 2246822519u;
      h ^= h >> 15;
      h *= 2654435761u;
      d.mix = float(h >> 8) / 16777216.0f;
    }
    maxDelay = 0;
    for (const auto& ch : chains) maxDelay = std::max(maxDelay, ch.delay);
    totals = {0, 0, 0};
    for (const auto& ch : chains) {
      double run = double(ch.count) / double(kSpeed), half = double((ch.count + 1) / 2) / double(kSpeed);
      totals[0] = std::max(totals[0], double(ch.delay) + run);
      totals[1] = std::max(totals[1], double(maxDelay - ch.delay) + run);
      totals[2] = std::max(totals[2], double(ch.delay) + half);
    }
    for (auto& t : totals) t += 0.4;
    total = totals[0];
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
    total = totals[size_t(std::clamp(m.recorrido, 0, 2))];
    double rate = f.delta * f.speed * (1.0 + 1.2 * drive) + (beat && phase == kTopple ? 0.08 * double(hit) : 0.0);
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
    auto gl = glide(f);
    float amp = f.intensity;
    float side = std::min(f.width, f.height) * 1.0f;
    float px = side / 400.0f;
    Vec2 center{f.width * 0.5f, f.height * 0.5f};
    const float L = 0.024f, T = 0.006f, W = 0.02f;
    const int buckets = 12, levels = 5;
    std::array<Path, buckets * levels> fallen;
    std::array<Path, buckets> standing;
    // Halo de las fichas recién caídas (sólo con Estela de luz).
    const int haloLevels = 3;
    std::array<std::vector<Vec2>, buckets * haloLevels> halos;
    // La ficha que está cayendo en cada frente lleva la luz: su color y lugar.
    std::vector<std::pair<Vec2, int>> heads;
    Path shadow;
    // Recorrido: mientras uno se funde en otro, cada ficha sigue uno de los dos.
    const float wDirect = gl.recorrido.weight(0), wReverse = gl.recorrido.weight(1);
    const float estela = std::clamp(gl.estela, 0.0f, 1.0f);
    for (const auto& d : dominoes) {
      const Chain& ch = chains[size_t(d.chain)];
      const int way = d.mix < wDirect ? 0 : (d.mix < wDirect + wReverse ? 1 : 2);
      const float delay = way == 1 ? maxDelay - ch.delay : ch.delay;
      const int back = ch.count - 1 - d.index;
      // Puesto de la ficha en su ola y hacia dónde cae (la ola la empuja).
      const bool forward = way == 0 || (way == 2 && d.index <= back);
      const float pos = float(forward ? d.index : back), dir = forward ? 1.0f : -1.0f;
      float front = float((g - double(delay)) * double(kSpeed));
      float tilt = std::clamp((front - pos) / 2.5f, 0.0f, 1.0f);
      float s = std::sin(tilt * 1.5707963f * 0.92f);
      float len = T + (L - T) * s;
      float bx = d.x - dir * d.dx * T * 0.5f, by = d.y - dir * d.dy * T * 0.5f;
      float ex = bx + dir * d.dx * len, ey = by + dir * d.dy * len;
      float nx = -d.dy * W * 0.5f, ny = d.dx * W * 0.5f;
      auto P = [&](float x, float y) { return Vec2{center.x + x * side, center.y + y * side}; };
      Vec2 p0 = P(bx + nx, by + ny), p1 = P(ex + nx, ey + ny), p2 = P(ex - nx, ey - ny), p3 = P(bx - nx, by - ny);
      int b = std::min(buckets - 1, int(d.hue * float(buckets)));
      // Estela de luz: cuanto más lejos quedó la ola, más se apaga la ficha;
      // las recién caídas brillan con un halo de su color.
      float age = std::clamp((front - pos - 3.0f) / 30.0f, 0.0f, 1.0f);
      int level = std::clamp(int(std::lround(age * float(levels - 1))), 0, levels - 1);
      Path& dst = tilt > 0.5f ? fallen[size_t(b * levels + level)] : standing[size_t(b)];
      if (estela > 0.001f && tilt > 0.5f && level < haloLevels)
        halos[size_t(b * haloLevels + level)].push_back(P((bx + ex) * 0.5f, (by + ey) * 0.5f));
      if (estela > 0.001f && tilt > 0.4f && tilt <= 0.8f && heads.size() < 64) heads.push_back({P(d.x, d.y), b});
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
    // El arcoíris empieza en el tono del primer acento de la paleta.
    const Color& accent = f.colors[1];
    float hi = std::max(accent.r, std::max(accent.g, accent.b)), lo = std::min(accent.r, std::min(accent.g, accent.b));
    float spread = hi - lo, baseHue = 0.0f;
    if (spread > 1e-4f) {
      baseHue = hi == accent.r ? (accent.g - accent.b) / spread
                               : (hi == accent.g ? 2.0f + (accent.b - accent.r) / spread : 4.0f + (accent.r - accent.g) / spread);
      baseHue /= 6.0f;
    }
    std::array<Color, buckets> hues;
    for (int b = 0; b < buckets; b++) {
      float h = baseHue + (float(b) + 0.5f) / float(buckets) * 0.85f;
      h -= std::floor(h);
      hues[size_t(b)] = Color{std::clamp(std::fabs(h * 6.0f - 3.0f) - 1.0f, 0.0f, 1.0f), std::clamp(2.0f - std::fabs(h * 6.0f - 2.0f), 0.0f, 1.0f),
                              std::clamp(2.0f - std::fabs(h * 6.0f - 4.0f), 0.0f, 1.0f), 1.0f};
    }
    if (estela > 0.001f) {
      const float shine = estela * (0.5f + 0.5f * std::clamp(f.glow, 0.0f, 2.0f));
      // Cada frente lleva una luz que alumbra el suelo a su alrededor.
      for (const auto& [spot, b] : heads) {
        Paint pool = Paint::radial(spot, side * 0.17f,
                                   {hues[size_t(b)].opacity(std::clamp(0.2f * shine, 0.0f, 1.0f)), hues[size_t(b)].opacity(0.0f)});
        pool.blend = Blend::plus;
        c.circle(spot, side * 0.17f, pool);
      }
      // Dos discos por ficha (ancho y tenue, estrecho y más vivo): un halo suave.
      for (int b = 0; b < buckets; b++) {
        for (int level = 0; level < haloLevels; level++) {
          const auto& spots = halos[size_t(b * haloLevels + level)];
          if (spots.empty()) continue;
          float fresh = 1.0f - float(level) / float(haloLevels);
          Paint hp;
          hp.blend = Blend::plus;
          hp.color = hues[size_t(b)].opacity(std::clamp(0.10f * shine * fresh, 0.0f, 1.0f));
          c.points(spots, 20.0f * px, hp);
          hp.color = hues[size_t(b)].opacity(std::clamp(0.16f * shine * fresh, 0.0f, 1.0f));
          c.points(spots, 10.0f * px, hp);
        }
      }
    }
    for (int b = 0; b < buckets; b++) {
      const Color& col = hues[size_t(b)];
      float lit = (0.85f + 0.25f * bass + 0.2f * kick) * amp;
      for (int level = 0; level < levels; level++) {
        const Path& path = fallen[size_t(b * levels + level)];
        if (path.data().empty()) continue;
        float dim = lit * (1.0f - 0.78f * estela * float(level) / float(levels - 1));
        Paint fp;
        fp.color = Color{std::clamp(col.r * dim, 0.0f, 1.0f), std::clamp(col.g * dim, 0.0f, 1.0f), std::clamp(col.b * dim, 0.0f, 1.0f), 1.0f};
        c.path(path, fp);
      }
      // Con Estela de luz la sala se oscurece: las fichas en pie se apagan un poco.
      const float shade = 1.0f - 0.45f * estela;
      Paint sp;
      sp.color = Color{std::clamp((col.r * 0.6f + 0.35f) * shade, 0.0f, 1.0f), std::clamp((col.g * 0.6f + 0.35f) * shade, 0.0f, 1.0f),
                       std::clamp((col.b * 0.6f + 0.35f) * shade, 0.0f, 1.0f), 1.0f};
      c.path(standing[size_t(b)], sp);
    }
    (void)aspect;
  }
};
''';
