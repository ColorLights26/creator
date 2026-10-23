// Reactiva · Carrera de Neón — transparencia momentánea. Con el golpe dos cometas de neón
// salen de un punto del borde y recorren el contorno redondeado de la
// pantalla en sentidos opuestos, dejando una estela que se apaga: núcleo
// blanco en la cabeza, rojo anaranjado y rojo neón en la estela. Al cruzarse
// en el otro lado se desvanecen. Sólo suma luz. Referente: tubos de neón
// flexible con efecto de persecución.
// Funciona encima de cualquier escena sin conocerla: sólo luz, sin objetos que
// se queden. Sin música no dibuja nada. Nunca más de tres destellos por segundo.
// Su detalle sale de una textura propia de alta calidad que el shader anima.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.choice('disparo', 'Lo dispara', options: ['Golpe grande', 'Cada frase', 'Subida de energía']),
  // FORMA: largo de la estela.
  CreatorModifier.slider('estela', 'Estela', min: .3, max: 1, value: .6),
  // MOVIMIENTO: velocidad de los cometas.
  CreatorModifier.slider('rapidez', 'Rapidez', min: .6, max: 1.8, value: 1),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Circuito', {'estela': .95, 'rapidez': .8}),
  CreatorVariation('Chispazo', {'estela': .35, 'rapidez': 1.7}),
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
    const Color red = f.colors[1], orange = f.colors[2], white = f.colors[3];
    for (const Pulse& p : slots) {
      const float a = float(now - p.start);
      // Recorren media vuelta cada uno (se cruzan en el lado opuesto).
      const float T = 0.75f * 1.0f / (pace(f) * g.rapidez) + 0.2f * 1.0f;
      if (a < 0.0f || a > T) continue;
      // El volumen cambia el tamaño, no el brillo del color.
      const float lv = std::min(f.intensity, 1.2f);
      const float sz = std::clamp(0.6f + 0.5f * p.power, 0.6f, 1.15f);
      c.material("neon", {0.0f, 0.0f, W, H},
                 {rnd(p.id * 7u + 1u), a, 0.75f * 1.0f / (pace(f) * g.rapidez), g.estela * sz, lv,
                  red.r, red.g, red.b, orange.r, orange.g, orange.b, white.r, white.g, white.b});
    }
  }
};
''';

const shaderSources = <String, String>{
  'neon': r'''
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform float uStart;
uniform float uAge;
uniform float uRun;
uniform float uTrail;
uniform float uAmp;
uniform vec3 uRed;
uniform vec3 uOrange;
uniform vec3 uWhite;
out vec4 fragColor;

void main() {
  vec2 p = FlutterFragCoord().xy;
  float px1 = uSize.x / 360.0;
  vec2 sz = uSize / px1;
  vec2 q = p / px1 - 0.5 * sz;
  // Contorno redondeado (como la pantalla) a 7 px del borde, radio 30 px.
  float r = 30.0;
  vec2 hh = 0.5 * sz - vec2(7.0 + r);
  vec2 cc = clamp(q, -hh, hh);
  vec2 df = q - cc;
  float dl = length(df);
  float th;
  if (dl < 0.001) {
    // Dentro del rectángulo interior: el lado más cercano.
    vec2 e = hh - abs(q);
    if (e.x < e.y) {
      th = q.x > 0.0 ? 0.0 : 3.14159;
      cc = vec2(sign(q.x) * hh.x, q.y);
    } else {
      th = q.y > 0.0 ? 1.5708 : -1.5708;
      cc = vec2(q.x, sign(q.y) * hh.y);
    }
    dl = 0.0;
  } else {
    th = atan(df.y, df.x);
  }
  float d = abs(dl - r);
  // Coordenada a lo largo del contorno (en el sentido de las agujas del reloj
  // desde la esquina de arriba a la izquierda).
  float A = 1.5708 * r;
  float P = 4.0 * hh.x + 4.0 * hh.y + 4.0 * A;
  float u;
  if (abs(cc.y + hh.y) < 0.01 && abs(cc.x) < hh.x - 0.01) u = cc.x + hh.x;
  else if (abs(cc.x - hh.x) < 0.01 && abs(cc.y) < hh.y - 0.01) u = 2.0 * hh.x + A + cc.y + hh.y;
  else if (abs(cc.y - hh.y) < 0.01 && abs(cc.x) < hh.x - 0.01) u = 2.0 * hh.x + 2.0 * A + 2.0 * hh.y + hh.x - cc.x;
  else if (abs(cc.x + hh.x) < 0.01 && abs(cc.y) < hh.y - 0.01) u = 4.0 * hh.x + 3.0 * A + 2.0 * hh.y + hh.y - cc.y;
  else if (cc.x > 0.0 && cc.y < 0.0) u = 2.0 * hh.x + (th + 1.5708) * r;
  else if (cc.x > 0.0) u = 2.0 * hh.x + A + 2.0 * hh.y + th * r;
  else if (cc.y > 0.0) u = 4.0 * hh.x + 2.0 * A + 2.0 * hh.y + (th - 1.5708) * r;
  else u = 4.0 * hh.x + 3.0 * A + 4.0 * hh.y + (th + 3.14159) * r;
  // Dos cometas desde el mismo punto en sentidos opuestos; cada uno recorre
  // media vuelta.
  float u0 = uStart * P;
  float prog = clamp(uAge / max(uRun, 0.01), 0.0, 1.0);
  float head = 0.04 * P + 0.46 * P * (1.0 - (1.0 - prog) * (1.0 - prog));
  float Lt = uTrail * 0.45 * P;
  float fadeOut = 1.0 - smoothstep(1.0, 1.0 + 0.2 / max(uRun, 0.01), uAge / max(uRun, 0.01));
  float L = 0.0;
  for (int k = 0; k < 2; k++) {
    float dir = k == 0 ? 1.0 : -1.0;
    float rel = mod(dir * (u - u0) + P, P);
    float behind = head - rel;
    if (behind < 0.0 || behind > Lt) continue;
    float B = pow(1.0 - behind / Lt, 1.6);
    float headGlow = exp(-behind / 18.0);
    L += (1.15 * exp(-d * d / 3.2) + 0.4 * exp(-d / 9.0)) * (0.55 * B + 0.6 * headGlow);
  }
  L *= fadeOut * uAmp;
  // Color por el brillo final: blanco en la cabeza, rojo anaranjado y rojo
  // neón en la estela.
  vec3 red = mix(vec3(1.0, 0.1, 0.12), uRed / max(uRed.r, 0.01), 0.15);
  vec3 orRed = mix(vec3(1.0, 0.32, 0.06), uOrange / max(uOrange.r, 0.01), 0.1);
  vec3 col = mix(red, orRed, smoothstep(0.45, 0.75, L));
  col = mix(col, mix(uWhite, vec3(1.0), 0.6), smoothstep(0.88, 1.05, L));
  vec3 tone = min(col * min(L, 1.0), vec3(1.0));
  fragColor = vec4(tone, 0.1 * max(tone.r, max(tone.g, tone.b)));
}
''',

};
