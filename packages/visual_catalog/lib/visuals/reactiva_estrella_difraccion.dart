// Reactiva · Estrella de Difracción — transparencia momentánea. Con la caja se abre en un
// punto alto la estrella que hace una lente ante una luz fuerte: un núcleo
// quemado de 4 px, dos picos diagonales largos y un par horizontal más corto y
// fino, que salen disparados en dos cuadros y luego se recogen desde la punta.
// Cada pico es blanco junto al núcleo y se abre en bandas de color espectral
// (azul, verde y rojo, el rojo llegando más lejos); alrededor del núcleo, un
// brillo frío y tres anillos de Airy finos que sólo se ven al principio.
// La luz se suma a la escena. Referente: las estrellas de difracción del
// telescopio James Webb y de un objetivo cerrado a f/16.
// Funciona encima de cualquier escena sin conocerla: sólo luz, sin objetos que
// se queden. Sin música no dibuja nada. Nunca más de tres destellos por segundo.
// Su detalle sale de una textura propia de alta calidad que el shader anima.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // MÚSICA: qué golpe abre la estrella.
  CreatorModifier.choice('disparo', 'Lo dispara', options: ['Caja', 'Platillos', 'Golpe grande']),
  // FORMA: cuántos picos tiene.
  CreatorModifier.choice('puntas', 'Puntas', options: ['Seis', 'Ocho', 'Catorce']),
  // ATMÓSFERA: hasta dónde llegan los picos.
  CreatorModifier.slider('largo', 'Largo de los rayos', min: .25, max: .8, value: .5),
  // MODO: dos estrellas a la vez.
  CreatorModifier.toggle('dos', 'Dos estrellas', value: false),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Diafragma', {'puntas': 'Catorce', 'largo': .7}),
  CreatorVariation('Gemelas', {'dos': true, 'puntas': 'Seis', 'largo': .4}),
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
    fire(d == 0 ? h.snare : d == 1 ? h.hat : h.big, d);
  }
  void render(const Frame& f, Canvas& c) const override {
    auto g = glide(f);
    const auto m = modifiers(f);
    const float W = f.width, H = f.height;
    const float px1 = W / 360.0f;
    const float points = m.puntas == 0 ? 6.0f : m.puntas == 1 ? 8.0f : 14.0f;
    const Color red = f.colors[1], green = f.colors[2], blue = f.colors[3];
    for (const Pulse& p : slots) {
      const float age = float(now - p.start) * pace(f);
      if (age < 0.0f || age > 0.45f) continue;
      const float k = std::min(amount(p.power) * f.intensity, 1.3f);
      const int stars = m.dos ? 2 : 1;
      for (int s = 0; s < stars; s++) {
        // Un punto alto, distinto en cada golpe.
        const float x = W * (0.25f + 0.5f * rnd(p.id * 7u + uint32_t(s) * 3u + 1u));
        const float y = H * (0.12f + 0.22f * rnd(p.id * 11u + uint32_t(s) * 5u + 2u));
        // Largo máximo (175 px con el ajuste por defecto): sale en dos
        // cuadros y luego se recoge desde la punta a unos 25 px por cuadro.
        const float lmax = 350.0f * g.largo * (s == 0 ? 1.0f : 0.65f);
        const float len = (age < 0.067f ? lmax * easeOut(age / 0.067f) : lmax - 750.0f * (age - 0.067f)) * px1;
        if (len <= 0.0f) continue;
        const float reach = len + 40.0f * px1;
        const float x0 = std::max(0.0f, x - reach), y0 = std::max(0.0f, y - reach);
        const float x1 = std::min(W, x + reach), y1 = std::min(H, y + reach);
        if (x1 <= x0 || y1 <= y0) continue;
        c.material("star", {x0, y0, x1 - x0, y1 - y0},
                   {x0, y0, W, x, y, len, lmax * px1, points, age, k * (s == 0 ? 1.0f : 0.7f),
                    red.r, red.g, red.b, green.r, green.g, green.b, blue.r, blue.g, blue.b});
      }
    }
  }
};
''';

const shaderSources = <String, String>{
  'star': r'''
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec2 uOffset;
uniform float uWidth;
uniform vec2 uCenter;
uniform float uLen;
uniform float uMax;
uniform float uPoints;
uniform float uAge;
uniform float uAmp;
uniform vec3 uRed;
uniform vec3 uGreen;
uniform vec3 uBlue;
out vec4 fragColor;

