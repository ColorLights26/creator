// Reactiva · Viñeta que Late — transparencia momentánea. Con el golpe, los bordes de la
// escena se oscurecen un instante, como si se mirara por un túnel, y el centro
// —donde está lo importante— no se toca. Sin música no dibuja nada.
// Funciona encima de cualquier escena sin conocerla: sólo sombra o luz neutra,
// sin objetos nuevos. Nunca más de tres destellos por segundo.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // MÚSICA: qué la hace latir.
  CreatorModifier.choice('disparo', 'Lo dispara', options: ['Bombo', 'Graves fuertes', 'Cada pulso']),
  // FORMA: qué bordes se oscurecen.
  CreatorModifier.choice('marco', 'Marco', options: ['Óvalo', 'Laterales', 'Arriba y abajo']),
  // ATMÓSFERA: cuánto del centro queda intacto.
  CreatorModifier.slider('apertura', 'Centro intacto', min: .2, max: .75, value: .45),
  // MOVIMIENTO: cuánto tarda en volver.
  CreatorModifier.slider('caida', 'Caída', min: .08, max: .5, value: .22),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Túnel', {'marco': 'Óvalo', 'apertura': .25, 'caida': .35}),
  CreatorVariation('Pantalla Ancha', {'marco': 'Arriba y abajo', 'apertura': .6, 'disparo': 'Cada pulso'}),
];

