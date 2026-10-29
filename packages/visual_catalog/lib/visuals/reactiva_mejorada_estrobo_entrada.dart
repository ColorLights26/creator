// Reactiva Mejorada · Estrobo de Entrada — transparencia momentánea. En el golpe grande, de uno a
// tres parpadeos de un estroboscopio colgado arriba, en los pulsos siguientes
// (nunca a menos de 0,34 s) y cada uno más débil (100 %, 70 %, 45 %) con la
// fuente un poco desplazada: quemado en el borde superior y cayendo a azul
// frío saturado sin velar el resto, a pleno en el mismo cuadro y apagado al
// segundo. En sombra, la escena baja de luz sin color, más en los bordes.
// Referente: la entrada de un estroboscopio en un drop.
// Versión mejorada: sigue el ritmo (cada golpe o cada tiempo) y su fuerza
// depende del volumen de la música.
// Funciona encima de cualquier escena sin conocerla: sólo luz, sin objetos que
// se queden. Sin música no dibuja nada. Nunca más de tres destellos por segundo.
// Su detalle sale de una textura propia de alta calidad que el shader anima.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // MÚSICA: qué momento lo lanza.
  CreatorModifier.choice('disparo', 'Lo dispara', options: ['Golpes acentuados', 'Golpes en la subida', 'Cada dos tiempos']),
  // FORMA: cuántos parpadeos.
  CreatorModifier.steps('rafaga', 'Parpadeos', min: 1, max: 3, value: 3),
  // ATMÓSFERA: luz, sombra o los dos alternados.
  CreatorModifier.choice('tono', 'Tono', options: ['Luz', 'Sombra', 'Luz y sombra']),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Relámpago', {'rafaga': 2, 'tono': 'Luz'}),
  CreatorVariation('Pulso Negro', {'tono': 'Sombra', 'rafaga': 3}),
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
  int pending = 0, blink = 0;
  float burst = 0.0f;
  void resetOwn(uint32_t) {
    pending = blink = 0;
    burst = 0.0f;
  }
  void update(const Frame& f) override {
    const Hits h = listen(f);
    const auto m = modifiers(f);
    float s = 0.0f;
    if (m.disparo == 0) {
      s = h.big;
    } else if (m.disparo == 1) {
      s = h.jump;
    } else {
      for (int i = 0; i < h.beats; i++)
        if (h.tick[i] % 2 == 0) s = std::max(h.beat, 0.5f);
    }
    // Los parpadeos que faltan de la ráfaga van primero: caen en los pulsos
    // siguientes (nunca a menos de 0,34 s); sin pulsos, la ráfaga se olvida.
    if (pending > 0 && now - lastFire > 1.5) pending = 0;
    if (pending > 0) {
      if (h.beats > 0 && fire(burst, blink)) {
        pending--;
        blink++;
      }
      return;
    }
    if (s > 0.0f && fire(s, 0)) {
      pending = std::clamp(m.rafaga, 1, 3) - 1;
      blink = 1;
      burst = s;
    }
  }
  void render(const Frame& f, Canvas& c) const override {
    const auto m = modifiers(f);
    const float W = f.width, H = f.height;
    const Pulse* last = nullptr;
    for (const Pulse& p : slots)
      if (p.start <= now && (last == nullptr || p.start > last->start)) last = &p;
    if (last == nullptr) return;
    const float a = float(now - last->start) * pace(f);
    // A pleno en el cuadro del golpe, un 30 % en el siguiente y nada.
    if (a > 0.058f) return;
    const float level = (a < 0.025f ? 1.0f : 0.3f) * std::min(amount(last->power) * f.intensity, 1.2f);
    // Los parpadeos siguientes se encogen (mismo pico, menos alcance).
    const float reach = last->kind == 0 ? 1.0f : last->kind == 1 ? 0.7f : 0.45f;
    // Cada parpadeo con la fuente un poco desplazada.
    const float x = 0.5f * W + (last->kind == 0 ? 0.0f : (rnd(last->id * 3u + 1u) < 0.5f ? -60.0f : 60.0f) * W / 360.0f);
    // Luz, sombra o los dos alternados.
    const bool dark = m.tono == 1 || (m.tono == 2 && last->kind % 2 == 1);
    const Color shadow = f.colors[1], cool = f.colors[2], white = f.colors[3];
    c.material("strobe", {0.0f, 0.0f, W, H},
               {dark ? 0.0f : level, dark ? 0.45f * level * reach : 0.0f, x, reach, shadow.r, shadow.g, shadow.b, cool.r, cool.g, cool.b, white.r, white.g, white.b});
  }
};
''';

const shaderSources = <String, String>{
  'strobe': r'''
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform float uLight;
uniform float uDark;
uniform float uX;
uniform float uReach;
uniform vec3 uShadow;
uniform vec3 uCool;
uniform vec3 uWhite;
out vec4 fragColor;

void main() {
  vec2 p = FlutterFragCoord().xy;
  float px1 = uSize.x / 360.0;
  // Desde el borde superior: quemado sólo hasta 12 px y siempre bajando:
  // +245 a 24, +232 a 44, +215 a 64, +200 a 80, +170 a 120, +110 a 180,
  // +60 a 260, +25 a 360 y nada a 470.
  float y = p.y / px1 / max(uReach, 0.1);
  float I = y < 12.0 ? mix(1.1, 1.0, y / 12.0) : (y < 40.0 ? mix(1.0, 0.933, (y - 12.0) / 28.0) : (y < 70.0 ? mix(0.933, 0.843, (y - 40.0) / 30.0)
          : (y < 100.0 ? mix(0.843, 0.745, (y - 70.0) / 30.0) : (y < 120.0 ? mix(0.745, 0.647, (y - 100.0) / 20.0)
          : (y < 180.0 ? mix(0.647, 0.431, (y - 120.0) / 60.0) : (y < 260.0 ? mix(0.431, 0.235, (y - 180.0) / 80.0)
          : (y < 360.0 ? mix(0.235, 0.098, (y - 260.0) / 100.0) : mix(0.098, 0.0, clamp((y - 360.0) / 110.0, 0.0, 1.0)))))))));
  float dx = (p.x - uX) / px1;
  I *= 0.75 + 0.25 * exp(-dx * dx / (2.0 * 150.0 * 150.0));
  // Color por el brillo final: blanco frío (B >= R) que se va volviendo azul
  // a la vez que baja el brillo, sin cambiar de tono a brillo constante.
  float L = I * uLight;
  float tw = smoothstep(0.65, 1.0, L);
  vec3 col = vec3(mix(0.3, 0.9, tw), mix(0.52, 0.94, tw), 1.0) * mix(vec3(1.0), uCool / max(uCool.b, 0.01), 0.05)
           * mix(vec3(1.0), uWhite, 0.03);
  vec3 light = col * min(L, 1.0);
  // En sombra, el campo de Latido Oscuro: el centro baja un 65 % de las
  // esquinas.
  // Cada parpadeo con su propio centro y forma.
  vec2 d = (p - vec2(uX, 0.5 * uSize.y)) / (0.5 * uSize);
  float shade = uDark * mix(0.64, 1.0, smoothstep(0.0, 1.3, length(d))) * (1.0 + 0.1 * cos(2.0 * atan(d.y, d.x) + uX / px1 * 0.05));
  vec3 tone = min(light, vec3(1.0));
  float m = max(tone.r, max(tone.g, tone.b));
  fragColor = vec4(tone + uShadow * shade, clamp(max(shade * (1.0 - m), 0.1 * m), 0.0, 1.0));
}
''',

};
