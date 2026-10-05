// Kandinsky Sinestesia — pintar la música como Kandinsky.
// Kandinsky veía colores y formas al oír música, y pintaba así: círculos con
// halos, triángulos agudos, líneas negras que cruzan el lienzo, arcos,
// damero y puntos. Aquí la composición se pinta sola con la canción: los
// graves hacen nacer círculos, los medios triángulos y arcos, los agudos
// líneas y puntos. Cada forma aparece con un pequeño rebote, vive unos
// segundos y se retira, y un gran círculo late como el corazón del cuadro.
// Puede verse sobre el lienzo crema o sobre negro, como «Varios círculos».
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // FORMA: el vocabulario de formas.
  CreatorModifier.choice(
    'figuras',
    'Figuras',
    options: ['Mezcla', 'Círculos', 'Ángulos'],
  ),
  // MOVIMIENTO: cómo bailan las formas.
  CreatorModifier.choice(
    'danza',
    'Danza',
    options: ['Flotar', 'Girar', 'Saltar'],
  ),
  // MÚSICA
  CreatorModifier.choice(
    'pulso',
    'Pulso',
    options: ['Instrumentos', 'Golpes', 'Graves'],
  ),
  // ATMÓSFERA: los halos de color alrededor de los círculos.
  CreatorModifier.slider('halos', 'Halos', min: 0, max: 1, value: .5),
  // MODO: lienzo crema o fondo negro.
  CreatorModifier.toggle('noche', 'Fondo negro', value: false),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Varios Círculos', {
    'figuras': 'Círculos',
    'noche': true,
    'danza': 'Flotar',
    'halos': 1,
  }),
  CreatorVariation('Composición VIII', {
    'figuras': 'Ángulos',
    'noche': false,
    'pulso': 'Instrumentos',
    'danza': 'Girar',
  }),
];

