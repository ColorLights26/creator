// Reactiva · Calle de Vórtices — transparencia momentánea. Con el golpe algo invisible cruza
// la escena y deja detrás una calle de remolinos de luz, como el humo detrás
// de un cilindro en un túnel de viento: dos hilos de tinte luminoso salen de
// su paso y se enrollan en espirales que giran alternando a un lado y a otro,
// cada vez más abiertas y difusas hacia atrás. La estela se borra desde su
// extremo más viejo. Los remolinos de un lado son carmesí y los del otro
// ámbar, y donde se tocan se suman en naranja;
// cada golpe cruza en otro sentido y a otra altura. Sólo suma luz. Referente:
// la calle de vórtices de von Kármán en los túneles de humo.
// Funciona encima de cualquier escena sin conocerla: sólo luz, sin objetos que
// se queden. Sin música no dibuja nada. Nunca más de tres destellos por segundo.
// Su detalle sale de una textura propia de alta calidad que el shader anima.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.choice('disparo', 'Lo dispara', options: ['Golpe grande', 'Cada frase', 'Subida de energía']),
  // FORMA: tamaño de los remolinos.
  CreatorModifier.slider('tamano', 'Tamaño', min: .6, max: 1.4, value: 1),
  // MOVIMIENTO: cuánto dura la estela.
  CreatorModifier.slider('caida', 'Duración', min: .5, max: 1.5, value: 1),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Remolinos Grandes', {'tamano': 1.35, 'caida': 1.3}),
  CreatorVariation('Estela Corta', {'tamano': .7, 'caida': .55}),
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
    const float W = f.width, H = f.height;
    const float px1 = W / 360.0f;
    const float T = g.caida * 1.6f * 1.0f / pace(f);
    const Color red = f.colors[1], orange = f.colors[2], white = f.colors[3];
    for (const Pulse& p : slots) {
      const float a = float(now - p.start);
      if (a < 0.0f || a > T) continue;
      const float q = a / T;
      // El volumen cambia el tamaño, no el brillo del color.
      const float lv = std::min(f.intensity, 1.2f);
      const float sz = std::clamp(0.6f + 0.5f * p.power, 0.6f, 1.15f);
      const uint32_t s = p.id * 2654435761u + 37u;
      // Cruza hacia un lado u otro, algo inclinado y a otra altura cada vez.
      const bool right = rnd(s + 1u) < 0.5f;
      const float tilt = (rnd(s + 2u) - 0.5f) * 0.5f;
      const Vec2 dir = {(right ? 1.0f : -1.0f) * std::cos(tilt), std::sin(tilt)};
      // En el golpe la estela ya está dentro de la pantalla.
      const Vec2 st = {W * (right ? 0.55f + 0.15f * rnd(s + 3u) : 0.3f + 0.15f * rnd(s + 3u)), H * (0.25f + 0.5f * rnd(s + 4u))};
      const float spacing = 76.0f * sz * g.tamano;
      // En el golpe ya hay tres remolinos detrás; la estela se borra desde
      // su extremo más viejo al final.
      const float travel = 430.0f * a * pace(f) * (1.0f < 0.5f ? 1.3f : 1.0f);
      const float maxAge = (1.0f < 0.5f ? 240.0f : 440.0f) * (1.0f - easeInOut((q - 0.45f) / 0.55f));
      if (maxAge < 4.0f) continue;
      // Sólo la banda de la estela, con margen para los remolinos.
      const float back = (3.4f * spacing + 70.0f) * px1, fwd = (travel + 50.0f) * px1, half = (spacing + 120.0f) * px1;
      const Vec2 e0 = {st.x - dir.x * back, st.y - dir.y * back}, e1 = {st.x + dir.x * fwd, st.y + dir.y * fwd};
      const float x0 = std::max(0.0f, std::min(e0.x, e1.x) - half), x1 = std::min(W, std::max(e0.x, e1.x) + half);
      const float y0 = std::max(0.0f, std::min(e0.y, e1.y) - half), y1 = std::min(H, std::max(e0.y, e1.y) + half);
      if (x1 - x0 < 1.0f || y1 - y0 < 1.0f) continue;
      c.material("wake", {x0, y0, x1 - x0, y1 - y0},
                 {x0, y0, st.x, st.y, dir.x, dir.y, px1, travel, spacing, 0.2f * spacing, maxAge, lv, rnd(s + 5u) < 0.5f ? 1.0f : -1.0f,
                  red.r, red.g, red.b, orange.r, orange.g, orange.b, white.r, white.g, white.b});
    }
  }
};
''';

const shaderSources = <String, String>{
  'wake': r'''
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec2 uOffset;
uniform vec2 uStart;
uniform vec2 uDir;
uniform float uPx;
uniform float uTravel;
uniform float uSpacing;
uniform float uHalf;
uniform float uMaxAge;
uniform float uAmp;
uniform float uSide;
uniform vec3 uDeep;
uniform vec3 uMid;
uniform vec3 uWhite;
out vec4 fragColor;

vec2 rot(vec2 v, float a) {
  float c = cos(a);
  float s = sin(a);
  return vec2(c * v.x - s * v.y, s * v.x + c * v.y);
}

