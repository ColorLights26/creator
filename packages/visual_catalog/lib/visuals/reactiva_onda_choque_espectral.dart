// Reactiva · Onda de Choque Espectral — transparencia momentánea. En el golpe grande cruza
// la pantalla un frente de luz gigante que nace fuera del cuadro: la cresta es
// una línea blanca nítida, con el azul adelantado y el rojo y el ámbar
// rezagados (los colores se separan como en un prisma), detrás deja una estela
// ámbar que se apaga en unos cuadros y, si se quiere, un eco más débil le
// sigue. Cruza en medio segundo y no se para. La luz se suma a la escena.
// Referente: las ondas de choque de los vídeos de música electrónica y de
// los títulos de cine.
// Funciona encima de cualquier escena sin conocerla: sólo luz, sin objetos que
// se queden. Sin música no dibuja nada. Nunca más de tres destellos por segundo.
// Su detalle sale de una textura propia de alta calidad que el shader anima.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // MÚSICA: qué momento lanza la onda.
  CreatorModifier.choice('disparo', 'Lo dispara', options: ['Golpe grande', 'Primer tiempo', 'Bombo']),
  // FORMA: desde dónde llega.
  CreatorModifier.choice('origen', 'Origen', options: ['Desde abajo', 'Desde una esquina', 'Desde el centro']),
  // ATMÓSFERA: cuánto se separan los colores del borde.
  CreatorModifier.slider('separacion', 'Separación de color', min: 0, max: 1, value: .6),
  // MODO: una segunda onda más débil detrás.
  CreatorModifier.toggle('eco', 'Eco', value: true),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Prisma Roto', {'separacion': 1, 'origen': 'Desde una esquina'}),
  CreatorVariation('Latido Limpio', {'disparo': 'Bombo', 'eco': false, 'separacion': .3, 'origen': 'Desde el centro'}),
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
    fire(d == 0 ? h.big : d == 1 ? every(h, 4) : h.kick, d);
  }
  void render(const Frame& f, Canvas& c) const override {
    auto g = glide(f);
    const auto m = modifiers(f);
    const float W = f.width, H = f.height;
    // Origen fuera del cuadro (o en el centro) y velocidad para cruzar en
    // medio segundo.
    const float ox = m.origen == 1 ? -0.35f * W : 0.5f * W;
    const float oy = m.origen == 0 ? H + 0.6f * W : m.origen == 1 ? H + 0.35f * W : 0.5f * H;
    const float far = std::max(std::hypot(ox, oy), std::max(std::hypot(W - ox, oy), std::max(std::hypot(ox, H - oy), std::hypot(W - ox, H - oy))));
    const float near = m.origen == 2 ? 0.0f : (m.origen == 0 ? oy - H : std::hypot(std::max(0.0f, -ox), std::max(0.0f, oy - H)));
    const float T = 0.5f / pace(f);
    const Color red = f.colors[1], amber = f.colors[2], blue = f.colors[3];
    for (const Pulse& p : slots) {
      const float age = float(now - p.start);
      if (age < 0.0f || age > T * 1.35f) continue;
      const float k = std::min(amount(p.power) * f.intensity, 1.3f);
      const float R = near + (far + 0.2f * W - near) * (age / T);
      c.material("shock", {0.0f, 0.0f, W, H},
                 {ox, oy, R, (far + 0.2f * W - near) / T, k, g.separacion, m.eco ? 1.0f : 0.0f,
                  red.r, red.g, red.b, amber.r, amber.g, amber.b, blue.r, blue.g, blue.b});
    }
  }
};
''';

const shaderSources = <String, String>{
  'shock': r'''
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec2 uOrigin;
uniform float uR;
uniform float uSpeed;
uniform float uAmp;
uniform float uSep;
uniform float uEcho;
uniform vec3 uRed;
uniform vec3 uAmber;
uniform vec3 uBlue;
out vec4 fragColor;

void main() {
  vec2 p = FlutterFragCoord().xy;
  float px1 = uSize.x / 360.0;
  vec2 v = p - uOrigin;
  float r = length(v);
  float time = uR / max(uSpeed, 1.0);
  // Arco recorrido a lo largo de la cresta (px), para su variación.
  float s = atan(v.y, v.x) * r / px1;
  float dpx = (r - uR) / px1;  // < 0 detrás del frente
  dpx += 0.4 * sin(6.2832 * s / 240.0 + time * 3.0);
  // De abajo arriba la cresta se ensancha de 3 a 6 px y baja al 70 %.
  float t = clamp(1.0 - p.y / uSize.y, 0.0, 1.0);
  float w = mix(3.0, 6.0, t);
  float bright = mix(1.0, 0.7, t) * (1.0 + 0.12 * sin(6.2832 * (s - 90.0 * time) / 80.0) + 0.08 * sin(6.2832 * (s + 60.0 * time) / 135.0));
  // Núcleo blanco quemado.
  float core = 1.3 * exp(-dpx * dpx / (0.36 * w * w));
  // Azul 2-3 px por delante, solapado con el blanco, que se apaga en 3 px.
  float lead = 2.0 + clamp(uSep, 0.0, 1.0);
  float bz = (dpx - lead) / 1.8;
  float blueL = 0.9 * exp(-bz * bz);
  // Estela de 30-40 px: oro sólo en los primeros 4 px, luego rojo anaranjado
  // y rojo (+150 a 6 px, +70 a 14, +25 a 25 y nada a 40).
  float b = max(-dpx, 0.0);
  float wake = b < 6.0 ? mix(1.0, 0.59, b / 6.0) : (b < 14.0 ? mix(0.59, 0.275, (b - 6.0) / 8.0)
             : (b < 25.0 ? mix(0.275, 0.098, (b - 14.0) / 11.0) : mix(0.098, 0.0, clamp((b - 25.0) / 15.0, 0.0, 1.0))));
  wake *= step(dpx, 0.0);
  vec3 red = uRed / max(uRed.r, 0.01);
  vec3 gold = mix(vec3(1.0, 0.78, 0.31), uAmber / max(uAmber.r, 0.01), 0.2);
  vec3 wakeC = mix(gold, vec3(1.0, 0.29, 0.063), smoothstep(2.0, 5.0, b));
  wakeC = mix(wakeC, vec3(1.0, 0.165, 0.063) * mix(vec3(1.0), red, 0.2), smoothstep(10.0, 25.0, b));
  vec3 blue = uBlue / max(uBlue.b, 0.01);
  // Un solo eco suave 75 px detrás (al 35 %), con su azul delante; se va
  // antes de que la cresta salga.
  float de = dpx + 75.0;
  float fadeE = smoothstep(0.25, 0.5, p.y / uSize.y) * uEcho;
  vec3 echo = 0.35 * exp(-de * de / 12.5) * vec3(1.0, 0.29, 0.063) * fadeE;
  vec3 light = (core * vec3(1.0) + blueL * blue + wake * wakeC) * bright + echo;
  light *= uAmp;
  vec3 tone = min(light, vec3(1.0));
  fragColor = vec4(tone, 0.1 * max(tone.r, max(tone.g, tone.b)));
}
''',

};
