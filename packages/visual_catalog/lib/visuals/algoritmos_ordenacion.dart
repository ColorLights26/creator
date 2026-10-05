// Algoritmos de Ordenación — el arcoíris se desordena y se ordena solo.
// Como en los vídeos de visualización de algoritmos: cada barra tiene un
// valor y su color; se barajan y un algoritmo las ordena paso a paso
// (burbuja, cóctel, inserción, selección, Shell, peine, rápido, montículo
// y mezcla, uno tras otro). Las dos barras que el algoritmo toca en cada paso
// se encienden en blanco. Al terminar, un barrido de luz recorre el
// resultado y se vuelve a barajar. Puede verse como barras, como una rueda de
// color (ordenada es una rueda perfecta) o como nube de puntos (ordenada es
// una diagonal). Algoritmo fija uno solo (cada uno deja su propio dibujo a
// medio ordenar) o los recorre todos; Rastro deja una estela de luz por
// donde pasó el algoritmo y alarga la cola del barrido final. El arcoíris
// empieza en el tono del primer acento de la paleta. La energía acelera el
// algoritmo, los graves dan brillo y cada golpe hace destellar las barras.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.steps('barras', 'Barras', min: 24, max: 128, value: 72),
  CreatorModifier.choice('vista', 'Vista', options: ['Barras', 'Rueda', 'Puntos']),
  // MOVIMIENTO: cómo viajan las barras (vecinas, saltos largos, montones…).
  CreatorModifier.choice(
    'algoritmo',
    'Algoritmo',
    options: ['Todos', 'Burbuja', 'Inserción', 'Selección', 'Shell', 'Rápido', 'Montículo', 'Mezcla'],
  ),
  // ATMÓSFERA: la luz que deja el algoritmo a su paso.
  CreatorModifier.slider('rastro', 'Rastro', min: 0, max: 1, value: .3),
];

