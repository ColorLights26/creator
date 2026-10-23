// Reactiva · Destello de Drop — transparencia momentánea. Sólo en el golpe grande se abre
// una luz desde el centro (o desde abajo, como un amanecer): un núcleo
// quemado de 8 px sin meseta, con una caída de luz real (blanco cálido, una
// franja de oro y rojo anaranjado a rojo vivo), que crece en tres cuadros y
// se apaga encogiéndose hasta quedar en una brasa roja que desaparece. A la
// vez sale un frente de luz roja suave, con lóbulos que giran, que se ensancha
// y se apaga antes de 220 px. Aparece muy de vez en cuando. Sólo suma luz.
// Referente: el fogonazo de luz de un drop en un festival.
// Funciona encima de cualquier escena sin conocerla: sólo luz, sin objetos que
// se queden. Sin música no dibuja nada. Nunca más de tres destellos por segundo.
// Su detalle sale de una textura propia de alta calidad que el shader anima.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // MÚSICA: qué momento lo enciende.
  CreatorModifier.choice('disparo', 'Lo dispara', options: ['Golpe grande', 'Subida de energía', 'Los dos']),
  // FORMA: desde dónde se abre la luz.
  CreatorModifier.choice('forma', 'Forma', options: ['Desde el centro', 'Desde abajo']),
  // ATMÓSFERA: cuánto más cálido es el núcleo de la luz.
  CreatorModifier.slider('nucleo', 'Núcleo cálido', min: 0, max: 1, value: .5),
  // MOVIMIENTO: cuánto tarda en apagarse.
  CreatorModifier.slider('caida', 'Caída', min: .3, max: .9, value: .45),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Amanecer', {'forma': 'Desde abajo', 'nucleo': 1, 'caida': .7}),
  CreatorVariation('Fogonazo', {'forma': 'Desde el centro', 'caida': .3, 'nucleo': 0}),
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
  float eFast = 0.0f, eMid = 0.0f, eSlow = 0.0f, bassSlow = 0.0f, build = 0.0f, impactMean = 0.0f, hatMean = 0.0f;
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
      bassSlow += (mu.bass - bassSlow) * (mu.bass > bassSlow ? 0.15f : 0.047f);
      // Subida: la energía de medio plazo crece por encima de la lenta.
      if (eMid > eSlow * 1.12f + 0.015f) build = std::min(1.0f, build + float(kStep) * 0.7f);
      else build = std::max(0.0f, build - float(kStep) * 0.9f);
    }
    for (const Event& e : mu.events[0]) {  // bombo
      const float s = std::max(e.strength, 0.05f);
      h.kick = std::max(h.kick, s);
      // Golpe grande: el primero tras una pausa o uno claramente más fuerte que los últimos.
      if (now - lastImpact > 1.5 || s > std::max(0.3f, impactMean * 1.3f)) h.big = std::max(h.big, std::max(s, 0.5f));
      // Vuelta tras una pausa: el primer golpe después de un silencio.
      if (quiet > 1.2) h.back = std::max(h.back, std::max(s, 0.5f));
      impactMean = impactMean <= 0.0f ? s : impactMean + (s - impactMean) * 0.25f;
      lastImpact = now;
    }
    for (const Event& e : mu.events[1]) {  // caja o palmada; platillos en la banda alta
      const float s = std::max(e.strength, 0.05f);
      if (e.band == 3) {
        h.hat = std::max(h.hat, s);
        if (s > std::max(0.12f, hatMean * 1.35f) && now - lastHatBig > 1.0) {
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
      if (now - lastBig < 2.5) {
        h.big = 0.0f;
      } else {
        lastBig = now;
        if (build > 0.5f) {  // golpe grande al final de una subida: el drop
          h.drop = true;
          build = 0.0f;
        }
      }
    }
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
    if (mu.active && (mu.energy > 0.06f || !mu.events[0].empty() || !mu.events[1].empty())) lastSound = now;
    return h;
  }

  // Guarda un momento. Con gated respeta la pausa mínima entre destellos.
  bool fire(float power, int kind = 0, double delay = 0.0, bool gated = true) {
    if (power <= 0.0f) return false;
    if (gated) {
      if (now - lastFire < kGap) return false;
      lastFire = now + delay;
    }
    slots[cursor] = Pulse{now + delay, power, kind, fired++};
    cursor = (cursor + 1) % kSlots;
    return true;
  }
  // Primer pulso de cada grupo de n (n = 4: compás; n = 16: frase).
  static float every(const Hits& h, int n) {
    for (int i = 0; i < h.beats; i++)
      if (h.tick[i] % n == 0) return std::max(h.beat, 0.5f);
    return 0.0f;
  }

  static uint32_t mixh(uint32_t x) {
    x ^= x >> 16; x *= 0x7feb352du; x ^= x >> 15; x *= 0x846ca68bu; x ^= x >> 16;
    return x;
  }
  static float rnd(uint32_t x) { return float(mixh(x) & 0xffffffu) / 16777216.0f; }
  // Un golpe más fuerte se nota un poco más, nunca el doble.
  static float amount(float power) { return std::clamp(0.65f + 0.7f * power, 0.65f, 1.25f); }
  static float pace(const Frame& f) { return std::clamp(f.speed, 0.5f, 2.0f); }
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
    eFast = eMid = eSlow = bassSlow = build = impactMean = hatMean = 0.0f;
    bassHigh = false;
    for (auto& b : bins_) b.reserve(2048);
    resetOwn(seed);
  }
  void resetOwn(uint32_t) {}
  void update(const Frame& f) override {
    const Hits h = listen(f);
    const int d = modifiers(f).disparo;
    fire(d == 0 ? h.big : d == 1 ? h.jump : std::max(h.big, h.jump), 0);
  }
  void render(const Frame& f, Canvas& c) const override {
    auto g = glide(f);
    const auto m = modifiers(f);
    const float W = f.width, H = f.height;
    const float T = g.caida;
    const Color red = f.colors[1], amber = f.colors[2], white = f.colors[3];
    for (const Pulse& p : slots) {
      const float a = float(now - p.start) * pace(f);
      if (a < 0.0f || a > T) continue;
      // Crece en tres cuadros, se encoge mientras sigue quemado (8 -> 3 px)
      // y acaba en una brasa roja que desaparece en los últimos tres.
      float sc = 0.0f, ember = 0.0f;
      if (a < 0.1f) sc = 0.4f + 0.6f * easeOut(a / 0.1f);
      else if (a < T - 0.1f) sc = 1.0f - 0.625f * easeInOut((a - 0.1f) / std::max(T - 0.2f, 0.05f));
      else ember = 0.001f + clamp01((a - (T - 0.1f)) / 0.1f);
      const float k = std::min(amount(p.power) * f.intensity, 1.2f);
      const float cy = m.forma == 1 ? H + 30.0f * W / 360.0f : 0.5f * H;
      c.material("bloom", {0.0f, 0.0f, W, H},
                 {0.5f * W, cy, sc, k, g.nucleo, float(m.forma), a, ember,
                  red.r, red.g, red.b, amber.r, amber.g, amber.b, white.r, white.g, white.b});
    }
  }
};
''';

const shaderSources = <String, String>{
  'bloom': r'''
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec2 uCenter;
uniform float uGrow;
uniform float uAmp;
uniform float uWarmth;
uniform float uForm;
uniform float uAge;
uniform float uEmber;
uniform vec3 uRed;
uniform vec3 uAmber;
uniform vec3 uWhite;
out vec4 fragColor;

