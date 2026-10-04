// Nudo Toroidal — un tubo de neón anudado que gira en 3D.
// Un nudo toroidal (p, q) da p vueltas alrededor del eje y q alrededor del
// tubo de un toro. Se dibuja como un tubo con sombreado de cilindro, tramo a
// tramo de atrás hacia delante para que los cruces se tapen bien, con
// franjas rojas sobre amarillo que corren a lo largo del nudo y un halo
// naranja detrás. El nudo gira despacio en 3D; los graves engordan el tubo,
// la energía acelera las franjas, cada golpe las enciende y en Auto el nudo
// se transforma en otro (2·3, 3·5, 2·5, 3·7 o 5·8) cada ocho golpes.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.choice('nudo', 'Nudo', options: ['Auto', '2·3', '3·5', '2·5', '3·7', '5·8']),
  CreatorModifier.slider('grosor', 'Grosor del tubo', min: .5, max: 1.8, value: 1),
  CreatorModifier.slider('giro', 'Velocidad de giro', min: 0, max: 2, value: 1),
  CreatorModifier.toggle('franjas', 'Franjas', value: true),
];

const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kSamples = 220;
  struct Item { float depth; int index; };
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double yaw = 0, pitch = 0, flow = 0, morph = 1, sinceKnot = 0;
  int knotFrom = 0, knotTo = 0, autoKnot = 0, beats = 0;
  mutable std::vector<Item> items;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  static std::array<float, 3> knot(int kind, float t) {
    static const float ps[5] = {2, 3, 2, 3, 5};
    static const float qs[5] = {3, 5, 5, 7, 8};
    float p = ps[kind], q = qs[kind];
    float r = 0.62f + 0.3f * std::cos(q * t);
    return {r * std::cos(p * t), 0.3f * std::sin(q * t), r * std::sin(p * t)};
  }

  void goTo(int next) {
    if (next == knotTo) return;
    knotFrom = knotTo;
    knotTo = next;
    morph = 0;
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    yaw = rng.unit() * 6.2831853;
    pitch = 0;
    flow = 0;
    morph = 1;
    sinceKnot = 0;
    knotFrom = knotTo = autoKnot = 0;
    beats = 0;
    items.reserve(kSamples);
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
    sinceKnot += f.delta;
    if (hit > kick + 0.2f) {
      beats++;
      if (beats % 8 == 0) {
        autoKnot = (autoKnot + 1) % 5;
        sinceKnot = 0;
      }
    }
    if (!mu.active && sinceKnot > 8.0) {
      autoKnot = (autoKnot + 1) % 5;
      sinceKnot -= 8.0;
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    goTo(m.nudo == 0 ? autoKnot : m.nudo - 1);
    morph = std::min(morph + f.delta / 1.8, 1.0);
    yaw += f.delta * f.speed * m.giro * (0.25 + 0.5 * drive);
    pitch += f.delta * f.speed * m.giro * 0.17;
    flow += f.delta * f.speed * (0.5 + 1.5 * drive + 1.0 * kick);
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    float amp = f.intensity;
    const Color& bg = f.colors[0];
    const Color& yellow = f.colors[1];
    const Color& red = f.colors[2];
    const Color& orange = f.colors[3];
    c.rect({0, 0, f.width, f.height},
           Paint::radial({f.width * 0.5f, f.height * 0.5f}, std::max(f.width, f.height) * 0.7f,
                         {Color{std::min(1.0f, bg.r + orange.r * 0.09f * (1.0f + bass)), std::min(1.0f, bg.g + orange.g * 0.05f),
                                std::min(1.0f, bg.b + 0.01f), 1.0f},
                          Color{bg.r, bg.g, bg.b, 1.0f}}));
    float side = std::min(f.width, f.height);
    float scale = side * 0.66f;
    float cy = float(std::cos(yaw)), sy = float(std::sin(yaw));
    float tilt = 0.5f + 0.35f * float(std::sin(pitch));
    float cp = std::cos(tilt), sp = std::sin(tilt);
    float mo = float(morph);
    mo = mo * mo * (3.0f - 2.0f * mo);
    struct P { float x, y, z, s; };
    std::array<P, kSamples + 1> pts{};
    for (int i = 0; i <= kSamples; i++) {
      float t = 6.2831853f * float(i) / float(kSamples);
      auto a = knot(knotFrom, t);
      auto b = knot(knotTo, t);
      float x = a[0] + (b[0] - a[0]) * mo, y = a[1] + (b[1] - a[1]) * mo, z = a[2] + (b[2] - a[2]) * mo;
      float rx = x * cy + z * sy, rz = -x * sy + z * cy;
      float ry = y * cp - rz * sp;
      float rzz = y * sp + rz * cp;
      float s = 2.4f / (3.0f + rzz);
      pts[size_t(i)] = {f.width * 0.5f + rx * s * scale, f.height * 0.5f - ry * s * scale, rzz, s};
    }
    // Halo naranja detrás de todo el nudo.
    Path whole;
    for (int i = 0; i <= kSamples; i++) {
      if (i == 0) whole.moveTo(pts[0].x, pts[0].y); else whole.lineTo(pts[size_t(i)].x, pts[size_t(i)].y);
    }
    float tube = 0.075f * m.grosor * (1.0f + 0.25f * bass * amp);
    Paint halo;
    halo.blend = Blend::plus;
    halo.strokeWidth = tube * scale * 2.4f * 2.2f;
    halo.strokeJoin = 1;
    halo.color = orange.opacity(std::clamp((0.045f + 0.07f * bass) * f.glow * amp, 0.0f, 1.0f));
    c.path(whole, halo);

    items.clear();
    for (int i = 0; i < kSamples; i++) items.push_back({(pts[size_t(i)].z + pts[size_t(i + 1)].z) * 0.5f, i});
    std::sort(items.begin(), items.end(), [](const Item& l, const Item& r) { return l.depth > r.depth; });
    float stripes = 14.0f;
    float lit = (1.0f + 0.35f * kick) * amp;
    for (const Item& it : items) {
      const P& a = pts[size_t(it.index)];
      const P& b = pts[size_t(it.index + 1)];
      float w = tube * 2.0f * (a.s + b.s) * 0.5f * scale;
      float dx = b.x - a.x, dy = b.y - a.y;
      float len = std::sqrt(dx * dx + dy * dy);
      float nx = len > 1e-3f ? -dy / len : 1.0f, ny = len > 1e-3f ? dx / len : 0.0f;
      Vec2 mid{(a.x + b.x) * 0.5f, (a.y + b.y) * 0.5f};
      float u = float(it.index) / float(kSamples) * stripes - float(std::fmod(flow, 1000.0));
      bool isRed = m.franjas && (u - std::floor(u)) < 0.35f;
      const Color& base = isRed ? red : yellow;
      // Lo lejano se ve más oscuro.
      float depthShade = std::clamp(1.05f - (a.z + b.z) * 0.35f, 0.45f, 1.2f) * lit;
      auto shade = [&](float g) {
        return Color{std::min(1.0f, base.r * g * depthShade), std::min(1.0f, base.g * g * depthShade),
                     std::min(1.0f, base.b * g * depthShade), 1.0f};
      };
      Color shine{std::min(1.0f, 0.9f * depthShade + 0.1f), std::min(1.0f, 0.85f * depthShade + 0.1f), std::min(1.0f, 0.7f * depthShade), 1.0f};
      Paint p = Paint::linear({mid.x - nx * w * 0.5f, mid.y - ny * w * 0.5f}, {mid.x + nx * w * 0.5f, mid.y + ny * w * 0.5f},
                              {shade(0.22f), shade(0.95f), shine, shade(0.85f), shade(0.15f)}, {0.0f, 0.3f, 0.42f, 0.6f, 1.0f});
      p.strokeWidth = w;
      p.strokeCap = 1;
      Path seg;
      seg.moveTo(a.x, a.y).lineTo(b.x, b.y);
      c.path(seg, p);
    }
    if (flash > 0.01f) {
      Paint fl;
      fl.blend = Blend::plus;
      fl.color = orange.opacity(std::clamp(flash * 0.05f * amp, 0.0f, 1.0f));
      c.rect({0, 0, f.width, f.height}, fl);
    }
  }
};
''';
