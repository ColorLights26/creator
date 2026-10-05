// Art Déco — el lujo dorado de los años veinte, al ritmo de la música.
// Líneas de oro sobre negro como en un cartel de Gatsby o la corona del
// edificio Chrysler: un sol de rayos con arcos escalonados, un mosaico de
// abanicos que se abren y se cierran, o una torre de arcos con ventanas en
// forma de rayo. Todo dentro de un marco con esquinas escalonadas. Los
// golpes disparan los rayos y abren los abanicos, los graves hacen respirar
// el ornamento y los agudos hacen correr destellos por las líneas de oro.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // FORMA: el motivo del ornamento.
  CreatorModifier.choice(
    'motivo',
    'Motivo',
    options: ['Sol', 'Abanicos', 'Torre'],
  ),
  // MOVIMIENTO: suave y majestuoso o a saltos, como un mecanismo.
  CreatorModifier.choice(
    'ritmo',
    'Carácter',
    options: ['Majestuoso', 'Mecánico'],
  ),
  // MÚSICA
  CreatorModifier.choice(
    'pulso',
    'Pulso',
    options: ['Golpes', 'Graves', 'Destellos'],
  ),
  // ATMÓSFERA: el brillo del oro que recorre las líneas.
  CreatorModifier.slider('lujo', 'Brillo del oro', min: 0, max: 1, value: .5),
  // MODO: sólo líneas de oro o paneles rellenos de carmesí.
  CreatorModifier.toggle('relleno', 'Paneles rellenos', value: true),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Gatsby', {
    'motivo': 'Abanicos',
    'relleno': true,
    'lujo': 1,
  }),
  CreatorVariation('Rascacielos', {
    'motivo': 'Torre',
    'ritmo': 'Mecánico',
    'relleno': false,
    'pulso': 'Destellos',
  }),
];