const nativeSource = r'''
class Visual final : public Scene {
  // Fotosensibilidad: nunca más de 3 destellos por segundo.
  static constexpr double kGap = 0.34;
  static constexpr double kStep = 1.0 / 60.0;
  // Por debajo de esta opacidad no se pinta nada: sin su momento, la capa
  // queda vacía y no cuesta nada.
  static constexpr float kMin = 0.004f;
  static constexpr int kSlots = 8;
  struct Pulse { double start = -100.0; float power = 0.0f; int kind = 0; };
  // Lo que la música trae en este cuadro.
  struct Hits {
    float kick = 0.0f, snare = 0.0f, hat = 0.0f, beat = 0.0f, big = 0.0f, jump = 0.0f, bassUp = 0.0f;
    int beats = 0;               // pulsos nuevos en este cuadro
    std::array<int, 4> tick{};   // número de cada pulso nuevo desde el inicio
  };
  std::array<Pulse, kSlots> slots{};
  int cursor = 0, beatCount = 0, flip = 0;
  double now = 0.0, acc = 0.0, lastFire = -100.0, lastImpact = -100.0, lastBig = -100.0, lastJump = -100.0;
  float eFast = 0.0f, eSlow = 0.0f, impactMean = 0.0f;
  bool bassHigh = false;

  Hits listen(const Frame& f) {
    Hits h;
    const Music& mu = f.music;
    now += f.delta;
    acc += f.delta;
    while (acc >= kStep) {
      acc -= kStep;
      eFast += (mu.energy - eFast) * 0.19f;
      eSlow += (mu.energy - eSlow) * 0.0042f;
    }
    for (const Event& e : mu.events[0]) {  // bombo
      const float s = std::max(e.strength, 0.05f);
      h.kick = std::max(h.kick, s);
      // Golpe grande: el primero tras una pausa o uno claramente más fuerte
      // que los últimos; así no depende del volumen de la canción.
      if (now - lastImpact > 1.5 || s > std::max(0.3f, impactMean * 1.3f)) h.big = std::max(h.big, std::max(s, 0.5f));
      impactMean = impactMean <= 0.0f ? s : impactMean + (s - impactMean) * 0.25f;
      lastImpact = now;
    }
    for (const Event& e : mu.events[1]) {  // caja o palmada; platillos en la banda alta
      const float s = std::max(e.strength, 0.05f);
      if (e.band == 3) h.hat = std::max(h.hat, s);
      else h.snare = std::max(h.snare, s);
    }
    for (const Event& e : mu.events[2]) {  // pulso
      h.beat = std::max(h.beat, std::max(e.strength, 0.05f));
      if (h.beats < 4) h.tick[h.beats++] = beatCount;
      beatCount++;
    }
    for (const Event& e : mu.events[3]) h.big = std::max(h.big, std::max(e.strength, 0.6f));  // gran momento
    if (h.big > 0.0f) {
      if (now - lastBig < 2.5) h.big = 0.0f;
      else lastBig = now;
    }
    // Subida de energía: la energía inmediata salta muy por encima de la media lenta.
    if (eFast > 0.12f && eFast > eSlow * 1.6f + 0.05f && now - lastJump > 6.0) {
      h.jump = std::clamp(eFast * 2.0f, 0.5f, 1.0f);
      lastJump = now;
    }
    if (!bassHigh && mu.bass > 0.72f) {
      bassHigh = true;
      h.bassUp = mu.bass;
    } else if (bassHigh && mu.bass < 0.5f) {
      bassHigh = false;
    }
    return h;
  }

  // Guarda un destello. Con gated, respeta la pausa mínima entre destellos.
  bool fire(float power, int kind, double delay = 0.0, bool gated = true) {
    if (power <= 0.0f) return false;
    if (gated) {
      if (now - lastFire < kGap) return false;
      lastFire = now + delay;
    }
    slots[cursor] = Pulse{now + delay, power, kind};
    cursor = (cursor + 1) % kSlots;
    return true;
  }

  // Entra en 25 ms y se apaga en dur segundos.
  static float envelope(double age, float dur) {
    if (age < 0.0) return 0.0f;
    const double attack = 0.025;
    if (age < attack) return float(age / attack);
    const float x = float((age - attack) / double(std::max(dur, 0.02f)));
    if (x >= 1.0f) return 0.0f;
    const float k = 1.0f - x;
    return k * k;
  }
  // Un golpe más fuerte se nota un poco más, nunca el doble.
  static float amount(float power) { return std::clamp(0.65f + 0.7f * power, 0.65f, 1.25f); }
  float level(int kind, float dur) const {
    float v = 0.0f;
    for (const Pulse& p : slots)
      if (kind < 0 || p.kind == kind) v = std::max(v, amount(p.power) * envelope(now - p.start, dur));
    return v;
  }
  static float pace(const Frame& f) { return std::clamp(f.speed, 0.5f, 2.0f); }
  static Color mixc(Color a, Color b, float t) {
    return {a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t};
  }
  static Color tint(Color c, float a) { return c.opacity(std::clamp(a, 0.0f, 1.0f)); }
  static float ease(float t) {
    t = std::clamp(t, 0.0f, 1.0f);
    return t * t * (3.0f - 2.0f * t);
  }

  // Toda la pantalla de un tono (edge 0) o cada vez más hacia los bordes (edge 1).
  static void shade(Canvas& c, const Frame& f, Color col, float a, float edge) {
    if (a < kMin) return;
    const float W = f.width, H = f.height;
    if (edge < 0.01f) {
      Paint p;
      p.color = tint(col, a);
      c.rect({0.0f, 0.0f, W, H}, p);
      return;
    }
    const float inner = a * (1.0f - 0.9f * edge), outer = a * (1.0f + 0.7f * edge);
    c.save();
    c.translate(W * 0.5f, H * 0.5f);
    c.scale(1.0f, H / W);
    Paint p = Paint::radial({0.0f, 0.0f}, W * 0.7072f, {tint(col, inner), tint(col, inner), tint(col, outer)},
                            {0.0f, 0.2f + 0.4f * edge, 1.0f});
    c.rect({-W * 0.5f, -W * 0.5f, W, W}, p);
    c.restore();
  }

  // Sólo los bordes: 0 óvalo, 1 laterales, 2 arriba y abajo. open es la
  // parte del centro que no se toca.
  static void frameShade(Canvas& c, const Frame& f, Color col, float a, float open, int marco) {
    if (a < kMin) return;
    const float W = f.width, H = f.height;
    if (marco == 0) {
      c.save();
      c.translate(W * 0.5f, H * 0.5f);
      c.scale(1.0f, H / W);
      Paint p = Paint::radial({0.0f, 0.0f}, W * 0.7072f, {tint(col, 0.0f), tint(col, 0.0f), tint(col, a)}, {0.0f, open, 1.0f});
      c.rect({-W * 0.5f, -W * 0.5f, W, W}, p);
      c.restore();
    } else if (marco == 1) {
      sideShade(c, f, col, a, open, false);
      sideShade(c, f, col, a, open, true);
    } else {
      const float d = H * (1.0f - open) * 0.5f;
      Paint top = Paint::linear({0.0f, 0.0f}, {0.0f, d}, {tint(col, a), tint(col, a * 0.4f), tint(col, 0.0f)}, {0.0f, 0.35f, 1.0f});
      c.rect({0.0f, 0.0f, W, d}, top);
      Paint bottom = Paint::linear({0.0f, H}, {0.0f, H - d}, {tint(col, a), tint(col, a * 0.4f), tint(col, 0.0f)}, {0.0f, 0.35f, 1.0f});
      c.rect({0.0f, H - d, W, d}, bottom);
    }
  }
  static void sideShade(Canvas& c, const Frame& f, Color col, float a, float open, bool right) {
    if (a < kMin) return;
    const float W = f.width, H = f.height, d = W * (1.0f - open) * 0.5f;
    const float x0 = right ? W : 0.0f, x1 = right ? W - d : d;
    Paint p = Paint::linear({x0, 0.0f}, {x1, 0.0f}, {tint(col, a), tint(col, a * 0.4f), tint(col, 0.0f)}, {0.0f, 0.35f, 1.0f});
    c.rect({right ? W - d : 0.0f, 0.0f, d, H}, p);
  }

  // Una franja de luz suave que cruza la pantalla; pos va de 0 a 1.
  static void sweep(Canvas& c, const Frame& f, Color lit, Color warm, float a, float pos, float band, float degrees) {
    const float b = a * std::sin(float(pi) * std::clamp(pos, 0.0f, 1.0f));
    if (b < kMin) return;
    const float W = f.width, H = f.height, L = 0.5f * std::sqrt(W * W + H * H) + band;
    const float x = -L + 2.0f * L * pos;
    c.save();
    c.translate(W * 0.5f, H * 0.5f);
    c.rotate(degrees * float(pi) / 180.0f);
    Paint p = Paint::linear({x - band * 0.5f, 0.0f}, {x + band * 0.5f, 0.0f},
                            {tint(warm, 0.0f), tint(warm, b * 0.35f), tint(lit, b), tint(warm, b * 0.35f), tint(warm, 0.0f)},
                            {0.0f, 0.3f, 0.5f, 0.7f, 1.0f});
    c.rect({x - band * 0.5f, -L, band, 2.0f * L}, p);
    c.restore();
  }

 public:
  void reset(uint32_t) override {
    slots = {};
    cursor = beatCount = flip = 0;
    now = acc = 0.0;
    lastFire = lastImpact = lastBig = lastJump = -100.0;
    eFast = eSlow = impactMean = 0.0f;
    bassHigh = false;
  }
  void update(const Frame& f) override {
    const Hits h = listen(f);
    const int d = modifiers(f).disparo;
    fire(d == 0 ? h.kick : d == 1 ? h.bassUp : h.beat, 0);
  }
  void render(const Frame& f, Canvas& c) const override {
    auto g = glide(f);
    const float a = std::min(0.22f * level(0, g.caida / pace(f)) * f.intensity, 0.34f);
    if (a < kMin) return;
    for (int m = 0; m < 3; m++) {
      const float w = g.marco.weight(m);
      if (w > 0.002f) frameShade(c, f, f.colors[1], a * w, g.apertura, m);
    }
  }
};
''';
