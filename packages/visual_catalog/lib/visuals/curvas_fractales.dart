// Curvas Fractales — una sola línea que llena la pantalla.
// Cuatro curvas famosas que se construyen repitiendo una regla: la curva de
// Hilbert (que pasa por todos los puntos de un cuadrado), la del dragón (la
// que sale al doblar una tira de papel una y otra vez), la de Gosper o copo
// de serpiente y el copo de Koch. Un lápiz de luz traza la curva de principio
// a fin con un degradado de color a lo largo; al terminar, la misma curva se
// redibuja un nivel más fina, y al llegar al nivel máximo pasa a la
// siguiente. El nivel máximo elige qué tres niveles recorre: con 3, curvas
// gruesas y geométricas; con 7, tramas finas que llenan la pantalla. La
// energía acelera el trazo, cada golpe manda un pulso de luz por toda la
// línea y los graves la engordan. Pulso elige qué más hace la música: en
// Golpes cada golpe enciende el trazo entero y su halo, el pulso de luz
// corre más fuerte y ancho y el lápiz destella; en Graves la línea engorda,
// se aviva y su halo respira con los graves; en Agudos la línea parpadea por
// tramos y se llena de chispas sueltas a lo largo del dibujo.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.choice('curva', 'Curva', options: ['Auto', 'Hilbert', 'Dragón', 'Gosper', 'Koch']),
  CreatorModifier.steps('nivel', 'Nivel máximo', min: 3, max: 7, value: 6),
  CreatorModifier.slider('velocidad', 'Velocidad del trazo', min: .3, max: 2.5, value: 1),
  CreatorModifier.slider('grosor', 'Grosor', min: .5, max: 2, value: 1),
  // MÚSICA: qué parte del trazo reacciona.
  CreatorModifier.choice('pulso', 'Pulso', options: ['Golpes', 'Graves', 'Agudos']),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Dragón de Luz', {
    'curva': 'Dragón',
    'nivel': 5,
    'grosor': 1.5,
    'pulso': 'Golpes',
  }),
  CreatorVariation('Trama Fina', {
    'curva': 'Hilbert',
    'nivel': 7,
    'grosor': .7,
    'pulso': 'Agudos',
  }),
];

