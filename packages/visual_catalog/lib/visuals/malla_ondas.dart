// Malla de Ondas — port de la galería immersive a escena nativa.
// Miles de puntos azules ondulando como agua vista desde arriba.
// La música ya aceleraba las ondas y levantaba la malla con los graves;
// Pulso decide qué más se ve: con Golpes cada golpe lanza una onda
// expansiva con un anillo de luz que levanta y enciende los puntos que
// cruza, y la malla entera late; con Graves los puntos engordan, brillan y
// las crestas se cubren de un halo; con Agudos las crestas se llenan de
// destellos que titilan. Sin música se ve igual que siempre.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // FORMA: cuántos focos lanzan ondas.
  CreatorModifier.steps('fuentes', 'Fuentes', min: 1, max: 4, value: 2),
  // MOVIMIENTO: agua en calma, picada o en remolinos.
  CreatorModifier.choice(
    'agua',
    'Agua',
    options: ['Calma', 'Picada', 'Remolino'],
  ),
  // MÚSICA
  CreatorModifier.choice(
    'pulso',
    'Pulso',
    options: ['Golpes', 'Graves', 'Agudos'],
  ),
  // ATMÓSFERA: un halo suave de espuma sobre las crestas.
  CreatorModifier.slider('espuma', 'Espuma', min: 0, max: 1, value: 0),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Mar Picado', {
    'fuentes': 4,
    'agua': 'Picada',
    'espuma': .5,
    'pulso': 'Golpes',
    'speed': 1.3,
  }),
  CreatorVariation('Remolinos', {
    'fuentes': 3,
    'agua': 'Remolino',
    'espuma': 1,
    'pulso': 'Agudos',
  }),
];