void main() {
  vec2 p = FlutterFragCoord().xy;
  float px1 = uSize.x / 360.0;
  vec2 d = (p - uCenter) / px1;
  if (uForm > 0.5) d.y *= 1.6;
  float r = length(d);
  vec3 red = mix(vec3(1.0, 0.165, 0.063), uRed / max(uRed.r, 0.01), 0.15);
  vec3 orRed = vec3(1.0, 0.29, 0.063);
  vec3 gold = mix(vec3(1.0, 0.784, 0.314), uAmber / max(uAmber.r, 0.01), 0.1);
  vec3 hot = mix(mix(uWhite, vec3(1.0), 0.5), vec3(1.0, 0.9, 0.72), uWarmth * 0.5);
  vec3 light = vec3(0.0);
  float glowAt = 0.0;
  if (uEmber > 0.0) {
    // Brasa roja de 6 px como mucho que desaparece.
    float e = 1.0 - clamp(uEmber - 0.001, 0.0, 1.0);
    light += red * 0.7 * e * uAmp * exp(-r * r / (2.0 * 2.5 * 2.5 * max(e, 0.2)));
  } else {
    // Núcleo sin meseta: quemado sólo en 8 px y +235 a 14, +190 a 22, +130
    // a 34, +80 a 50, +40 a 75, +15 a 110 y nada a 150.
    float rho = r / max(uGrow, 0.05);
    float I = rho < 3.0 ? mix(1.2, 1.0, rho / 3.0) : (rho < 6.0 ? mix(1.0, 0.96, (rho - 3.0) / 3.0) : (rho < 10.0 ? mix(0.96, 0.92, (rho - 6.0) / 4.0)
            : (rho < 13.0 ? mix(0.92, 0.88, (rho - 10.0) / 3.0) : (rho < 22.0 ? mix(0.88, 0.745, (rho - 13.0) / 9.0)
            : (rho < 27.0 ? mix(0.745, 0.68, (rho - 22.0) / 5.0) : (rho < 31.0 ? mix(0.68, 0.62, (rho - 27.0) / 4.0)
            : (rho < 36.0 ? mix(0.62, 0.51, (rho - 31.0) / 5.0) : (rho < 50.0 ? mix(0.51, 0.314, (rho - 36.0) / 14.0)
            : (rho < 75.0 ? mix(0.314, 0.157, (rho - 50.0) / 25.0) : (rho < 110.0 ? mix(0.157, 0.059, (rho - 75.0) / 35.0)
            : mix(0.059, 0.0, clamp((rho - 110.0) / 40.0, 0.0, 1.0))))))))))));
    glowAt = I * uAmp;
    float L = glowAt;
    // Oro sólo por encima del 62 %; por debajo, rojo anaranjado a rojo.
    vec3 col = mix(red, orRed, smoothstep(0.25, 0.55, L));
    col = mix(col, gold, smoothstep(0.62, 0.745, L));
    col = mix(col, hot, smoothstep(0.8, 0.92, L));
    light += col * min(L, 1.2);
  }
  // Frente de luz roja suave: nace a 50 px, sube en 3 px por dentro y deja
  // 15-25 px de cola por fuera; se ensancha de 6 a 20 px y se apaga a 220.
  float Rr = 50.0 + 600.0 * uAge;
  float grow = clamp((Rr - 50.0) / 170.0, 0.0, 1.0);
  float th = 6.0 + 14.0 * grow;
  float dr = r - Rr;
  // Borde exterior nítido (3 px) y estela hacia dentro; entra en dos cuadros.
  // Borde exterior suave (7 px) y estela de 11 px hacia dentro; como mucho
  // 0,6 veces el brillo que tiene debajo.
  float ring = dr > 0.0 ? 1.0 - smoothstep(0.0, 7.0, dr) : exp(dr / 11.0);
  float lobes = 0.8 + 0.2 * sin(4.0 * atan(d.y, d.x) + uAge * 4.2);
  float fin = clamp(uAge / 0.066, 0.0, 1.0);
  float Ir = min(0.55 * (1.0 - grow) * uAmp, 0.6 * glowAt + 0.04 * (1.0 - grow)) * ring * lobes * fin * fin;
  light += mix(red, vec3(1.0, 0.416, 0.063), smoothstep(0.55, 0.62, Ir)) * Ir;
  vec3 tone = min(light, vec3(1.0));
  fragColor = vec4(tone, 0.1 * max(tone.r, max(tone.g, tone.b)));
}
''',

};
