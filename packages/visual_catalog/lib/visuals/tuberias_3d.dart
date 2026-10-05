// Tuberías 3D — el salvapantallas de tuberías, rehecho con brillo.
// Dentro de una rejilla invisible de 8×8×8 crecen varios tubos a la vez:
// avanzan en línea recta, a veces giran en un codo con una bola y, si se
// quedan sin salida, aparece otro tubo de otro color en un hueco libre. Cada
// tubo tiene sombreado de cilindro con su reflejo y el tramo nuevo crece de
// forma continua. Cuando el espacio se llena, todo se desvanece y empieza de
// nuevo. La energía acelera el crecimiento, cada golpe da un acelerón y
// enciende los tubos, y la cámara gira despacio alrededor.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.steps('tubos', 'Tubos a la vez', min: 1, max: 6, value: 4),
  CreatorModifier.slider('velocidad', 'Velocidad de crecimiento', min: .4, max: 2.5, value: 1),
  CreatorModifier.slider('grosor', 'Grosor', min: .5, max: 1.6, value: 1),
  CreatorModifier.toggle('giro', 'Cámara girando', value: true),
];

const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kGrid = 8;
  static constexpr int kCells = kGrid * kGrid * kGrid;
  static constexpr int kMaxSegments = 380;
  static constexpr int kMaxPipes = 6;
  // Duración del fundido (segundos del reloj propio) y margen de redondeo del
  // crecimiento: el tramo nuevo usa el mismo margen que decide cuántos hay.
  static constexpr double kClear = 1.4;
  static constexpr double kEps = 1e-6;
  struct Segment { int ax, ay, az, bx, by, bz, color; int64_t step; };
  struct Joint { int x, y, z, color; };
  struct Pipe { int x, y, z, dir, color; bool alive; };
  struct Item { float depth; int index; bool joint; };
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double growth = 0, yaw = 0, clearing = -1;
  int64_t stepsDone = 0;
  int nextColor = 0;
  Random rng{1};
  std::array<uint8_t, kCells> used{};
  std::vector<Segment> segments;
  std::vector<Joint> joints;
  std::array<Pipe, kMaxPipes> pipes{};
  mutable std::vector<Item> items;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  static int cellIndex(int x, int y, int z) { return (z * kGrid + y) * kGrid + x; }
  static bool inside(int x, int y, int z) { return x >= 0 && y >= 0 && z >= 0 && x < kGrid && y < kGrid && z < kGrid; }

  void clearAll() {
    used.fill(0);
    segments.clear();
    joints.clear();
    for (auto& p : pipes) p.alive = false;
  }

  bool spawn(Pipe& p) {
    for (int attempt = 0; attempt < 24; attempt++) {
      int x = int(rng.unit() * kGrid), y = int(rng.unit() * kGrid), z = int(rng.unit() * kGrid);
      x = std::min(x, kGrid - 1);
      y = std::min(y, kGrid - 1);
      z = std::min(z, kGrid - 1);
      if (used[size_t(cellIndex(x, y, z))]) continue;
      used[size_t(cellIndex(x, y, z))] = 1;
      p = {x, y, z, int(rng.unit() * 6.0f) % 6, nextColor, true};
      nextColor = (nextColor + 1) % 4;
      joints.push_back({x, y, z, p.color});
      return true;
    }
    return false;
  }

  void step(int active) {
    static const int dx[6] = {1, -1, 0, 0, 0, 0};
    static const int dy[6] = {0, 0, 1, -1, 0, 0};
    static const int dz[6] = {0, 0, 0, 0, 1, -1};
    stepsDone++;
    for (int i = 0; i < kMaxPipes; i++) {
      Pipe& p = pipes[size_t(i)];
      if (i >= active) {
        p.alive = false;
        continue;
      }
      if (!p.alive) {
        if (int(segments.size()) < kMaxSegments - 20) spawn(p);
        continue;
      }
      auto freeDir = [&](int d) {
        int x = p.x + dx[d], y = p.y + dy[d], z = p.z + dz[d];
        return inside(x, y, z) && !used[size_t(cellIndex(x, y, z))];
      };
      int dir = -1;
      if (freeDir(p.dir) && rng.unit() < 0.7f) {
        dir = p.dir;
      } else {
        int options[6];
        int count = 0;
        for (int d = 0; d < 6; d++) if (freeDir(d)) options[count++] = d;
        if (count > 0) dir = options[std::min(int(rng.unit() * float(count)), count - 1)];
      }
      if (dir < 0) {
        p.alive = false;
        continue;
      }
      if (dir != p.dir) joints.push_back({p.x, p.y, p.z, p.color});
      int nx = p.x + dx[dir], ny = p.y + dy[dir], nz = p.z + dz[dir];
      segments.push_back({p.x, p.y, p.z, nx, ny, nz, p.color, stepsDone});
      used[size_t(cellIndex(nx, ny, nz))] = 1;
      p.x = nx;
      p.y = ny;
      p.z = nz;
      p.dir = dir;
    }
    if (int(segments.size()) >= kMaxSegments) clearing = 0;
  }

 public:
  void reset(uint32_t seed) override {
    rng = Random(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    growth = 0;
    yaw = rng.unit() * 6.2831853;
    clearing = -1;
    stepsDone = 0;
    nextColor = 0;
    segments.reserve(kMaxSegments + kMaxPipes);
    joints.reserve(kMaxSegments + kMaxPipes * 2);
    items.reserve(size_t(kMaxSegments + kMaxPipes) * 3);
    clearAll();
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
    if (m.giro) yaw += f.delta * f.speed * (0.12 + 0.2 * drive);

    // Segundos del reloj propio en este cuadro y tramos por segundo: el
    // crecimiento y el fundido siguen el tiempo, no la cantidad de cuadros.
    double run = f.delta * f.speed;
    const double rate = double(m.velocidad) * (5.0 + 9.0 * drive);
    if (clearing >= 0.0) {
      // Todo se desvanece y la rejilla se vacía para empezar de nuevo.
      clearing += run;
      if (clearing < kClear) return;
      // El fundido termina dentro de este cuadro: lo que sobra ya hace crecer.
      run = clearing - kClear;
      clearing = -1;
      clearAll();
      growth = double(stepsDone);
    }
    growth += run * rate + (beat ? 1.5 * hit : 0.0);
    int64_t target = int64_t(std::floor(growth + kEps));
    if (target - stepsDone > 24) stepsDone = target - 24;
    int active = std::clamp(m.tubos, 1, kMaxPipes);
    while (stepsDone < target) {
      step(active);
      if (clearing < 0.0) continue;
      // La rejilla se llenó en el instante en que growth cruzó este tramo: el
      // crecimiento que sobra en este cuadro ya cuenta como fundido.
      clearing = rate > 1e-9 ? std::clamp((growth - double(stepsDone)) / rate, 0.0, run) : 0.0;
      growth = double(stepsDone);
      break;
    }
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    float amp = f.intensity;
    const Color& bg = f.colors[0];
    c.rect({0, 0, f.width, f.height},
           Paint::radial({f.width * 0.5f, f.height * 0.45f}, std::max(f.width, f.height) * 0.75f,
                         {Color{std::min(1.0f, bg.r + 0.05f), std::min(1.0f, bg.g + 0.05f), std::min(1.0f, bg.b + 0.08f), 1.0f},
                          Color{bg.r, bg.g, bg.b, 1.0f}}));
    std::array<Color, 4> pal = {f.colors[1], f.colors[2], f.colors[3],
                                Color{(f.colors[1].r + f.colors[2].r) * 0.5f, (f.colors[1].g + f.colors[2].g) * 0.5f,
                                      (f.colors[1].b + f.colors[2].b) * 0.5f, 1.0f}};
    float fade = clearing >= 0.0 ? float(std::clamp(1.0 - clearing / kClear, 0.0, 1.0)) : 1.0f;
    float side = std::min(f.width, f.height);
    float scale = side * 0.62f;
    float cyaw = float(std::cos(yaw)), syaw = float(std::sin(yaw));
    const float pitch = 0.42f;
    float cp = std::cos(pitch), sp = std::sin(pitch);
    const float spacing = 2.0f / float(kGrid - 1) * 0.9f;
    auto world = [&](float gx, float gy, float gz) {
      float h = float(kGrid - 1) * 0.5f;
      return std::array<float, 3>{(gx - h) * spacing, (gy - h) * spacing, (gz - h) * spacing};
    };
    struct Proj { float x, y, depth, s; };
    auto project = [&](float gx, float gy, float gz) {
      auto w = world(gx, gy, gz);
      float x = w[0] * cyaw + w[2] * syaw;
      float z = -w[0] * syaw + w[2] * cyaw;
      float y = w[1] * cp - z * sp;
      float zz = w[1] * sp + z * cp;
      float s = 2.6f / (3.6f + zz);
      return Proj{f.width * 0.5f + x * s * scale, f.height * 0.5f - y * s * scale, zz, s};
    };
    // Cuánto ha crecido el tramo nuevo, con el mismo margen que decidió crearlo:
    // así un crecimiento de 49.9999999 o 50.0000001 dibuja lo mismo.
    float frac = float(std::clamp(growth + kEps - double(stepsDone), 0.0, 1.0));
    float tube = 0.055f * m.grosor * (1.0f + 0.12f * bass * amp);
    float lit = (1.0f + 0.45f * kick * amp) * fade;

    items.clear();
    for (size_t i = 0; i < segments.size(); i++) {
      const Segment& s = segments[i];
      Proj a = project(float(s.ax), float(s.ay), float(s.az));
      Proj b = project(float(s.bx), float(s.by), float(s.bz));
      items.push_back({(a.depth + b.depth) * 0.5f, int(i), false});
    }
    for (size_t i = 0; i < joints.size(); i++) {
      const Joint& j = joints[i];
      items.push_back({project(float(j.x), float(j.y), float(j.z)).depth - 0.001f, int(i), true});
    }
    std::sort(items.begin(), items.end(), [](const Item& l, const Item& r) { return l.depth > r.depth; });

    auto shade = [&](const Color& col, float g) {
      return Color{std::min(1.0f, col.r * g), std::min(1.0f, col.g * g), std::min(1.0f, col.b * g), fade};
    };
    for (const Item& it : items) {
      if (it.joint) {
        const Joint& j = joints[size_t(it.index)];
        Proj p = project(float(j.x), float(j.y), float(j.z));
        float r = tube * 1.3f * p.s * scale;
        const Color& col = pal[size_t(j.color)];
        Paint ball = Paint::radial({p.x - r * 0.35f, p.y - r * 0.4f}, r * 1.5f,
                                   {shade(Color{1, 1, 1, 1}, 0.95f * lit), shade(col, 1.0f * lit), shade(col, 0.25f)}, {0.0f, 0.3f, 1.0f});
        c.circle({p.x, p.y}, r, ball);
        continue;
      }
      const Segment& s = segments[size_t(it.index)];
      float t = s.step == stepsDone && clearing < 0.0 ? frac : 1.0f;
      Proj a = project(float(s.ax), float(s.ay), float(s.az));
      Proj b = project(float(s.ax) + float(s.bx - s.ax) * t, float(s.ay) + float(s.by - s.ay) * t,
                       float(s.az) + float(s.bz - s.az) * t);
      float w = tube * 2.0f * (a.s + b.s) * 0.5f * scale;
      float ddx = b.x - a.x, ddy = b.y - a.y;
      float len = std::sqrt(ddx * ddx + ddy * ddy);
      float nx = len > 1e-3f ? -ddy / len : 1.0f, ny = len > 1e-3f ? ddx / len : 0.0f;
      Vec2 mid{(a.x + b.x) * 0.5f, (a.y + b.y) * 0.5f};
      const Color& col = pal[size_t(s.color)];
      // Sombreado de cilindro: borde oscuro, color, reflejo claro y borde.
      Paint pipe = Paint::linear({mid.x - nx * w * 0.5f, mid.y - ny * w * 0.5f}, {mid.x + nx * w * 0.5f, mid.y + ny * w * 0.5f},
                                 {shade(col, 0.25f), shade(col, 0.9f * lit), shade(Color{1, 1, 1, 1}, 0.9f * lit), shade(col, 0.8f * lit), shade(col, 0.18f)},
                                 {0.0f, 0.28f, 0.4f, 0.6f, 1.0f});
      pipe.strokeWidth = w;
      pipe.strokeCap = 1;
      Path p;
      p.moveTo(a.x, a.y).lineTo(b.x, b.y);
      c.path(p, pipe);
    }
    if (flash > 0.01f) {
      Paint fl;
      fl.blend = Blend::plus;
      fl.color = f.colors[2].opacity(std::clamp(flash * 0.05f * amp, 0.0f, 1.0f));
      c.rect({0, 0, f.width, f.height}, fl);
    }
  }
};
''';
