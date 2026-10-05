// Hipervelocidad — port de la galería immersive a escena nativa.
// Estelas reales por segmentos, agrupadas en tres lotes por color. La
// posición es función pura del tiempo, así que 30 y 60 FPS coinciden.
// La energía y los graves de la música ya aceleraban el viaje; Pulso decide
// qué más se ve: con Golpes el núcleo estalla en cada golpe con un gran
// resplandor azul, un tirón hacia delante y estelas mucho más largas y
// gruesas; con Graves el campo se abre, las estelas engordan y el resplandor
// central respira; con Agudos las cabezas tiemblan, muchas centellean y el
// resplandor central titila.
// Sin música se ve igual que siempre.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // FORMA: de un núcleo de estrellas compacto a un salto que llena la pantalla.
  CreatorModifier.slider('apertura', 'Apertura', min: 0, max: 1, value: 0),
  // MOVIMIENTO: viaje recto o en torbellino (las estelas se curvan).
  CreatorModifier.slider('remolino', 'Remolino', min: 0, max: 1, value: 0),
  // MÚSICA
  CreatorModifier.choice(
    'pulso',
    'Pulso',
    options: ['Golpes', 'Graves', 'Agudos'],
  ),
  // ATMÓSFERA: estelas cortas como puntos o largas como rayos.
  CreatorModifier.slider('estela', 'Estela', min: .3, max: 3, value: 1),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Hiperespacio', {
    'apertura': .9,
    'estela': 2.2,
    'pulso': 'Golpes',
    'speed': 1.3,
  }),
  CreatorVariation('Torbellino', {
    'apertura': .7,
    'remolino': 1,
    'estela': .6,
    'pulso': 'Agudos',
  }),
];

