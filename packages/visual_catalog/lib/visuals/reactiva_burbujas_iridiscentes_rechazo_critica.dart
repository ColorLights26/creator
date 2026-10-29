// Reactiva · Burbujas Iridiscentes — transparencia momentánea. Con el golpe aparecen
// burbujas de jabón de distintos tamaños que suben bamboleándose: su película
// tiene bandas de color de interferencia que fluyen (magenta, verde y azul
// saturados, más intensas en el borde), un reflejo blanco pequeño y el centro
// casi transparente; al final revientan una a una en un anillo de gotas que se
// apaga. Sólo suma luz. Referente: burbujas de jabón en macro y cámara lenta.
// Funciona encima de cualquier escena sin conocerla: sólo luz, sin objetos que
// se queden. Sin música no dibuja nada. Nunca más de tres destellos por segundo.
// Su detalle sale de una textura propia de alta calidad que el shader anima.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.choice('disparo', 'Lo dispara', options: ['Golpe grande', 'Cada frase', 'Subida de energía']),
  // FORMA: cuántas burbujas.
  CreatorModifier.steps('burbujas', 'Burbujas', min: 3, max: 8, value: 6),
  // MOVIMIENTO: cuánto duran antes de reventar.
  CreatorModifier.slider('caida', 'Duración', min: .6, max: 2, value: 1.2),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Nube de Burbujas', {'burbujas': 8, 'caida': 1.8}),
  CreatorVariation('Pompas Rápidas', {'burbujas': 3, 'caida': .7}),
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
    fire(d == 0 ? h.big : d == 1 ? every(h, 16) : h.jump, 0);
  }
  void render(const Frame& f, Canvas& c) const override {
    auto g = glide(f);
    const auto m = modifiers(f);
    const float W = f.width, H = f.height;
    const float px1 = W / 360.0f;
    const float T = g.caida * 1.0f / pace(f);
    const Color mag = f.colors[1], green = f.colors[2], blue = f.colors[3];
    for (const Pulse& p : slots) {
      const float a = float(now - p.start);
      if (a < 0.0f || a > T) continue;
      // El volumen cambia el tamaño, no el brillo del color.
      const float lv = std::min(f.intensity, 1.2f);
      const float sz = std::clamp(0.6f + 0.5f * p.power, 0.6f, 1.15f);
      const int n = 1.0f < 0.5f ? std::clamp(m.burbujas / 2 + int(p.id % 2u), 2, 5) : std::clamp(m.burbujas, 3, 8);
      for (int i = 0; i < n; i++) {
        const uint32_t s = p.id * 53u + uint32_t(i) * 17u;
        const float R = (18.0f + 52.0f * rnd(s + 1u)) * px1 * sz;
        // Revientan una a una, en el último tercio de su vida.
        const float popAt = T * (0.55f + 0.4f * rnd(s + 2u));
        const float pop = clamp01((a - popAt) / 0.12f);
        if (a > popAt + 0.12f) continue;
        const float x = W * (0.12f + 0.76f * rnd(s + 3u)) + std::sin(a * (2.0f + 2.0f * rnd(s + 4u)) + 6.0f * rnd(s + 5u)) * 10.0f * px1;
        const float y = H * (0.3f + 0.6f * rnd(s + 6u)) - a * (40.0f + 50.0f * rnd(s + 7u)) * px1;
        const float reach = R + 24.0f * px1;
        const float x0 = std::max(0.0f, x - reach), y0 = std::max(0.0f, y - reach);
        const float x1 = std::min(W, x + reach), y1 = std::min(H, y + reach);
        if (x1 <= x0 || y1 <= y0) continue;
        c.material("bubble", {x0, y0, x1 - x0, y1 - y0},
                   {x0, y0, W, x, y, R, pop, a, lv, rnd(s + 8u),
                    mag.r, mag.g, mag.b, green.r, green.g, green.b, blue.r, blue.g, blue.b},
                   {"noise"});
      }
    }
  }
};
''';

const shaderSources = <String, String>{
  'bubble': r'''
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec2 uOffset;
uniform float uWidth;
uniform vec2 uCenter;
uniform float uR;
uniform float uPop;
uniform float uAge;
uniform float uAmp;
uniform float uSeed;
uniform vec3 uMag;
uniform vec3 uGreen;
uniform vec3 uBlue;
uniform sampler2D uTex;
out vec4 fragColor;

