// Árbol Bioluminiscente — port de la galería immersive a escena nativa.
// Fractal verde que respira con la música, esporas flotando y puntas brillantes.
// La música ya aceleraba el vaivén y hacía crecer el árbol con los graves;
// Pulso decide qué más se ve: con Golpes el árbol da un respingo, una
// sacudida recorre las ramas, que se engrosan y destellan, y la copa estalla
// en un resplandor verde; con Graves las ramas se engrosan y la copa respira
// con su halo; con Agudos centellean las esporas y la mitad de las puntas.
// Sin música se ve igual que siempre.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // FORMA: copa cerrada como un ciprés o abierta como un abanico.
  CreatorModifier.slider('apertura', 'Apertura', min: .4, max: 1.8, value: 1),
  // MOVIMIENTO: árbol quieto o doblado por el viento.
  CreatorModifier.slider('viento', 'Viento', min: 0, max: 3, value: 1),
  // MÚSICA
  CreatorModifier.choice(
    'pulso',
    'Pulso',
    options: ['Golpes', 'Graves', 'Agudos'],
  ),
  // ATMÓSFERA: un halo verde que envuelve las ramas finas.
  CreatorModifier.slider('aura', 'Aura', min: 0, max: 1, value: 0),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Sauce', {
    'apertura': .55,
    'viento': 2.2,
    'aura': .5,
    'pulso': 'Graves',
  }),
  CreatorVariation('Abanico Mágico', {
    'apertura': 1.7,
    'viento': .4,
    'aura': 1,
    'pulso': 'Agudos',
    'speed': 1.3,
  }),
];