// Enrolla un punto (coordenadas del aire) alrededor de los remolinos, más
// cuanto más viejo es cada uno.
vec2 roll(vec2 q, float head) {
  float rc = 0.38 * uSpacing;
  for (int k = 0; k < 16; k++) {
    float xk = (float(k) + 0.5) * uSpacing;
    if (xk > head - 0.3 * uSpacing) {
      break;
    }
    float sgn = mod(float(k), 2.0) < 0.5 ? 1.0 : -1.0;
    vec2 vk = vec2(xk, sgn * uHalf);
    vec2 dv = q - vk;
    float th = sgn * 7.0 * (1.0 - exp(-(head - xk) / (0.9 * uSpacing))) / (1.0 + dot(dv, dv) / (rc * rc));
    q = vk + rot(dv, th);
  }
  return q;
}

void main() {
  vec2 lp = FlutterFragCoord().xy;
  float inside = step(lp.x, uSize.x + 1.0) * step(lp.y, uSize.y + 1.0);
  vec2 d = (lp + uOffset - uStart) / uPx;
  float along = dot(d, uDir);
  float y = dot(d, vec2(-uDir.y, uDir.x)) * uSide;
  // Coordenadas del aire: los remolinos quedan quietos donde nacieron y la
  // cabeza (el paso del objeto invisible) avanza.
  float head = 3.4 * uSpacing + uTravel;
  float X = along + 3.4 * uSpacing;
  float behind = head - X;
  if (behind < -30.0 || X < -50.0 || behind > uMaxAge + 60.0) {
    fragColor = vec4(0.0);
    return;
  }
  // Cada remolino enrolla los hilos a su alrededor; la compresión local
  // (diferencias de un píxel) ensancha los hilos donde se estiran, para que
  // ninguno quede en una línea de 1-2 px.
  vec2 q = roll(vec2(X, y), head);
  float qa = roll(vec2(X + 1.0, y), head).y;
  float qb = roll(vec2(X, y + 1.0), head).y;
  float grad = length(vec2(qa - q.y, qb - q.y));
  // Dos hilos de tinte (carmesí arriba, ámbar abajo) que salen afilados
  // del paso del objeto (10-15 px), se ensanchan y apagan hacia atrás; un
  // velo de tinte disuelto que nunca se corta en seco.
  float age = max(behind, 0.0);
  float tp = smoothstep(0.0, 14.0, behind);
  float w = max(1.4 + 1.8 * tp + 0.02 * age, 3.2 * tp * min(grad, 3.0));
  float dd = 0.6 * uHalf + 2.0;
  float y1 = (q.y - dd) / w;
  float y2 = (q.y + dd) / w;
  float hot = (0.5 + 0.5 * tp) * (1.0 + 0.4 * exp(-age / 12.0));
  float lineEnd = smoothstep(-2.0, 2.0, behind) * smoothstep(-50.0, 20.0, X);
  // Donde los pliegues quedan más juntos que un píxel, los hilos se funden
  // en un velo suave (sin parpadeo de píxeles alternos).
  float fold = smoothstep(2.0, 4.5, grad);
  float near1 = exp(-(q.y - dd) * (q.y - dd) / (0.25 * uSpacing * uSpacing));
  float near2 = exp(-(q.y + dd) * (q.y + dd) / (0.25 * uSpacing * uSpacing));
  float l1 = mix(0.7 * exp(-y1 * y1) + 0.22 * exp(-y1 * y1 / 9.0), 0.32 * near1, fold) * hot * lineEnd;
  float l2 = mix(0.7 * exp(-y2 * y2) + 0.22 * exp(-y2 * y2 / 9.0), 0.32 * near2, fold) * hot * lineEnd;
  float haze = 0.2 * exp(-q.y * q.y / 1800.0) * smoothstep(-20.0, 20.0, behind) * smoothstep(-50.0, 20.0, X);
  float side = smoothstep(-12.0, 12.0, q.y);
  float att = exp(-age / (0.6 * uMaxAge + 40.0)) * smoothstep(uMaxAge + 20.0, uMaxAge - 40.0, age) * uAmp * inside;
  float L1 = (l1 + haze * side) * att;
  float L2 = (l2 + haze * (1.0 - side)) * att;
  L1 = L1 < 0.85 ? L1 : 0.85 + 0.15 * (1.0 - exp(-(L1 - 0.85) / 0.15));
  L2 = L2 < 0.85 ? L2 : 0.85 + 0.15 * (1.0 - exp(-(L2 - 0.85) / 0.15));
  // Carmesí a cualquier brillo; ámbar con oro sólo arriba (0,75) y naranja
  // sólo por encima de +170; donde se tocan se suman en naranja.
  vec3 white = mix(uWhite, vec3(1.0), 0.5);
  vec3 c1 = mix(vec3(1.0, 0.1, 0.19), uDeep / max(uDeep.r, 0.01), 0.15);
  c1 = mix(c1, white, smoothstep(0.93, 0.99, L1));
  vec3 c2 = mix(vec3(1.0, 0.27, 0.04), vec3(1.0, 0.45, 0.05), smoothstep(0.62, 0.7, L2));
  c2 = mix(c2, mix(vec3(1.0, 0.64, 0.12), uMid / max(uMid.r, 0.01), 0.1), smoothstep(0.72, 0.8, L2));
  c2 = mix(c2, white, smoothstep(0.93, 0.99, L2));
  vec3 tone = min(c1 * L1 + c2 * L2, vec3(1.0));
  fragColor = vec4(tone, 0.1 * max(tone.r, max(tone.g, tone.b)));
}
''',

};
