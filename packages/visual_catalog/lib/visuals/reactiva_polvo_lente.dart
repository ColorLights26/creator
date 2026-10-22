// Reactiva · Polvo de Lente Revelado — transparencia momentánea. Una luz cálida e intensa
// (naranja, rojo o ámbar, distinta en cada golpe) con el centro blanco cruza la
// lente en un arco suave y se apaga antes de salir, y revela a su alrededor,
// con la caída de la luz real, la suciedad del cristal: manchas grandes, huellas,
// vetas de grasa, fibras rizadas y motas desenfocadas con borde cromático. Una
// estela anamórfica azul nace de la fuente y se afina antes del borde; al otro
// lado del centro, los fantasmas del diafragma, casi transparentes, de esquinas
// redondeadas y borde suave más claro, de tamaños distintos, se mueven al revés
// que la luz. La luz se suma a la escena.
// Referente: lens dirt y flares de Optical Flares (Video Copilot).
// Funciona encima de cualquier escena sin conocerla: sólo luz, sin objetos que
// se queden. Sin música no dibuja nada. Nunca más de tres destellos por segundo.
// Su detalle sale de una textura propia de alta calidad que el shader anima.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // MÚSICA: qué momento enciende la luz.
  CreatorModifier.choice('disparo', 'Lo dispara', options: ['Golpe grande', 'Bombo', 'Cambio de frase']),
  // FORMA: cuánta suciedad tiene la lente.
  CreatorModifier.slider('suciedad', 'Suciedad', min: .3, max: 1, value: .75),
  // MOVIMIENTO: por dónde cruza la luz.
  CreatorModifier.choice('barrido', 'Barrido', options: ['Izquierda a derecha', 'Derecha a izquierda', 'De arriba abajo']),
  // ATMÓSFERA: cuánto tarda en cruzar.
  CreatorModifier.slider('caida', 'Duración', min: .35, max: 1.2, value: .6),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Lente Vieja', {'suciedad': 1, 'caida': 1}),
  CreatorVariation('Reflejo Rápido', {'suciedad': .45, 'caida': .4, 'barrido': 'De arriba abajo'}),
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
    fire(d == 0 ? h.big : d == 1 ? h.kick : every(h, 16), d);
  }
  void render(const Frame& f, Canvas& c) const override {
    auto g = glide(f);
    const float W = f.width, H = f.height;
    const float T = g.caida / pace(f);
    const float wl = g.barrido.weight(0), wr = g.barrido.weight(1), wt = g.barrido.weight(2);
    const Color blue = f.colors[0];
    for (const Pulse& p : slots) {
      const double age = now - p.start;
      if (age <= 0.0 || age >= double(T)) continue;
      const float q = float(age / double(T));
      float e = std::pow(std::max(0.0f, std::sin(float(pi) * q)), 0.6f) * std::min(amount(p.power) * f.intensity, 1.3f) * (p.kind == 1 ? 0.75f : 1.0f);
      // Un color intenso distinto en cada golpe; los fantasmas toman el siguiente.
      const Color tint = f.colors[size_t(1 + p.id % 3u)], ghost = f.colors[size_t(1 + (p.id + 1u) % 3u)];
      // Cruza en un arco suave, con entrada y salida suaves.
      const float s = easeInOut(q), bow = 1.0f - (2.0f * s - 1.0f) * (2.0f * s - 1.0f);
      const float y = H * (0.25f + 0.45f * rnd(p.id * 13u)), x = W * (0.3f + 0.4f * rnd(p.id * 29u));
      const float tilt = (rnd(p.id * 41u) < 0.5f ? -1.0f : 1.0f) * 0.07f * H;
      const Vec2 L = {wl * W * (-0.15f + 1.3f * s) + wr * W * (1.15f - 1.3f * s) + wt * (x + 0.06f * W * bow),
                      (wl + wr) * (y + tilt * (2.0f * s - 1.0f) - 0.05f * H * bow) + wt * H * (-0.1f + 1.2f * s)};
      // Se apaga antes de salir del cuadro.
      const float margin = (wl + wr) * std::min(L.x, W - L.x) + wt * std::min(L.y, H - L.y);
      e *= easeInOut((margin + 0.06f * W) / (0.18f * W));
      if (e < kMin) continue;
      c.material("dirt", {0.0f, 0.0f, W, H},
                 {L.x, L.y, 0.55f * W, e * g.suciedad, e, tint.r, tint.g, tint.b, ghost.r, ghost.g, ghost.b, blue.r, blue.g, blue.b},
                 {"dirt"});
    }
  }
};
''';

const shaderSources = <String, String>{
  'dirt': r'''
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec2 uLight;
uniform float uReach;
uniform float uAmount;
uniform float uGlow;
uniform vec3 uTint;
uniform vec3 uGhost;
uniform vec3 uBlue;
uniform sampler2D uTex;
out vec4 fragColor;

