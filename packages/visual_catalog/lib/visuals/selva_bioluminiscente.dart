// Selva Bioluminiscente — un bosque de noche que brilla con luz propia.
// Al fondo, troncos lejanos y una niebla verde que se mueve despacio,
// atravesada por rayos de luna. Delante, árboles de ramas retorcidas que se
// estrechan hasta las puntas, cubiertos de hojas que brillan en verde menta
// y esmeralda; en el suelo, helechos con el borde encendido y setas de un
// ámbar intenso. Esporas que suben, luciérnagas que se encienden y se
// apagan, y ramas que cuelgan desde arriba. Todo cabe en la pantalla
// vertical: los árboles se ajustan al alto y al ancho al nacer.
// Música: con Golpes, cada golpe enciende las setas y lanza un pulso de luz
// que sube desde las raíces por todas las ramas hasta las hojas, que
// destellan al recibirlo, y la niebla se ilumina a su paso. Con Graves, el
// brillo de hojas, setas y niebla respira con los graves. Con Agudos, las
// esporas y las puntas de las ramas centellean y las luciérnagas parpadean.
// Sin música, cada pocos segundos un pulso suave recorre el bosque.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // FORMA: qué brilla en las ramas.
  CreatorModifier.choice(
    'flora',
    'Flora',
    options: ['Hojas', 'Lianas', 'Flores'],
  ),
  // MOVIMIENTO: bosque quieto o doblado y mecido por el viento.
  CreatorModifier.slider('viento', 'Viento', min: 0, max: 3, value: 1),
  // MÚSICA
  CreatorModifier.choice(
    'pulso',
    'Pulso',
    options: ['Golpes', 'Graves', 'Agudos'],
  ),
  // ATMÓSFERA: de una noche clara a una niebla luminosa espesa.
  CreatorModifier.slider('niebla', 'Niebla', min: 0, max: 1, value: .45),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Sauce Lunar', {
    'flora': 'Lianas',
    'viento': 2.2,
    'niebla': .75,
    'pulso': 'Graves',
  }),
  CreatorVariation('Jardín de Flores', {
    'flora': 'Flores',
    'viento': .4,
    'niebla': .2,
    'pulso': 'Agudos',
    'speed': 1.3,
  }),
];