const nativeSource = r'''
class Visual final : public Scene {
  struct Star { float x, y, z0, cycle; };
  std::vector<Star> stars;
  float travel = 0.0f;
  float smoothBass = 0.0f;
  float smoothEnergy = 0.0f;
  // Música estándar: envolventes y golpe corto (valen 0 sin música).
  float bass = 0, body = 0, spark = 0, energy = 0, drive = 0, slowBass = 0, kick = 0, flash = 0;
  // Reloj propio para el temblor de los agudos.
  double clock = 0;
  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }
  static float hashU(uint32_t x) {
    x ^= x >> 16; x *= 0x7feb352dU; x ^= x >> 15; x *= 0x846ca68bU; x ^= x >> 16;
    return float(x & 0xffffffu) / 16777216.0f;
  }
  // Remolino: gira un punto alrededor del centro de la pantalla.
  static void turn(float& x, float& y, float angle) {
    const float cs = std::cos(angle), sn = std::sin(angle);
    const float nx = x * cs - y * sn;
    y = x * sn + y * cs; x = nx;
  }
 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    stars.clear(); stars.reserve(621);
    travel = 0.0f; smoothBass = 0.0f; smoothEnergy = 0.0f;
    bass = body = spark = energy = drive = slowBass = kick = flash = 0; clock = 0;
    for (int i = 0; i < 621; i++) {
      Star s;
      s.x = (rng.unit() - 0.5f) * 2.2f;
      s.y = (rng.unit() - 0.5f) * 2.2f;
      s.z0 = rng.unit() * 2.2f + 0.05f;
      s.cycle = 2.2f + 1.2f;
      stars.push_back(s);
    }
  }
  void update(const Frame& f) override {
    float dt = float(f.delta);
    float targetEnergy = f.music.active ? f.music.energy : 0.0f;
    float targetBass = f.music.active ? f.music.bass : 0.0f;
    smoothBass += (targetBass - smoothBass) * float(1.0 - std::exp(-dt * 6.0));
    smoothEnergy += (targetEnergy - smoothEnergy) * float(1.0 - std::exp(-dt * 5.0));

    // En silencio reposa en un crucero estelar pausado (~0.10f).
    // Con música acelera hacia velocidad hiperlumínica con estelas largas.
    float audioDrive = 0.10f + smoothEnergy * 0.90f + smoothBass * 0.45f;
    if (f.reducedMotion) audioDrive *= 0.4f;
    travel += dt * f.speed * audioDrive * 1.6f;

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
    // Golpes: cada golpe da un tirón hacia delante (vale 0 sin música).
    auto g = glide(f);
    travel += dt * f.speed * std::min(kick * f.intensity, 1.0f) * g.pulso.weight(0) * 1.4f;
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
    float cx = w * 0.5f, cy = h * 0.5f;
    float boost = std::clamp((0.7f + 0.5f * smoothEnergy + 0.4f * smoothBass) * f.intensity, 0.0f, 1.0f);
    Paint bg; bg.color = Color::argb(0xff02020c);
    c.rect({0, 0, w, h}, bg);
    // Apertura: 0 es el núcleo original; 1 abre el salto a toda la pantalla.
    // Graves: el campo se abre un 14% más con los graves.
    // Golpes: el núcleo estalla hacia fuera en cada golpe (menos cuanto más
    // abierto está ya el salto, para no sacar las estrellas de la pantalla).
    const float lens = 0.75f * std::exp(g.apertura * 5.7f) * (1.0f + graves * 0.14f)
      * (1.0f + golpe * 3.0f * (1.0f - g.apertura * 0.85f));
    const float swirl = g.remolino;
    const float trail = g.estela;
    Path lanes[3];
    std::vector<Vec2> heads[3];
    for (int i = 0; i < 3; i++) heads[i].reserve(240);
    std::vector<Vec2> glints;
    for (size_t idx = 0; idx < stars.size(); idx++) {
      const Star& s = stars[idx];
      float z = std::fmod(s.z0 - travel, s.cycle);
      if (z < 0.04f) z += s.cycle;
      // Remolino: las estrellas cercanas giran más, así el viaje se enrosca.
      float hx = s.x, hy = s.y;
      if (swirl > 0.001f) turn(hx, hy, swirl * 1.3f / (z + 0.3f));
      float x1 = cx + (hx / z) * lens;
      float y1 = cy + (hy / z) * lens;
      if (x1 < -80 || x1 > w + 80 || y1 < -80 || y1 > h + 80) continue;
      // Estela alarga o acorta el rastro; Golpes lo estira mucho un instante.
      float tail = z + 0.04f * trail + smoothEnergy * 0.10f * trail + golpe * 0.6f;
      float tx = s.x, ty = s.y;
      if (swirl > 0.001f) turn(tx, ty, swirl * 1.3f / (tail + 0.3f));
      if (agudos > 0.001f) {
        // Agudos: las cabezas tiemblan y algunas centellean.
        x1 += std::sin(tick * 53.0f + float(idx) * 1.9f) * 1.5f * agudos;
        y1 += std::cos(tick * 47.0f + float(idx) * 2.7f) * 1.5f * agudos;
        if (hashU(uint32_t(idx) * 2654435761u ^ uint32_t(tick * 14.0f) * 0x9e3779b9u) > 0.55f) glints.push_back({x1, y1});
      }
      int lane = int(idx % 3);
      lanes[lane].moveTo(cx + (tx / tail) * lens, cy + (ty / tail) * lens);
      lanes[lane].lineTo(x1, y1);
      heads[lane].push_back({x1, y1});
    }
    for (int lane = 0; lane < 3; lane++) {
      Paint p; p.blend = Blend::plus;
      if (lane == 0) { p.color = {1, 1, 1, 0.9f * boost}; p.strokeWidth = 1.7f; }
      else if (lane == 1) { p.color = {0.749f, 0.894f, 1, 0.55f * boost}; p.strokeWidth = 1.1f; }
      else { p.color = {1, 0.839f, 0.941f, 0.55f * boost}; p.strokeWidth = 1.1f; }
      // Golpes: las estelas se engrosan en cada golpe (×2,2); Graves, ×1,6.
      p.strokeWidth *= 1.0f + golpe * 1.2f + graves * 0.6f;
      p.strokeCap = 1; p.strokeJoin = 1;
      c.path(lanes[lane], p);
      if (!heads[lane].empty()) {
        Paint hp; hp.blend = Blend::plus;
        hp.color = {1, 1, 1, 0.85f * boost};
        c.points(heads[lane], 0.85f * (1.0f + golpe * 0.6f), hp);
      }
    }
    if (!glints.empty()) {
      Paint gp; gp.blend = Blend::plus;
      gp.color = {0.6f, 0.8f, 1, std::min(1.0f, agudos * 0.3f * f.glow)};
      c.points(glints, 6.0f, gp);
      gp.color = {0.85f, 0.93f, 1, std::min(1.0f, agudos)};
      c.points(glints, 2.6f, gp);
    }
    // Graves: el resplandor central crece y se aviva.
    Paint glow = Paint::radial({cx, cy}, std::min(w, h) * 0.45f * (1.0f + graves * 0.25f),
      {{0.549f, 0.745f, 1, std::min(1.0f, 0.28f * boost * (1.0f + graves * 0.8f)
        + agudos * 0.25f * (0.5f + 0.5f * std::sin(tick * 31.0f)))}, {0, 0, 0, 0}});
    glow.blend = Blend::plus;
    c.rect({0, 0, w, h}, glow);
    if (golpe > 0.001f) {
      // Golpes: un gran resplandor local estalla desde el núcleo.
      const float flare = std::min(1.0f, 0.65f * golpe * f.glow);
      const float reach = std::min(w, h) * 0.8f;
      Paint burst = Paint::radial({cx, cy}, reach,
        {{0.75f, 0.88f, 1, flare}, {0.45f, 0.65f, 1, flare * 0.35f}, {0.3f, 0.4f, 1, 0}}, {0, 0.3f, 1.0f});
      burst.blend = Blend::plus;
      c.circle({cx, cy}, reach, burst);
    }
  }
};
''';
