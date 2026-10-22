// Reactiva Mejorada · Aurora que se Enciende — transparencia momentánea. Durante la subida de
// energía baja desde arriba, en unos veinte cuadros, la cortina de una aurora
// boreal: una cinta de borde suave que ondula en dos o tres olas y se pliega,
// con rayos verticales finos que bailan despacio y que en los pliegues (donde
// la lámina se ve de canto) se apiñan y brillan el doble. El borde es verde
// intenso que se desvanece hacia arriba, con una franja magenta debajo y el
// carmesí de la gran altura sólo arriba del todo. En el pico brilla el doble y
// se retira hacia arriba en medio segundo. La luz se suma a la escena.
// Referente: fotografías de aurora boreal (Tromsø, Islandia).
// Versión mejorada: sigue el ritmo (cada golpe o cada tiempo) y su fuerza
// depende del volumen de la música.
// Funciona encima de cualquier escena sin conocerla: sólo luz, sin objetos que
// se queden. Sin música no dibuja nada. Nunca más de tres destellos por segundo.
// Su detalle sale de una textura propia de alta calidad que el shader anima.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // MÚSICA: qué la enciende.
  CreatorModifier.choice('disparo', 'Lo dispara', options: ['Volumen', 'Cada dos tiempos', 'Golpes acentuados']),
  // FORMA: hasta dónde baja la cortina.
  CreatorModifier.slider('altura', 'Altura de la cortina', min: .15, max: .45, value: .3),
  // MOVIMIENTO: cuánto se pliega.
  CreatorModifier.slider('pliegues', 'Pliegues', min: 0, max: 1, value: .6),
  // ATMÓSFERA: colores de la aurora.
  CreatorModifier.choice('tono', 'Tono', options: ['Verde y carmesí', 'Toda roja']),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Aurora Roja', {'tono': 'Toda roja', 'altura': .4}),
  CreatorVariation('Velo Polar', {'altura': .2, 'pliegues': 1, 'disparo': 'Cada dos tiempos'}),
];