const nativeSource = r'''
class Visual final : public Scene {
  float bass = 0, spark = 0, slowBass = 0;
  float kick = 0, flash = 0;
  // Reloj en doble precisión: sin música es idéntico a 30 y 60 FPS.
  double clock = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }
  static float hashU(uint32_t x) {
    x ^= x >> 16; x *= 0x7feb352dU; x ^= x >> 15; x *= 0x846ca68bU; x ^= x >> 16;
    return float(x & 0xffffffu) / 16777216.0f;
  }
  static void arc(Path& p, Vec2 c, float r, float a0, float a1, int segments, bool move) {
    for (int i = 0; i <= segments; i++) {
      const float a = a0 + (a1 - a0) * float(i) / float(segments);
      const float x = c.x + r * std::cos(a), y = c.y + r * std::sin(a);
      if (i == 0 && move) p.moveTo(x, y); else p.lineTo(x, y);
    }
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = spark = slowBass = kick = flash = 0;
    clock = double(rng.unit()) * 20.0;
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
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    clock += f.delta * f.speed;
  }

  void render(const Frame& f, Canvas& c) const override {
    auto g = glide(f);
    const auto& pal = f.colors;
    const float amp = f.intensity;
    const float W = f.width, H = f.height;
    const float side = std::min(W, H);
    const float px = side / 400.0f;
    // Carácter: el tiempo corre suave o avanza a saltos de mecanismo.
    const double tt = clock;
    const double tq = (std::floor(tt * 1.5) + double(std::clamp(float((tt * 1.5 - std::floor(tt * 1.5) - 0.75) / 0.25), 0.0f, 1.0f))) / 1.5;
    const float at = float(g.ritmo.weight(0) * tt + g.ritmo.weight(1) * tq);
    const float wGolpes = g.pulso.weight(0), wGraves = g.pulso.weight(1), wDest = g.pulso.weight(2);
    const float punch = std::min(kick * amp, 1.0f) * wGolpes;
    const float breath = 1.0f + 0.08f * std::min(bass * amp, 1.0f) * wGraves;
    const float lujo = std::clamp(g.lujo, 0.0f, 1.0f);
    const float fill = std::clamp(g.relleno, 0.0f, 1.0f);
    const Color& bg = pal[0];
    c.rect({0, 0, W, H}, Paint::radial({W * 0.5f, H * 0.55f}, std::max(W, H) * 0.8f,
                                       {Color{std::min(1.0f, bg.r + pal[1].r * 0.08f), std::min(1.0f, bg.g + pal[1].g * 0.05f), std::min(1.0f, bg.b + pal[1].b * 0.05f), 1.0f},
                                        Color{bg.r, bg.g, bg.b, 1.0f}}));
    // Oro: un degradado de dos tonos cuyo brillo recorre la pantalla.
    const float sweep = float(std::sin(clock * 0.4)) * W * 0.35f * (0.3f + 0.7f * lujo);
    auto gold = [&](float width) {
      Paint p = Paint::linear({-W * 0.3f + sweep, -H * 0.2f}, {W * 1.3f + sweep, H * 1.2f},
                              {pal[2], pal[3], pal[2], pal[3], pal[2], pal[3], pal[2]});
      p.strokeWidth = width;
      p.strokeJoin = 0;
      return p;
    };
    auto glowPaint = [&](float width) {
      Paint p;
      p.blend = Blend::plus;
      p.strokeWidth = width;
      p.strokeCap = 1;
      p.color = pal[3].opacity(std::clamp((0.06f + 0.14f * lujo + 0.15f * punch) * f.glow, 0.0f, 1.0f));
      return p;
    };
    std::vector<Vec2> sparkA, sparkB;
    // Segmentos por los que corren los destellos.
    auto sparkOn = [&](Vec2 a, Vec2 b, int id) {
      if (wDest < 0.01f) return;
      const float s = float(std::fmod(at * 0.5 + double(id) * 0.37, 1.0));
      if (hashU(uint32_t(id) * 2654435761u + uint32_t(std::floor(at * 2.0f))) > spark * amp * wDest * 1.4f) return;
      sparkA.push_back({a.x + (b.x - a.x) * s, a.y + (b.y - a.y) * s});
    };
    const int rays = std::clamp(int(std::lround(16.0f + 12.0f * f.detail)), 16, 40);

    // Todo el ornamento queda dentro del marco.
    const float inset = side * 0.05f + 6.0f * px;
    Path inside;
    inside.rect({inset, inset, W - 2.0f * inset, H - 2.0f * inset});
    c.save();
    c.clip(inside);
    c.save();
    c.translate(W * 0.5f, H * 0.55f);
    c.scale(breath, breath);
    c.translate(-W * 0.5f, -H * 0.55f);

    // SOL: rayos desde un sol bajo, con arcos escalonados encima.
    const float wSol = g.motivo.weight(0);
    if (wSol > 0.01f) {
      if (wSol < 0.99f) c.saveLayer(wSol);
      const Vec2 O{W * 0.5f, H * 0.64f};
      const float r0 = side * 0.13f;
      Path thick, thin, wedgeA;
      for (int i = 0; i < rays; i++) {
        const float a = -3.14159265f + 0.15f + (3.14159265f - 0.3f) * (float(i) + 0.5f) / float(rays);
        const float open = 0.85f + 0.15f * std::sin(at * 0.9f + float(i) * 0.25f);
        const float L = side * (i % 2 == 0 ? 0.8f : 0.58f) * open * (1.0f + 0.4f * punch);
        const Vec2 a0{O.x + r0 * std::cos(a), O.y + r0 * std::sin(a)};
        const Vec2 a1{O.x + L * std::cos(a), O.y + L * std::sin(a)};
        (i % 2 == 0 ? thick : thin).moveTo(a0.x, a0.y).lineTo(a1.x, a1.y);
        sparkOn(a0, a1, i);
        if (i % 2 == 0 && i + 1 < rays) {
          const float b = -3.14159265f + 0.15f + (3.14159265f - 0.3f) * (float(i) + 1.5f) / float(rays);
          wedgeA.moveTo(a0.x, a0.y).lineTo(a1.x, a1.y).lineTo(O.x + L * 0.72f * std::cos(b), O.y + L * 0.72f * std::sin(b))
              .lineTo(O.x + r0 * std::cos(b), O.y + r0 * std::sin(b)).close();
        }
      }
      if (fill > 0.01f) {
        Paint wp = Paint::radial(O, side * 0.8f, {pal[1].opacity(0.95f * fill), pal[1].opacity(0.35f * fill)});
        c.path(wedgeA, wp);
      }
      c.path(thick, glowPaint(6.0f * px));
      c.path(thick, gold(2.4f * px));
      c.path(thin, gold(1.1f * px));
      // Arcos escalonados como la puerta de un rascacielos.
      Path arches;
      for (int k = 0; k < 4; k++) {
        const float r = side * (0.17f + 0.075f * float(k)) * (0.97f + 0.03f * std::sin(at * 1.3f - float(k)));
        const float foot = O.y + side * 0.06f * float(k + 1);
        arches.moveTo(O.x - r - side * 0.03f, foot).lineTo(O.x - r, foot).lineTo(O.x - r, O.y);
        arc(arches, O, r, -3.14159265f, 0.0f, 28, false);
        arches.lineTo(O.x + r, foot).lineTo(O.x + r + side * 0.03f, foot);
      }
      c.path(arches, glowPaint(5.0f * px));
      c.path(arches, gold(1.6f * px));
      Paint sun = Paint::radial(O, r0, {pal[3], pal[2]});
      c.circle(O, r0 * (0.92f + 0.2f * punch), sun);
      Path sunRings;
      sunRings.circle(O, r0 * 0.7f);
      sunRings.circle(O, r0 * 0.45f);
      Paint sr;
      sr.strokeWidth = 1.2f * px;
      sr.color = pal[1].opacity(0.8f);
      c.path(sunRings, sr);
      Path base;
      base.moveTo(W * 0.08f, O.y + side * 0.3f).lineTo(W * 0.92f, O.y + side * 0.3f);
      base.moveTo(W * 0.08f, O.y + side * 0.32f).lineTo(W * 0.92f, O.y + side * 0.32f);
      c.path(base, gold(1.4f * px));
      if (wSol < 0.99f) c.restore();
    }

    // ABANICOS: mosaico de abanicos que se abren y cierran en olas.
    const float wFan = g.motivo.weight(1);
    if (wFan > 0.01f) {
      if (wFan < 0.99f) c.saveLayer(wFan);
      const int cols = std::clamp(int(std::lround(2.0f + 1.2f * f.detail)), 2, 5);
      const float fr = W / float(cols) * 0.5f;
      const int rows = int(H / (fr * 0.55f)) + 3;
      int id = 100;
      for (int row = 0; row < rows; row++) {
        const float cy = -fr * 0.5f + float(row) * fr * 0.55f;
        const float shift = (row % 2 == 0) ? 0.0f : fr;
        for (int col = -1; col <= cols; col++) {
          const Vec2 O{float(col) * fr * 2.0f + fr + shift, cy + fr};
          const float open = std::clamp(0.55f + 0.45f * std::sin(at * 1.2f - float(row) * 0.5f - float(col) * 0.3f) + 0.35f * punch, 0.2f, 1.0f);
          const float span = 3.14159265f * open;
          const float a0 = -1.5707963f - span * 0.5f, a1 = -1.5707963f + span * 0.5f;
          Path fan;
          fan.moveTo(O.x, O.y);
          arc(fan, O, fr, a0, a1, 20, false);
          fan.close();
          if (fill > 0.01f) {
            Paint fp = Paint::radial(O, fr, {(row % 2 == 0 ? pal[1] : bg).opacity(0.95f * fill), pal[1].opacity(0.55f * fill)});
            c.path(fan, fp);
          }
          Path lines;
          for (int k = 0; k <= 6; k++) {
            const float a = a0 + span * float(k) / 6.0f;
            lines.moveTo(O.x, O.y).lineTo(O.x + fr * std::cos(a), O.y + fr * std::sin(a));
          }
          arc(lines, O, fr * 0.45f, a0, a1, 12, true);
          arc(lines, O, fr * 0.75f, a0, a1, 14, true);
          c.path(fan, gold(1.8f * px));
          c.path(lines, gold(0.9f * px));
          sparkOn({O.x + fr * std::cos(a0), O.y + fr * std::sin(a0)}, {O.x + fr * std::cos(a1), O.y + fr * std::sin(a1)}, id++);
        }
      }
      if (wFan < 0.99f) c.restore();
    }

    // TORRE: la corona del Chrysler, arcos que se encienden de abajo arriba.
    const float wTorre = g.motivo.weight(2);
    if (wTorre > 0.01f) {
      if (wTorre < 0.99f) c.saveLayer(wTorre);
      const float cx = W * 0.5f;
      // Líneas de velocidad que suben a los lados.
      Path speed;
      for (int i = 0; i < 10; i++) {
        const float x = W * (0.06f + 0.035f * float(i % 5)) + (i >= 5 ? W * 0.72f : 0.0f);
        const float len = H * 0.12f;
        const float y = H - float(std::fmod(double(at) * 0.18 * double(H) + double(i) * 0.37 * double(H), double(H + len)));
        speed.moveTo(x, y).lineTo(x, y + len);
      }
      c.path(speed, gold(1.0f * px));
      Path crown, windows;
      int id = 300;
      for (int k = 0; k < 6; k++) {
        const float r = W * (0.4f - 0.055f * float(k));
        const float by = H * (0.86f - 0.095f * float(k));
        const float lightK = std::clamp(0.5f + 0.5f * std::sin(at * 2.0f - float(k) * 0.9f) + punch, 0.0f, 1.0f);
        crown.moveTo(cx - r, by + H * 0.06f).lineTo(cx - r, by);
        arc(crown, {cx, by}, r, -3.14159265f, 0.0f, 30, false);
        crown.lineTo(cx + r, by + H * 0.06f);
        // Ventanas triangulares en abanico a lo largo de cada arco.
        const int teeth = 7 + k;
        for (int j = 0; j < teeth; j++) {
          const float a = -3.14159265f + 3.14159265f * (float(j) + 0.5f) / float(teeth);
          const float da = 3.14159265f / float(teeth) * 0.35f;
          windows.moveTo(cx + r * 0.78f * std::cos(a - da), by + r * 0.78f * std::sin(a - da))
              .lineTo(cx + r * 0.95f * std::cos(a), by + r * 0.95f * std::sin(a))
              .lineTo(cx + r * 0.78f * std::cos(a + da), by + r * 0.78f * std::sin(a + da))
              .close();
        }
        if (lightK > 0.05f) {
          Paint lit;
          lit.blend = Blend::plus;
          lit.color = pal[3].opacity(std::clamp(0.12f * lightK * f.glow, 0.0f, 1.0f));
          Path glowArc;
          glowArc.moveTo(cx - r, by);
          arc(glowArc, {cx, by}, r, -3.14159265f, 0.0f, 30, false);
          glowArc.close();
          c.path(glowArc, lit);
        }
        sparkOn({cx - r, by}, {cx + r, by - r * 0.2f}, id++);
      }
      if (fill > 0.01f) {
        Paint wp;
        wp.color = pal[1].opacity(0.9f * fill);
        c.path(windows, wp);
      }
      c.path(crown, glowPaint(5.0f * px));
      c.path(crown, gold(1.8f * px));
      c.path(windows, gold(1.0f * px));
      // La aguja de la cúspide con su rombo.
      const float topY = H * (0.86f - 0.095f * 5.0f) - W * (0.4f - 0.055f * 5.0f);
      Path spire;
      spire.moveTo(cx, topY).lineTo(cx, H * 0.05f);
      spire.moveTo(cx, H * 0.1f - side * 0.04f).lineTo(cx + side * 0.025f, H * 0.1f).lineTo(cx, H * 0.1f + side * 0.04f)
          .lineTo(cx - side * 0.025f, H * 0.1f).close();
      c.path(spire, glowPaint(5.0f * px));
      c.path(spire, gold(1.8f * px));
      sparkOn({cx, topY}, {cx, H * 0.05f}, id++);
      if (wTorre < 0.99f) c.restore();
    }
    c.restore();
    c.restore();

    // Marco doble con esquinas escalonadas y rombos arriba y abajo.
    {
      const float m = side * 0.05f;
      const float s = side * 0.035f;
      Path frame;
      auto stepped = [&](float inset) {
        const float x0 = m + inset, y0 = m + inset, x1 = W - m - inset, y1 = H - m - inset;
        frame.moveTo(x0 + s, y0).lineTo(x1 - s, y0).lineTo(x1 - s, y0 + s).lineTo(x1, y0 + s)
            .lineTo(x1, y1 - s).lineTo(x1 - s, y1 - s).lineTo(x1 - s, y1).lineTo(x0 + s, y1)
            .lineTo(x0 + s, y1 - s).lineTo(x0, y1 - s).lineTo(x0, y0 + s).lineTo(x0 + s, y0 + s).close();
      };
      stepped(0.0f);
      stepped(6.0f * px);
      Path gems;
      for (int k = 0; k < 2; k++) {
        const float y = k == 0 ? m : H - m;
        gems.moveTo(W * 0.5f, y - side * 0.03f).lineTo(W * 0.5f + side * 0.045f, y).lineTo(W * 0.5f, y + side * 0.03f)
            .lineTo(W * 0.5f - side * 0.045f, y).close();
      }
      Paint gemFill;
      gemFill.color = pal[1];
      c.path(gems, gemFill);
      c.path(frame, glowPaint(4.0f * px));
      c.path(frame, gold(1.3f * px));
      c.path(gems, gold(1.3f * px));
    }
    if (!sparkA.empty()) {
      Paint sp;
      sp.blend = Blend::plus;
      sp.color = pal[3].opacity(0.95f);
      c.points(sparkA, 2.6f * px, sp);
      Paint halo;
      halo.blend = Blend::plus;
      halo.color = pal[3].opacity(std::clamp(0.25f * f.glow, 0.0f, 1.0f));
      c.points(sparkA, 7.0f * px, halo);
    }
    if (flash > 0.01f) {
      Paint fl;
      fl.blend = Blend::plus;
      fl.color = pal[2].opacity(std::clamp(flash * 0.06f * amp, 0.0f, 1.0f));
      c.rect({0, 0, W, H}, fl);
    }
    (void)sparkB;
  }
};
''';