const nativeSource = r'''
class Visual final : public Scene {
  // Puntos de cada tono: memoria de trabajo que se rellena al dibujar.
  mutable std::vector<Vec2> buckets[6];
  mutable std::vector<Vec2> glints;
  float waveTime = 0.0f;
  float smoothBass = 0.0f;
  float smoothEnergy = 0.0f;
  // Música estándar: envolventes y golpe corto (valen 0 sin música).
  float bass = 0, body = 0, spark = 0, energy = 0, drive = 0, slowBass = 0, kick = 0, flash = 0;
  // Segundos reales: las ondas de los golpes no dependen de Velocidad.
  double clock = 0;
  // Golpes: anillo fijo de ondas expansivas {nacimiento, fuerza}.
  static constexpr int kRings = 4;
  std::array<double, kRings> ringBirth{};
  std::array<float, kRings> ringPower{};
  int nextRing = 0;
  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }
  static float hashU(uint32_t x) {
    x ^= x >> 16; x *= 0x7feb352dU; x ^= x >> 15; x *= 0x846ca68bU; x ^= x >> 16;
    return float(x & 0xffffffu) / 16777216.0f;
  }
  // Una onda: Picada le suma un armónico agudo; Remolino la enrosca en espiral.
  static float wave(float phase, float dx, float dy, float choppy, float swirl) {
    if (swirl > 0.001f) phase += swirl * 2.0f * std::atan2(dy, dx);
    float s = std::sin(phase);
    if (choppy > 0.001f) s += choppy * 0.8f * std::sin(phase * 2.0f + 1.3f);
    return s;
  }
 public:
  void reset(uint32_t seed) override {
    (void)seed;
    for (int i = 0; i < 6; i++) buckets[i].clear();
    glints.clear();
    waveTime = 0.0f; smoothBass = 0.0f; smoothEnergy = 0.0f;
    bass = body = spark = energy = drive = slowBass = kick = flash = 0; clock = 0;
    ringBirth.fill(-100.0); ringPower.fill(0.0f); nextRing = 0;
  }
  void update(const Frame& f) override {
    float dt = float(f.delta);
    float targetEnergy = f.music.active ? f.music.energy : 0.0f;
    float targetBass = f.music.active ? f.music.bass : 0.0f;
    smoothBass += (targetBass - smoothBass) * float(1.0 - std::exp(-dt * 6.0));
    smoothEnergy += (targetEnergy - smoothEnergy) * float(1.0 - std::exp(-dt * 5.0));

    // En silencio reposa en una ondulación zen (~0.10f).
    // Con música acelera la onda y multiplica la amplitud vertical.
    float audioDrive = 0.10f + smoothEnergy * 0.75f + smoothBass * 0.35f;
    waveTime += dt * f.speed * audioDrive;

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
    const bool fresh = hit > kick + 0.2f;
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    clock += f.delta;
    // Golpes: cada golpe nuevo lanza una onda expansiva desde el centro.
    if (fresh) {
      ringBirth[size_t(nextRing)] = clock;
      ringPower[size_t(nextRing)] = hit;
      nextRing = (nextRing + 1) % kRings;
    }
  }
  void render(const Frame& f, Canvas& c) const override {
    auto g = glide(f);
    const float level = f.intensity;
    // Pulso: cada opción mueve algo distinto y sus pesos mezclan las opciones.
    const float golpe = g.pulso.weight(0) * std::min(kick * level, 1.0f);
    const float graves = g.pulso.weight(1) * std::min(bass * level, 1.0f);
    const float agudos = g.pulso.weight(2) * std::min(spark * level, 1.0f);
    float w = f.width, h = f.height;
    // La malla (antes en update) se calcula aquí: los ajustes se ven en pausa.
    const float step = std::max(9.0f, std::min(w, h) / (18.0f + 16.0f * f.detail));
    const float cols = std::ceil(w / step) + 1.0f;
    const float rows = std::ceil(h / step) + 1.0f;
    float t = waveTime;
    float amp = 1.0f + smoothBass * 0.85f;
    float s1x = w * (0.5f + std::sin(t * 0.35f) * 0.32f);
    float s1y = h * (0.35f + std::sin(t * 0.27f + 1.0f) * 0.2f);
    float s2x = w * (0.5f + std::sin(t * 0.31f + 2.4f) * 0.34f);
    float s2y = h * (0.68f + std::sin(t * 0.23f + 3.0f) * 0.2f);
    // Fuentes: 2 es el original; la tercera y la cuarta entran poco a poco.
    const float n = g.fuentes;
    // Varias ondas se suman casi como su raíz: con más de dos fuentes se
    // normaliza menos para no apagar el contraste (con 2 queda el original).
    const float norm = n <= 2.0f ? n : 2.0f + (n - 2.0f) * 0.4f;
    const float w2 = std::clamp(n - 1.0f, 0.0f, 1.0f);
    const float w3 = std::clamp(n - 2.0f, 0.0f, 1.0f);
    const float w4 = std::clamp(n - 3.0f, 0.0f, 1.0f);
    float s3x = w * (0.5f + std::sin(t * 0.33f + 4.2f) * 0.36f);
    float s3y = h * (0.5f + std::sin(t * 0.21f + 5.1f) * 0.3f);
    float s4x = w * (0.5f + std::sin(t * 0.27f + 1.3f) * 0.3f);
    float s4y = h * (0.12f + std::sin(t * 0.25f + 0.7f) * 0.1f);
    const float choppy = g.agua.weight(1), swirl = g.agua.weight(2);
    // Ondas expansivas vivas: radio y fuerza (Golpes; 0 sin música).
    float ringR[kRings], ringA[kRings];
    int live = 0;
    const float ringSpeed = std::max(w, h) * 0.85f, ringLife = 1.3f;
    for (int r = 0; r < kRings; r++) {
      const float age = float(clock - ringBirth[size_t(r)]);
      const float power = std::min(ringPower[size_t(r)] * level, 1.0f) * g.pulso.weight(0);
      if (age < 0.0f || age >= ringLife || power <= 0.001f) continue;
      ringR[live] = age * ringSpeed;
      ringA[live] = power * (1.0f - age / ringLife);
      live++;
    }
    const float ox = w * 0.5f, oy = h * 0.5f;
    const uint32_t sparkle = uint32_t(std::fmod(clock * 12.0, 1.0e6));
    for (int i = 0; i < 6; i++) buckets[i].clear();
    glints.clear();
    for (int j = 0; j < int(rows); j++) {
      float y = float(j) * step;
      for (int i = 0; i < int(cols); i++) {
        float x = float(i) * step;
        float dx1 = x - s1x, dy1 = y - s1y;
        float dx2 = x - s2x, dy2 = y - s2y;
        float d1 = std::sqrt(dx1 * dx1 + dy1 * dy1);
        float d2 = std::sqrt(dx2 * dx2 + dy2 * dy2);
        float v = wave(d1 * 0.085f - t * 2.4f, dx1, dy1, choppy, swirl) + w2 * wave(d2 * 0.07f - t * 1.9f, dx2, dy2, choppy, swirl);
        if (w3 > 0.0f) {
          float dx3 = x - s3x, dy3 = y - s3y;
          v += w3 * wave(std::sqrt(dx3 * dx3 + dy3 * dy3) * 0.078f - t * 2.1f, dx3, dy3, choppy, swirl);
        }
        if (w4 > 0.0f) {
          float dx4 = x - s4x, dy4 = y - s4y;
          v += w4 * wave(std::sqrt(dx4 * dx4 + dy4 * dy4) * 0.092f - t * 2.7f, dx4, dy4, choppy, swirl);
        }
        float k = (v + norm) / (2.0f * norm);
        // Golpes: la onda expansiva levanta y enciende los puntos que cruza.
        float bump = 0.0f;
        if (live > 0) {
          const float d = std::sqrt((x - ox) * (x - ox) + (y - oy) * (y - oy));
          for (int r = 0; r < live; r++) {
            const float dr = (d - ringR[r]) / (step * 2.5f);
            bump += ringA[r] * std::exp(-dr * dr);
          }
          k += bump * 0.8f;
        }
        int b = int(k * 5.99f);
        if (b < 0) b = 0; if (b > 5) b = 5;
        const Vec2 point{x, y + (k - 0.5f) * step * 0.55f * amp - bump * step * 1.2f};
        buckets[b].push_back(point);
        // Agudos: destellos que titilan sobre las crestas.
        if (agudos > 0.001f && k > 0.5f &&
            hashU(uint32_t(j * 4099 + i) * 2654435761u ^ sparkle * 0x9e3779b9u) > 0.5f)
          glints.push_back(point);
      }
    }
    Paint bg; bg.color = Color::argb(0xff03071c);
    c.rect({0, 0, w, h}, bg);
    const uint32_t pal[6] = {0xff0a1b4a, 0xff123a8a, 0xff1f6fd0,
      0xff35b3f0, 0xff7fe9ff, 0xffd9fbff};
    const float foam = std::clamp(g.espuma, 0.0f, 1.0f);
    for (int b = 0; b < 6; b++) {
      if (buckets[b].empty()) continue;
      Color cc = Color::argb(pal[b]);
      // Graves: los puntos engordan (+30%) y brillan; Golpes los hincha un 20%.
      const float radius = (1.0f + float(b) / 5.0f * step * 0.42f) * 0.5f * (1.0f + graves * 0.3f + golpe * 0.2f);
      // Espuma y Graves: un halo suave sobre las crestas.
      const float haze = foam * 0.13f + graves * 0.14f * f.glow;
      if (haze > 0.001f && b >= 3) {
        Paint halo; halo.blend = Blend::plus;
        halo.color = {cc.r, cc.g, cc.b, std::min(1.0f, haze * float(b - 2))};
        c.points(buckets[b], radius * (1.6f + foam * 1.2f + graves * 0.8f), halo);
      }
      Paint p; p.blend = Blend::plus;
      p.color = {cc.r, cc.g, cc.b, std::min(1.0f, (0.55f + 0.45f * f.music.energy) * f.intensity * (1.0f + graves * 0.5f + golpe * 0.6f))};
      c.points(buckets[b], radius, p);
    }
    if (golpe > 0.001f) {
      // Golpes: un resplandor azul brota del centro, de donde salen las ondas.
      const float flare = std::min(1.0f, 0.4f * golpe * f.glow);
      const float reach = std::min(w, h) * 0.6f;
      Paint burst = Paint::radial({ox, oy}, reach,
        {{0.55f, 0.85f, 1, flare}, {0.3f, 0.6f, 1, flare * 0.35f}, {0.2f, 0.4f, 1, 0}}, {0, 0.4f, 1.0f});
      burst.blend = Blend::plus;
      c.circle({ox, oy}, reach, burst);
    }
    // Golpes: cada onda expansiva lleva un anillo de luz que recorre la malla.
    for (int r = 0; r < live; r++) {
      const float width = step * 3.0f;
      const float outer = ringR[r] + width;
      const float inner = std::max(0.0f, ringR[r] - width) / outer;
      const float a = std::min(1.0f, 0.45f * ringA[r] * f.glow);
      Paint ring = Paint::radial({ox, oy}, outer,
        {{0.5f, 0.85f, 1, 0}, {0.55f, 0.9f, 1, a}, {0.5f, 0.85f, 1, 0}}, {inner, ringR[r] / outer, 1.0f});
      ring.blend = Blend::plus;
      c.circle({ox, oy}, outer, ring);
    }
    if (!glints.empty()) {
      Paint gp; gp.blend = Blend::plus;
      gp.color = {0.6f, 0.9f, 1.0f, std::min(1.0f, agudos * 0.3f * f.glow)};
      c.points(glints, (1.0f + step * 0.12f) * 3.0f, gp);
      gp.color = {0.85f, 0.97f, 1.0f, std::min(1.0f, agudos)};
      c.points(glints, 1.0f + step * 0.14f, gp);
    }
  }
};
''';
