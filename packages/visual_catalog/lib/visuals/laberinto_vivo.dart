// Laberinto Vivo — un laberinto que se excava, se inunda y se resuelve.
// Primero un excavador recorre la rejilla con el algoritmo de búsqueda en
// profundidad: avanza a una celda sin visitar al azar y, si se queda sin
// salida, retrocede; deja pasillos tenues y su rama actual brilla en naranja.
// Al terminar, la luz entra por la esquina de arriba y avanza por todos los
// pasillos a la vez (búsqueda en anchura): cada pasillo toma el color de su
// distancia a la entrada, en franjas de rojo a amarillo. Después se dibuja en
// blanco el camino más corto a la salida, el laberinto se apaga y empieza
// otro. La energía acelera todo, los graves hacen latir el neón y cada golpe
// da un empujón a la luz.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.steps('celdas', 'Celdas a lo ancho', min: 8, max: 34, value: 16),
  CreatorModifier.slider('velocidad', 'Velocidad', min: .4, max: 2.5, value: 1),
  CreatorModifier.slider('grosor', 'Grosor de pasillos', min: .3, max: .8, value: .5),
  CreatorModifier.toggle('franjas', 'Franjas de color', value: true),
];

const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kMaxCols = 34;
  static constexpr int kMaxRows = 80;
  static constexpr int kMaxCells = kMaxCols * kMaxRows;
  enum Phase { kGen, kFlood, kPath, kHold, kFade };
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double phaseTime = 0, genSteps = 0;
  int64_t stepsDone = 0;
  int cols = 0, rows = 0, phase = kGen, maxDist = 1;
  float cellPx = 1, ox = 0, oy = 0;
  Random rng{1};
  // Por celda: pasillo a la derecha (1) y abajo (2), visitada, distancia, padre.
  std::vector<uint8_t> carved, visited;
  std::vector<int16_t> dist, parent;
  std::vector<int> stack, queue, path;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  void clearMaze() {
    std::fill(carved.begin(), carved.end(), 0);
    std::fill(visited.begin(), visited.end(), 0);
    std::fill(dist.begin(), dist.end(), -1);
    stack.clear();
    path.clear();
    int start = std::min(int(rng.unit() * float(cols * rows)), cols * rows - 1);
    visited[size_t(start)] = 1;
    stack.push_back(start);
    phase = kGen;
    phaseTime = 0;
    genSteps = 0;
    stepsDone = 0;
  }

  bool open(int a, int b) const {
    int lo = std::min(a, b), hi = std::max(a, b);
    if (hi - lo == 1) return (carved[size_t(lo)] & 1) != 0;
    return (carved[size_t(lo)] & 2) != 0;
  }

  void genStep() {
    if (stack.empty()) return;
    int cur = stack.back();
    int x = cur % cols, y = cur / cols;
    int options[4];
    int count = 0;
    if (x + 1 < cols && !visited[size_t(cur + 1)]) options[count++] = cur + 1;
    if (x > 0 && !visited[size_t(cur - 1)]) options[count++] = cur - 1;
    if (y + 1 < rows && !visited[size_t(cur + cols)]) options[count++] = cur + cols;
    if (y > 0 && !visited[size_t(cur - cols)]) options[count++] = cur - cols;
    if (count == 0) {
      stack.pop_back();
      return;
    }
    int next = options[std::min(int(rng.unit() * float(count)), count - 1)];
    int lo = std::min(cur, next);
    carved[size_t(lo)] |= (std::abs(next - cur) == 1) ? 1 : 2;
    visited[size_t(next)] = 1;
    stack.push_back(next);
  }

  void solve() {
    // Búsqueda en anchura desde la entrada (arriba a la izquierda).
    std::fill(dist.begin(), dist.end(), -1);
    queue.clear();
    queue.push_back(0);
    dist[0] = 0;
    parent[0] = -1;
    size_t head = 0;
    maxDist = 1;
    while (head < queue.size()) {
      int cur = queue[head++];
      int x = cur % cols, y = cur / cols;
      int nb[4] = {x + 1 < cols ? cur + 1 : -1, x > 0 ? cur - 1 : -1, y + 1 < rows ? cur + cols : -1, y > 0 ? cur - cols : -1};
      for (int k = 0; k < 4; k++) {
        int b = nb[k];
        if (b < 0 || dist[size_t(b)] >= 0 || !open(cur, b)) continue;
        dist[size_t(b)] = int16_t(dist[size_t(cur)] + 1);
        parent[size_t(b)] = int16_t(cur);
        maxDist = std::max(maxDist, int(dist[size_t(b)]));
        queue.push_back(b);
      }
    }
    path.clear();
    for (int c = cols * rows - 1; c >= 0; c = parent[size_t(c)]) {
      path.push_back(c);
      if (c == 0) break;
    }
    std::reverse(path.begin(), path.end());
  }

  Vec2 center(int cell) const {
    return {ox + (float(cell % cols) + 0.5f) * cellPx, oy + (float(cell / cols) + 0.5f) * cellPx};
  }

 public:
  void reset(uint32_t seed) override {
    rng = Random(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    cols = rows = 0;
    carved.assign(kMaxCells, 0);
    visited.assign(kMaxCells, 0);
    dist.assign(kMaxCells, -1);
    parent.assign(kMaxCells, -1);
    stack.reserve(kMaxCells);
    queue.reserve(kMaxCells);
    path.reserve(kMaxCells);
    phase = kGen;
    phaseTime = genSteps = 0;
    stepsDone = 0;
    maxDist = 1;
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

    int c = std::clamp(m.celdas, 6, kMaxCols);
    cellPx = f.width * 0.92f / float(c);
    int r = std::clamp(int(f.height * 0.92f / cellPx), 4, kMaxRows);
    if (c != cols || r != rows) {
      cols = c;
      rows = r;
      clearMaze();
    }
    ox = (f.width - float(cols) * cellPx) * 0.5f;
    oy = (f.height - float(rows) * cellPx) * 0.5f;
    double rate = f.delta * f.speed * m.velocidad * (1.0 + 1.2 * drive + 1.5 * kick);
    // Unos 7 segundos para excavar todo, sea cual sea el tamaño.
    double stepsPerSecond = double(2 * cols * rows) / 7.0;
    if (phase == kGen) {
      genSteps += rate * stepsPerSecond;
      int64_t target = int64_t(std::floor(genSteps + 1e-6));
      while (stepsDone < target && !stack.empty()) {
        genStep();
        stepsDone++;
      }
      if (!stack.empty()) return;
      // El tiempo sobrante pasa a la siguiente fase: igual a 30 y 60 FPS.
      solve();
      phase = kFlood;
      phaseTime = std::max(0.0, genSteps - double(stepsDone)) / stepsPerSecond;
    } else {
      phaseTime += rate;
    }
    static const double lengths[5] = {0.0, 3.2, 1.6, 1.8, 0.9};
    while (phase != kGen && phaseTime >= lengths[phase]) {
      phaseTime -= lengths[phase];
      if (phase == kFade) {
        double carry = phaseTime;
        clearMaze();
        genSteps = carry * stepsPerSecond;
      } else {
        phase++;
      }
    }
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    float amp = f.intensity;
    const Color& bg = f.colors[0];
    c.rect({0, 0, f.width, f.height}, Paint::radial({f.width * 0.5f, f.height * 0.5f}, std::max(f.width, f.height) * 0.75f,
                                                   {Color{std::min(1.0f, bg.r + 0.035f), std::min(1.0f, bg.g + 0.025f), std::min(1.0f, bg.b + 0.04f), 1.0f},
                                                    Color{bg.r, bg.g, bg.b, 1.0f}}));
    if (cols <= 0) return;
    float px = std::min(f.width, f.height) / 400.0f;
    float fade = phase == kFade ? float(1.0 - phaseTime / 0.9) : 1.0f;
    float flood = phase == kGen ? -1.0f : (phase == kFlood ? float(phaseTime / 3.2) * float(maxDist + 4) : float(maxDist + 4));
    float width = cellPx * m.grosor;
    const Color& red = f.colors[1];
    const Color& orange = f.colors[2];
    const Color& yellow = f.colors[3];
    auto ramp = [&](float t) {
      t = std::clamp(t, 0.0f, 1.0f);
      if (t < 0.5f) return Color{red.r + (orange.r - red.r) * t * 2.0f, red.g + (orange.g - red.g) * t * 2.0f, red.b + (orange.b - red.b) * t * 2.0f, 1.0f};
      float u = (t - 0.5f) * 2.0f;
      return Color{orange.r + (yellow.r - orange.r) * u, orange.g + (yellow.g - orange.g) * u, orange.b + (yellow.b - orange.b) * u, 1.0f};
    };
    // Pasillos: tenues hasta que llega la luz; luego por franjas de distancia.
    const int buckets = 10;
    std::array<Path, buckets> lit;
    Path dim, front;
    bool anyFront = false;
    for (int cell = 0; cell < cols * rows; cell++) {
      Vec2 a = center(cell);
      for (int k = 0; k < 2; k++) {
        if (!(carved[size_t(cell)] & (k == 0 ? 1 : 2))) continue;
        int other = cell + (k == 0 ? 1 : cols);
        Vec2 b = center(other);
        int d = std::max(dist[size_t(cell)], dist[size_t(other)]);
        if (flood >= 0.0f && d >= 0 && float(d) <= flood) {
          float t = m.franjas ? float(d % 24) / 23.0f : float(d) / float(maxDist);
          lit[size_t(std::min(buckets - 1, int(t * float(buckets))))].moveTo(a.x, a.y).lineTo(b.x, b.y);
          if (float(d) > flood - 2.5f) {
            front.moveTo(a.x, a.y).lineTo(b.x, b.y);
            anyFront = true;
          }
        } else {
          dim.moveTo(a.x, a.y).lineTo(b.x, b.y);
        }
      }
    }
    Paint pd;
    pd.strokeWidth = width;
    pd.strokeCap = 1;
    pd.strokeJoin = 1;
    pd.color = Color{0.55f, 0.5f, 0.52f, std::clamp((0.22f + 0.1f * bass) * fade * amp, 0.0f, 1.0f)};
    c.path(dim, pd);
    for (int b = 0; b < buckets; b++) {
      Color col = ramp((float(b) + 0.5f) / float(buckets));
      float g = (0.8f + 0.35f * bass + 0.2f * kick) * amp;
      Paint halo;
      halo.blend = Blend::plus;
      halo.strokeWidth = width * 2.2f;
      halo.strokeCap = 1;
      halo.color = col.opacity(std::clamp(0.12f * f.glow * fade * amp, 0.0f, 1.0f));
      c.path(lit[size_t(b)], halo);
      Paint p;
      p.strokeWidth = width;
      p.strokeCap = 1;
      p.strokeJoin = 1;
      p.color = Color{std::min(1.0f, col.r * g), std::min(1.0f, col.g * g), std::min(1.0f, col.b * g), fade};
      c.path(lit[size_t(b)], p);
    }
    if (anyFront && phase == kFlood) {
      Paint fp;
      fp.blend = Blend::plus;
      fp.strokeWidth = width * 1.4f;
      fp.strokeCap = 1;
      fp.color = Color{1.0f, 0.95f, 0.8f, std::clamp((0.45f + 0.5f * kick) * amp, 0.0f, 1.0f)};
      c.path(front, fp);
    }
    // Rama actual del excavador.
    if (phase == kGen && stack.size() > 1) {
      Path branch;
      for (size_t i = 0; i < stack.size(); i++) {
        Vec2 p = center(stack[i]);
        if (i == 0) branch.moveTo(p.x, p.y); else branch.lineTo(p.x, p.y);
      }
      Paint bp;
      bp.strokeWidth = width * 0.8f;
      bp.strokeCap = 1;
      bp.strokeJoin = 1;
      bp.color = orange.opacity(std::clamp(0.75f * amp, 0.0f, 1.0f));
      c.path(branch, bp);
      Vec2 head = center(stack.back());
      Paint hp = Paint::radial(head, cellPx * 1.6f, {yellow.opacity(std::clamp((0.8f + 0.2f * kick) * amp, 0.0f, 1.0f)), yellow.opacity(0.0f)});
      hp.blend = Blend::plus;
      c.circle(head, cellPx * 1.6f, hp);
    }
    // Camino más corto, en blanco.
    if ((phase == kPath || phase == kHold || phase == kFade) && path.size() > 1) {
      float prog = phase == kPath ? float(phaseTime / 1.6) : 1.0f;
      size_t count = std::max<size_t>(2, size_t(prog * float(path.size())));
      Path sol;
      for (size_t i = 0; i < std::min(count, path.size()); i++) {
        Vec2 p = center(path[i]);
        if (i == 0) sol.moveTo(p.x, p.y); else sol.lineTo(p.x, p.y);
      }
      Paint glow;
      glow.blend = Blend::plus;
      glow.strokeWidth = width * 2.4f;
      glow.strokeCap = 1;
      glow.strokeJoin = 1;
      glow.color = Color{1.0f, 0.9f, 0.7f, std::clamp(0.25f * f.glow * fade * amp, 0.0f, 1.0f)};
      c.path(sol, glow);
      Paint line;
      line.strokeWidth = width * 0.75f;
      line.strokeCap = 1;
      line.strokeJoin = 1;
      line.color = Color{1.0f, 1.0f, 1.0f, fade};
      c.path(sol, line);
    }
    // Entrada y salida.
    Paint mark;
    mark.blend = Blend::plus;
    mark.color = yellow.opacity(std::clamp((0.6f + 0.4f * kick) * fade * amp, 0.0f, 1.0f));
    c.circle(center(0), width * 0.9f, mark);
    c.circle(center(cols * rows - 1), width * 0.9f, mark);
    (void)px;
    if (flash > 0.01f) {
      Paint fl;
      fl.blend = Blend::plus;
      fl.color = orange.opacity(std::clamp(flash * 0.05f * amp, 0.0f, 1.0f));
      c.rect({0, 0, f.width, f.height}, fl);
    }
  }
};
''';
