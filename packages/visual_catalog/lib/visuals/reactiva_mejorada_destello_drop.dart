// Reactiva Mejorada · Destello de Drop — transparencia momentánea. Sólo en el golpe grande (el
// primero tras una pausa, uno mucho más fuerte que los anteriores o el gran
// momento que marca el análisis) se abre desde el centro una luz suave que se
// apaga enseguida. Aparece muy de vez en cuando. Sin música no dibuja nada.
// Versión mejorada: sigue el ritmo (cada golpe o cada tiempo) y su fuerza
// depende del volumen de la música; los pulsos son cortos para que se
// vean con el compás. La original («Reactiva · Destello de Drop») no se toca.
// Funciona encima de cualquier escena sin conocerla: sólo sombra o luz neutra,
// sin objetos nuevos. Nunca más de tres destellos por segundo.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // MÚSICA: qué momento lo enciende.
  CreatorModifier.choice('disparo', 'Lo dispara', options: ['Golpes acentuados', 'Golpes en la subida', 'Los dos']),
  // FORMA: desde dónde se abre la luz.
  CreatorModifier.choice('forma', 'Forma', options: ['Desde el centro', 'Desde abajo', 'Toda la pantalla']),
  // ATMÓSFERA: cuánto más cálido es el núcleo de la luz.
  CreatorModifier.slider('nucleo', 'Núcleo cálido', min: 0, max: 1, value: .5),
  // MOVIMIENTO: cuánto tarda en apagarse.
  CreatorModifier.slider('caida', 'Caída', min: .2, max: .9, value: .45),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Amanecer', {'forma': 'Desde abajo', 'nucleo': 1, 'caida': .7}),
  CreatorVariation('Fogonazo', {'forma': 'Toda la pantalla', 'caida': .25, 'nucleo': 0}),
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
  float eFast = 0.0f, eSlow = 0.0f, impactMean = 0.0f, loud = 0.0f, peak = 0.0f;
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
      // Volumen: cuánto suena ahora, mezcla del nivel absoluto y del relativo
      // al pico reciente. En silencio vuelve a cero.
      peak = std::max(peak * 0.9985f, eFast);
      const float loudTarget = std::clamp(0.5f * eFast / std::max(peak, 0.05f) + 1.2f * eFast, 0.0f, 1.3f);
      loud += (loudTarget - loud) * (loudTarget > loud ? 0.35f : 0.06f);
    }
    for (const Event& e : mu.events[0]) {  // bombo
      const float s = std::max(e.strength, 0.05f);
      h.kick = std::max(h.kick, s);
      // Golpe grande: el primero tras una pausa o uno claramente más fuerte
      // que los últimos; así no depende del volumen de la canción.
      // Golpe acentuado: igual o más fuerte que la media reciente. En un ritmo
      // regular son casi todos; si unos suenan más, sólo esos.
      if (now - lastImpact > 1.5 || s >= impactMean * 0.98f) h.big = std::max(h.big, std::clamp(s / std::max(impactMean, 0.05f) * 0.6f, 0.3f, 1.2f));
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
      if (now - lastBig < 0.3) h.big = 0.0f;
      else lastBig = now;
    }
    // Subida de energía: la energía inmediata salta muy por encima de la media lenta.
    // Golpes en la subida: cada golpe mientras la energía crece.
    if (h.kick > 0.0f && eFast > eSlow * 1.05f) h.jump = h.kick;
    if (!bassHigh && mu.bass > 0.45f) {
      bassHigh = true;
      h.bassUp = mu.bass;
    } else if (bassHigh && mu.bass < 0.3f) {
      bassHigh = false;
    }
    return h;
  }

  // Guarda un destello. Con gated, respeta la pausa mínima entre destellos.
  bool fire(float power, int kind, double delay = 0.0, bool gated = true) {
    if (power <= 0.0f) return false;
    power *= 0.3f + 0.9f * loud;  // el volumen decide cuánto se ve
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
  // Cuanto más fuerte suena el golpe, más se nota.
  static float amount(float power) { return std::clamp(0.25f + 0.85f * power, 0.15f, 1.45f); }
  float level(int kind, float dur) const {
    float v = 0.0f;
    for (const Pulse& p : slots)
      if (kind < 0 || p.kind == kind) v = std::max(v, amount(p.power) * envelope(now - p.start, dur));
    return v;
  }
  static float pace(const Frame& f) { return 1.6f * std::clamp(f.speed, 0.5f, 2.0f); }
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
    eFast = eSlow = impactMean = loud = peak = 0.0f;
    bassHigh = false;
  }
  void update(const Frame& f) override {
    const Hits h = listen(f);
    const int d = modifiers(f).disparo;
    fire(d == 0 ? h.big : d == 1 ? h.jump : std::max(h.big, h.jump), 0);
  }
  void render(const Frame& f, Canvas& c) const override {
    auto g = glide(f);
    const float dur = g.caida / pace(f);
    float v = 0.0f, grow = 0.0f;
    for (const Pulse& p : slots) {
      const float e = amount(p.power) * envelope(now - p.start, dur);
      if (e > v) {
        v = e;
        grow = std::clamp(float((now - p.start) / double(dur)), 0.0f, 1.0f);
      }
    }
    const float a = std::min(0.22f * v * f.intensity, 0.3f);
    if (a < kMin) return;
    const float W = f.width, H = f.height, D = std::sqrt(W * W + H * H);
    const Color lit = f.colors[3], core = mixc(f.colors[3], f.colors[2], g.nucleo);
    // La luz se abre mientras se apaga.
    const float r = D * (0.42f + 0.45f * grow);
    const float w0 = g.forma.weight(0), w1 = g.forma.weight(1), w2 = g.forma.weight(2);
    if (w0 > 0.002f) {
      Paint p = Paint::radial({W * 0.5f, H * 0.46f}, r, {tint(core, a * w0), tint(lit, a * 0.45f * w0), tint(lit, 0.0f)}, {0.0f, 0.45f, 1.0f});
      c.rect({0.0f, 0.0f, W, H}, p);
    }
    if (w1 > 0.002f) {
      Paint p = Paint::radial({W * 0.5f, H * 1.04f}, r * 1.3f, {tint(core, a * w1), tint(lit, a * 0.45f * w1), tint(lit, 0.0f)}, {0.0f, 0.45f, 1.0f});
      c.rect({0.0f, 0.0f, W, H}, p);
    }
    if (w2 > 0.002f) {
      Paint p;
      p.color = tint(mixc(lit, core, 0.5f), a * 0.7f * w2);
      c.rect({0.0f, 0.0f, W, H}, p);
    }
  }
};
''';