// Sensor: el color se satura en lo tenue y se quema a blanco en lo intenso.
vec3 sensor(vec3 c) {
  return c / max(max(c.r, c.g), max(c.b, 0.01)) * 0.86 + 0.14;
}

// Fantasma del diafragma: hexágono de esquinas redondeadas, casi transparente,
// con el borde suave y más claro.
float ghost(vec2 p, float rad, float soft) {
  p = abs(p) / rad;
  float d = mix(max(p.x * 0.866 + p.y * 0.5, p.y), length(p) * 0.93, 0.35);
  float fill = 1.0 - smoothstep(1.0 - soft, 1.0, d);
  return fill * (0.3 + 0.45 * smoothstep(0.6, 0.98, d));
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  vec2 d = (p - uLight) / uReach;
  float r2 = dot(d, d);
  // La suciedad aparece con la caída de la luz real (1/r²).
  float reveal = 1.0 / (1.0 + r2 * 14.0);
  // Borde cromático en la suciedad: el rojo un poco más grande que el azul.
  vec2 st = p / uSize.x * 0.9;
  vec2 c = 0.45 * uSize / uSize.x;
  float dr = texture(uTex, fract(c + (st - c) * 0.995)).r;
  vec4 t = texture(uTex, fract(st));
  float db = texture(uTex, fract(c + (st - c) * 1.005)).r;
  vec3 kT = sensor(uTint);
  vec3 light = vec3(dr, t.r, db) * kT * (3.2 * reveal * uAmount) + kT * (t.g * reveal * uAmount * 0.5);
  // La fuente: centro blanco, halo ajustado y un velo mínimo.
  light += kT * uGlow * (9.0 / (1.0 + r2 * 160.0) + 0.35 / (1.0 + r2 * 22.0) + 0.04 / (1.0 + r2 * 3.0));
  // Estela anamórfica azul: núcleo casi blanco de 3-4 px y resplandor vertical
  // suave; máxima en la fuente y apagada antes del borde.
  float ax = abs(p.x - uLight.x) / uSize.x;
  float dy = abs(p.y - uLight.y) / uSize.x;
  float taper = exp(-ax / 0.32) * smoothstep(0.0, 0.08, min(p.x, uSize.x - p.x) / uSize.x);
  light += sensor(uBlue) * uGlow * taper * (3.0 * exp(-dy / 0.0045) + 0.35 * exp(-dy / 0.045));
  // Fantasmas sobre el eje que pasa por el centro: se mueven al revés que la luz.
  vec2 C = 0.5 * uSize;
  vec2 axis = C - uLight;
  vec3 kG = sensor(uGhost);
  vec3 green = vec3(0.3, 1.0, 0.45);
  for (int i = 0; i < 5; i++) {
    float s = i == 0 ? 0.35 : (i == 1 ? 0.8 : (i == 2 ? 1.25 : (i == 3 ? 1.7 : 2.3)));
    float rad = uSize.x * (i == 0 ? 0.03 : (i == 1 ? 0.09 : (i == 2 ? 0.05 : (i == 3 ? 0.17 : 0.07))));
    float soft = uSize.x * 0.016 / rad;
    vec2 q = p - (C + axis * s);
    vec3 shape = vec3(ghost(q, rad * 1.03, soft), ghost(q, rad, soft), ghost(q, rad * 0.97, soft));
    vec3 col = i == 1 ? kT : (i == 2 ? green : kG);
    light += shape * col * uGlow * 0.55;
  }
  vec3 col = vec3(1.0) - exp(-light);
  fragColor = vec4(col, 0.1 * max(col.r, max(col.g, col.b)));
}
''',

};
