// Aurora Boreal — port de la galería immersive a escena nativa.
// Cintas de luz sobre cielo estrellado y montañas en sombra. La energía de
// la música ya hacía respirar y destellar las cintas; Pulso decide qué más
// se ve: con Golpes las cortinas saltan, se estiran y se encienden sobre un
// resplandor verde en cada golpe; con Graves se engrosan, ondulan y brillan
// despacio; con Agudos centellean las estrellas, parpadean las cintas y su
// borde tiembla. Sin música se ve igual que siempre.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // FORMA: cuántas cortinas de luz hay.
  CreatorModifier.steps('cintas', 'Cintas', min: 2, max: 6, value: 4),
  // MOVIMIENTO: cortinas casi planas o muy onduladas.
  CreatorModifier.slider('oleaje', 'Oleaje', min: 0, max: 2.5, value: 1),
  // MÚSICA
  CreatorModifier.choice(
    'pulso',
    'Pulso',
    options: ['Golpes', 'Graves', 'Agudos'],
  ),
  // ATMÓSFERA: estrías verticales de luz que suben desde cada cortina.
  CreatorModifier.slider('rayos', 'Rayos', min: 0, max: 1, value: 0),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Tormenta Solar', {
    'cintas': 6,
    'oleaje': 2,
    'rayos': .7,
    'pulso': 'Golpes',
  }),
  CreatorVariation('Velo Sereno', {
    'cintas': 2,
    'oleaje': .4,
    'rayos': 1,
    'pulso': 'Graves',
  }),
];