const nativeSource = r'''
class Visual final : public Scene {
  // Fotosensibilidad: nunca más de 3 destellos por segundo.
  static constexpr double kGap = 0.34;
  static constexpr double kStep = 1.0 / 60.0;
  // Por debajo de esta opacidad no se pinta nada: sin su momento la capa
  // queda vacía y no cuesta nada.
  static constexpr float kMin = 0.004f;
  static constexpr int kSlots = 8;
  struct Pulse { double start = -100.0; float power = 0.0f; int kind = 0; uint32_t id = 0; };
  // Lo que la música trae en este cuadro.
  struct Hits {
    float kick = 0.0f, snare = 0.0f, hat = 0.0f, hatBig = 0.0f, beat = 0.0f, big = 0.0f, jump = 0.0f, back = 0.0f, bassUp = 0.0f;
    bool drop = false;
    int beats = 0;               // pulsos nuevos en este cuadro
    std::array<int, 4> tick{};   // número de cada pulso nuevo desde el inicio
  };
  std::array<Pulse, kSlots> slots{};
  int cursor = 0, beatCount = 0, flip = 0;
  uint32_t fired = 0;
  double now = 0.0, acc = 0.0, lastFire = -100.0, lastImpact = -100.0, lastBig = -100.0, lastJump = -100.0;
  double lastSound = -100.0, lastHatBig = -100.0;
  float eFast = 0.0f, eMid = 0.0f, eSlow = 0.0f, bassSlow = 0.0f, build = 0.0f, impactMean = 0.0f, hatMean = 0.0f, loud = 0.0f, peak = 0.0f;
  bool bassHigh = false;
  // Lotes de puntos reutilizados cada cuadro (reservados en reset).
  mutable std::array<std::vector<Vec2>, 12> bins_;

  Hits listen(const Frame& f) {
    Hits h;
    const Music& mu = f.music;
    const double quiet = now - lastSound;
    now += f.delta;
    acc += f.delta;
    while (acc >= kStep) {
      acc -= kStep;
      eFast += (mu.energy - eFast) * 0.19f;
      eMid += (mu.energy - eMid) * 0.033f;
      eSlow += (mu.energy - eSlow) * 0.0042f;
      // Volumen: cuánto suena ahora, mezcla del nivel absoluto y del relativo
      // al pico reciente. En silencio vuelve a cero.
      peak = std::max(peak * 0.9985f, eFast);
      const float loudTarget = std::clamp(0.5f * eFast / std::max(peak, 0.05f) + 1.2f * eFast, 0.0f, 1.3f);
      loud += (loudTarget - loud) * (loudTarget > loud ? 0.35f : 0.06f);
      bassSlow += (mu.bass - bassSlow) * (mu.bass > bassSlow ? 0.15f : 0.047f);
      // Subida: la energía de medio plazo crece por encima de la lenta.
      if (eMid > eSlow * 1.12f + 0.015f) build = std::min(1.0f, build + float(kStep) * 0.7f);
      else build = std::max(0.0f, build - float(kStep) * 0.9f);
    }
    for (const Event& e : mu.events[0]) {  // bombo
      const float s = std::max(e.strength, 0.05f);
      h.kick = std::max(h.kick, s);
      // Golpe grande: el primero tras una pausa o uno claramente más fuerte que los últimos.
      // Golpe acentuado: igual o más fuerte que la media reciente. En un ritmo
      // regular son casi todos; si unos suenan más, sólo esos.
      if (now - lastImpact > 1.5 || s >= impactMean * 0.98f) h.big = std::max(h.big, std::clamp(s / std::max(impactMean, 0.05f) * 0.6f, 0.3f, 1.2f));
      // Vuelta tras una pausa: el primer golpe después de un silencio.
      // Cada golpe, con más fuerza si llega tras un silencio.
      h.back = std::max(h.back, quiet > 1.2 ? std::max(s, 0.8f) : s);
      impactMean = impactMean <= 0.0f ? s : impactMean + (s - impactMean) * 0.25f;
      lastImpact = now;
    }
    for (const Event& e : mu.events[1]) {  // caja o palmada; platillos en la banda alta
      const float s = std::max(e.strength, 0.05f);
      if (e.band == 3) {
        h.hat = std::max(h.hat, s);
        if (s >= hatMean * 0.98f && now - lastHatBig > 0.2) {
          h.hatBig = std::max(h.hatBig, s);
          lastHatBig = now;
        }
        hatMean = hatMean <= 0.0f ? s : hatMean + (s - hatMean) * 0.2f;
      } else {
        h.snare = std::max(h.snare, s);
      }
    }
    for (const Event& e : mu.events[2]) {  // pulso
      h.beat = std::max(h.beat, std::max(e.strength, 0.05f));
      if (h.beats < 4) h.tick[h.beats++] = beatCount;
      beatCount++;
    }
    for (const Event& e : mu.events[3]) h.big = std::max(h.big, std::max(e.strength, 0.6f));  // gran momento
    if (h.big > 0.0f) {
      if (now - lastBig < 0.3) {
        h.big = 0.0f;
      } else {
        lastBig = now;
        if (build > 0.5f) {  // golpe grande al final de una subida: el drop
          h.drop = true;
          build = 0.0f;
        }
      }
    }
    // Golpes en la subida: cada golpe mientras la energía crece.
    if (h.kick > 0.0f && eFast > eSlow * 1.05f) h.jump = h.kick;
    if (!bassHigh && mu.bass > 0.45f) {
      bassHigh = true;
      h.bassUp = mu.bass;
    } else if (bassHigh && mu.bass < 0.3f) {
      bassHigh = false;
    }
    if (mu.active && (mu.energy > 0.06f || !mu.events[0].empty() || !mu.events[1].empty())) lastSound = now;
    return h;
  }

  // Guarda un momento. Con gated respeta la pausa mínima entre destellos.
  bool fire(float power, int kind = 0, double delay = 0.0, bool gated = true) {
    if (power <= 0.0f) return false;
    power *= 0.3f + 0.9f * loud;  // el volumen decide cuánto se ve
    if (gated) {
      if (now - lastFire < kGap) return false;
      lastFire = now + delay;
    }
    slots[cursor] = Pulse{now + delay, power, kind, fired++};
    cursor = (cursor + 1) % kSlots;
    return true;
  }
  // Con el ritmo: n = 4 (antes cada compás) es cada tiempo y n = 16 (antes
  // cada frase) es cada dos tiempos.
  static float every(const Hits& h, int n) {
    const int m = n >= 16 ? 2 : 1;
    for (int i = 0; i < h.beats; i++)
      if (h.tick[i] % m == 0) return std::max(h.beat, 0.5f);
    return 0.0f;
  }

  static uint32_t mixh(uint32_t x) {
    x ^= x >> 16; x *= 0x7feb352du; x ^= x >> 15; x *= 0x846ca68bu; x ^= x >> 16;
    return x;
  }
  static float rnd(uint32_t x) { return float(mixh(x) & 0xffffffu) / 16777216.0f; }
  // Cuanto más fuerte suena el golpe, más se nota.
  static float amount(float power) { return std::clamp(0.25f + 0.85f * power, 0.15f, 1.45f); }
  static float pace(const Frame& f) { return 1.6f * std::clamp(f.speed, 0.5f, 2.0f); }
  static float clamp01(float x) { return std::clamp(x, 0.0f, 1.0f); }
  static float easeOut(float t) {
    t = clamp01(t);
    const float k = 1.0f - t;
    return 1.0f - k * k * k;
  }
  static float easeInOut(float t) {
    t = clamp01(t);
    return t * t * (3.0f - 2.0f * t);
  }
  // Entra en attack segundos y se apaga en dur (caída cuadrática).
  static float env(double age, float attack, float dur) {
    if (age < 0.0) return 0.0f;
    if (age < double(attack)) return float(age / double(attack));
    const float x = float((age - double(attack)) / double(std::max(dur, 0.02f)));
    if (x >= 1.0f) return 0.0f;
    const float k = 1.0f - x;
    return k * k;
  }
  // Sube y baja suave en dur segundos.
  static float arc(double age, float dur) {
    if (age <= 0.0 || age >= double(dur)) return 0.0f;
    return std::sin(float(pi) * float(age / double(dur)));
  }
  static Color mixc(Color a, Color b, float t) {
    return {a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t};
  }
  static Color tint(Color c, float a) { return c.opacity(std::clamp(a, 0.0f, 1.0f)); }
  static Color white() { return Color{1.0f, 1.0f, 1.0f, 1.0f}; }
  static Color spectral(float t) {
    const float k = 2.0f * float(pi);
    return {0.5f + 0.5f * std::cos(k * t), 0.5f + 0.5f * std::cos(k * (t - 0.333f)), 0.5f + 0.5f * std::cos(k * (t - 0.667f)), 1.0f};
  }
  // Luz con caída real: núcleo, halo y velo muy tenue.
  static void glow(Canvas& c, Vec2 p, float r, Color core, Color halo, float a) {
    if (a < kMin || r < 0.5f) return;
    Paint q = Paint::radial(p, r, {tint(core, a), tint(halo, a * 0.55f), tint(halo, a * 0.22f), tint(halo, a * 0.06f), tint(halo, 0.0f)},
                            {0.0f, 0.08f, 0.2f, 0.45f, 1.0f});
    q.blend = Blend::plus;
    c.circle(p, r, q);
  }
  // Luz ancha y suave (fugas, quemaduras, humo): cae más despacio que glow.
  static void softGlow(Canvas& c, Vec2 p, float r, Color core, Color halo, float a) {
    if (a < kMin || r < 0.5f) return;
    Paint q = Paint::radial(p, r, {tint(core, a), tint(halo, a * 0.75f), tint(halo, a * 0.32f), tint(halo, 0.0f)}, {0.0f, 0.25f, 0.6f, 1.0f});
    q.blend = Blend::plus;
    c.circle(p, r, q);
  }
  // Anillo de luz fino de radio r y ancho w.
  static void ring(Canvas& c, const Frame& f, Vec2 o, float r, float w, Color col, float a) {
    if (a < kMin || r <= w * 1.05f) return;
    const float R = r + 2.0f * w;
    Paint q = Paint::radial(o, R, {tint(col, 0.0f), tint(col, 0.0f), tint(col, a), tint(col, 0.0f), tint(col, 0.0f)},
                            {0.0f, (r - w) / R, r / R, (r + w) / R, 1.0f});
    q.blend = Blend::plus;
    const float x0 = std::max(0.0f, o.x - R), y0 = std::max(0.0f, o.y - R);
    const float x1 = std::min(f.width, o.x + R), y1 = std::min(f.height, o.y + R);
    if (x1 > x0 && y1 > y0) c.rect({x0, y0, x1 - x0, y1 - y0}, q);
  }
  void clearBins() const {
    for (auto& b : bins_) b.clear();
  }
  void drawBin(Canvas& c, int i, float radius, Color col, float a) const {
    if (bins_[size_t(i)].empty() || a < kMin) return;
    Paint p;
    p.color = tint(col, a);
    p.blend = Blend::plus;
    c.points(bins_[size_t(i)], radius, p);
  }

 public:
  void reset(uint32_t seed) override {
    slots = {};
    cursor = beatCount = flip = 0;
    fired = 0;
    now = acc = 0.0;
    lastFire = lastImpact = lastBig = lastJump = lastSound = lastHatBig = -100.0;
    eFast = eMid = eSlow = bassSlow = build = impactMean = hatMean = loud = peak = 0.0f;
    bassHigh = false;
    for (auto& b : bins_) b.reserve(2048);
    resetOwn(seed);
  }
  float level = 0.0f;
  void resetOwn(uint32_t) { level = 0.0f; }
  void update(const Frame& f) override {
    const Hits h = listen(f);
    const int d = modifiers(f).disparo;
    // Con el volumen: la cortina sube y baja con lo fuerte que suena.
    const float target = d == 0 ? clamp01(loud * 0.9f + 0.4f * build) : 0.0f;
    level += (target - level) * clamp01(float(f.delta) * 3.0f);
    if (d == 0 && h.drop) fire(1.0f, 1);  // en el pico brilla el doble y se retira
    if (d == 0) fire(0.6f * h.kick, 0);  // y late con cada golpe
    if (d == 1) fire(every(h, 16), 0);
    if (d == 2) fire(h.big, 0);
  }
  void render(const Frame& f, Canvas& c) const override {
    auto g = glide(f);
    const auto m = modifiers(f);
    const float W = f.width, H = f.height;
    // Brillo y bajada: la subida (o el volumen), los golpes y el pico, que la
    // dobla y la retira hacia arriba en medio segundo.
    float glow = level * f.intensity, reach = level, lift = 0.0f;
    for (const Pulse& p : slots) {
      const double age = now - p.start;
      if (age < 0.0 || age > 1.6) continue;
      const float k = std::min(amount(p.power) * f.intensity, 1.3f);
      if (p.kind == 1) {
        glow = std::max(glow, 2.0f * env(age, 0.05f, 0.5f / pace(f)) * k);
        lift = std::max(lift, easeInOut(float(age) * pace(f) / 0.45f));
      } else {
        const float e = env(age, 0.6f / pace(f), 1.0f / pace(f)) * k;
        glow = std::max(glow, e);
        reach = std::max(reach, age * pace(f) < 0.6 ? e : 1.0f);
      }
    }
    if (glow < kMin) return;
    const Color red = f.colors[1], green = f.colors[2], pink = f.colors[3];
    // Sólo la parte de arriba, hasta un poco por debajo de la cortina.
    const float band = std::min(H, H * g.altura * 1.1f + 0.2f * W);
    c.material("aurora", {0.0f, 0.0f, W, band},
               {float(now) * pace(f), glow, easeOut(clamp01(reach / 0.7f)), lift, g.altura, g.pliegues, m.tono == 1 ? 1.0f : 0.0f, H / W,
                red.r, red.g, red.b, green.r, green.g, green.b, pink.r, pink.g, pink.b},
               {"noise"});
  }
};
''';