const nativeSource = r'''
class Visual final : public Scene {
  struct Seg { float x1, y1, x2, y2; int level; };
  struct Spore { float x, y, speed, phase; };
  // Ramas y puntas: memoria de trabajo que se rellena al dibujar.
  mutable std::vector<Seg> segs[10];
  mutable std::vector<Vec2> tips;
  std::vector<Spore> spores;
  float treeTime = 0.0f;
  float smoothEnergy = 0.0f;
  float smoothBass = 0.0f;
  float motion = 1.0f;
  // Música estándar: envolventes y golpe corto (valen 0 sin música).
  float bass = 0, body = 0, spark = 0, energy = 0, drive = 0, slowBass = 0, kick = 0, flash = 0;
  // Reloj propio para el centelleo de los agudos.
  double clock = 0;
  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }
  // wind: Viento; open: Apertura; shake: sacudida de Golpes (0 sin música).
  void grow(float x, float y, float a, float len, int d, float seed, float t,
            float wind, float open, float shake) const {
    float sway = std::sin(seed * 0.7f + t * 0.25f) * float(9 - d) * 0.025f * motion * wind;
    float na = a + sway + shake * std::sin(seed * 2.3f) * float(9 - d) * 0.02f;
    float x2 = x + std::cos(na) * len, y2 = y + std::sin(na) * len;
    segs[9 - d].push_back({x, y, x2, y2, 9 - d});
    if (d <= 1) {
      if (tips.size() < 256) tips.push_back({x2, y2});
      return;
    }
    float spread = (0.42f + std::sin(t * 0.4f + seed) * 0.07f) * open;
    grow(x2, y2, na - spread, len * 0.74f, d - 1, seed * 2.0f + 1.0f, t, wind, open, shake);
    grow(x2, y2, na + spread, len * 0.74f, d - 1, seed * 2.0f + 2.0f, t, wind, open, shake);
  }
 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    spores.clear(); motion = 1.0f;
    for (int i = 0; i < 10; i++) segs[i].clear();
    tips.clear();
    treeTime = 0.0f; smoothEnergy = 0.0f; smoothBass = 0.0f;
    bass = body = spark = energy = drive = slowBass = kick = flash = 0; clock = 0;
    for (int i = 0; i < 70; i++)
      spores.push_back({rng.unit(), rng.unit(), 0.3f + rng.unit() * 1.2f, rng.unit() * 6.2831853f});
  }
  void update(const Frame& f) override {
    float dt = float(f.delta);
    float targetEnergy = f.music.active ? f.music.energy : 0.0f;
    float targetBass = f.music.active ? f.music.bass : 0.0f;
    smoothEnergy += (targetEnergy - smoothEnergy) * float(1.0 - std::exp(-dt * 5.0));
    smoothBass += (targetBass - smoothBass) * float(1.0 - std::exp(-dt * 6.0));

    // En silencio reposa en un vaivén suave y meditativo (~0.12f).
    // Con música la selva bioluminiscente respira y late con el audio.
    float audioDrive = 0.12f + smoothEnergy * 0.75f + smoothBass * 0.35f;
    treeTime += dt * f.speed * audioDrive;

    motion = f.reducedMotion ? 0.3f : 1.0f;

    // Música estándar: graves, cuerpo, agudos, energía y golpe corto.
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
    const float onset = std::clamp((mu.bass - slowBass - 0.15f) * 2.5f, 0.0f, 1.0f);
    slowBass = follow(slowBass, mu.bass, 3.0f, 3.0f, dt);
    hit = std::min(std::max(hit, onset), 1.0f);
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    clock += f.delta;
  }
  void render(const Frame& f, Canvas& c) const override {
    auto g = glide(f);
    const float level = f.intensity;
    // Pulso: cada opción mueve algo distinto y sus pesos mezclan las opciones.
    const float golpe = g.pulso.weight(0) * std::min(kick * level, 1.0f);
    const float graves = g.pulso.weight(1) * std::min(bass * level, 1.0f);
    const float agudos = g.pulso.weight(2) * std::min(spark * level, 1.0f);
    const float tick = float(std::fmod(clock, 1000.0));
    float w = f.width, h = f.height;
    float t = treeTime;
    // El árbol (antes en update) crece aquí: los ajustes se ven también en pausa.
    for (int i = 0; i < 10; i++) segs[i].clear();
    tips.clear();
    // Golpes: el árbol entero da un respingo (+12%) en cada golpe.
    grow(f.width * 0.5f, f.height * 0.94f, -1.5707963f, f.height * (0.16f + smoothBass * 0.035f) * (1.0f + golpe * 0.12f), 9, 1.0f, t,
         g.viento, g.apertura, golpe);
    float boost = std::clamp((0.8f + 0.4f * smoothEnergy + 0.3f * smoothBass) * f.intensity, 0.0f, 1.0f);
    Paint bg = Paint::radial({w * 0.5f, h * 0.75f}, h * 0.9f,
      {Color::argb(0xff04231c), Color::argb(0xff021410), Color::argb(0xff000705)}, {0, 0.5f, 1.0f});
    c.rect({0, 0, w, h}, bg);
    std::vector<Vec2> sbuf; sbuf.reserve(spores.size());
    for (const auto& s : spores) {
      float y = std::fmod(s.y * h - t * s.speed * 9.0f, h);
      if (y < 0) y += h;
      sbuf.push_back({s.x * w + std::sin(t * 0.6f + s.phase) * 12.0f, y});
    }
    Paint sp; sp.blend = Blend::plus;
    sp.color = {0.435f, 1, 0.753f, 0.4f * boost};
    c.points(sbuf, 1.0f, sp);
    // Golpes: la copa estalla en un resplandor verde; Graves la hace respirar.
    const float burst = std::min(1.0f, (0.4f * golpe + 0.22f * graves) * f.glow);
    if (burst > 0.001f) {
      const float reach = h * 0.4f;
      Paint light = Paint::radial({w * 0.5f, h * 0.38f}, reach,
        {{0.5f, 1, 0.75f, burst}, {0.25f, 0.9f, 0.6f, burst * 0.4f}, {0.1f, 0.6f, 0.4f, 0}}, {0, 0.4f, 1.0f});
      light.blend = Blend::plus;
      c.circle({w * 0.5f, h * 0.38f}, reach, light);
    }
    if (agudos > 0.001f) {
      // Agudos: algunas esporas centellean y tiemblan con los agudos.
      std::vector<Vec2> lit; lit.reserve(sbuf.size());
      for (size_t i = 0; i < sbuf.size(); i++)
        if (std::sin(spores[i].phase * 3.0f + tick * 9.0f) > -0.3f)
          lit.push_back({sbuf[i].x + std::sin(tick * 43.0f + float(i)) * 2.0f * agudos,
                         sbuf[i].y + std::cos(tick * 39.0f + float(i) * 1.3f) * 2.0f * agudos});
      Paint lp; lp.blend = Blend::plus;
      lp.color = {0.5f, 1, 0.75f, std::min(1.0f, agudos * 0.3f * f.glow)};
      c.points(lit, 6.0f, lp);
      lp.color = {0.75f, 1, 0.88f, std::min(1.0f, agudos)};
      c.points(lit, 2.4f, lp);
    }
    const uint32_t cols[10] = {0xff0b3a2e, 0xff0f5c42, 0xff14855a, 0xff1fb573, 0xff43e08f,
      0xff7bffb0, 0xffb9ffd6, 0xffe6fff1, 0xffffffff, 0xffffffff};
    const float aura = std::clamp(g.aura, 0.0f, 1.0f);
    for (int i = 0; i < 10; i++) {
      Path path;
      for (const auto& s : segs[i]) {
        path.moveTo(s.x1, s.y1); path.lineTo(s.x2, s.y2);
      }
      Paint p; p.blend = Blend::plus;
      Color cc = Color::argb(cols[i]);
      // Golpes destella las ramas; Graves las aviva despacio.
      p.color = {cc.r, cc.g, cc.b, std::min(1.0f, 0.85f * boost * (1.0f + golpe * 0.8f + graves * 0.3f))};
      // Golpes engrosa las ramas (×2); Graves, despacio (×1,6).
      p.strokeWidth = std::max(0.6f, float(9 - i) * 0.52f) * (1.0f + golpe * 1.0f + graves * 0.6f);
      if (aura > 0.001f && i >= 3) {
        // Aura: un halo verde y tenue alrededor de las ramas finas.
        Paint glowPaint = p;
        glowPaint.strokeWidth = p.strokeWidth * (3.0f + aura * 4.0f) + 2.0f * aura;
        glowPaint.color.a = std::min(1.0f, 0.14f * aura * boost);
        c.path(path, glowPaint);
      }
      c.path(path, p);
    }
    if (aura > 0.001f) {
      // Aura: las puntas también llevan su halo.
      Paint tipGlow; tipGlow.blend = Blend::plus;
      tipGlow.color = {0.55f, 1, 0.75f, std::min(1.0f, 0.12f * aura * boost)};
      c.points(tips, 1.6f * (3.0f + aura * 3.0f), tipGlow);
    }
    // Golpes: las puntas destellan y se hinchan en cada golpe.
    Paint tp; tp.blend = Blend::plus;
    tp.color = {0.788f, 1, 0.902f, std::min(1.0f, (0.45f + 0.45f * std::abs(std::sin(t * 2.0f))) * boost + golpe * 0.6f)};
    c.points(tips, 1.6f * (1.0f + golpe * 0.8f), tp);
    if (agudos > 0.001f) {
      // Agudos: la mitad de las puntas centellea, cada una a su ritmo.
      std::vector<Vec2> lit; lit.reserve(tips.size());
      for (size_t k = 0; k < tips.size(); k++)
        if (std::sin(tick * 13.0f + float(k) * 2.39f) > 0.0f) lit.push_back(tips[k]);
      Paint sp2; sp2.blend = Blend::plus;
      sp2.color = {0.85f, 1, 0.93f, std::min(1.0f, agudos)};
      c.points(lit, 2.6f, sp2);
    }
  }
};
''';