// Brillo de un pico a lo largo (px de 360 a escala del largo máximo):
// +200 a 20 px, +120 a 50, +60 a 100, +25 a 150 y nada a 175.
float spikeI(float a) {
  if (a < 20.0) return 1.2;
  if (a < 34.0) return mix(1.0, 0.573, (a - 20.0) / 14.0);
  if (a < 58.0) return mix(0.573, 0.353, (a - 34.0) / 24.0);
  if (a < 66.0) return 0.353;
  if (a < 90.0) return mix(0.353, 0.216, (a - 66.0) / 24.0);
  if (a < 100.0) return mix(0.216, 0.235, (a - 90.0) / 10.0);
  if (a < 150.0) return mix(0.235, 0.098, (a - 100.0) / 50.0);
  return mix(0.098, 0.0, clamp((a - 150.0) / 25.0, 0.0, 1.0));
}

// Color del pico: blanco sólo donde pasa de +200, luego azul, verde y rojo
// saturados; cada uno se apaga mientras sube el siguiente.
vec3 spikeCol(float a) {
  vec3 blue = uBlue / max(uBlue.b, 0.01);
  vec3 green = uGreen / max(uGreen.g, 0.01);
  vec3 red = uRed / max(uRed.r, 0.01);
  vec3 c = mix(vec3(1.0), blue, smoothstep(26.0, 37.0, a));
  // Cada relevo cruza al ~40 % de los dos colores: sin hueco y sin oliva.
  float t1 = clamp((a - 56.0) / 9.0, 0.0, 1.0);
  float t2 = clamp((a - 87.0) / 10.0, 0.0, 1.0);
  float wB = pow(1.0 - t1, 1.3);
  float wG = pow(t1, 1.3) * pow(1.0 - t2, 1.3) * 1.4;
  float wR = pow(t2, 1.3);
  return c * wB + green * wG + red * wR;
}

void main() {
  vec2 q = FlutterFragCoord().xy + uOffset - uCenter;
  float px1 = uWidth / 360.0;
  float r = length(q) / px1;
  float scale = 175.0 / max(uMax / px1, 1.0);
  vec3 light = vec3(0.0);
  // Un par horizontal más corto y fino; el resto, diagonales.
  float lines = uPoints * 0.5;
  for (int i = 0; i < 7; i++) {
    float fi = float(i);
    if (fi >= lines) continue;
    float ang = fi * 3.14159 / lines + (lines > 3.5 ? 0.0 : 0.0);
    vec2 dir = vec2(cos(ang), sin(ang));
    bool horiz = i == 0;
    float along = abs(dot(q, dir)) / px1;
    float across = abs(q.x * dir.y - q.y * dir.x) / px1;
    float lenPx = uLen / px1 * (horiz ? 0.6 : 1.0);
    float a = along * scale / (horiz ? 0.6 : 1.0);
    // La punta se apaga y se afina a 1 px en sus últimos 20 px.
    float tip = smoothstep(lenPx, lenPx - 20.0, along);
    float w = (horiz ? 0.7 : 1.0) * mix(0.55, 1.0, tip);
    float prof = exp(-across * across / (w * w));
    light += prof * tip * spikeI(a) * spikeCol(a);
  }
  // Núcleo quemado de 4 px y un brillo frío alrededor que se apaga a 32 px.
  float glow = r < 4.0 ? 1.2 : (r < 7.0 ? mix(1.2, 0.59, (r - 4.0) / 3.0) : (r < 12.0 ? mix(0.59, 0.235, (r - 7.0) / 5.0)
             : (r < 20.0 ? mix(0.235, 0.08, (r - 12.0) / 8.0) : mix(0.08, 0.0, clamp((r - 20.0) / 12.0, 0.0, 1.0)))));
  vec3 cool = mix(vec3(0.45, 0.65, 1.0), vec3(1.0), smoothstep(0.62, 0.8, glow));
  light += glow * cool;
  // Tres anillos de Airy finos, sólo en los primeros cuadros; el rojo 1,5 px
  // más afuera que el azul.
  float rings = 1.0 - smoothstep(0.06, 0.1, uAge);
  vec3 ring = vec3(0.0);
  for (int k = 0; k < 3; k++) {
    float rr = k == 0 ? 12.0 : (k == 1 ? 20.0 : 28.0);
    float amp = k == 0 ? 0.18 : (k == 1 ? 0.1 : 0.05);
    vec3 z = (vec3(r) - vec3(rr + 1.5, rr + 0.75, rr)) / 0.8;
    ring += exp(-z * z) * amp;
  }
  light += ring * rings * vec3(0.7, 0.85, 1.0);
  light *= uAmp * step(0.0, uSize.x);
  vec3 tone = min(light, vec3(1.0));
  fragColor = vec4(tone, 0.1 * max(tone.r, max(tone.g, tone.b)));
}
''',

};