const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kShapes = 48;
  // Formas: círculo, triángulo, línea, arco, damero y puntos.
  struct Shape { int type; float x, y, size, rot, spin; int colA, colB; double birth; float life, seed; };
  float bass = 0, body = 0, spark = 0, slowBass = 0;
  float kick = 0, flash = 0;
  // Relojes en doble precisión: sin música es idéntico a 30 y 60 FPS.
  double clock = 0, sinceIdle = 0;
  std::array<float, 3> credit{};
  std::array<Shape, kShapes> shapes{};
  int next = 0;
  uint32_t spawns = 0, idleCount = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }
  static float hashU(uint32_t x) {
    x ^= x >> 16; x *= 0x7feb352dU; x ^= x >> 15; x *= 0x846ca68bU; x ^= x >> 16;
    return float(x & 0xffffffu) / 16777216.0f;
  }
  static int capacity(float detail) { return std::clamp(int(std::lround(16.0f + 16.0f * detail)), 16, kShapes); }
  static float easeOutBack(float x) {
    const float c1 = 1.70158f, c3 = c1 + 1.0f;
    const float e = x - 1.0f;
    return 1.0f + c3 * e * e * e + c1 * e * e;
  }

  // Nace una forma: los graves dan círculos, los medios triángulos y arcos,
  // los agudos líneas y puntos.
  void spawn(int band, int vocab, double carry, int limit) {
    const uint32_t k = spawns++;
    const float h1 = hashU(k * 2654435761u + 1u), h2 = hashU(k * 2246822519u + 2u);
    const float h3 = hashU(k * 3266489917u + 3u), h4 = hashU(k * 668265263u + 4u);
    const float h5 = hashU(k * 374761393u + 5u), h6 = hashU(k * 1274126177u + 6u);
    int type;
    if (vocab == 1) {
      type = band == 0 ? 0 : (band == 1 ? 3 : 5);
      if (h4 < 0.3f) type = 0;
    } else if (vocab == 2) {
      type = band == 0 ? 1 : (band == 1 ? 4 : 2);
      if (h4 < 0.25f) type = 2;
    } else {
      const int byBand[3][2] = {{0, 0}, {1, 3}, {2, 5}};
      type = byBand[band][h4 < 0.5f ? 0 : 1];
      if (h5 < 0.12f) type = 4;
    }
    const int slot = next % limit;
    Shape& s = shapes[size_t(slot)];
    s.type = type;
    s.x = 0.1f + 0.8f * h1;
    s.y = 0.08f + 0.84f * h2;
    s.size = type == 0 ? 0.05f + 0.12f * h3 : (type == 2 ? 0.25f + 0.35f * h3 : 0.04f + 0.08f * h3);
    s.rot = h5 * 6.2831853f;
    s.spin = (h6 - 0.5f) * 0.6f;
    s.colA = 1 + int(h3 * 3.0f) % 3;
    s.colB = 1 + s.colA % 3;
    s.birth = clock - carry;
    s.life = 5.0f + 4.0f * h6;
    s.seed = h1;
    next = (slot + 1) % limit;
  }

 public:
  void reset(uint32_t seed) override {
    bass = body = spark = slowBass = kick = flash = 0;
    clock = 0;
    sinceIdle = 0;
    credit.fill(0.0f);
    for (auto& s : shapes) s = Shape{0, 0.5f, 0.5f, 0.0f, 0.0f, 0.0f, 1, 2, -1000.0, 0.0f, 0.0f};
    next = 0;
    spawns = seed * 11u;
    idleCount = 0;
    // El cuadro empieza ya pintado.
    for (int i = 0; i < 12; i++) spawn(i % 3, 0, 0.45 * double(12 - i), kShapes);
  }

  void update(const Frame& f) override {
    auto m = modifiers(f);
    const float dt = float(f.delta);
    const Music& mu = f.music;
    bass = follow(bass, mu.bass, 22.0f, 4.5f, dt);
    body = follow(body, mu.body, 12.0f, 3.0f, dt);
    spark = follow(spark, mu.spark, 30.0f, 7.0f, dt);
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
    clock += step;
    const int limit = capacity(f.detail);
    const float amp = f.intensity;
    // Instrumentos: cada banda de la música pinta su tipo de forma.
    if (m.pulso == 0 && mu.active) {
      credit[0] += bass * amp * dt * 2.5f;
      credit[1] += body * amp * dt * 2.5f;
      credit[2] += spark * amp * dt * 3.5f;
      for (int b = 0; b < 3; b++) {
        while (credit[size_t(b)] >= 1.0f) {
          credit[size_t(b)] -= 1.0f;
          spawn(b, m.figuras, 0.0, limit);
        }
      }
    }
    // Golpes: cada golpe lanza tres formas a la vez.
    if (m.pulso == 1 && fresh) {
      for (int b = 0; b < 3; b++) spawn(b, m.figuras, 0.0, limit);
    }
    // A su ritmo el cuadro sigue pintándose.
    const double period = mu.active ? 0.9 : 0.45;
    sinceIdle += step;
    while (sinceIdle >= period) {
      sinceIdle -= period;
      spawn(int(idleCount++ % 3u), m.figuras, sinceIdle, limit);
    }
  }

  void render(const Frame& f, Canvas& c) const override {
    auto g = glide(f);
    const auto& pal = f.colors;
    const float amp = f.intensity;
    const float W = f.width, H = f.height;
    const float side = std::min(W, H);
    const float px = side / 400.0f;
    const float night = std::clamp(g.noche, 0.0f, 1.0f);
    const float halo = std::clamp(g.halos, 0.0f, 1.0f);
    const Color& paper = pal[0];
    const Color dark{pal[3].r * 0.12f + 0.02f, pal[3].g * 0.12f + 0.02f, pal[3].b * 0.12f + 0.03f, 1.0f};
    auto mixc = [](const Color& a, const Color& b, float t) {
      return Color{a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1.0f};
    };
    const Color bg = mixc(paper, dark, night);
    // La tinta es casi negra sobre crema y crema sobre negro.
    const Color ink = mixc(dark, paper, night);
    c.rect({0, 0, W, H}, Paint::radial({W * 0.45f, H * 0.42f}, std::max(W, H) * 0.8f,
                                       {bg, mixc(bg, Color{0, 0, 0, 1}, 0.18f + 0.12f * halo)}));
    const float wGolpes = g.pulso.weight(1), wGraves = g.pulso.weight(2);
    const float throb = std::min(bass * amp, 1.0f) * (0.35f + 0.65f * wGraves);
    const Blend shapeBlend = night > 0.5f ? Blend::screen : Blend::sourceOver;
    // Las grandes líneas que cruzan el cuadro.
    for (int i = 0; i < 3; i++) {
      const float a = 0.35f + 1.05f * float(i) + 0.05f * float(std::sin(clock * 0.1 + double(i)));
      const float ox = W * (0.35f + 0.15f * float(i)), oy = H * (0.4f + 0.12f * float(i));
      const float L = std::max(W, H) * 1.2f;
      Path line;
      line.moveTo(ox - L * std::cos(a), oy - L * std::sin(a)).lineTo(ox + L * std::cos(a), oy + L * std::sin(a));
      Paint lp;
      lp.strokeWidth = (1.2f + 1.3f * float(i % 2)) * px;
      lp.color = ink.opacity(0.75f);
      c.path(line, lp);
    }
    // El gran círculo, corazón del cuadro, late con los graves.
    {
      const Vec2 sun{W * 0.3f, H * 0.25f};
      const float r = side * 0.17f * (1.0f + 0.15f * throb);
      if (halo > 0.01f) {
        Paint hp = Paint::radial(sun, r * 1.9f, {pal[1].opacity(std::clamp(0.45f * halo * f.glow, 0.0f, 1.0f)), pal[1].opacity(0.0f)});
        c.circle(sun, r * 1.9f, hp);
      }
      Paint fill;
      fill.color = mixc(dark, pal[3], 0.25f + 0.5f * night);
      c.circle(sun, r, fill);
      Path ring;
      ring.circle(sun, r * 0.72f);
      Paint rp;
      rp.strokeWidth = r * 0.12f;
      rp.color = pal[2];
      c.path(ring, rp);
      Paint core;
      core.color = pal[1];
      c.circle(sun, r * 0.3f * (1.0f + 0.2f * kick * amp * wGolpes), core);
    }
    const int limit = capacity(f.detail);
    const float wFlotar = g.danza.weight(0), wGirar = g.danza.weight(1), wSaltar = g.danza.weight(2);
    // De la más vieja a la más nueva, para que las nuevas queden encima.
    for (int n = 0; n < limit; n++) {
      const Shape& s = shapes[size_t((next + n) % limit)];
      const float age = float(clock - s.birth);
      if (age < 0.0f || age > s.life) continue;
      const float grow = easeOutBack(std::clamp(age / 0.35f, 0.0f, 1.0f));
      const float leave = std::clamp((s.life - age) / 0.8f, 0.0f, 1.0f);
      float k = grow * leave;
      if (k <= 0.01f) continue;
      if (s.type == 0) k *= 1.0f + 0.18f * throb;
      // Danza: flotar, girar alrededor del centro o saltar con los golpes.
      float x = s.x, y = s.y;
      x += wFlotar * 0.015f * std::sin(age * 0.7f + s.seed * 20.0f);
      y += wFlotar * 0.02f * std::sin(age * 0.5f + s.seed * 13.0f);
      if (wGirar > 0.001f) {
        const float a = wGirar * 0.22f * age * (s.seed < 0.5f ? 1.0f : -1.0f);
        const float dx = x - 0.5f, dy = (y - 0.5f) * H / W;
        x = 0.5f + dx * std::cos(a) - dy * std::sin(a);
        y = 0.5f + (dx * std::sin(a) + dy * std::cos(a)) * W / H;
      }
      y -= wSaltar * kick * amp * 0.05f * (0.5f + s.seed);
      const float rot = s.rot + s.spin * age * (1.0f + 3.0f * wGirar);
      const Vec2 at{x * W, y * H};
      const float r = s.size * side * k;
      const Color& ca = pal[size_t(s.colA)];
      const Color& cb = pal[size_t(s.colB)];
      Paint outline;
      outline.strokeWidth = 1.5f * px;
      outline.color = ink.opacity(0.85f * leave);
      switch (s.type) {
        case 0: {
          if (halo > 0.01f) {
            Paint hp = Paint::radial(at, r * 1.6f, {ca.opacity(std::clamp(0.35f * halo * f.glow * leave, 0.0f, 1.0f)), ca.opacity(0.0f)});
            c.circle(at, r * 1.6f, hp);
          }
          Paint fa;
          fa.blend = shapeBlend;
          fa.color = ca.opacity(0.92f * leave);
          c.circle(at, r, fa);
          Paint fb;
          fb.blend = shapeBlend;
          fb.color = cb.opacity(0.92f * leave);
          c.circle(at, r * 0.55f, fb);
          Path o;
          o.circle(at, r);
          c.path(o, outline);
          Paint dot;
          dot.color = ink.opacity(leave);
          c.circle(at, r * 0.12f, dot);
          break;
        }
        case 1: {
          Path tri;
          const float a0 = rot, a1 = rot + 2.2f, a2 = rot + 4.0f;
          tri.moveTo(at.x + r * 1.6f * std::cos(a0), at.y + r * 1.6f * std::sin(a0))
              .lineTo(at.x + r * std::cos(a1), at.y + r * std::sin(a1))
              .lineTo(at.x + r * std::cos(a2), at.y + r * std::sin(a2))
              .close();
          Paint fa;
          fa.blend = shapeBlend;
          fa.color = ca.opacity(0.9f * leave);
          c.path(tri, fa);
          c.path(tri, outline);
          break;
        }
        case 2: {
          const float draw = std::clamp(age / 0.5f, 0.0f, 1.0f);
          const float L = s.size * side * draw * leave;
          Path line;
          line.moveTo(at.x - L * std::cos(rot), at.y - L * std::sin(rot)).lineTo(at.x + L * std::cos(rot), at.y + L * std::sin(rot));
          Paint lp;
          lp.strokeWidth = (1.5f + 3.0f * s.seed) * px;
          lp.color = ink.opacity(0.9f * leave);
          c.path(line, lp);
          break;
        }
        case 3: {
          Path arc;
          for (int i = 0; i <= 18; i++) {
            const float a = rot + 3.14159265f * float(i) / 18.0f;
            const float ax = at.x + r * 1.4f * std::cos(a), ay = at.y + r * 1.4f * std::sin(a);
            if (i == 0) arc.moveTo(ax, ay); else arc.lineTo(ax, ay);
          }
          Paint ap;
          ap.strokeWidth = 4.0f * px;
          ap.strokeCap = 1;
          ap.color = ca.opacity(0.95f * leave);
          c.path(arc, ap);
          break;
        }
        case 4: {
          c.save();
          c.translate(at.x, at.y);
          c.rotate(rot);
          const float cell = r * 0.5f;
          Path light, darkCells;
          for (int i = 0; i < 3; i++) {
            for (int j = 0; j < 3; j++) {
              Rect rc{(float(i) - 1.5f) * cell, (float(j) - 1.5f) * cell, cell, cell};
              if ((i + j) % 2 == 0) light.rect(rc); else darkCells.rect(rc);
            }
          }
          Paint pl;
          pl.color = ca.opacity(0.9f * leave);
          c.path(light, pl);
          Paint pd;
          pd.color = ink.opacity(0.9f * leave);
          c.path(darkCells, pd);
          c.restore();
          break;
        }
        default: {
          for (int i = 0; i < 5; i++) {
            const float d = (float(i) - 2.0f) * r * 0.5f;
            Paint dp;
            dp.blend = shapeBlend;
            dp.color = (i % 2 == 0 ? ca : ink).opacity(0.9f * leave);
            c.circle({at.x + d * std::cos(rot), at.y + d * std::sin(rot)}, r * 0.18f, dp);
          }
          break;
        }
      }
    }
    if (flash > 0.01f) {
      Paint fl;
      fl.blend = Blend::screen;
      fl.color = pal[2].opacity(std::clamp(flash * 0.08f * amp, 0.0f, 1.0f));
      c.rect({0, 0, W, H}, fl);
    }
  }
};
''';
