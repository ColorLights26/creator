// Círculo Trap — el visualizador circular de los canales de música.
// Alrededor de un disco central se apilan varias ondas circulares de colores:
// cada una dibuja el espectro de la música en espejo (graves arriba, agudos
// abajo) y las de atrás llegan un instante más tarde, así el círculo deja un
// rastro de colores que se despliega con cada golpe. Los graves hacen
// temblar la pantalla y crecer el disco, y las partículas salen despedidas
// del centro más rápido cuanta más energía hay. Sin música, el círculo
// respira con una onda tranquila. Con remolino, las capas se abren en abanico
// y se mecen con retraso, sus picos se curvan como aspas y las partículas
// salen en espiral.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.steps('capas', 'Capas de onda', min: 2, max: 6, value: 5),
  // MOVIMIENTO: de ondas alineadas y quietas a un abanico que se mece.
  CreatorModifier.slider('remolino', 'Remolino', min: 0, max: 1, value: 0),
  CreatorModifier.toggle('temblor', 'Temblor de pantalla', value: true),
  CreatorModifier.toggle('particulas', 'Partículas', value: true),
];

const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kLayers = 6;
  static constexpr int kBins = 32;
  static constexpr int kParticles = 150;
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  std::array<std::array<float, kBins>, kLayers> layers{};
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double clock = 0, rise = 0, sway = 0;
  bool live = false;
  std::array<float, kParticles> pAngle{}, pSpeed{}, pPhase{}, pSize{};

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  // Onda tranquila sin música, calculada directamente del tiempo.
  static float idle(int i, double t) {
    return 0.18f + 0.1f * float(std::sin(t * 1.7 + double(i) * 0.45)) * float(std::sin(t * 0.6 + double(i) * 0.21)) +
           0.08f * float(std::sin(t * 3.1 + double(i) * 0.9));
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    for (auto& l : layers) l.fill(0);
    clock = 0;
    rise = 0;
    sway = 0;
    live = false;
    for (int i = 0; i < kParticles; i++) {
      pAngle[size_t(i)] = rng.unit() * 6.2831853f;
      pSpeed[size_t(i)] = 0.15f + 0.35f * rng.unit();
      pPhase[size_t(i)] = rng.unit();
      pSize[size_t(i)] = 0.6f + 1.4f * rng.unit();
    }
  }

  void update(const Frame& f) override {
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
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    clock += f.delta * f.speed;
    rise += f.delta * f.speed * (1.0 + 2.5 * drive + 2.0 * kick);
    sway = std::fmod(sway + f.delta * f.speed * 0.9, 6.283185307179586);
    live = mu.active;
    if (mu.active) {
      // Cada capa sigue a la anterior con retraso: el círculo deja un rastro.
      for (int i = 0; i < kBins; i++) {
        float v = mu.smoothSpectrum[size_t(std::min(i, 30))];
        layers[0][size_t(i)] = follow(layers[0][size_t(i)], v, 30.0f, 8.0f, dt);
      }
      for (int l = 1; l < kLayers; l++) {
        for (int i = 0; i < kBins; i++) layers[size_t(l)][size_t(i)] = follow(layers[size_t(l)][size_t(i)], layers[size_t(l - 1)][size_t(i)], 9.0f, 6.0f, dt);
      }
    }
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    auto gl = glide(f);
    float amp = f.intensity;
    const Color& bg = f.colors[0];
    float side = std::min(f.width, f.height);
    float px = side / 400.0f;
    float shakeX = 0, shakeY = 0;
    if (m.temblor) {
      float a = bass * bass * 7.0f * px * amp + kick * 4.0f * px * amp;
      shakeX = a * float(std::sin(clock * 37.0));
      shakeY = a * float(std::cos(clock * 43.0));
    }
    Vec2 center{f.width * 0.5f + shakeX, f.height * 0.5f + shakeY};
    int n = std::clamp(m.capas, 2, kLayers);
    // De delante hacia atrás: los acentos de la paleta y el primero cada vez
    // más oscuro, así el rastro se hunde en el fondo.
    auto dim = [](const Color& col, float k) { return Color{col.r * k, col.g * k, col.b * k, 1.0f}; };
    const std::array<Color, kLayers> pal = {f.colors[3], f.colors[2], f.colors[1],
                                            dim(f.colors[1], 0.85f), dim(f.colors[1], 0.55f), dim(f.colors[1], 0.35f)};
    // Remolino: cada capa gira un poco más que la de delante y se mece con
    // retraso, y lo que sobresale de cada onda se curva hacia un lado; a 0
    // todas quedan alineadas como el visualizador clásico.
    const float swirl = gl.remolino;
    auto twist = [&](int l) { return swirl * (0.6f * float(l) + 0.35f * float(std::sin(sway + 0.7 * double(l)))); };
    // Fondo con resplandor del color principal y rayos tenues que giran.
    c.rect({0, 0, f.width, f.height}, Paint::radial(center, std::max(f.width, f.height) * 0.75f,
                                                   {Color{std::min(1.0f, bg.r + pal[2].r * 0.12f * (1.0f + bass)), std::min(1.0f, bg.g + pal[2].g * 0.06f * (1.0f + bass)),
                                                          std::min(1.0f, bg.b + pal[2].b * 0.06f), 1.0f},
                                                    Color{bg.r, bg.g, bg.b, 1.0f}}));
    float R = side * 0.2f * (1.0f + 0.1f * bass * amp + 0.05f * kick * amp);
    if (m.particulas) {
      std::array<std::vector<Vec2>, 3> groups;
      for (auto& g : groups) g.reserve(kParticles / 3 + 1);
      float reach = std::max(f.width, f.height) * 0.7f;
      for (int i = 0; i < kParticles; i++) {
        float life = float(std::fmod(rise * double(pSpeed[size_t(i)]) + double(pPhase[size_t(i)]), 1.0));
        float r = R * 1.05f + life * life * reach;
        // Con remolino salen en espiral: el ángulo avanza con la distancia.
        float a = pAngle[size_t(i)] + float(clock * 0.05) + swirl * 1.6f * life;
        groups[size_t(i % 3)].push_back({center.x + r * std::cos(a), center.y + r * std::sin(a)});
      }
      for (int g = 0; g < 3; g++) {
        Paint p;
        p.blend = Blend::plus;
        p.color = pal[size_t(1 + g)].opacity(std::clamp((0.35f + 0.4f * spark) * amp, 0.0f, 1.0f));
        c.points(groups[size_t(g)], (1.2f + 0.8f * float(g)) * px, p);
      }
    }
    // Ondas de atrás hacia delante.
    const int samples = 72;
    for (int l = n - 1; l >= 0; l--) {
      Path p;
      const float turn = twist(l);
      for (int k = 0; k <= samples * 2; k++) {
        float u = float(k) / float(samples * 2);
        float a = -1.5707963f + u * 6.2831853f + turn;
        float mirror = 1.0f - std::fabs(1.0f - 2.0f * u);
        float pos = mirror * float(kBins - 1) * 0.85f;
        int i0 = int(pos);
        float fr = pos - float(i0);
        int i1 = std::min(i0 + 1, kBins - 1);
        float v0, v1;
        if (live) {
          v0 = layers[size_t(l)][size_t(i0)];
          v1 = layers[size_t(l)][size_t(i1)];
        } else {
          v0 = idle(i0, clock - 0.08 * double(l));
          v1 = idle(i1, clock - 0.08 * double(l));
        }
        float v = (v0 + (v1 - v0) * fr) * amp;
        float bulge = std::max(v * (1.0f + 0.22f * float(l)), 0.0f);
        float r = R * (1.02f + 0.07f * float(l)) + side * 0.2f * bulge;
        // Cuanto más sobresale, más se curva (hasta ~1 radián).
        a += swirl * 1.1f * bulge / (0.5f + bulge);
        float x = center.x + r * std::cos(a), y = center.y + r * std::sin(a);
        if (k == 0) p.moveTo(x, y); else p.lineTo(x, y);
      }
      p.close();
      Paint fill;
      const Color& col = pal[size_t(std::min(l, kLayers - 1))];
      fill.color = col;
      c.path(p, fill);
      if (l == 0) {
        // Borde blanco fino en la onda de delante.
        Paint edge;
        edge.strokeWidth = 2.0f * px;
        edge.strokeJoin = 1;
        edge.color = Color{1.0f, 1.0f, 1.0f, std::clamp(0.85f * amp, 0.0f, 1.0f)};
        c.path(p, edge);
      }
    }
    // Disco central oscuro con aros que laten.
    Paint disc = Paint::radial(center, R, {Color{bg.r * 0.6f + 0.06f, bg.g * 0.6f + 0.03f, bg.b * 0.6f + 0.04f, 1.0f}, Color{bg.r, bg.g, bg.b, 1.0f}});
    c.circle(center, R, disc);
    Paint ring;
    ring.strokeWidth = (2.5f + 3.0f * kick) * px;
    ring.color = pal[0].opacity(std::clamp(0.9f * amp, 0.0f, 1.0f));
    Path rp;
    rp.circle(center, R);
    c.path(rp, ring);
    Paint inner;
    inner.blend = Blend::plus;
    inner.strokeWidth = 1.5f * px;
    inner.color = pal[2].opacity(std::clamp((0.25f + 0.5f * bass) * amp, 0.0f, 1.0f));
    Path ip;
    ip.circle(center, R * (0.55f + 0.25f * float(std::fmod(rise * 0.4, 1.0))));
    c.path(ip, inner);
    if (flash > 0.01f) {
      Paint fl;
      fl.blend = Blend::plus;
      fl.color = pal[2].opacity(std::clamp(flash * 0.06f * amp, 0.0f, 1.0f));
      c.rect({0, 0, f.width, f.height}, fl);
    }
  }
};
''';