float hash(float n) {
  return fract(sin(n * 12.9898) * 43758.5453);
}
float hash2(vec2 p) {
  return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// Color de interferencia de la película fina: magenta, verde y azul
// saturados en ciclo, sin pasar por grises.
vec3 film(float h) {
  vec3 mag = mix(vec3(1.0, 0.16, 0.42), uMag / max(uMag.r, 0.01), 0.2);
  vec3 grn = mix(vec3(0.19, 1.0, 0.6), uGreen / max(uGreen.g, 0.01), 0.2);
  vec3 blu = mix(vec3(0.29, 0.42, 1.0), uBlue / max(uBlue.b, 0.01), 0.2);
  float s = fract(h) * 3.0;
  float i = floor(s);
  float u = smoothstep(0.0, 1.0, s - i);
  vec3 a = i < 0.5 ? mag : (i < 1.5 ? grn : blu);
  vec3 b = i < 0.5 ? grn : (i < 1.5 ? blu : mag);
  vec3 c = mix(a, b, u);
  // En el relevo magenta-verde baja el rojo para no pasar por oliva.
  if (i < 0.5) c.r *= 1.0 - 0.6 * 4.0 * u * (1.0 - u);
  return c;
}

void main() {
  vec2 p = FlutterFragCoord().xy + uOffset;
  float px1 = uWidth / 360.0;
  vec2 v = (p - uCenter) / px1;
  float Rp = uR / px1;
  float r = length(v);
  float ang = atan(v.y, v.x);
  float L = 0.0;
  vec3 col = vec3(0.0);
  if (uPop <= 0.0) {
    // Película: más brillante en el borde (como un reflejo rasante), centro
    // casi transparente, bandas de color que fluyen con el espesor.
    float x = r / max(Rp, 1.0);
    float rim = exp(-(r - Rp) * (r - Rp) / 3.2) + 0.55 * pow(clamp(x, 0.0, 1.0), 6.0) * step(r, Rp);
    float thick = texture(uTex, fract(v / (Rp * 3.0) + vec2(uSeed, uAge * 0.08))).g;
    float h = thick * 1.6 + x * 0.6 + uAge * 0.25 + uSeed;
    vec3 fc = film(h);
    float body = 0.06 * step(r, Rp);
    // Reflejo de ventana: un arco blanco pequeño arriba a la izquierda.
    vec2 hv = v - vec2(-0.45, -0.5) * Rp;
    float hl = exp(-dot(hv, hv) / (Rp * Rp * 0.012)) * 0.9;
    L = (rim * 0.85 + body) * uAmp;
    col = fc * min(L, 1.0) + vec3(1.0) * min(hl * uAmp, 1.0);
  } else {
    // Revienta: un anillo de gotas que se abre y se apaga.
    float rr = Rp * (1.0 + 0.6 * uPop);
    float drops = 0.0;
    for (int i = 0; i < 10; i++) {
      float fi = float(i);
      float aa = 6.2832 * (fi + hash(fi + uSeed * 7.0) * 0.6) / 10.0;
      vec2 dp = vec2(cos(aa), sin(aa)) * rr;
      drops += exp(-dot(v - dp, v - dp) / 3.0);
    }
    L = drops * (1.0 - uPop) * uAmp;
    col = film(uSeed + ang * 0.3) * min(L, 1.0);
  }
  vec3 tone = min(col, vec3(1.0));
  fragColor = vec4(tone, 0.1 * max(tone.r, max(tone.g, tone.b)));
}
''',

};
