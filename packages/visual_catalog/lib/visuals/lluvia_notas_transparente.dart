// Lluvia de Notas Transparente — notas de neón que brotan de un teclado de luz.
// Versión overlay: mismo movimiento y reacción a la música sin fondo opaco.
// Abajo hay un teclado de piano; cada tecla escucha su parte del espectro
// (las graves a la izquierda, las agudas a la derecha). Cuando su banda suena
// fuerte la tecla se hunde y de ella brota una barra de neón que crece
// mientras la nota dura y luego sube hasta perderse arriba, como en los
// vídeos de piano con notas de colores. Cada octava tiene su color (rojo,
// naranja, amarillo). Sólo las bandas que más destacan tocan a la vez, así
// salen melodías y acordes en lugar de un muro de notas. Sin música el
// teclado toca solo arpegios sobre cuatro acordes.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.steps('octavas', 'Octavas', min: 1, max: 4, value: 3),
  CreatorModifier.slider('subida', 'Velocidad de subida', min: .4, max: 2.5, value: 1),
  CreatorModifier.steps('voces', 'Notas a la vez', min: 1, max: 8, value: 5),
  CreatorModifier.toggle('brillo', 'Halo de las notas', value: true),
];

const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kMaxKeys = 48;
  static constexpr int kMaxNotes = 320;
  struct Note { int key; double start, end; };
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double clock = 0, nextNote = 0;
  int keys = 0, step = 0;
  Random rng{1};
  std::vector<Note> notes;
  std::array<int, kMaxKeys> activeNote{};
  std::array<float, kMaxKeys> level{};
  std::array<double, kMaxKeys> lastEnd{};

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  static bool isBlack(int key) {
    int k = key % 12;
    return k == 1 || k == 3 || k == 6 || k == 8 || k == 10;
  }

  void start(int key, double when, double end) {
    if (int(notes.size()) >= kMaxNotes) return;
    notes.push_back({key, when, end});
    if (end < 0.0) activeNote[size_t(key)] = int(notes.size()) - 1;
  }

  // Melodía sin música: arpegios sobre I–V–vi–IV.
  void schedule(double when) {
    static const int chords[4][3] = {{0, 4, 7}, {7, 11, 14}, {9, 12, 16}, {5, 9, 12}};
    int bar = (step / 8) % 4;
    int beat = step % 8;
    int octaves = std::max(1, keys / 12);
    int base = 12 * std::max(0, octaves / 2 - 1);
    const int* ch = chords[bar];
    int note = base + ch[beat % 3] + (beat >= 3 && beat < 6 ? 12 : 0);
    double len = 0.18 + 0.25 * double(rng.unit());
    if (note < keys) start(note, when, when + len);
    if (beat == 0) {
      int bassKey = std::max(0, base - 12 + ch[0]);
      if (bassKey < keys) start(bassKey, when, when + 1.6);
      int high = base + 12 + ch[2];
      if (high < keys) start(high, when + 0.02, when + 0.9);
    }
    step++;
  }

 public:
  void reset(uint32_t seed) override {
    rng = Random(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    clock = 0;
    nextNote = 0.2;
    keys = 0;
    step = 0;
    notes.clear();
    notes.reserve(kMaxNotes);
    activeNote.fill(-1);
    level.fill(0);
    lastEnd.fill(-10.0);
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

    int k = std::clamp(m.octavas, 1, 4) * 12;
    if (k != keys) {
      keys = k;
      notes.clear();
      activeNote.fill(-1);
    }
    clock += f.delta * f.speed;
    if (mu.active) {
      // Cada tecla escucha su parte del espectro.
      float mean = 0;
      for (int i = 0; i < keys; i++) {
        float pos = float(i) / float(keys - 1) * 28.0f;
        int b = int(pos);
        float fr = pos - float(b);
        float v = mu.smoothSpectrum[size_t(b)] * (1.0f - fr) + mu.smoothSpectrum[size_t(std::min(b + 1, 30))] * fr;
        level[size_t(i)] = follow(level[size_t(i)], v, 30.0f, 8.0f, dt);
        mean += level[size_t(i)];
      }
      mean /= float(keys);
      float thr = std::max(0.16f, mean + 0.07f);
      // Sólo las que más destacan pueden sonar.
      std::array<int, kMaxKeys> order{};
      for (int i = 0; i < keys; i++) order[size_t(i)] = i;
      std::sort(order.begin(), order.begin() + keys, [&](int a, int b) { return level[size_t(a)] > level[size_t(b)]; });
      // Sólo picos: una tecla suena si destaca sobre sus vecinas cercanas.
      std::array<bool, kMaxKeys> allowed{};
      int voices = std::clamp(m.voces, 1, 8);
      int chosen = 0;
      for (int r = 0; r < keys && chosen < voices; r++) {
        int key = order[size_t(r)];
        bool peak = true;
        for (int d = -2; d <= 2 && peak; d++) {
          int nb = key + d;
          if (d == 0 || nb < 0 || nb >= keys) continue;
          if (level[size_t(nb)] > level[size_t(key)] || allowed[size_t(nb)]) peak = false;
        }
        if (peak) {
          allowed[size_t(key)] = true;
          chosen++;
        }
      }
      for (int i = 0; i < keys; i++) {
        int a = activeNote[size_t(i)];
        float v = level[size_t(i)];
        if (a >= 0) {
          // Cada nota dura al menos un instante: así no salta de tecla en tecla.
          Note& note = notes[size_t(a)];
          double age = clock - note.start;
          if (age > 0.14 && (!allowed[size_t(i)] || v < thr - 0.08f || age > 1.6)) {
            note.end = clock;
            activeNote[size_t(i)] = -1;
            lastEnd[size_t(i)] = clock;
          }
        } else if (allowed[size_t(i)] && v > thr + 0.03f && clock - lastEnd[size_t(i)] > 0.1) {
          start(i, clock, -1.0);
        }
      }
      // Cada golpe toca la nota grave que más suena.
      if (beat) {
        int best = 0;
        for (int i = 1; i < keys / 3; i++) if (level[size_t(i)] > level[size_t(best)]) best = i;
        if (activeNote[size_t(best)] < 0) start(best, clock, clock + 0.25 + 0.3 * double(hit));
      }
    } else {
      for (int i = 0; i < keys; i++) {
        int a = activeNote[size_t(i)];
        if (a >= 0) {
          notes[size_t(a)].end = clock;
          activeNote[size_t(i)] = -1;
        }
      }
      while (nextNote <= clock) {
        schedule(nextNote);
        nextNote += 0.25;
      }
    }
    if (mu.active) nextNote = clock + 0.25;
    // Se borran las notas que ya salieron por arriba.
    double travel = 1.6 / std::max(0.2, double(m.subida));
    size_t before = notes.size();
    notes.erase(std::remove_if(notes.begin(), notes.end(), [&](const Note& n) { return n.end >= 0.0 && clock - n.end > travel; }), notes.end());
    if (notes.size() != before) {
      activeNote.fill(-1);
      for (size_t i = 0; i < notes.size(); i++) if (notes[i].end < 0.0) activeNote[size_t(notes[i].key)] = int(i);
    }
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    float amp = f.intensity;
    if (keys <= 0) return;
    float px = std::min(f.width, f.height) / 400.0f;
    int whites = 0;
    for (int i = 0; i < keys; i++) if (!isBlack(i)) whites++;
    float ww = f.width / float(whites);
    float keyH = f.height * 0.13f;
    float keyTop = f.height - keyH;
    float speed = f.height * 0.62f * m.subida;
    // Posición horizontal de cada tecla.
    auto keyX = [&](int key, float& w) {
      int wIndex = 0;
      for (int i = 0; i < key; i++) if (!isBlack(i)) wIndex++;
      if (isBlack(key)) {
        w = ww * 0.6f;
        return float(wIndex) * ww - w * 0.5f;
      }
      w = ww;
      return float(wIndex) * ww;
    };
    auto noteColor = [&](int key) {
      int oct = key / 12 % 3;
      const Color& base = f.colors[size_t(1 + oct)];
      return isBlack(key) ? Color{base.r * 0.8f, base.g * 0.8f, base.b * 0.85f, 1.0f} : base;
    };
    // Guías de octava.
    Path guides;
    for (int o = 0; o <= keys / 12; o++) {
      float x = float(o * 7) * ww;
      guides.moveTo(x, 0).lineTo(x, keyTop);
    }
    Paint gp;
    gp.strokeWidth = 1.0f * px;
    gp.color = Color{1, 1, 1, 0.06f};
    c.path(guides, gp);
    // Notas: barras redondeadas por color.
    std::array<bool, kMaxKeys> pressed{};
    for (const auto& n : notes) {
      float w;
      float x = keyX(n.key, w);
      float yTop = keyTop - float(clock - n.start) * speed;
      float yBottom = n.end < 0.0 ? keyTop : keyTop - float(clock - n.end) * speed;
      if (n.end < 0.0 || clock - n.end < 0.05) pressed[size_t(n.key)] = true;
      if (yBottom < 0.0f) continue;
      Color col = noteColor(n.key);
      float lit = (0.85f + 0.3f * bass + 0.2f * kick) * amp;
      Rect r{x + w * 0.1f, std::max(yTop, -10.0f), w * 0.8f, std::max(yBottom - std::max(yTop, -10.0f), 2.0f)};
      if (m.brillo) {
        Paint halo;
        halo.blend = Blend::plus;
        halo.color = col.opacity(std::clamp(0.18f * f.glow * amp, 0.0f, 1.0f));
        c.rect({r.x - 4.0f * px, r.y - 4.0f * px, r.width + 8.0f * px, r.height + 8.0f * px}, halo);
      }
      Paint body;
      body.color = Color{std::min(1.0f, col.r * lit), std::min(1.0f, col.g * lit), std::min(1.0f, col.b * lit), 1.0f};
      c.rect(r, body);
      Paint edge;
      edge.blend = Blend::plus;
      edge.color = Color{1.0f, 0.95f, 0.85f, std::clamp(0.45f * amp, 0.0f, 1.0f)};
      c.rect({r.x, r.y, r.width, 2.0f * px}, edge);
    }
    // Línea de luz sobre el teclado.
    Paint bar = Paint::linear({0, keyTop - 10.0f * px}, {0, keyTop}, {f.colors[2].opacity(0.0f), f.colors[2].opacity(std::clamp((0.35f + 0.4f * kick) * amp, 0.0f, 1.0f))});
    c.rect({0, keyTop - 10.0f * px, f.width, 10.0f * px}, bar);
    // Teclado: blancas y luego negras.
    for (int pass = 0; pass < 2; pass++) {
      for (int i = 0; i < keys; i++) {
        if (isBlack(i) != (pass == 1)) continue;
        float w;
        float x = keyX(i, w);
        float h = isBlack(i) ? keyH * 0.62f : keyH;
        Paint kp;
        if (pressed[size_t(i)]) {
          Color col = noteColor(i);
          kp.color = Color{std::min(1.0f, col.r * 1.1f), std::min(1.0f, col.g * 1.1f), std::min(1.0f, col.b * 1.1f), 1.0f};
        } else {
          kp.color = isBlack(i) ? Color{0.06f, 0.05f, 0.07f, 1.0f} : Color{0.93f, 0.91f, 0.88f, 1.0f};
        }
        c.rect({x + 0.8f * px, keyTop, w - 1.6f * px, h}, kp);
      }
    }
  }
};
''';