const shaderSources = <String, String>{
  'aurora': r'''
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform float uTime;
uniform float uGlow;
uniform float uDescent;
uniform float uLift;
uniform float uHeight;
uniform float uFolds;
uniform float uAllRed;
uniform float uAspect;
uniform vec3 uRed;
uniform vec3 uGreen;
uniform vec3 uPink;
uniform sampler2D uTex;
out vec4 fragColor;

// Sensor: el color se satura en lo tenue y se quema a blanco en lo intenso.
vec3 sensor(vec3 c) {
  return pow(c / max(max(c.r, c.g), max(c.b, 0.01)), vec3(1.5)) * 0.95 + 0.05;
}

void main() {
  vec2 px = FlutterFragCoord().xy;
  vec2 uv = px / uSize.x;
  float t = uTime;
  float fk = 0.4 + 0.6 * uFolds;
  // Cinta de borde suave: dos olas largas (unos 215 y 130 px) que derivan
  // 1-2 px por cuadro.
  float k1 = 6.2832 / 0.6;
  float k2 = 6.2832 / 0.36;
  float k3 = 6.2832 / 0.167;
  float wave = (0.07 * sin(uv.x * k1 + t * 1.4) + 0.035 * sin(uv.x * k2 - t * 1.0 + 1.3) + 0.014 * sin(uv.x * k3 + t * 2.2)) * fk;
  float slope = (0.07 * k1 * cos(uv.x * k1 + t * 1.4) + 0.035 * k2 * cos(uv.x * k2 - t * 1.0 + 1.3)) * fk;
  // Donde el borde se inclina, la lámina se ve de canto: más rayos y el doble de brillo.
  float steep = smoothstep(0.3, 1.2, abs(slope));
  float target = uHeight * uAspect * 0.85;
  float rx = uv.x * (1.0 + 0.6 * steep) + wave * 0.5;
  float r = texture(uTex, fract(vec2(rx * 6.0 + t * 0.04, uv.y * 0.12 - t * 0.015))).r;
  float r2 = texture(uTex, fract(vec2(rx * 2.3 - t * 0.02, uv.y * 0.08 + 0.4))).g;
  float rays = (0.3 + 1.5 * r * r) * (0.6 + 0.8 * r2);
  // Baja desde arriba con la energía (y en el pico sube y se va); cada rayo
  // acaba a su altura, con no más de 2 px de diferencia.
  float yE = mix(-0.11, target, uDescent) + wave + (r - 0.5) * 0.0055 - uLift * (target + 0.2);
  float d = yE - uv.y;  // > 0 dentro de la cortina
  float dd = max(d, 0.0);
  float inside = smoothstep(-0.007, 0.0, d);
  float base = 0.8 + 0.2 * steep;
  float boost = 1.0 + 1.2 * steep * exp(-dd / 0.035);
  // Verde intenso en todo el borde (el doble en los pliegues) y una cola que
  // sube 120-150 px hasta el carmesí, con la mitad de la energía abajo.
  float hem = 1.5 * boost * rays * base;
  float greenL = (hem * exp(-dd / 0.03) + 0.45 * exp(-dd / 0.15) * rays * base) * inside;
  // Un pliegue en S: la cinta vuelve sobre sí misma 30-50 px más arriba en
  // una zona que deriva despacio, y las dos capas se suman.
  float x0 = fract(0.35 + t * 0.02);
  float fold = exp(-(uv.x - x0) * (uv.x - x0) / 0.0049);
  // La capa de arriba tiene su propio borde (60 % del verde) y su franja.
  float d2 = yE - 0.035 - 0.02 * sin((uv.x - x0) * 40.0) - uv.y;
  float hem2 = 0.6 * hem * fold;
  greenL += hem2 * exp(-max(d2, 0.0) / 0.03) * smoothstep(-0.007, 0.0, d2);
  float fz2 = (d2 + 0.0055) / 0.011;
  float pink2 = 0.45 * hem2 * exp(-fz2 * fz2);
  // Carmesí arriba, que baja fundiéndose con la cola verde unos 60 px.
  float redL = 0.4 * smoothstep(0.25 * max(yE, 0.01) + 0.25, 0.0, uv.y) * (0.5 + 0.5 * rays) * inside;
  // Franja magenta: el 45 % del verde del borde, 2 px por debajo, rota por
  // los mismos rayos.
  float fz = (d + 0.0055) / 0.011;
  float pinkL = 0.45 * hem * exp(-fz * fz) + pink2;
  vec3 light = greenL * sensor(mix(uGreen, uRed, uAllRed)) + redL * sensor(uRed)
             + pinkL * sensor(mix(uPink, uRed, uAllRed * 0.5));
  light *= uGlow * 1.4 * smoothstep(uSize.y, uSize.y * 0.85, px.y);
  vec3 tone = vec3(1.0) - exp(-light);
  fragColor = vec4(tone, 0.1 * max(tone.r, max(tone.g, tone.b)));
}
''',

};