const nativeSource = r'''
class Visual final : public Scene {
  struct Star { float x, y, tw; };
  std::vector<Star> stars;
  float breath = 0, flash = 0;
  // Música estándar (vale 0 sin música). flash ya es el destello propio de
  // la aurora, así que el de events[3] se llama blink.
  float bass = 0, body = 0, spark = 0, energy = 0, drive = 0, slowBass = 0, kick = 0, blink = 0;
  // Reloj propio para el temblor de los agudos.
  double clock = 0;
  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }
  static float vhash(int x, int y) {
    uint32_t h = uint32_t(x) * 374761393u + uint32_t(y) * 668265263u;
    h = (h ^ (h >> 13)) * 1274126177u; h ^= h >> 16;
    return float(h & 0xffffu) / 65535.0f;
  }
  static float vnoise(float x, float y) {
    int xi = int(std::floor(x)), yi = int(std::floor(y));
    float xf = x - float(xi), yf = y - float(yi);
    float u = xf * xf * (3.0f - 2.0f * xf), v = yf * yf * (3.0f - 2.0f * yf);
    float a = vhash(xi, yi), b = vhash(xi + 1, yi);
    float c = vhash(xi, yi + 1), d = vhash(xi + 1, yi + 1);
    return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v;
  }
 public:
  void reset(uint32_t seed) override {
    Random rng(seed); stars.clear(); stars.reserve(110); breath = 0; flash = 0;
    bass = body = spark = energy = drive = slowBass = kick = blink = 0; clock = 0;
    for (int i = 0; i < 110; i++)
      stars.push_back({rng.unit(), rng.unit() * 0.62f, rng.unit() * 6.2831853f});
  }
  void update(const Frame& f) override {
    breath += (f.music.energy - breath) * float(1.0 - std::exp(-f.delta * 3.0));
    for (const auto& band : f.music.events)
      for (const auto& e : band) flash += e.strength;
    flash *= float(std::exp(-f.delta * 4.0));
    // Música estándar: graves, cuerpo, agudos, energía y golpe corto.
    const float dt = float(f.delta);
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
    blink = std::max(blink * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
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
    float t = float(f.time) * f.speed;
    float glow = (0.8f + 0.35f * breath + 0.5f * flash) * f.intensity;
    if (glow > 1.0f) glow = 1.0f; if (glow < 0.0f) glow = 0.0f;
    Paint sky = Paint::linear({0, 0}, {0, h},
      {Color::argb(0xff01030f), Color::argb(0xff04122b),
       Color::argb(0xff062033), Color::argb(0xff010409)}, {0, 0.45f, 0.8f, 1.0f});
    c.rect({0, 0, w, h}, sky);
    std::vector<Vec2> batch; batch.reserve(stars.size());
    for (const auto& s : stars) batch.push_back({s.x * w, s.y * h});
    Paint sp; sp.blend = Blend::plus;
    sp.color = {1, 1, 1, (0.35f + 0.25f * std::abs(std::sin(t * 0.9f))) * glow};
    c.points(batch, 0.8f, sp);
    if (agudos > 0.001f) {
      // Agudos: cada estrella centellea a su ritmo con los agudos.
      std::vector<Vec2> lit; lit.reserve(stars.size());
      for (const auto& s : stars)
        if (std::sin(s.tw + tick * 7.0f) > -0.2f) lit.push_back({s.x * w, s.y * h});
      Paint shine; shine.blend = Blend::plus;
      shine.color = {0.7f, 1, 0.9f, std::min(1.0f, agudos * 0.3f * f.glow)};
      c.points(lit, 5.0f, shine);
      shine.color = {1, 1, 1, std::min(1.0f, agudos)};
      c.points(lit, 2.2f, shine);
    }
    // Golpes: un resplandor verde estalla detrás de las cortinas; Graves lo
    // hace respirar más suave.
    const float burst = std::min(1.0f, (0.32f * golpe + 0.2f * graves) * f.glow);
    if (burst > 0.001f) {
      Paint aura = Paint::radial({w * 0.5f, h * 0.4f}, w * 0.8f,
        {{0.25f, 1, 0.8f, burst}, {0.3f, 0.6f, 1, burst * 0.4f}, {0.3f, 0.4f, 1, 0}}, {0, 0.5f, 1.0f});
      aura.blend = Blend::plus;
      c.circle({w * 0.5f, h * 0.4f}, w * 0.8f, aura);
    }
    // Las cuatro primeras cintas son las originales; Cintas añade dos más.
    const float cy[6] = {0.30f, 0.36f, 0.44f, 0.50f, 0.24f, 0.56f};
    const float am[6] = {0.05f, 0.06f, 0.045f, 0.035f, 0.04f, 0.05f};
    const float th[6] = {0.20f, 0.16f, 0.13f, 0.09f, 0.12f, 0.08f};
    const float sp2[6] = {0.18f, -0.25f, 0.33f, -0.40f, 0.22f, -0.31f};
    const float fr[6] = {1.7f, 2.3f, 3.1f, 4.2f, 2.0f, 3.6f};
    const uint32_t col[6] = {0xff38ffc4, 0xff4be0ff, 0xff9d6bff, 0xffff5fd2, 0xffff4060, 0xff5cff7a};
    const float rays = std::clamp(g.rayos, 0.0f, 1.0f);
    // Golpes: las cortinas saltan hacia arriba un instante.
    const float jump = -h * 0.03f * golpe;
    for (int b = 0; b < 6; b++) {
      // Cintas se desliza: la última cortina aparece o se apaga poco a poco.
      const float share = std::clamp(g.cintas - float(b), 0.0f, 1.0f);
      if (share <= 0.0f) continue;
      float amp = am[b] * (1.0f + 0.4f * breath);
      // Oleaje: amplitud de las ondas de la cortina (1 es el original).
      const float swing = amp * g.oleaje * (1.0f + graves * 0.15f);
      // Graves: la cortina se engrosa (×1,6); Golpes la estira un instante.
      const float thick = th[b] * (1.0f + graves * 0.6f + golpe * 0.25f);
      float top[27];
      Path ribbon;
      for (int i = 0; i <= 26; i++) {
        float x = float(i) / 26.0f * w;
        float n = vnoise(float(i) * 0.22f + t * sp2[b], float(b) * 5.5f + t * 0.15f);
        float y = h * cy[b] + std::sin(float(i) * fr[b] * 0.14f + t * sp2[b] * 3.0f) * h * swing
          + (n - 0.5f) * h * 0.07f;
        // Agudos: el borde tiembla fino con los agudos.
        y += jump + std::sin(float(i) * 7.3f + tick * 38.0f + float(b) * 2.0f) * h * 0.006f * agudos;
        top[i] = y;
        if (i == 0) ribbon.moveTo(x, y); else ribbon.lineTo(x, y);
      }
      for (int i = 26; i >= 0; i--) {
        float x = float(i) / 26.0f * w;
        float n = vnoise(float(i) * 0.22f + t * sp2[b], float(b) * 5.5f + t * 0.15f);
        float y = h * cy[b] + std::sin(float(i) * fr[b] * 0.14f + t * sp2[b] * 3.0f) * h * swing
          + (n - 0.5f) * h * 0.07f + h * thick * (0.6f + n * 0.8f);
        y += jump + std::sin(float(i) * 7.3f + tick * 38.0f + float(b) * 2.0f) * h * 0.006f * agudos;
        ribbon.lineTo(x, y);
      }
      ribbon.close();
      Color base = Color::argb(col[b]);
      // Golpes destella la cortina (+90%); Graves la aviva despacio; Agudos la
      // hace parpadear, cada cinta a su ritmo.
      const float flicker = agudos * 0.6f * std::sin(tick * 21.0f + float(b) * 1.9f);
      const float alpha = std::clamp(0.40f * glow * (1.0f + golpe * 0.9f + graves * 0.5f + flicker), 0.0f, 1.0f) * share;
      Paint band = Paint::linear({0, h * (cy[b] - amp - thick) + jump}, {0, h * (cy[b] + amp + 0.02f) + jump},
        {{base.r, base.g, base.b, 0}, {base.r, base.g, base.b, alpha},
         {base.r, base.g, base.b, 0}}, {0, 0.45f, 1.0f});
      band.blend = Blend::plus;
      c.path(ribbon, band);
      if (rays > 0.001f) {
        // Rayos: estrías de luz que suben desde el borde de la cortina, cada
        // una de su largo y titilando despacio.
        Path streaks;
        for (int i = 0; i <= 52; i++) {
          const float x = float(i) / 52.0f * w;
          const float y = (top[i / 2] + top[(i + 1) / 2]) * 0.5f;
          const float reach = 0.3f + 0.7f * vnoise(float(i) * 0.9f + t * 0.4f, float(b) * 3.1f + 7.0f);
          streaks.moveTo(x, y + h * thick * 0.5f).lineTo(x, y - h * (0.03f + thick * 1.1f) * reach * rays);
        }
        Paint ray = Paint::linear({0, h * (cy[b] - amp - thick * 2.2f) + jump}, {0, h * (cy[b] + amp) + jump},
          {{base.r, base.g, base.b, 0}, {base.r, base.g, base.b, std::min(1.0f, 0.4f * glow * rays) * share}}, {0, 1.0f});
        ray.blend = Blend::plus;
        ray.strokeWidth = std::max(1.0f, w / 52.0f * 0.28f);
        c.path(streaks, ray);
      }
    }
    Path ridge; ridge.moveTo(0, h);
    for (int i = 0; i < 42; i++)
      ridge.lineTo(float(i) / 41.0f * w,
        h * (0.8f + vnoise(float(i) * 0.35f, 3.0f) * 0.12f) - float(std::abs(i - 20)) * 0.8f);
    ridge.lineTo(w, h); ridge.close();
    Paint dk; dk.color = Color::argb(0xff01050c);
    c.path(ridge, dk);
  }
};
''';