const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kPts = 9;
  static constexpr int kPulses = 4;
  static constexpr int kMotes = 160;
  static constexpr int kFlies = 32;
  // Rama: polilínea de hasta 8 tramos que se estrecha de w0 a w1.
  struct Limb {
    int parent = -1, at = 0, segs = 6, depth = 0, tree = 0, hue = 0;
    bool root = false;
    float rel = 0, len = 0, w0 = 0, w1 = 0, curl = 0, phase = 0, dist = 0;
    std::array<float, 8> kink{};
  };
  // layer 0: árboles del fondo; layer 1: árboles principales.
  struct Tree { float x = 0, lean = 0, scale = 1, reach = 0.5f; int layer = 0, depth = 3, first = 0, last = 0; };
  struct Liana { int limb = 0, at = 0; float len = 0, phase = 0; };
  struct Shroom { float x = 0, size = 0, lean = 0; int hue = 0; };
  // Helecho o rama colgante: up = 1 nace del suelo, up = -1 cuelga de arriba.
  struct Frond { float x = 0, dir = 1, len = 0, phase = 0, up = 1; };
  struct Mote { float x = 0, y = 0, speed = 0, phase = 0, drift = 0; };
  struct Fly { float cx = 0, cy = 0, ax = 0, ay = 0, fx = 0, fy = 0, phase = 0, rate = 0; };
  std::vector<Limb> limbs;
  std::vector<Tree> trees;
  std::vector<Liana> lianas;
  std::vector<Shroom> shrooms;
  std::vector<Frond> fronds;
  std::vector<Mote> motes;
  std::vector<Fly> flies;
  // Memoria de trabajo: posición y dirección de cada punto de cada rama.
  mutable std::vector<Vec2> pts;
  mutable std::vector<float> dirs;
  // Memoria de trabajo de los puntos de luz (ver dots()) y listas de puntos
  // de cada frame: se vacían y se reutilizan, sin pedir memoria nueva.
  mutable std::vector<int> dotOrder;
  mutable std::vector<char> dotAlone;
  mutable float viewW = 1, viewH = 1;
  mutable std::vector<Vec2> dotKeep, dotTips, tipsAt[3], hotAt, twinkleAt, beadsAt, litBeadsAt, fernTipsAt, motesAt[3][2], sparksAt, flyAt;
  // Música estándar: envolventes y golpe corto (valen 0 sin música).
  float bass = 0, body = 0, spark = 0, slowBass = 0, kick = 0, flash = 0;
  // Relojes en doble precisión: igual a 30 y 60 FPS.
  double clock = 0, secs = 0;
  // Pulsos de luz de los golpes: anillo fijo de ranuras {inicio, fuerza}.
  std::array<double, kPulses> pulseAt{};
  std::array<float, kPulses> pulsePow{};
  int nextPulse = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }
  static Color mixc(Color a, Color b, float k) {
    return {a.r + (b.r - a.r) * k, a.g + (b.g - a.g) * k, a.b + (b.b - a.b) * k, 1.0f};
  }
  static Paint light(Color c, float a) {
    Paint p;
    p.blend = Blend::plus;
    p.color = c.opacity(std::clamp(a, 0.0f, 1.0f));
    return p;
  }
  // Un punto de luz de pocos píxeles: dos medias vueltas cúbicas (la
  // diferencia con un círculo exacto es menor de una décima de píxel).
  static void dot(Path& path, Vec2 c, float r) {
    const float k = r * 1.3333333f;
    path.moveTo(c.x + r, c.y);
    path.cubicTo(c.x + r, c.y + k, c.x - r, c.y + k, c.x - r, c.y);
    path.cubicTo(c.x - r, c.y - k, c.x + r, c.y - k, c.x + r, c.y);
    path.close();
  }
  void dot(Canvas& c, Vec2 at, float r, const Paint& p) const {
    Path one;
    dot(one, at, r);
    c.path(one, p);
  }
  // Puntos de luz (suma) como círculos dentro de la tanda de trazos: cada
  // llamada a points() era una pasada entera de GPU. Los puntos que no
  // tocan a otro van juntos en un solo trazo; los que se tocan van sueltos
  // para que su luz se siga sumando como antes.
  void dots(Canvas& c, const std::vector<Vec2>& all, float r, const Paint& p) const {
    if (all.empty() || r <= 0.0f || p.color.a <= 0.0f) return;
    // Sólo los que caen en pantalla: fuera no pintan ni un píxel.
    dotKeep.clear();
    for (const Vec2& q : all)
      if (q.x > -r - 1.0f && q.x < viewW + r + 1.0f && q.y > -r - 1.0f && q.y < viewH + r + 1.0f) dotKeep.push_back(q);
    const std::vector<Vec2>& at = dotKeep;
    const size_t n = at.size();
    if (n == 0) return;
    dotOrder.resize(n);
    for (size_t i = 0; i < n; i++) dotOrder[i] = int(i);
    std::sort(dotOrder.begin(), dotOrder.end(), [&](int a, int b) { return at[size_t(a)].x < at[size_t(b)].x; });
    dotAlone.assign(n, 1);
    const float reach = 2.0f * r + 1.0f;
    for (size_t i = 0; i < n; i++) {
      const Vec2 a = at[size_t(dotOrder[i])];
      for (size_t j = i + 1; j < n; j++) {
        const Vec2 b = at[size_t(dotOrder[j])];
        const float dx = b.x - a.x, dy = b.y - a.y;
        if (dx >= reach) break;
        if (dx * dx + dy * dy < reach * reach) dotAlone[size_t(dotOrder[i])] = dotAlone[size_t(dotOrder[j])] = 0;
      }
    }
    Path group;
    for (size_t i = 0; i < n; i++) {
      if (dotAlone[i]) dot(group, at[i], r);
      else dot(c, at[i], r, p);
    }
    if (!group.data().empty()) c.path(group, p);
  }

  // Hoja (o pétalo) en coordenadas de pantalla: base, ángulo (y hacia arriba).
  static void leaf(Path& path, Vec2 b, float a, float len, float wid) {
    const float dx = std::cos(a), dy = -std::sin(a);
    const Vec2 tip{b.x + dx * len, b.y + dy * len};
    const Vec2 mid{b.x + dx * len * 0.45f, b.y + dy * len * 0.45f};
    path.moveTo(b.x, b.y);
    path.quadraticTo(mid.x - dy * wid, mid.y + dx * wid, tip.x, tip.y);
    path.quadraticTo(mid.x + dy * wid, mid.y - dx * wid, b.x, b.y);
    path.close();
  }

  // Crece una rama y sus hijas (en unidades del árbol).
  void grow(Random& rng, int tree, int parent, int at, float rel, float len, float w0, int depth, int maxDepth) {
    Limb L;
    L.parent = parent; L.at = at; L.depth = depth; L.tree = tree; L.rel = rel; L.len = len; L.w0 = w0;
    L.segs = depth == 0 ? 8 : (depth >= 3 ? 4 : 6);
    L.w1 = w0 * (depth >= maxDepth ? 0.15f : 0.45f);
    L.curl = (rng.unit() - 0.5f) * 0.08f;
    for (auto& k : L.kink) k = (rng.unit() - 0.5f) * 0.14f;
    L.phase = rng.unit() * 6.2831853f;
    L.hue = std::min(2, int(rng.unit() * 3.0f));
    if (parent >= 0) {
      const Limb& P = limbs[size_t(parent)];
      L.dist = P.dist + P.len * float(at) / float(P.segs);
    }
    const int me = int(limbs.size());
    limbs.push_back(L);
    if (depth >= maxDepth) return;
    const int kids = depth == 0 ? 5 : (depth >= 2 ? 2 : 3);
    const float flip = rng.unit() < 0.5f ? 1.0f : -1.0f;
    for (int k = 0; k < kids; k++) {
      const bool leader = k == kids - 1;
      const float frac = depth == 0 ? 0.42f + 0.58f * float(k + 1) / float(kids)
                                    : 0.35f + 0.65f * float(k + 1) / float(kids);
      const int a = std::clamp(int(std::lround(frac * float(L.segs))), 1, L.segs);
      const float side = (k % 2 == 0 ? 1.0f : -1.0f) * flip;
      const float angle = leader ? side * (0.1f + 0.12f * rng.unit()) : side * (0.45f + 0.35f * rng.unit());
      const float shrink = depth == 0 ? (1.1f - 0.45f * frac) : (0.95f - 0.25f * frac);
      const float childLen = len * (depth == 0 ? 0.42f + 0.14f * rng.unit() : 0.55f + 0.2f * rng.unit()) * shrink;
      const float wAt = w0 + (L.w1 - w0) * float(a) / float(L.segs);
      grow(rng, tree, me, a, angle, childLen, wAt * 0.68f, depth + 1, maxDepth);
    }
  }

  // Coloca todas las ramas (escena: x desde el centro, y hacia arriba, en
  // unidades del ancho). wind: Viento; shake: sacudida del golpe.
  void place(float wind, float t, float shake) const {
    // Con viento fuerte todo el bosque se inclina hacia la derecha.
    const float tilt = std::max(wind - 1.0f, 0.0f) * 0.17f;
    for (size_t i = 0; i < limbs.size(); i++) {
      const Limb& L = limbs[i];
      const Tree& T = trees[size_t(L.tree)];
      Vec2 p;
      float a;
      if (L.parent < 0) {
        p = {T.x, 0.0f};
        a = 1.5707963f + T.lean - tilt * 0.25f;
      } else {
        const size_t q = size_t(L.parent) * kPts + size_t(L.at);
        p = pts[q];
        a = dirs[q] + L.rel;
      }
      float sway = 0.0f;
      if (!L.root) {
        const float d = float(L.depth);
        sway = wind * (0.014f + 0.02f * d) * std::sin(t * 0.9f + T.x * 3.0f + d * 0.5f + L.phase * 0.3f)
             + shake * 0.05f * d * std::sin(L.phase * 2.3f);
      }
      const float step = L.len * T.scale / float(L.segs);
      // Las ramas buscan la luz: se curvan poco a poco hacia arriba.
      const float rise = L.root || L.depth == 0 ? 0.0f : 0.09f;
      pts[i * kPts] = p;
      dirs[i * kPts] = a;
      for (int k = 1; k <= L.segs; k++) {
        a += L.curl + L.kink[size_t(k - 1)] + sway / float(L.segs) + rise * (1.5707963f - tilt - a);
        p.x += std::cos(a) * step;
        p.y += std::sin(a) * step;
        pts[i * kPts + size_t(k)] = p;
        dirs[i * kPts + size_t(k)] = a;
      }
    }
  }

  void addTree(Random& rng, float x, float lean, float height, float halfW, int layer, int depth, float width) {
    Tree T;
    T.x = x; T.lean = lean; T.layer = layer; T.depth = depth;
    T.first = int(limbs.size());
    trees.push_back(T);
    const int id = int(trees.size()) - 1;
    grow(rng, id, -1, 0, 0.0f, 1.0f, width, 0, depth);
    // Raíces que se abren en la base.
    const int roots = layer == 1 ? 3 : 2;
    for (int r = 0; r < roots; r++) {
      Limb L;
      L.parent = T.first; L.at = 1; L.tree = id; L.depth = depth; L.root = true; L.segs = 4;
      L.rel = (r % 2 == 0 ? 1.0f : -1.0f) * (2.1f + 0.35f * rng.unit()) + (r == 2 ? 0.5f : 0.0f);
      L.len = 0.18f + 0.08f * rng.unit();
      L.w0 = width * 0.7f; L.w1 = width * 0.1f;
      L.curl = (rng.unit() - 0.5f) * 0.1f;
      for (auto& k : L.kink) k = (rng.unit() - 0.5f) * 0.1f;
      limbs.push_back(L);
    }
    trees[size_t(id)].last = int(limbs.size());
    // Ajuste: el árbol entero cabe en el alto y el ancho pedidos.
    pts.assign(limbs.size() * kPts, Vec2{});
    dirs.assign(limbs.size() * kPts, 0.0f);
    place(0.0f, 0.0f, 0.0f);
    float top = 0.01f, side = 0.01f;
    for (int i = trees[size_t(id)].first; i < trees[size_t(id)].last; i++) {
      if (limbs[size_t(i)].root) continue;
      for (int k = 0; k <= limbs[size_t(i)].segs; k++) {
        const Vec2 p = pts[size_t(i) * kPts + size_t(k)];
        top = std::max(top, p.y);
        side = std::max(side, std::abs(p.x - x));
      }
    }
    trees[size_t(id)].scale = std::min(height / top, halfW / side);
    trees[size_t(id)].reach = side * trees[size_t(id)].scale + 0.1f;
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    limbs.clear(); trees.clear(); lianas.clear(); shrooms.clear(); fronds.clear(); motes.clear(); flies.clear();
    limbs.reserve(700);
    dotOrder.reserve(2048); dotAlone.reserve(2048); dotKeep.reserve(256);
    for (auto& v : tipsAt) v.reserve(256);
    hotAt.reserve(256); twinkleAt.reserve(512); beadsAt.reserve(2048); litBeadsAt.reserve(2048);
    dotTips.reserve(256); fernTipsAt.reserve(128); sparksAt.reserve(kMotes); flyAt.reserve(kFlies);
    for (auto& row : motesAt) for (auto& v : row) v.reserve(kMotes);
    bass = body = spark = slowBass = kick = flash = 0;
    clock = 0; secs = 0;
    pulseAt.fill(-100.0); pulsePow.fill(0.0f); nextPulse = 0;
    // Árboles del fondo (también fuera de la vista vertical, para pantallas anchas).
    const float back[7][4] = {{-0.33f, 0.06f, 1.7f, 0.3f}, {0.36f, -0.05f, 1.55f, 0.3f}, {-0.64f, 0.08f, 1.85f, 0.34f},
                              {0.68f, -0.07f, 1.8f, 0.34f}, {-1.05f, 0.03f, 1.7f, 0.32f}, {1.08f, -0.03f, 1.75f, 0.32f},
                              {-1.45f, 0.05f, 1.8f, 0.32f}};
    for (const auto& b : back) addTree(rng, b[0], b[1], b[2], b[3], 0, 3, 0.08f);
    // Árbol principal: completo dentro de la pantalla vertical.
    addTree(rng, 0.0f, 0.0f, 1.8f, 0.4f, 1, 4, 0.1f);
    addTree(rng, -1.25f, 0.04f, 1.6f, 0.4f, 1, 3, 0.1f);
    addTree(rng, 1.3f, -0.04f, 1.65f, 0.4f, 1, 3, 0.1f);
    pts.assign(limbs.size() * kPts, Vec2{});
    dirs.assign(limbs.size() * kPts, 0.0f);
    // Lianas colgando de las ramas medias.
    for (size_t i = 0; i < limbs.size(); i++) {
      const Limb& L = limbs[i];
      if (L.root || L.depth < 1 || L.depth > 3) continue;
      if (rng.unit() > (trees[size_t(L.tree)].layer == 1 ? 0.75f : 0.4f)) continue;
      lianas.push_back({int(i), std::max(1, L.segs - 1 - int(rng.unit() * 2.0f)), 0.25f + 0.55f * rng.unit(), rng.unit() * 6.2831853f});
    }
    // Setas en el suelo, en grupos.
    const float groups[4] = {-0.36f, -0.08f, 0.22f, 0.4f};
    for (float gx : groups) {
      const int n = 2 + int(rng.unit() * 2.0f);
      for (int k = 0; k < n; k++)
        shrooms.push_back({gx + (rng.unit() - 0.5f) * 0.1f, 0.022f + 0.03f * rng.unit(), (rng.unit() - 0.5f) * 0.3f,
                           rng.unit() < 0.68f ? 0 : 1});
    }
    // Helechos que entran desde las esquinas de abajo.
    fronds.push_back({-0.52f, 1.0f, 0.42f, rng.unit() * 6.28f, 1.0f});
    fronds.push_back({-0.47f, 1.0f, 0.3f, rng.unit() * 6.28f, 1.0f});
    fronds.push_back({0.53f, -1.0f, 0.4f, rng.unit() * 6.28f, 1.0f});
    fronds.push_back({0.46f, -1.0f, 0.27f, rng.unit() * 6.28f, 1.0f});
    // Ramas colgantes que enmarcan la parte de arriba.
    fronds.push_back({-0.56f, 1.0f, 0.5f, rng.unit() * 6.28f, -1.0f});
    fronds.push_back({-0.5f, 1.0f, 0.32f, rng.unit() * 6.28f, -1.0f});
    fronds.push_back({0.57f, -1.0f, 0.44f, rng.unit() * 6.28f, -1.0f});
    for (int i = 0; i < kMotes; i++)
      motes.push_back({(rng.unit() - 0.5f) * 3.2f, rng.unit() * 2.6f, 0.4f + rng.unit(), rng.unit() * 6.2831853f, 0.01f + 0.03f * rng.unit()});
    for (int i = 0; i < kFlies; i++)
      flies.push_back({(rng.unit() - 0.5f) * 1.1f, 0.25f + rng.unit() * 1.2f, 0.06f + 0.12f * rng.unit(), 0.04f + 0.08f * rng.unit(),
                       0.6f + 0.8f * rng.unit(), 0.6f + 0.8f * rng.unit(), rng.unit() * 6.2831853f, 0.5f + 0.7f * rng.unit()});
  }

  void update(const Frame& f) override {
    auto m = modifiers(f);
    const float dt = float(f.delta);
    const Music& mu = f.music;
    bass = follow(bass, mu.bass, 22.0f, 4.5f, dt);
    body = follow(body, mu.body, 12.0f, 3.0f, dt);
    spark = follow(spark, mu.spark, 30.0f, 7.0f, dt);
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
    secs += f.delta;
    // Golpes: cada golpe lanza un pulso de luz desde las raíces.
    if (fresh && m.pulso == 0) {
      pulseAt[size_t(nextPulse)] = secs;
      pulsePow[size_t(nextPulse)] = hit;
      nextPulse = (nextPulse + 1) % kPulses;
    }
    clock += f.delta * f.speed;
  }

  void render(const Frame& f, Canvas& c) const override {
    auto g = glide(f);
    const float amp = f.intensity;
    // Pulso: cada opción mueve algo distinto (todo vale 0 sin música).
    const float golpe = g.pulso.weight(0) * std::min(kick * amp, 1.0f);
    const float grave = g.pulso.weight(1) * std::min((bass * 0.8f + body * 0.3f) * amp, 1.2f);
    const float agudo = g.pulso.weight(2) * std::min((spark + flash * 0.5f) * amp, 1.2f);
    const float w = f.width, h = f.height, cx = w * 0.5f;
    const float s = std::min(w, h * 0.5f);
    const float sc = std::max(0.6f, s / 390.0f);
    const float view = 0.5f * w / s + 0.05f;
    const float t = float(std::fmod(clock, 10000.0));
    const float rt = float(std::fmod(secs, 1000.0));
    const float wind = std::clamp(g.viento, 0.0f, 3.0f) * (f.reducedMotion ? 0.3f : 1.0f);
    const float mist = std::clamp(g.niebla, 0.0f, 1.0f);
    const float glowK = std::clamp(f.glow, 0.0f, 2.0f);
    const float wHojas = g.flora.weight(0), wLianas = g.flora.weight(1), wFlores = g.flora.weight(2);
    // Con Lianas o Flores quedan algunas hojas tenues: el árbol nunca se ve seco.
    const float leafAmount = wHojas + 0.3f * wLianas + 0.25f * wFlores;
    const Color bg = f.colors[0], mint = f.colors[1], amber = f.colors[2], emerald = f.colors[3];
    const Color jade = mixc(mint, emerald, 0.35f);
    const Color white{1, 1, 1, 1};
    const Color hues[3] = {mint, jade, emerald};
    auto S = [&](Vec2 p) { return Vec2{cx + p.x * s, h - p.y * s}; };
    // Lo que queda entero fuera de la pantalla no se dibuja: no cambia ni un
    // píxel y ahorra trazos.
    viewW = w;
    viewH = h;
    auto onScreen = [&](Vec2 p, float m) { return p.x > -m && p.x < w + m && p.y > -m && p.y < h + m; };
    auto limbOnScreen = [&](size_t i, float m) {
      const Limb& L = limbs[i];
      float x0 = 1e9f, x1 = -1e9f, y0 = 1e9f, y1 = -1e9f;
      for (int k = 0; k <= L.segs; k++) {
        const Vec2 p = S(pts[i * kPts + size_t(k)]);
        x0 = std::min(x0, p.x); x1 = std::max(x1, p.x); y0 = std::min(y0, p.y); y1 = std::max(y1, p.y);
      }
      return x1 > -m && x0 < w + m && y1 > -m && y0 < h + m;
    };

    // Pulsos: los de los golpes y uno suave cada 6,5 s (también en silencio).
    float front[kPulses + 1], power[kPulses + 1];
    for (int j = 0; j < kPulses; j++) {
      const float age = float(std::min(secs - pulseAt[size_t(j)], 100.0));
      front[j] = age * 1.5f;
      power[j] = age < 4.0f ? std::min(pulsePow[size_t(j)] * amp, 1.2f) * g.pulso.weight(0) * std::exp(-age * 0.45f) : 0.0f;
    }
    {
      const double lap = std::floor(clock / 6.5);
      const float age = float(clock - lap * 6.5);
      front[kPulses] = age * 1.1f;
      power[kPulses] = 0.32f * std::exp(-age * 0.35f);
    }
    auto pulse = [&](float d) {
      float v = 0.0f;
      for (int j = 0; j <= kPulses; j++) {
        if (power[j] < 0.003f) continue;
        const float off = (front[j] - d) / 0.16f;
        if (off * off > 40.0f) continue;  // exp(-40): no cambia el resultado
        v += power[j] * std::exp(-off * off);
      }
      return std::min(v, 1.5f);
    };
    // El pulso más reciente de los golpes, para la niebla del fondo.
    int newest = 0;
    for (int j = 1; j < kPulses; j++) if (pulseAt[size_t(j)] > pulseAt[size_t(newest)]) newest = j;
    const float ground = std::min(golpe + 0.6f * grave, 1.2f);

    // 1. Fondo: degradado, rayos de luna, troncos lejanos y niebla (material).
    std::vector<float> u;
    u.reserve(24);
    u.insert(u.end(), {t, s, h / s, mist});
    u.insert(u.end(), {grave, glowK, front[newest], power[newest]});
    u.insert(u.end(), {front[kPulses], power[kPulses], ground, agudo});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[size_t(i)].r, f.colors[size_t(i)].g, f.colors[size_t(i)].b});
    c.material("jungle_mist", {0, 0, w, h}, u);

    // 2. Ramas: posiciones con el viento y la sacudida del golpe.
    place(wind, t, golpe);
    auto visible = [&](const Tree& T) { return std::abs(T.x) - T.reach < view; };
    auto width = [&](const Limb& L, const Tree& T, int k) {
      return (L.w0 + (L.w1 - L.w0) * float(k) / float(L.segs)) * T.scale;
    };
    // Silueta: un polígono que se estrecha a lo largo de cada rama.
    auto silhouette = [&](Path& path, size_t i) {
      const Limb& L = limbs[i];
      const Tree& T = trees[size_t(L.tree)];
      Vec2 right[kPts];
      for (int k = 0; k <= L.segs; k++) {
        const size_t q = i * kPts + size_t(k);
        const float a = k < L.segs ? 0.5f * (dirs[q] + dirs[q + 1]) : dirs[q];
        const float half = 0.5f * width(L, T, k);
        const Vec2 p = pts[q];
        const Vec2 l = S({p.x - std::sin(a) * half, p.y + std::cos(a) * half});
        right[k] = S({p.x + std::sin(a) * half, p.y - std::cos(a) * half});
        if (k == 0) path.moveTo(l.x, l.y); else path.lineTo(l.x, l.y);
      }
      for (int k = L.segs; k >= 0; k--) path.lineTo(right[k].x, right[k].y);
      path.close();
    };
    // Venas que brillan en la corteza: el eje de las ramas gruesas.
    auto veins = [&](Path& path, size_t i) {
      const Limb& L = limbs[i];
      for (int k = 0; k <= L.segs; k++) {
        const Vec2 p = S(pts[i * kPts + size_t(k)]);
        if (k == 0) path.moveTo(p.x, p.y); else path.lineTo(p.x, p.y);
      }
    };

    for (int layer = 0; layer < 2; layer++) {
      const bool hero = layer == 1;
      // Los árboles del fondo quedan tras la niebla.
      if (hero) {
        Paint haze = Paint::linear({0, h}, {0, h - s * 1.1f},
          {jade.opacity(std::clamp(0.1f + 0.3f * mist, 0.0f, 1.0f)), jade.opacity(0.0f)}, {0.0f, 1.0f});
        c.rect({0, 0, w, h}, haze);
      }
      Path wood, vein, lit[3];
      for (const Tree& T : trees) {
        if (T.layer != layer || !visible(T)) continue;
        for (int i = T.first; i < T.last; i++) {
          const size_t ii = size_t(i);
          const Limb& L = limbs[ii];
          if (limbOnScreen(ii, 0.5f * std::max(L.w0, L.w1) * T.scale * s + 1.0f)) silhouette(wood, ii);
          if (L.depth <= (hero ? 2 : 1) && !L.root && limbOnScreen(ii, sc * 2.0f + 1.0f)) veins(vein, ii);
          // Golpes: el pulso recorre las ramas desde las raíces.
          if (L.root) continue;
          const float step = L.len * T.scale / float(L.segs);
          for (int k = 0; k < L.segs; k++) {
            const float pv = pulse((L.dist * T.scale + step * (float(k) + 0.5f)) * (hero ? 1.0f : 1.15f));
            if (pv < 0.05f) continue;
            const int b = pv > 0.6f ? 2 : (pv > 0.25f ? 1 : 0);
            const Vec2 p0 = S(pts[ii * kPts + size_t(k)]), p1 = S(pts[ii * kPts + size_t(k + 1)]);
            const float m = sc * 3.5f + 1.0f;
            if (std::max(p0.x, p1.x) < -m || std::min(p0.x, p1.x) > w + m || std::max(p0.y, p1.y) < -m || std::min(p0.y, p1.y) > h + m) continue;
            lit[b].moveTo(p0.x, p0.y);
            lit[b].lineTo(p1.x, p1.y);
          }
        }
      }
      Paint bark;
      bark.color = hero ? mixc(bg, mint, 0.05f) : mixc(bg, jade, 0.12f + 0.12f * mist);
      c.path(wood, bark);
      Paint veinGlow = light(mint, (hero ? 0.1f : 0.05f) * glowK * (1.0f + 0.6f * grave));
      veinGlow.strokeWidth = sc * 4.0f; veinGlow.strokeCap = 1; veinGlow.strokeJoin = 1;
      c.path(vein, veinGlow);
      Paint veinCore = light(mixc(mint, white, 0.2f), (hero ? 0.45f : 0.22f) * (1.0f + 0.5f * grave));
      veinCore.strokeWidth = sc * 1.0f; veinCore.strokeCap = 1; veinCore.strokeJoin = 1;
      c.path(vein, veinCore);
      for (int b = 0; b < 3; b++) {
        const float a = 0.3f + 0.35f * float(b);
        Paint pg = light(jade, a * 0.35f * glowK);
        pg.strokeWidth = sc * (hero ? 7.0f : 4.5f); pg.strokeCap = 1;
        c.path(lit[b], pg);
        Paint pc = light(mixc(jade, white, 0.45f), a);
        pc.strokeWidth = sc * (hero ? 2.2f : 1.4f); pc.strokeCap = 1;
        c.path(lit[b], pc);
      }

      // Flora: hojas, lianas o flores en las ramas finas.
      Path leaves[3], litLeaves, petals;
      std::vector<Vec2>* tips = tipsAt;
      std::vector<Vec2>& hot = hotAt;
      for (int k = 0; k < 3; k++) tips[k].clear();
      hot.clear();
      const float leafLen = (hero ? 0.042f : 0.03f) * s * (1.0f + 0.2f * grave);
      for (const Tree& T : trees) {
        if (T.layer != layer || !visible(T)) continue;
        for (int i = T.first; i < T.last; i++) {
          const size_t ii = size_t(i);
          const Limb& L = limbs[ii];
          if (L.root || L.depth < T.depth - 1) continue;
          const bool end = L.depth == T.depth;
          const float step = L.len * T.scale / float(L.segs);
          for (int k = std::max(1, L.segs - 2); k <= L.segs; k++) {
            const size_t q = ii * kPts + size_t(k);
            const Vec2 p = S(pts[q]);
            const bool tip = k == L.segs && end;
            const float lenK = leafLen * (0.75f + 0.25f * float(k) / float(L.segs));
            const bool leafShown = leafAmount > 0.001f && onScreen(p, lenK + 1.0f);
            if (!leafShown && !tip) continue;
            const float pv = pulse((L.dist * T.scale + step * float(k)) * (hero ? 1.0f : 1.15f));
            if (leafShown) {
              const float flutter = 0.25f * wind * std::sin(t * 2.1f + L.phase + float(k));
              Path& dest = pv > 0.3f ? litLeaves : leaves[L.hue];
              leaf(dest, p, dirs[q] + 0.8f + flutter, lenK, lenK * 0.32f);
              leaf(dest, p, dirs[q] - 0.8f + flutter, lenK, lenK * 0.32f);
            }
            if (tip) {
              tips[L.hue].push_back(p);
              if (pv > 0.3f) hot.push_back(p);
              // Flores de cinco pétalos en las puntas.
              const float pl = leafLen * 0.9f * (1.0f + 0.25f * pv);
              if (wFlores > 0.001f && onScreen(p, pl + 1.0f)) {
                for (int k2 = 0; k2 < 5; k2++)
                  leaf(petals, p, L.phase + float(k2) * 1.2566371f + 0.2f * std::sin(t + L.phase), pl, pl * 0.42f);
              }
            }
          }
        }
      }
      const float leafA = (hero ? 0.6f : 0.3f) * (1.0f + 0.5f * grave) *
                          (1.0f + 0.5f * agudo * (0.5f + 0.5f * std::sin(rt * 21.0f + float(layer))));
      for (int k = 0; k < 3; k++) c.path(leaves[k], light(hues[k], leafA * leafAmount));
      c.path(litLeaves, light(mixc(jade, white, 0.5f), std::min(1.0f, leafA * 1.6f) * leafAmount));
      c.path(petals, light(amber, (hero ? 0.75f : 0.45f) * wFlores * (1.0f + 0.4f * grave)));
      // Halos suaves en las puntas (degradado radial: sin bordes). Primero
      // todos los halos (normal) y después todos los puntos de luz (suma):
      // alternarlos por tono costaba dos pasadas por tono. Un halo de un tono
      // posterior velaba los puntos de los tonos anteriores; ese velo se
      // aplica ahora al alfa de cada punto, así el píxel es el mismo.
      const float haloR = s * (hero ? 0.05f : 0.032f) * (1.0f + 0.3f * grave);
      const float haloA = (hero ? 0.22f : 0.12f) * glowK * (1.0f + 0.7f * grave) * (wHojas + wFlores);
      const float haloK = std::clamp(haloA, 0.0f, 1.0f);
      auto haloShown = [&](Vec2 p) { return !(p.x < -haloR || p.x > w + haloR || p.y < -haloR); };
      for (int k = 0; k < 3; k++) {
        const Color hc = mixc(hues[k], amber, wFlores);
        // Un solo degradado por tono; sólo cambia su centro.
        Paint hp = Paint::radial({0, 0}, haloR, {hc.opacity(haloK), hc.opacity(0.0f)}, {0.0f, 1.0f});
        for (const Vec2& p : tips[k]) {
          if (!haloShown(p)) continue;
          hp.geometry[0] = p.x;
          hp.geometry[1] = p.y;
          c.circle(p, haloR, hp);
        }
      }
      for (int k = 0; k < 3; k++) {
        const float dotR = sc * (hero ? 1.5f : 1.0f) * (1.0f + 0.6f * wFlores);
        const Color dotC = mixc(hues[k], white, 0.55f);
        const float dotA = (hero ? 0.9f : 0.5f) * (wHojas + wFlores);
        if (dotA <= 0.0f) continue;
        dotTips.clear();
        for (const Vec2& p : tips[k]) {
          float veil = 1.0f;
          for (int m2 = k + 1; m2 < 3 && haloK > 0.0f; m2++) {
            for (const Vec2& q : tips[m2]) {
              const float dx = p.x - q.x;
              if (dx >= haloR || dx <= -haloR) continue;
              const float d2 = dx * dx + (p.y - q.y) * (p.y - q.y);
              if (d2 >= haloR * haloR || !haloShown(q)) continue;
              veil *= 1.0f - haloK * (1.0f - std::sqrt(d2) / haloR);
            }
          }
          if (veil < 1.0f) {
            if (onScreen(p, dotR + 1.0f)) dot(c, p, dotR, light(dotC, dotA * veil));
          } else {
            dotTips.push_back(p);
          }
        }
        dots(c, dotTips, dotR, light(dotC, dotA));
      }
      // El pulso hace destellar las puntas al llegar.
      Paint hotDot = light(white, 0.9f);
      dots(c, hot, sc * (hero ? 2.6f : 1.8f), hotDot);
      // Agudos: las puntas centellean, cada una a su ritmo.
      if (agudo > 0.003f) {
        std::vector<Vec2>& twinkle = twinkleAt;
        twinkle.clear();
        int n = 0;
        for (int k = 0; k < 3; k++)
          for (const Vec2& p : tips[k])
            if (std::sin(rt * 19.0f + float(n++) * 2.39f) > 0.45f) twinkle.push_back(p);
        dots(c, twinkle, sc * (hero ? 4.0f : 2.6f), light(mixc(mint, white, 0.4f), 0.35f * agudo));
        dots(c, twinkle, sc * (hero ? 2.0f : 1.4f), light(white, std::min(1.0f, agudo)));
      }
      if (wFlores > 0.001f) {
        for (int k = 0; k < 3; k++) dots(c, tips[k], sc * 1.8f, light(emerald, 0.9f * wFlores));
      }

      // Lianas: hilos que cuelgan con cuentas de luz.
      if (wLianas > 0.001f) {
        Path strands;
        std::vector<Vec2>& beads = beadsAt;
        std::vector<Vec2>& litBeads = litBeadsAt;
        beads.clear();
        litBeads.clear();
        for (const Liana& li : lianas) {
          const Limb& L = limbs[size_t(li.limb)];
          const Tree& T = trees[size_t(L.tree)];
          if (T.layer != layer || !visible(T)) continue;
          const Vec2 a = pts[size_t(li.limb) * kPts + size_t(li.at)];
          const float len = li.len * (hero ? 1.0f : 0.75f) * (0.4f + 0.6f * wLianas);
          const float swing = (0.03f + 0.05f * wind) * std::sin(t * 0.8f + li.phase) * len;
          const Vec2 ctrl{a.x + swing * 0.4f, a.y - len * 0.55f};
          const Vec2 end{a.x + swing, a.y - len};
          const Vec2 A = S(a), C = S(ctrl), E = S(end);
          strands.moveTo(A.x, A.y);
          strands.quadraticTo(C.x, C.y, E.x, E.y);
          const float base = L.dist * T.scale + L.len * T.scale * float(li.at) / float(L.segs);
          for (int k = 1; k <= 6; k++) {
            const float v = float(k) / 6.0f;
            const float iv = 1.0f - v;
            const Vec2 b{iv * iv * A.x + 2.0f * v * iv * C.x + v * v * E.x, iv * iv * A.y + 2.0f * v * iv * C.y + v * v * E.y};
            (pulse(base + len * v) > 0.3f ? litBeads : beads).push_back(b);
          }
        }
        Paint sg = light(jade, (hero ? 0.14f : 0.08f) * glowK * wLianas * (1.0f + 0.6f * grave));
        sg.strokeWidth = sc * 4.0f;
        c.path(strands, sg);
        Paint sl = light(mint, (hero ? 0.55f : 0.3f) * wLianas * (1.0f + 0.4f * grave));
        sl.strokeWidth = sc * 1.0f;
        c.path(strands, sl);
        dots(c, beads, sc * (hero ? 1.8f : 1.3f), light(mixc(mint, white, 0.35f), (hero ? 0.85f : 0.5f) * wLianas));
        dots(c, litBeads, sc * (hero ? 2.8f : 2.0f), light(white, wLianas));
      }
    }

    // 3. Suelo, helechos y setas delante.
    {
      Paint mistFront = Paint::linear({0, h}, {0, h - s * 0.5f},
        {jade.opacity(std::clamp(0.06f + 0.2f * mist, 0.0f, 1.0f)), jade.opacity(0.0f)}, {0.0f, 1.0f});
      c.rect({0, 0, w, h}, mistFront);
      Path ground;
      ground.moveTo(0, h);
      for (int k = 0; k <= 32; k++) {
        const float x = w * float(k) / 32.0f;
        const float xs = (x - cx) / s;
        ground.lineTo(x, h - s * (0.055f + 0.02f * std::sin(xs * 7.0f + 1.0f) + 0.012f * std::sin(xs * 17.0f)));
      }
      ground.lineTo(w, h);
      ground.close();
      Paint soil;
      soil.color = {bg.r * 0.5f, bg.g * 0.5f, bg.b * 0.5f, 1.0f};
      c.path(ground, soil);
    }
    // Helechos: siluetas oscuras con el borde encendido.
    const float topY = h / s;
    Path fernBody, fernSpine;
    std::vector<Vec2>& fernTips = fernTipsAt;
    fernTips.clear();
    for (const Frond& fr : fronds) {
      if (std::abs(fr.x) - fr.len > view) continue;
      const float sway = (0.01f + 0.025f * wind) * std::sin(t * 0.7f + fr.phase);
      const bool hang = fr.up < 0.0f;
      const float y0 = hang ? topY + 0.02f : 0.02f;
      const Vec2 P0{fr.x, y0};
      // Del suelo: sube y se arquea hacia dentro. De arriba: sale y cae.
      const Vec2 P1 = hang ? Vec2{fr.x + fr.dir * fr.len * 0.55f, y0 + 0.04f}
                           : Vec2{fr.x - fr.dir * 0.04f, y0 + fr.len * 0.9f};
      const Vec2 P2 = hang ? Vec2{fr.x + fr.dir * fr.len * 0.85f + sway, y0 - fr.len * 0.8f}
                           : Vec2{fr.x + fr.dir * fr.len * 0.8f, y0 + fr.len * 0.38f + sway};
      for (int k = 0; k <= 16; k++) {
        const float v = float(k) / 16.0f, iv = 1.0f - v;
        const Vec2 p{iv * iv * P0.x + 2 * v * iv * P1.x + v * v * P2.x, iv * iv * P0.y + 2 * v * iv * P1.y + v * v * P2.y};
        const Vec2 sp = S(p);
        if (k == 0) fernSpine.moveTo(sp.x, sp.y); else fernSpine.lineTo(sp.x, sp.y);
        if (k == 0 || k == 16) continue;
        const Vec2 tg{2 * iv * (P1.x - P0.x) + 2 * v * (P2.x - P1.x), 2 * iv * (P1.y - P0.y) + 2 * v * (P2.y - P1.y)};
        const float a = std::atan2(tg.y, tg.x);
        const float len = s * fr.len * 0.22f * (1.0f - 0.75f * v) * (0.4f + 0.6f * std::min(1.0f, v * 4.0f));
        const float flutter = 0.12f * wind * std::sin(t * 1.6f + fr.phase + v * 5.0f);
        if (onScreen(sp, len + sc + 1.0f)) {
          leaf(fernBody, sp, a + 1.15f + flutter, len, len * 0.22f);
          leaf(fernBody, sp, a - 1.15f + flutter, len, len * 0.22f);
        }
        if (k % 3 == 0) {
          fernTips.push_back({sp.x + std::cos(a + 1.15f) * len, sp.y - std::sin(a + 1.15f) * len});
          fernTips.push_back({sp.x + std::cos(a - 1.15f) * len, sp.y - std::sin(a - 1.15f) * len});
        }
      }
    }
    Paint fernFill; fernFill.color = {bg.r * 0.6f, bg.g * 0.6f, bg.b * 0.6f, 1.0f};
    c.path(fernBody, fernFill);
    Paint fernEdge = light(emerald, 0.3f * (1.0f + 0.6f * grave + 0.8f * golpe));
    fernEdge.strokeWidth = sc * 0.9f;
    c.path(fernBody, fernEdge);
    Paint spine; spine.color = fernFill.color; spine.strokeWidth = sc * 2.2f; spine.strokeCap = 1;
    c.path(fernSpine, spine);
    Paint spineGlow = light(emerald, 0.35f * (1.0f + 0.5f * grave));
    spineGlow.strokeWidth = sc * 0.9f;
    c.path(fernSpine, spineGlow);
    dots(c, fernTips, sc * 1.3f, light(mixc(emerald, white, 0.3f), 0.7f * (1.0f + agudo * 0.4f)));

    // Setas: el golpe las enciende primero (el pulso nace en el suelo).
    // Cada seta pinta tallo (suma), resplandor (normal) y sombrero (suma);
    // seta a seta eran dos pasadas por seta. Se reparten en capas: una seta
    // sube de capa sólo si toca a una anterior, y en cada capa van primero
    // los resplandores y después tallos y sombreros. El tallo lleva en su
    // degradado el velo de su propio resplandor, que antes caía encima.
    const float shroomPulse = pulse(0.05f);
    constexpr int kShroomMax = 12, kShroomLevels = 5;
    struct ShroomDraw { Vec2 b, top; float size, stem, glowR; int level; Color capC; };
    std::array<ShroomDraw, kShroomMax> sd;
    int shroomCount = 0, shroomLevels = 0;
    for (const Shroom& sh : shrooms) {
      if (std::abs(sh.x) > view || shroomCount == kShroomMax) continue;
      ShroomDraw& d = sd[size_t(shroomCount)];
      d.capC = sh.hue == 0 ? amber : mint;
      d.size = sh.size * s * (1.0f + 0.12f * grave + 0.1f * shroomPulse);
      d.b = S({sh.x, 0.035f});
      d.stem = d.size * 1.3f;
      d.top = {d.b.x + sh.lean * d.stem, d.b.y - d.stem};
      d.glowR = d.size * (2.4f + 0.4f * shroomPulse);
      // Una seta posterior va en una capa mayor si su resplandor toca el
      // cuerpo de una anterior; en la misma o mayor si sólo se tocan los
      // resplandores (el orden normal dentro de la capa se conserva).
      d.level = 0;
      for (int j = 0; j < shroomCount; j++) {
        const ShroomDraw& e = sd[size_t(j)];
        const float dx = d.top.x - e.top.x, dy = d.top.y - e.top.y, d2 = dx * dx + dy * dy;
        const float body = d.glowR + 1.4f * e.size + 1.0f, glows = d.glowR + e.glowR + 1.0f;
        if (d2 < body * body) d.level = std::max(d.level, e.level + 1);
        else if (d2 < glows * glows) d.level = std::max(d.level, e.level);
      }
      d.level = std::min(d.level, kShroomLevels - 1);
      shroomLevels = std::max(shroomLevels, d.level + 1);
      shroomCount++;
    }
    const float glowA = std::clamp((0.2f + 0.22f * grave + 0.3f * shroomPulse) * std::min(glowK, 1.3f), 0.0f, 1.0f);
    for (int lv = 0; lv < shroomLevels; lv++) {
      for (int i = 0; i < shroomCount; i++) {
        const ShroomDraw& d = sd[size_t(i)];
        if (d.level != lv) continue;
        c.circle(d.top, d.glowR, Paint::radial(d.top, d.glowR, {d.capC.opacity(glowA), d.capC.opacity(0.0f)}, {0.0f, 1.0f}));
      }
      for (int i = 0; i < shroomCount; i++) {
        const ShroomDraw& d = sd[size_t(i)];
        if (d.level != lv) continue;
        const Vec2 b = d.b, top = d.top;
        const float size = d.size;
        Path st;
        st.moveTo(b.x - size * 0.2f, b.y);
        st.lineTo(top.x - size * 0.13f, top.y);
        st.lineTo(top.x + size * 0.13f, top.y);
        st.lineTo(b.x + size * 0.2f, b.y);
        st.close();
        const Color stemC = mixc(d.capC, white, 0.6f);
        const float stemA = std::clamp(0.4f + 0.2f * shroomPulse, 0.0f, 1.0f);
        Paint stemPaint = Paint::radial(top, d.glowR, {stemC.opacity(stemA * (1.0f - glowA)), stemC.opacity(stemA)}, {0.0f, 1.0f});
        stemPaint.blend = Blend::plus;
        c.path(st, stemPaint);
        Path cap;
        cap.moveTo(top.x - size, top.y);
        cap.cubicTo(top.x - size, top.y - size * 1.25f, top.x + size, top.y - size * 1.25f, top.x + size, top.y);
        cap.quadraticTo(top.x, top.y - size * 0.3f, top.x - size, top.y);
        cap.close();
        Paint capPaint = Paint::radial({top.x, top.y - size * 0.7f}, size * 1.2f,
          {mixc(d.capC, white, 0.55f).opacity(0.95f), d.capC.opacity(0.9f), d.capC.opacity(0.55f)}, {0.0f, 0.5f, 1.0f});
        capPaint.blend = Blend::plus;
        c.path(cap, capPaint);
      }
    }

    // 4. Esporas que suben y luciérnagas.
    const int moteCount = std::clamp(int(50.0f + 55.0f * f.detail), 0, kMotes);
    auto& motesBy = motesAt;
    for (auto& row : motesBy) for (auto& v : row) v.clear();
    std::vector<Vec2>& sparks = sparksAt;
    sparks.clear();
    for (int i = 0; i < moteCount; i++) {
      const Mote& mo = motes[size_t(i)];
      const float x = mo.x + mo.drift * std::sin(t * 0.4f + mo.phase);
      if (std::abs(x) > view) continue;
      const float y = std::fmod(mo.y + t * 0.05f * mo.speed, topY + 0.2f) - 0.1f;
      float b = 0.5f + 0.5f * std::sin(t * 1.3f * mo.speed + mo.phase);
      const float flick = std::sin(rt * 17.0f + mo.phase * 7.0f);
      if (agudo > 0.003f && flick > 0.6f) sparks.push_back(S({x, y}));
      b = std::clamp(b * (1.0f + agudo * flick), 0.0f, 0.999f);
      motesBy[int(b * 3.0f)][i % 2].push_back(S({x, y}));
    }
    for (int k = 0; k < 3; k++) {
      const float a = 0.25f + 0.3f * float(k);
      dots(c, motesBy[k][0], sc * (0.9f + 0.4f * float(k)), light(mint, a));
      dots(c, motesBy[k][1], sc * (0.9f + 0.4f * float(k)), light(emerald, a));
    }
    dots(c, sparks, sc * 2.2f, light(mixc(mint, white, 0.6f), std::min(1.0f, agudo)));
    const int flyCount = std::clamp(int(12.0f + 10.0f * f.detail), 0, kFlies);
    std::vector<Vec2>& flyCores = flyAt;
    flyCores.clear();
    // Un solo degradado para todas: cambian su centro y su alfa.
    const float flyR = s * 0.035f * (1.0f + 0.3f * grave);
    Paint flyGlow = Paint::radial({0, 0}, flyR, {emerald.opacity(0.0f), emerald.opacity(0.0f)}, {0.0f, 1.0f});
    for (int i = 0; i < flyCount; i++) {
      const Fly& fl = flies[size_t(i)];
      const float x = fl.cx + fl.ax * std::sin(t * fl.fx * 0.35f + fl.phase);
      const float y = fl.cy + fl.ay * std::sin(t * fl.fy * 0.3f + fl.phase * 1.7f);
      const float on = std::sin(t * fl.rate + fl.phase);
      float blink = std::clamp((on - 0.45f) / 0.45f, 0.0f, 1.0f);
      blink = std::clamp(blink + agudo * 0.6f * std::max(std::sin(rt * 23.0f + fl.phase * 5.0f), 0.0f), 0.0f, 1.0f);
      if (blink < 0.03f || std::abs(x) > view) continue;
      const Vec2 p = S({x, y});
      flyGlow.geometry[0] = p.x;
      flyGlow.geometry[1] = p.y;
      flyGlow.colors[0].a = std::clamp(0.45f * blink * glowK, 0.0f, 1.0f);
      c.circle(p, flyR, flyGlow);
      flyCores.push_back(p);
    }
    c.points(flyCores, sc * 1.6f, light(mixc(emerald, white, 0.5f), 0.95f));
  }
};
''';

const shaderSources = <String, String>{
  'jungle_mist': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // reloj, píxeles por unidad, alto en unidades, niebla
uniform vec4 uB;   // graves, glow, altura y fuerza del pulso del golpe
uniform vec4 uP;   // altura y fuerza del pulso suave, brillo del suelo, agudos
uniform vec3 uC0;
uniform vec3 uC1;
uniform vec3 uC2;
uniform vec3 uC3;
out vec4 fragColor;

float hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
             mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
  return 0.55 * vnoise(p) + 0.3 * vnoise(p * 2.1 + 3.1) + 0.15 * vnoise(p * 4.3 + 7.7);
}

// Troncos lejanos: uno por celda, más anchos en la base.
float trunks(vec2 q, float cellW, float seed, float pxu) {
  float cell = floor(q.x / cellW);
  float h1 = hash12(vec2(cell, seed));
  if (h1 < 0.3) return 0.0;
  float center = (cell + 0.3 + 0.4 * hash12(vec2(cell, seed + 5.0))) * cellW;
  center += (hash12(vec2(cell, seed + 9.0)) - 0.5) * 0.02 * q.y;
  float hw = cellW * (0.05 + 0.08 * hash12(vec2(cell, seed + 2.0))) * (1.0 + 1.2 * exp(-q.y * 5.0));
  return 1.0 - smoothstep(hw - pxu, hw + pxu, abs(q.x - center));
}

void main() {
  vec2 px = FlutterFragCoord().xy;
  float s = uA.y;
  float top = uA.z;
  float mist = uA.w;
  float t = uA.x;
  vec2 q = vec2((px.x - 0.5 * uSize.x) / s, (uSize.y - px.y) / s);
  float pxu = 1.0 / s;
  vec3 jade = mix(uC1, uC3, 0.35);
  float yn = q.y / top;
  // Degradado: suelo turquesa, noche azul verdosa y negro arriba.
  vec3 col = mix(mix(uC0, jade, 0.11), mix(uC0, uC1, 0.04), smoothstep(0.0, 0.4, yn));
  col = mix(col, uC0 * 0.7, smoothstep(0.4, 0.9, yn));
  // Rayos de luna que entran desde arriba a la izquierda.
  vec2 dv = q - vec2(-0.55, top + 0.35);
  float ang = atan(dv.x, -dv.y);
  float rays = vnoise(vec2(ang * 9.0 + t * 0.02, 0.5));
  rays = rays * rays * rays;
  float dist = length(dv);
  col += mix(uC1, vec3(1.0), 0.35) * rays * smoothstep(0.0, 0.6, dist) * exp(-dist * 0.6) * (0.06 + 0.2 * mist) * uB.y;
  // Dos capas de troncos lejanos; la niebla las envuelve.
  // Se funden con la oscuridad hacia arriba.
  float up = 1.0 - smoothstep(0.25, 0.95, yn);
  float far1 = trunks(q, 0.11, 3.0, pxu) * (0.25 + 0.75 * up);
  col = mix(col, mix(uC0, jade, 0.12 + 0.12 * mist) * (0.7 + 0.3 * up), far1 * 0.6);
  float far2 = trunks(q + vec2(0.05, 0.0), 0.2, 17.0, pxu) * (0.4 + 0.6 * up);
  col = mix(col, mix(uC0, jade, 0.05 + 0.06 * mist), far2 * 0.85);
  float canopy = 1.0 - up;
  vec2 cell = floor(q * 26.0);
  float hc = hash12(cell + 41.0);
  float twinkle = 0.5 + 0.5 * sin(t * (1.0 + 2.0 * hc) + hc * 40.0);
  twinkle *= 1.0 + uP.w * 2.0 * max(sin(t * 11.0 + hc * 70.0), 0.0);
  vec2 dc = (fract(q * 26.0) - 0.5) / 26.0;
  float mote = step(0.86, hc) * exp(-dot(dc, dc) / (0.000004 + 0.000004 * hc)) * twinkle;
  col += mix(mix(uC1, uC3, step(0.91, hc)), uC2, step(0.96, hc)) * mote * (0.35 + 0.65 * canopy) * 0.8;
  // Niebla luminosa que deriva: densa junto al suelo y en una franja media.
  float n = fbm(vec2(q.x * 1.6 + t * 0.05, q.y * 3.2 - t * 0.02));
  float band = exp(-q.y * 1.8) + 0.5 * exp(-(q.y - 0.95) * (q.y - 0.95) * 6.0);
  float fog = mist * band * (0.35 + 0.9 * n) * (1.0 + 0.6 * uB.x);
  col = mix(col, jade * 0.45, clamp(fog * 0.42, 0.0, 0.85));
  col += jade * fog * 0.12;
  // Musgo luminoso en el suelo; se enciende con el golpe y los graves.
  col += jade * exp(-q.y * 9.0) * (0.22 + 0.35 * uP.z);
  // Pulsos: una franja de luz sube por el bosque y enciende la niebla.
  float b1 = (q.y - uB.z * 0.9) / 0.14;
  float b2 = (q.y - uP.x * 0.9) / 0.14;
  float rise = uB.w * exp(-b1 * b1) + uP.y * exp(-b2 * b2);
  col += mix(jade, vec3(1.0), 0.2) * rise * (0.12 + 0.5 * fog);
  col += (hash12(px) - 0.5) / 255.0;
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