const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kMax = 128;
  static constexpr int kAlgorithms = 9;
  struct Op { int16_t a, b, value; uint8_t kind; };  // 0 cambio, 1 escritura, 2 comparación
  enum Phase { kShuffle, kSort, kSweep };
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double phaseTime = 0, duration = 1;
  int n = 0, algorithm = 0, phase = kShuffle;
  size_t applied = 0;
  int lastA = -1, lastB = -1;
  Random rng{1};
  std::array<int, kMax> values{};
  std::vector<Op> ops;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  // Tono (0..1) de un color de la paleta: el arcoíris empieza en él.
  static float hueOf(const Color& c) {
    float hi = std::max(c.r, std::max(c.g, c.b)), lo = std::min(c.r, std::min(c.g, c.b));
    float d = hi - lo;
    if (d < 1e-4f) return 0.0f;
    float h = hi == c.r ? (c.g - c.b) / d : (hi == c.g ? 2.0f + (c.b - c.r) / d : 4.0f + (c.r - c.g) / d);
    h /= 6.0f;
    return h - std::floor(h);
  }

  static Color hsv(float h, float s, float v) {
    h = h - std::floor(h);
    float r = std::clamp(std::fabs(h * 6.0f - 3.0f) - 1.0f, 0.0f, 1.0f);
    float g = std::clamp(2.0f - std::fabs(h * 6.0f - 2.0f), 0.0f, 1.0f);
    float b = std::clamp(2.0f - std::fabs(h * 6.0f - 4.0f), 0.0f, 1.0f);
    return {v * (1.0f - s + s * r), v * (1.0f - s + s * g), v * (1.0f - s + s * b), 1.0f};
  }

  // Grabación: cada algoritmo trabaja sobre una copia y anota sus pasos.
  void swapOp(std::array<int, kMax>& w, int i, int j) {
    std::swap(w[size_t(i)], w[size_t(j)]);
    ops.push_back({int16_t(i), int16_t(j), 0, 0});
  }
  void setOp(std::array<int, kMax>& w, int i, int v) {
    w[size_t(i)] = v;
    ops.push_back({int16_t(i), int16_t(i), int16_t(v), 1});
  }
  void cmpOp(int i, int j) { ops.push_back({int16_t(i), int16_t(j), 0, 2}); }

  void record(int which) {
    ops.clear();
    std::array<int, kMax> w = values;
    switch (which) {
      case 0:  // Burbuja
        for (int end = n - 1; end > 0; end--) {
          bool any = false;
          for (int i = 0; i < end; i++) {
            if (w[size_t(i)] > w[size_t(i + 1)]) {
              swapOp(w, i, i + 1);
              any = true;
            }
          }
          if (!any) break;
        }
        break;
      case 1: {  // Cóctel
        int lo = 0, hi = n - 1;
        bool any = true;
        while (any && lo < hi) {
          any = false;
          for (int i = lo; i < hi; i++) if (w[size_t(i)] > w[size_t(i + 1)]) { swapOp(w, i, i + 1); any = true; }
          hi--;
          for (int i = hi; i > lo; i--) if (w[size_t(i - 1)] > w[size_t(i)]) { swapOp(w, i - 1, i); any = true; }
          lo++;
        }
        break;
      }
      case 2:  // Inserción
        for (int i = 1; i < n; i++) {
          for (int j = i; j > 0 && w[size_t(j - 1)] > w[size_t(j)]; j--) swapOp(w, j - 1, j);
        }
        break;
      case 3:  // Selección: se ve cómo recorre buscando el mínimo
        for (int i = 0; i < n - 1; i++) {
          int best = i;
          for (int j = i + 1; j < n; j++) {
            cmpOp(best, j);
            if (w[size_t(j)] < w[size_t(best)]) best = j;
          }
          if (best != i) swapOp(w, i, best);
        }
        break;
      case 4:  // Shell
        for (int gap = n / 2; gap > 0; gap /= 2) {
          for (int i = gap; i < n; i++) {
            for (int j = i; j >= gap && w[size_t(j - gap)] > w[size_t(j)]; j -= gap) swapOp(w, j - gap, j);
          }
        }
        break;
      case 5: {  // Peine
        int gap = n;
        bool sorted = false;
        while (!sorted) {
          gap = std::max(1, int(float(gap) / 1.3f));
          sorted = gap == 1;
          for (int i = 0; i + gap < n; i++) {
            cmpOp(i, i + gap);
            if (w[size_t(i)] > w[size_t(i + gap)]) {
              swapOp(w, i, i + gap);
              sorted = false;
            }
          }
        }
        break;
      }
      case 6: {  // Rápido (Lomuto, con pila propia)
        std::array<int, kMax * 4> stack{};
        int top = 0;
        stack[size_t(top++)] = 0;
        stack[size_t(top++)] = n - 1;
        while (top > 0) {
          int hi = stack[size_t(--top)];
          int lo = stack[size_t(--top)];
          if (lo >= hi) continue;
          int pivot = w[size_t(hi)];
          int i = lo;
          for (int j = lo; j < hi; j++) {
            cmpOp(j, hi);
            if (w[size_t(j)] < pivot) {
              if (i != j) swapOp(w, i, j);
              i++;
            }
          }
          if (i != hi) swapOp(w, i, hi);
          if (top + 4 <= int(stack.size())) {
            stack[size_t(top++)] = lo;
            stack[size_t(top++)] = i - 1;
            stack[size_t(top++)] = i + 1;
            stack[size_t(top++)] = hi;
          }
        }
        break;
      }
      case 7: {  // Montículo
        auto sift = [&](int start, int end) {
          int root = start;
          while (root * 2 + 1 <= end) {
            int child = root * 2 + 1;
            int target = root;
            if (w[size_t(target)] < w[size_t(child)]) target = child;
            if (child + 1 <= end && w[size_t(target)] < w[size_t(child + 1)]) target = child + 1;
            cmpOp(root, child);
            if (target == root) return;
            swapOp(w, root, target);
            root = target;
          }
        };
        for (int start = (n - 2) / 2; start >= 0; start--) sift(start, n - 1);
        for (int end = n - 1; end > 0; end--) {
          swapOp(w, 0, end);
          sift(0, end - 1);
        }
        break;
      }
      default: {  // Mezcla, de abajo arriba
        std::array<int, kMax> tmp{};
        for (int width = 1; width < n; width *= 2) {
          for (int lo = 0; lo < n - width; lo += 2 * width) {
            int mid = lo + width, hi = std::min(lo + 2 * width, n);
            int i = lo, j = mid, k = 0;
            while (i < mid && j < hi) {
              cmpOp(i, j);
              tmp[size_t(k++)] = w[size_t(i)] <= w[size_t(j)] ? w[size_t(i++)] : w[size_t(j++)];
            }
            while (i < mid) tmp[size_t(k++)] = w[size_t(i++)];
            while (j < hi) tmp[size_t(k++)] = w[size_t(j++)];
            for (int t = 0; t < k; t++) setOp(w, lo + t, tmp[size_t(t)]);
          }
        }
        break;
      }
    }
  }

  void recordShuffle() {
    ops.clear();
    std::array<int, kMax> w = values;
    for (int i = n - 1; i > 0; i--) {
      int j = std::min(int(rng.unit() * float(i + 1)), i);
      swapOp(w, i, j);
    }
  }

  void apply(const Op& op) {
    if (op.kind == 0) std::swap(values[size_t(op.a)], values[size_t(op.b)]);
    else if (op.kind == 1) values[size_t(op.a)] = op.value;
    lastA = op.a;
    lastB = op.b;
  }

  void startPhase(int next) {
    phase = next;
    applied = 0;
    if (next == kShuffle) {
      recordShuffle();
      duration = 1.1;
    } else if (next == kSort) {
      record(algorithm);
      duration = std::clamp(2.5 + double(ops.size()) / 1100.0, 4.0, 9.0);
    } else {
      ops.clear();
      duration = 1.3;
    }
  }

 public:
  void reset(uint32_t seed) override {
    rng = Random(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    phaseTime = 0;
    duration = 1;
    n = 0;
    algorithm = int(seed % uint32_t(kAlgorithms));
    phase = kShuffle;
    applied = 0;
    lastA = lastB = -1;
    ops.reserve(20000);
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

    int want = std::clamp(m.barras, 8, kMax);
    if (want != n) {
      n = want;
      for (int i = 0; i < kMax; i++) values[size_t(i)] = i;
      phaseTime = 0;
      startPhase(kShuffle);
    }
    // Algoritmo: uno fijo (o Todos, que los recorre). Si cambia a mitad de
    // ordenar, el nuevo sigue desde el estado actual: ninguna barra salta.
    constexpr int kChoice[8] = {-1, 0, 2, 3, 4, 6, 7, 8};
    int pick = kChoice[std::clamp(m.algoritmo, 0, 7)];
    if (pick >= 0 && pick != algorithm) {
      algorithm = pick;
      if (phase == kSort) {
        phaseTime = 0;
        startPhase(kSort);
      }
    }
    phaseTime += f.delta * f.speed * (1.0 + 1.3 * drive + 1.5 * kick);
    for (int guard = 0; guard < 4; guard++) {
      double t = std::min(phaseTime / duration, 1.0);
      size_t target = std::min(ops.size(), size_t(std::floor(t * double(ops.size()) + 1e-6)));
      while (applied < target) apply(ops[applied++]);
      if (phaseTime < duration) break;
      phaseTime -= duration;
      if (phase == kShuffle) {
        startPhase(kSort);
      } else if (phase == kSort) {
        lastA = lastB = -1;
        startPhase(kSweep);
      } else {
        if (pick < 0) algorithm = (algorithm + 1) % kAlgorithms;
        startPhase(kShuffle);
      }
    }
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    auto gl = glide(f);
    float amp = f.intensity;
    const Color& bg = f.colors[0];
    c.rect({0, 0, f.width, f.height}, Paint::radial({f.width * 0.5f, f.height * 0.5f}, std::max(f.width, f.height) * 0.75f,
                                                   {Color{std::min(1.0f, bg.r + 0.04f), std::min(1.0f, bg.g + 0.03f), std::min(1.0f, bg.b + 0.05f), 1.0f},
                                                    Color{bg.r, bg.g, bg.b, 1.0f}}));
    if (n <= 0) return;
    float side = std::min(f.width, f.height);
    float px = side / 400.0f;
    float sweep = phase == kSweep ? float(phaseTime / duration) * float(n + 6) : -10.0f;
    // Rastro: los pasos recientes dejan luz en las barras que tocaron y se
    // apaga con la edad del paso; también alarga la cola del barrido final.
    const float rastro = std::clamp(gl.rastro, 0.0f, 1.0f);
    const float tail = 2.0f + 20.0f * rastro;
    std::array<float, kMax> trail{};
    if (phase != kSweep && applied > 0 && rastro > 0.001f) {
      // Los pasos de los últimos 0,8 s del algoritmo (en su propio reloj).
      size_t reach = size_t(std::clamp(double(rastro) * double(ops.size()) / duration * 0.8, 0.0, 2000.0));
      size_t first = applied > reach ? applied - reach : 0;
      for (size_t j = first; j < applied; j++) {
        float fresh = 1.0f - float(applied - 1 - j) / float(std::max<size_t>(reach, 1));
        float w = fresh * fresh * 0.6f;
        const Op& op = ops[j];
        trail[size_t(op.a)] = std::max(trail[size_t(op.a)], w);
        trail[size_t(op.b)] = std::max(trail[size_t(op.b)], w);
      }
    }
    const float baseHue = hueOf(f.colors[1]);
    auto colorOf = [&](int value, int index) {
      float t = float(value) / float(n - 1);
      Color col = hsv(baseHue + t * 0.83f, 0.95f, 1.0f);
      float lit = (0.8f + 0.25f * bass + 0.25f * kick) * amp;
      // Barrido final: las barras ya revisadas brillan hacia el blanco.
      float s = std::clamp(sweep - float(index), 0.0f, 1.0f) * std::clamp(1.0f - (sweep - float(index)) / tail, 0.0f, 1.0f);
      bool touched = index == lastA || index == lastB;
      float trace = index >= 0 && index < kMax ? trail[size_t(index)] : 0.0f;
      float w = touched ? 0.85f : std::max(s * 0.7f, trace);
      return Color{std::clamp((col.r * lit) * (1.0f - w) + w, 0.0f, 1.0f), std::clamp((col.g * lit) * (1.0f - w) + w, 0.0f, 1.0f),
                   std::clamp((col.b * lit) * (1.0f - w) + w, 0.0f, 1.0f), 1.0f};
    };

    if (m.vista == 0) {
      float left = f.width * 0.04f, usable = f.width * 0.92f;
      float bw = usable / float(n);
      float bottom = f.height * 0.9f, maxH = f.height * 0.78f;
      for (int i = 0; i < n; i++) {
        int v = values[size_t(i)];
        float h = maxH * (float(v) + 1.0f) / float(n);
        Paint p;
        p.color = colorOf(v, i);
        c.rect({left + float(i) * bw, bottom - h, std::max(bw * 0.82f, 1.0f), h}, p);
      }
      // Reflejo tenue bajo las barras.
      Paint floor = Paint::linear({0, bottom}, {0, bottom + f.height * 0.08f}, {Color{1, 1, 1, 0.08f * amp}, Color{1, 1, 1, 0}});
      c.rect({left, bottom + 2.0f * px, usable, f.height * 0.08f}, floor);
    } else if (m.vista == 1) {
      // Rueda: cada cuña con su color; el radio baja cuanto más lejos está
      // la barra de su sitio, así ordenada es un círculo perfecto.
      Vec2 center{f.width * 0.5f, f.height * 0.5f};
      float R = side * 0.44f * (1.0f + 0.05f * bass * amp);
      for (int i = 0; i < n; i++) {
        int v = values[size_t(i)];
        float off = std::fabs(float(i - v)) / float(n);
        float r = R * (1.0f - 0.75f * off);
        float a0 = 6.2831853f * float(i) / float(n) - 1.5707963f;
        float a1 = 6.2831853f * float(i + 1) / float(n) - 1.5707963f;
        Path wedge;
        wedge.moveTo(center.x, center.y);
        for (int k = 0; k <= 3; k++) {
          float a = a0 + (a1 - a0) * float(k) / 3.0f;
          wedge.lineTo(center.x + r * std::cos(a), center.y + r * std::sin(a));
        }
        wedge.close();
        Paint p;
        p.color = colorOf(v, i);
        c.path(wedge, p);
      }
      Paint hole;
      hole.color = Color{bg.r, bg.g, bg.b, 1.0f};
      c.circle(center, R * 0.12f, hole);
    } else {
      float left = f.width * 0.06f, usable = f.width * 0.88f;
      float bottom = f.height * 0.5f + usable * 0.5f, top = f.height * 0.5f - usable * 0.5f;
      std::array<std::vector<Vec2>, 8> groups;
      for (auto& g : groups) g.reserve(size_t(n));
      for (int i = 0; i < n; i++) {
        int v = values[size_t(i)];
        float x = left + usable * (float(i) + 0.5f) / float(n);
        float y = bottom - (bottom - top) * (float(v) + 0.5f) / float(n);
        groups[size_t(std::min(7, v * 8 / n))].push_back({x, y});
      }
      for (int g = 0; g < 8; g++) {
        int v = (g * n) / 8 + n / 16;
        Paint halo;
        halo.blend = Blend::plus;
        Color col = colorOf(std::min(v, n - 1), -10);
        halo.color = col.opacity(std::clamp(0.22f * f.glow * amp, 0.0f, 1.0f));
        c.points(groups[size_t(g)], 7.0f * px, halo);
        Paint dot;
        dot.color = col;
        c.points(groups[size_t(g)], 2.6f * px, dot);
      }
      // Rastro en la nube: un halo blanco que se apaga sobre los puntos tocados.
      std::array<std::vector<Vec2>, 4> traced;
      for (int i = 0; i < n; i++) {
        float w = trail[size_t(i)];
        if (w < 0.03f) continue;
        float x = left + usable * (float(i) + 0.5f) / float(n);
        float y = bottom - (bottom - top) * (float(values[size_t(i)]) + 0.5f) / float(n);
        traced[size_t(std::min(3, int(w / 0.6f * 4.0f)))].push_back({x, y});
      }
      for (int k = 0; k < 4; k++) {
        if (traced[size_t(k)].empty()) continue;
        Paint tp;
        tp.blend = Blend::plus;
        tp.color = Color{1, 1, 1, std::clamp(0.12f * float(k + 1), 0.0f, 1.0f)};
        c.points(traced[size_t(k)], 4.5f * px, tp);
      }
      if (lastA >= 0 && lastA < n) {
        Paint hl;
        hl.blend = Blend::plus;
        hl.color = Color{1, 1, 1, 0.9f};
        for (int idx : {lastA, lastB}) {
          if (idx < 0 || idx >= n) continue;
          float x = left + usable * (float(idx) + 0.5f) / float(n);
          float y = bottom - (bottom - top) * (float(values[size_t(idx)]) + 0.5f) / float(n);
          c.circle({x, y}, 4.0f * px, hl);
        }
      }
    }
    if (flash > 0.01f) {
      Paint fl;
      fl.blend = Blend::plus;
      fl.color = Color{1, 1, 1, std::clamp(flash * 0.05f * amp, 0.0f, 1.0f)};
      c.rect({0, 0, f.width, f.height}, fl);
    }
  }
};
''';