const nativeSource = r'''
class Visual final : public Scene {
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double phaseTime = 0, pulseAge = 100;
  float pulsePower = 0;
  // Reloj del parpadeo y las chispas de los agudos.
  double shimmer = 0;
  // stage: posición dentro de la ventana de niveles que fija Nivel máximo.
  int autoCurve = 0, stage = 0, builtCurve = -1, builtLevel = -1;
  bool holding = false;
  std::vector<Vec2> pts;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  static float hashU(uint32_t x) {
    x ^= x >> 16; x *= 0x7feb352dU; x ^= x >> 15; x *= 0x846ca68bU; x ^= x >> 16;
    return float(x & 0xffffffu) / 16777216.0f;
  }

  static void hilbert(int order, std::vector<Vec2>& out) {
    int n = 1 << order;
    out.clear();
    for (int d = 0; d < n * n; d++) {
      int x = 0, y = 0, t = d;
      for (int s = 1; s < n; s *= 2) {
        int rx = 1 & (t / 2), ry = 1 & (t ^ rx);
        if (ry == 0) {
          if (rx == 1) {
            x = s - 1 - x;
            y = s - 1 - y;
          }
          std::swap(x, y);
        }
        x += s * rx;
        y += s * ry;
        t /= 4;
      }
      out.push_back({float(x), float(y)});
    }
  }

  static void dragon(int order, std::vector<Vec2>& out) {
    out.clear();
    int x = 0, y = 0, dir = 0;
    static const int dx[4] = {1, 0, -1, 0}, dy[4] = {0, 1, 0, -1};
    out.push_back({0, 0});
    int n = 1 << order;
    for (int i = 1; i <= n; i++) {
      x += dx[dir];
      y += dy[dir];
      out.push_back({float(x), float(y)});
      bool right = (((i & -i) << 1) & i) != 0;
      dir = (dir + (right ? 3 : 1)) % 4;
    }
  }

  // Tortuga para los sistemas L de Gosper y Koch.
  struct Turtle { float x = 0, y = 0, a = 0; };
  static void gosper(int lv, bool isA, Turtle& t, std::vector<Vec2>& out) {
    if (lv == 0) {
      t.x += std::cos(t.a);
      t.y += std::sin(t.a);
      out.push_back({t.x, t.y});
      return;
    }
    const float r = 1.0471976f;
    const char* rule = isA ? "A-B--B+A++AA+B-" : "+A-AA--B-B++A+B";
    for (const char* p = rule; *p; p++) {
      if (*p == 'A') gosper(lv - 1, true, t, out);
      else if (*p == 'B') gosper(lv - 1, false, t, out);
      else if (*p == '+') t.a += r;
      else t.a -= r;
    }
  }
  static void koch(int lv, Turtle& t, std::vector<Vec2>& out) {
    if (lv == 0) {
      t.x += std::cos(t.a);
      t.y += std::sin(t.a);
      out.push_back({t.x, t.y});
      return;
    }
    koch(lv - 1, t, out);
    t.a += 1.0471976f;
    koch(lv - 1, t, out);
    t.a -= 2.0943951f;
    koch(lv - 1, t, out);
    t.a += 1.0471976f;
    koch(lv - 1, t, out);
  }

  // Nivel más fino de cada curva para un Nivel máximo dado.
  static int maxLevel(int curve, int nivel) {
    if (curve == 0 || curve == 1) return std::clamp(nivel, 1, 7);
    if (curve == 2) return std::clamp(nivel - 2, 1, 4);
    return std::clamp(nivel - 1, 1, 6);
  }
  // Ventana que recorre: los tres niveles que terminan en el máximo. Así el
  // ajuste se ve desde el primer trazo, no sólo al final de un ciclo largo.
  static int firstLevel(int curve, int nivel) { return std::max(1, maxLevel(curve, nivel) - 2); }
  static int stages(int curve, int nivel) { return maxLevel(curve, nivel) - firstLevel(curve, nivel) + 1; }
  // El dragón dobla la tira dos veces por nivel.
  static int order(int curve, int lv) { return curve == 1 ? std::max(2, lv * 2) : lv; }
  void buildStage(int curve, int nivel) {
    stage = std::clamp(stage, 0, stages(curve, nivel) - 1);
    build(curve, order(curve, firstLevel(curve, nivel) + stage));
  }

  void build(int curve, int lv) {
    if (curve == builtCurve && lv == builtLevel) return;
    builtCurve = curve;
    builtLevel = lv;
    if (curve == 0) {
      hilbert(lv, pts);
    } else if (curve == 1) {
      dragon(lv, pts);
    } else if (curve == 2) {
      pts.clear();
      Turtle t;
      pts.push_back({0, 0});
      gosper(lv, true, t, pts);
    } else {
      pts.clear();
      Turtle t;
      pts.push_back({0, 0});
      for (int k = 0; k < 3; k++) {
        koch(lv, t, pts);
        t.a -= 2.0943951f;
      }
    }
    // Normaliza al cuadrado [-1, 1] conservando proporciones.
    float minX = 1e9f, maxX = -1e9f, minY = 1e9f, maxY = -1e9f;
    for (auto& p : pts) {
      minX = std::min(minX, p.x);
      maxX = std::max(maxX, p.x);
      minY = std::min(minY, p.y);
      maxY = std::max(maxY, p.y);
    }
    float cx = (minX + maxX) * 0.5f, cy = (minY + maxY) * 0.5f;
    float s = 2.0f / std::max(std::max(maxX - minX, maxY - minY), 1e-3f);
    for (auto& p : pts) p = {(p.x - cx) * s, (p.y - cy) * s};
  }

  double drawTime() const { return 3.2 + 0.6 * double(builtLevel > 0 ? std::min(builtLevel, 7) : 1); }

 public:
  void reset(uint32_t seed) override {
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    phaseTime = 0;
    pulseAge = 100;
    pulsePower = 0;
    shimmer = 0;
    autoCurve = int(seed % 4u);
    stage = 0;
    builtCurve = builtLevel = -1;
    holding = false;
    pts.reserve(20000);
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
    pulseAge += f.delta;
    shimmer += f.delta;
    if (hit > kick + 0.2f) {
      pulseAge = 0;
      pulsePower = hit;
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));

    int curve = m.curva == 0 ? autoCurve : m.curva - 1;
    buildStage(curve, m.nivel);
    phaseTime += f.delta * f.speed * m.velocidad * (1.0 + 1.2 * drive);
    for (int guard = 0; guard < 4; guard++) {
      double length = holding ? 1.4 : drawTime();
      if (phaseTime < length) break;
      phaseTime -= length;
      if (!holding) {
        holding = true;
        continue;
      }
      holding = false;
      if (stage + 1 >= stages(curve, m.nivel)) {
        stage = 0;
        if (m.curva == 0) autoCurve = (autoCurve + 1) % 4;
      } else {
        stage++;
      }
      curve = m.curva == 0 ? autoCurve : m.curva - 1;
      buildStage(curve, m.nivel);
    }
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    auto gl = glide(f);
    float amp = f.intensity;
    // Pulso: cada opción mueve algo distinto; sin música todo vale cero.
    const float wGolpes = gl.pulso.weight(0);
    const float kickP = std::min(kick * amp, 1.0f) * wGolpes;
    const float bassP = std::min(bass * amp, 1.0f) * gl.pulso.weight(1);
    const float sparkP = std::min(spark * amp, 1.0f) * gl.pulso.weight(2);
    const uint32_t tick = uint32_t(std::fmod(shimmer, 100000.0) * 14.0);
    const Color& bg = f.colors[0];
    c.rect({0, 0, f.width, f.height}, Paint::radial({f.width * 0.5f, f.height * 0.5f}, std::max(f.width, f.height) * 0.7f,
                                                   {Color{std::min(1.0f, bg.r + 0.05f), std::min(1.0f, bg.g + 0.02f), std::min(1.0f, bg.b + 0.06f), 1.0f},
                                                    Color{bg.r, bg.g, bg.b, 1.0f}}));
    if (pts.size() < 2) return;
    float side = std::min(f.width, f.height);
    float px = side / 400.0f;
    float half = side * 0.45f;
    Vec2 center{f.width * 0.5f, f.height * 0.5f};
    size_t n = pts.size();
    float prog = holding ? 1.0f : float(std::clamp(phaseTime / drawTime(), 0.0, 1.0));
    prog = prog * prog * (3.0f - 2.0f * prog);
    size_t shown = std::max<size_t>(2, size_t(prog * float(n)));
    float spacing = 2.0f * half / std::sqrt(float(n));
    // Graves: la línea engorda con los graves.
    float width = std::clamp(spacing * 0.32f, 1.0f * px, 6.0f * px) * m.grosor * (1.0f + 0.3f * bass * amp) * (1.0f + 0.45f * bassP);
    const int chunks = 28;
    float wave = pulseAge < 2.5 ? float(pulseAge / 1.6) : 9.0f;
    for (int ch = 0; ch < chunks; ch++) {
      size_t a = n * size_t(ch) / chunks, b = std::min(shown, n * size_t(ch + 1) / chunks + 1);
      if (a >= shown) break;
      Path p;
      for (size_t i = a; i < b; i++) {
        Vec2 q{center.x + pts[i].x * half, center.y + pts[i].y * half};
        if (i == a) p.moveTo(q.x, q.y); else p.lineTo(q.x, q.y);
      }
      float t = float(ch) / float(chunks - 1);
      const Color& c0 = f.colors[1];
      const Color& c1 = f.colors[2];
      const Color& c2 = f.colors[3];
      Color col = t < 0.5f ? Color{c0.r + (c1.r - c0.r) * t * 2.0f, c0.g + (c1.g - c0.g) * t * 2.0f, c0.b + (c1.b - c0.b) * t * 2.0f, 1.0f}
                           : Color{c1.r + (c2.r - c1.r) * (t - 0.5f) * 2.0f, c1.g + (c2.g - c1.g) * (t - 0.5f) * 2.0f, c1.b + (c2.b - c1.b) * (t - 0.5f) * 2.0f, 1.0f};
      // Golpes: el pulso de luz corre más fuerte y más ancho (sin música no hay pulso).
      float pulse = pulsePower * std::exp(-(t - wave) * (t - wave) * (60.0f - 30.0f * wGolpes)) * (1.0f + 0.4f * wGolpes);
      // Golpes enciende el trazo entero; Graves lo aviva; Agudos lo hace parpadear por tramos.
      const float flick = sparkP > 0.002f ? hashU(uint32_t(ch) * 2654435761u + tick * 40503u) : 0.0f;
      float lit = (0.8f + 0.3f * body + 1.2f * pulse) * amp * (1.0f + 0.5f * kickP + 0.25f * bassP + 0.45f * sparkP * flick);
      Paint glow;
      glow.blend = Blend::plus;
      glow.strokeWidth = width * 3.0f + 2.0f * px;
      glow.strokeJoin = 1;
      glow.strokeCap = 1;
      glow.color = col.opacity(std::clamp((0.1f + 0.3f * pulse) * f.glow * amp * (1.0f + 1.2f * kickP + 0.8f * bassP), 0.0f, 1.0f));
      c.path(p, glow);
      Paint line;
      line.strokeWidth = width;
      line.strokeJoin = 1;
      line.strokeCap = 1;
      line.color = Color{std::min(1.0f, col.r * lit + pulse * 0.4f), std::min(1.0f, col.g * lit + pulse * 0.4f), std::min(1.0f, col.b * lit + pulse * 0.4f), 1.0f};
      c.path(p, line);
    }
    // Agudos: chispas sueltas a lo largo del dibujo, unas 160 a la vez.
    if (sparkP > 0.002f) {
      std::vector<Vec2> glints;
      glints.reserve(512);
      const float chance = std::min(0.5f, 160.0f * sparkP / float(shown));
      for (size_t i = 0; i < shown && glints.size() < 512; i++) {
        if (hashU(uint32_t(i) * 2654435761u + tick * 40503u) < chance) glints.push_back({center.x + pts[i].x * half, center.y + pts[i].y * half});
      }
      const Color& c3 = f.colors[3];
      Paint gp;
      gp.blend = Blend::plus;
      gp.color = Color{std::min(1.0f, c3.r * 0.5f + 0.5f), std::min(1.0f, c3.g * 0.5f + 0.5f), std::min(1.0f, c3.b * 0.5f + 0.5f),
                       std::clamp(0.85f * sparkP, 0.0f, 0.9f)};
      c.points(glints, std::max(1.6f * px, width * 0.9f), gp);
    }
    // Lápiz de luz en la punta; Golpes lo hace destellar.
    if (!holding) {
      const Vec2& h = pts[shown - 1];
      Vec2 q{center.x + h.x * half, center.y + h.y * half};
      const float tipR = 16.0f * px * (1.0f + 0.6f * kickP);
      Paint halo = Paint::radial(q, tipR, {f.colors[3].opacity(std::clamp(0.8f * amp, 0.0f, 1.0f)), f.colors[3].opacity(0.0f)});
      halo.blend = Blend::plus;
      c.circle(q, tipR, halo);
      Paint dot;
      dot.color = Color{1.0f, 1.0f, 0.95f, 1.0f};
      c.circle(q, 2.4f * px, dot);
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
