// Cubo Mágico — un cubo de colores que se desordena y se resuelve solo.
// Veintisiete piezas forman un cubo de 3×3×3 con sus seis caras de color.
// El cubo gira despacio en 3D mientras sus capas dan cuartos de vuelta: veinte
// giros lo desordenan y después los mismos giros al revés lo resuelven, con
// un destello al quedar perfecto, y vuelta a empezar con otra mezcla. Cada
// pieza es un cubito negro con pegatinas brillantes y sombreado según la
// luz. Las piezas pueden ir juntas, separadas o flotando sueltas. La energía
// acelera los giros, los graves hacen latir el cubo y cada golpe da un
// empujón al giro de la cámara (y abre las piezas sueltas).
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.slider('velocidad', 'Velocidad de giros', min: .3, max: 2.5, value: 1),
  // FORMA: cubo macizo, cubitos con huecos o cubitos sueltos que flotan.
  CreatorModifier.choice('estilo', 'Piezas', options: ['Juntas', 'Separadas', 'Flotantes']),
  CreatorModifier.slider('giro', 'Giro de cámara', min: 0, max: 2, value: 1),
  CreatorModifier.toggle('brillo', 'Brillo de pegatinas', value: true),
];

const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kMoves = 20;
  static constexpr int kSlots = kMoves * 2 + 6;
  struct Cubie { int p[3]; int o[3]; int r[9]; };
  struct Move { int axis, layer, dir; };
  struct Quad { Vec2 v[4]; float depth; Color color; bool sticker; float light; };
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double moveClock = 0, yaw = 0, clock = 0;
  int64_t applied = 0;
  int cycle = -1;
  uint32_t baseSeed = 1;
  std::array<Cubie, 27> cubes{};
  std::array<Move, kMoves> scramble{};
  mutable std::vector<Quad> quads;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  static void rot90(int axis, int dir, int& x, int& y, int& z) {
    int a = x, b = y, c = z;
    if (axis == 0) { if (dir > 0) { y = -c; z = b; } else { y = c; z = -b; } }
    else if (axis == 1) { if (dir > 0) { x = c; z = -a; } else { x = -c; z = a; } }
    else { if (dir > 0) { x = -b; y = a; } else { x = b; y = -a; } }
  }

  void solved() {
    int k = 0;
    for (int x = -1; x <= 1; x++) {
      for (int y = -1; y <= 1; y++) {
        for (int z = -1; z <= 1; z++) {
          Cubie& c = cubes[size_t(k++)];
          c.p[0] = c.o[0] = x;
          c.p[1] = c.o[1] = y;
          c.p[2] = c.o[2] = z;
          for (int i = 0; i < 9; i++) c.r[i] = (i % 4 == 0) ? 1 : 0;
        }
      }
    }
  }

  void apply(const Move& mv) {
    for (auto& c : cubes) {
      if (c.p[mv.axis] != mv.layer) continue;
      rot90(mv.axis, mv.dir, c.p[0], c.p[1], c.p[2]);
      // Las columnas de la orientación son los ejes propios de la pieza.
      for (int col = 0; col < 3; col++) rot90(mv.axis, mv.dir, c.r[col], c.r[3 + col], c.r[6 + col]);
    }
  }

  void newCycle(int index) {
    cycle = index;
    solved();
    Random rng(baseSeed + uint32_t(index) * 7919u);
    int last = -1;
    for (int i = 0; i < kMoves; i++) {
      int axis;
      do {
        axis = std::min(int(rng.unit() * 3.0f), 2);
      } while (axis == last);
      last = axis;
      scramble[size_t(i)] = {axis, rng.unit() < 0.5f ? -1 : 1, rng.unit() < 0.5f ? -1 : 1};
    }
  }

  // Giro de la casilla s del ciclo: mezcla, pausa, resolución, pausa.
  bool slotMove(int s, Move& mv) const {
    if (s < kMoves) {
      mv = scramble[size_t(s)];
      return true;
    }
    if (s >= kMoves + 2 && s < kMoves * 2 + 2) {
      Move m = scramble[size_t(kMoves - 1 - (s - kMoves - 2))];
      mv = {m.axis, m.layer, -m.dir};
      return true;
    }
    return false;
  }

  static Color faceColor(int axis, int sign) {
    int k = axis * 2 + (sign > 0 ? 0 : 1);
    std::array<Color, 6> pal = {Color{0.92f, 0.08f, 0.1f, 1.0f}, Color{1.0f, 0.5f, 0.0f, 1.0f}, Color{0.96f, 0.96f, 0.93f, 1.0f},
                                Color{1.0f, 0.86f, 0.0f, 1.0f},  Color{0.05f, 0.78f, 0.25f, 1.0f}, Color{0.1f, 0.32f, 1.0f, 1.0f}};
    return pal[size_t(k)];
  }

 public:
  void reset(uint32_t seed) override {
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    baseSeed = seed;
    moveClock = 0;
    yaw = 0.6;
    clock = 0;
    applied = 0;
    newCycle(0);
    quads.reserve(240);
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
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    clock += f.delta * f.speed;
    yaw += f.delta * f.speed * m.giro * (0.35 + 0.5 * drive + 1.5 * kick);
    // Un giro de capa cada 0,45 s a velocidad 1.
    moveClock += f.delta * f.speed * m.velocidad * (2.2 + 2.0 * drive);
    int64_t target = int64_t(std::floor(moveClock + 1e-9));
    while (applied < target) {
      int s = int(applied % kSlots);
      Move mv;
      if (slotMove(s, mv)) apply(mv);
      applied++;
      if (applied % kSlots == 0) newCycle(int(applied / kSlots));
    }
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    auto g = glide(f);
    float amp = f.intensity;
    const Color& bg = f.colors[0];
    c.rect({0, 0, f.width, f.height}, Paint::radial({f.width * 0.5f, f.height * 0.45f}, std::max(f.width, f.height) * 0.7f,
                                                   {Color{std::min(1.0f, bg.r + 0.08f), std::min(1.0f, bg.g + 0.06f), std::min(1.0f, bg.b + 0.09f), 1.0f},
                                                    Color{bg.r, bg.g, bg.b, 1.0f}}));
    int s = int(applied % kSlots);
    // Avance del giro actual medido desde el último giro aplicado en update:
    // así un final justo en el borde de un giro es igual a 30 y a 60 FPS.
    float prog = float(std::clamp(moveClock - double(applied), 0.0, 1.0));
    float anim = std::clamp(prog / 0.7f, 0.0f, 1.0f);
    anim = anim * anim * (3.0f - 2.0f * anim);
    Move mv{0, 9, 1};
    bool moving = slotMove(s, mv);
    float theta = moving ? float(mv.dir) * anim * 1.5707963f : 0.0f;
    float ct = std::cos(theta), st = std::sin(theta);
    auto partial = [&](float& x, float& y, float& z) {
      float a = x, b = y, cc = z;
      if (mv.axis == 0) { y = b * ct - cc * st; z = b * st + cc * ct; }
      else if (mv.axis == 1) { x = a * ct + cc * st; z = -a * st + cc * ct; }
      else { x = a * ct - b * st; y = a * st + b * ct; }
    };
    float cy = float(std::cos(yaw)), sy = float(std::sin(yaw));
    float pitch = -0.55f - 0.12f * float(std::sin(clock * 0.37));
    float cp = std::cos(pitch), sp = std::sin(pitch);
    float side = std::min(f.width, f.height);
    // Piezas: juntas (cubo macizo), separadas (huecos entre cubitos) o
    // flotantes (cubitos sueltos que levitan). Los pesos funden el cambio.
    const float wOpen = g.estilo.weight(1), wFloat = g.estilo.weight(2);
    const float gap = wOpen * 0.32f + wFloat * 0.8f;
    // Con piezas abiertas, los graves y cada golpe las empujan hacia fuera.
    const float push = (wOpen + wFloat) * std::min((0.06f * bass + 0.12f * kick) * amp, 0.25f);
    // El cubo abierto ocupa el mismo lugar que el macizo: las piezas se achican.
    float scale = side * 0.24f * (1.0f + 0.04f * bass * amp) * (1.47f / (1.47f + gap));
    auto toCam = [&](float x, float y, float z, float& X, float& Y, float& Z) {
      float rx = x * cy + z * sy, rz = -x * sy + z * cy;
      X = rx;
      Y = y * cp - rz * sp;
      Z = y * sp + rz * cp;
    };
    auto project = [&](float X, float Y, float Z) {
      float k = 7.0f / (Z + 9.0f);
      return Vec2{f.width * 0.5f + X * k * scale, f.height * 0.5f - Y * k * scale};
    };
    // Celebración: destello al quedar resuelto.
    bool done = s >= kMoves * 2 + 2;
    float celebrate = done ? std::exp(-float(s - (kMoves * 2 + 2)) * 0.6f - prog * 0.6f) : 0.0f;
    quads.clear();
    const float h = 0.47f;
    for (const auto& cu : cubes) {
      bool inLayer = moving && cu.p[mv.axis] == mv.layer;
      // Cada pieza conserva su fase de flotación aunque cambie de sitio.
      const float spread = 1.0f + gap + push;
      const float lift = wFloat * 0.16f * float(std::sin(clock * 1.3 + 1.7 * cu.o[0] + 2.9 * cu.o[1] + 4.3 * cu.o[2]));
      for (int ax = 0; ax < 3; ax++) {
        for (int sg = -1; sg <= 1; sg += 2) {
          // Normal y esquinas en el espacio propio de la pieza.
          for (int pass = 0; pass < 2; pass++) {
            bool sticker = pass == 1;
            if (sticker && cu.o[ax] != sg) continue;
            float inset = sticker ? 0.39f : h, out = sticker ? h + 0.004f : h;
            int a1 = (ax + 1) % 3, a2 = (ax + 2) % 3;
            std::array<float, 3> corner[4];
            float sx[4] = {-1, 1, 1, -1}, sy2[4] = {-1, -1, 1, 1};
            Quad q;
            float zs = 0;
            float nX = 0, nY = 0, nZ = 0;
            {
              float nl[3] = {0, 0, 0};
              nl[ax] = float(sg);
              float wx = float(cu.r[0]) * nl[0] + float(cu.r[1]) * nl[1] + float(cu.r[2]) * nl[2];
              float wy = float(cu.r[3]) * nl[0] + float(cu.r[4]) * nl[1] + float(cu.r[5]) * nl[2];
              float wz = float(cu.r[6]) * nl[0] + float(cu.r[7]) * nl[1] + float(cu.r[8]) * nl[2];
              if (inLayer) partial(wx, wy, wz);
              toCam(wx, wy, wz, nX, nY, nZ);
            }
            float cxw = 0, cyw = 0, czw = 0;
            for (int k = 0; k < 4; k++) {
              float l[3];
              l[ax] = float(sg) * out;
              l[a1] = sx[k] * inset;
              l[a2] = sy2[k] * inset;
              float wx = float(cu.r[0]) * l[0] + float(cu.r[1]) * l[1] + float(cu.r[2]) * l[2] + float(cu.p[0]) * spread;
              float wy = float(cu.r[3]) * l[0] + float(cu.r[4]) * l[1] + float(cu.r[5]) * l[2] + float(cu.p[1]) * spread;
              float wz = float(cu.r[6]) * l[0] + float(cu.r[7]) * l[1] + float(cu.r[8]) * l[2] + float(cu.p[2]) * spread;
              if (inLayer) partial(wx, wy, wz);
              wy += lift;
              float X, Y, Z;
              toCam(wx, wy, wz, X, Y, Z);
              corner[k] = {X, Y, Z};
              cxw += X;
              cyw += Y;
              czw += Z;
              zs += Z;
            }
            // Cara de espaldas a la cámara: no se dibuja.
            float vx = cxw * 0.25f, vy = cyw * 0.25f, vz = czw * 0.25f + 9.0f;
            if (nX * vx + nY * vy + nZ * vz >= 0.0f) continue;
            for (int k = 0; k < 4; k++) q.v[k] = project(corner[k][0], corner[k][1], corner[k][2]);
            q.depth = zs * 0.25f - (sticker ? 0.001f : 0.0f);
            q.sticker = sticker;
            q.light = std::clamp(0.45f + 0.55f * (0.4f * nX + 0.75f * nY - 0.5f * nZ), 0.25f, 1.1f);
            q.color = sticker ? faceColor(ax, sg) : Color{0.05f, 0.05f, 0.06f, 1.0f};
            quads.push_back(q);
          }
        }
      }
    }
    std::sort(quads.begin(), quads.end(), [](const Quad& a, const Quad& b) { return a.depth > b.depth; });
    float lit = (0.9f + 0.2f * kick + 0.5f * celebrate) * amp;
    // Halo de las pegatinas: suave en reposo, se enciende con cada golpe y al resolverse.
    const float halo = std::clamp((0.05f + 0.22f * kick * amp + 0.3f * celebrate) * f.glow, 0.0f, 0.45f);
    for (const auto& q : quads) {
      Path p;
      p.moveTo(q.v[0].x, q.v[0].y).lineTo(q.v[1].x, q.v[1].y).lineTo(q.v[2].x, q.v[2].y).lineTo(q.v[3].x, q.v[3].y).close();
      Paint paint;
      float shade = q.sticker ? q.light * lit : q.light * 0.8f;
      paint.color = Color{std::clamp(q.color.r * shade, 0.0f, 1.0f), std::clamp(q.color.g * shade, 0.0f, 1.0f), std::clamp(q.color.b * shade, 0.0f, 1.0f), 1.0f};
      c.path(p, paint);
      if (q.sticker && halo > 0.005f) {
        Paint glow;
        glow.blend = Blend::plus;
        glow.strokeWidth = 6.0f * side / 400.0f;
        glow.strokeJoin = 1;
        glow.color = q.color.opacity(halo);
        c.path(p, glow);
      }
      if (q.sticker && m.brillo) {
        // Reflejo en una esquina de la pegatina.
        Vec2 a = q.v[0], b = q.v[1], d = q.v[3];
        Path shine;
        shine.moveTo(a.x + (b.x - a.x) * 0.12f + (d.x - a.x) * 0.12f, a.y + (b.y - a.y) * 0.12f + (d.y - a.y) * 0.12f)
            .lineTo(a.x + (b.x - a.x) * 0.45f + (d.x - a.x) * 0.12f, a.y + (b.y - a.y) * 0.45f + (d.y - a.y) * 0.12f)
            .lineTo(a.x + (b.x - a.x) * 0.12f + (d.x - a.x) * 0.45f, a.y + (b.y - a.y) * 0.12f + (d.y - a.y) * 0.45f)
            .close();
        Paint sp;
        sp.blend = Blend::plus;
        sp.color = Color{1.0f, 1.0f, 1.0f, std::clamp(0.18f * q.light * amp, 0.0f, 1.0f)};
        c.path(shine, sp);
      }
    }
    if (celebrate > 0.01f || flash > 0.01f) {
      Paint fl;
      fl.blend = Blend::plus;
      fl.color = f.colors[3].opacity(std::clamp((celebrate * 0.12f + flash * 0.05f) * amp, 0.0f, 1.0f));
      c.rect({0, 0, f.width, f.height}, fl);
    }
  }
};
''';
