// Reactiva · Barrido Holográfico — transparencia momentánea. Al empezar una frase cruza en
// diagonal una banda iridiscente, como al inclinar una carta holográfica: el
// arcoíris de interferencia de una película fina, que cambia de color con la
// posición, sobre una rejilla de difracción finísima, una línea especular
// nítida en el centro y purpurina que destella dentro. Los bordes de la banda
// caen suaves. La luz se suma a la escena. Referente: las cartas holográficas
// y los hologramas de seguridad de los billetes.
// Funciona encima de cualquier escena sin conocerla: sólo luz, sin objetos que
// se queden. Sin música no dibuja nada. Nunca más de tres destellos por segundo.
// Su detalle sale de una textura propia de alta calidad que el shader anima.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // MÚSICA: qué momento la hace cruzar.
  CreatorModifier.choice('disparo', 'Lo dispara', options: ['Cambio de frase', 'Primer tiempo', 'Golpe grande']),
  // FORMA: inclinación de la banda.
  CreatorModifier.slider('angulo', 'Ángulo', min: -60, max: 60, value: 35),
  // ATMÓSFERA: ancho de la banda.
  CreatorModifier.slider('ancho', 'Ancho de la banda', min: .2, max: .6, value: .4),
  // Destellos dentro de la banda.
  CreatorModifier.slider('purpurina', 'Purpurina', min: 0, max: 1, value: .7),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Carta Rara', {'ancho': .6, 'purpurina': 1, 'angulo': 50}),
  CreatorVariation('Filo de Luz', {'ancho': .22, 'purpurina': .2, 'angulo': -20}),
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
    fire(d == 0 ? every(h, 16) : d == 1 ? every(h, 4) : h.big, d);
  }
  void render(const Frame& f, Canvas& c) const override {
    auto g = glide(f);
    const float W = f.width, H = f.height;
    const float T = 0.9f / pace(f);
    const Color red = f.colors[1], gold = f.colors[2], white = f.colors[3];
    for (const Pulse& p : slots) {
      const float age = float(now - p.start);
      if (age < 0.0f || age > T) continue;
      const float k = std::min(amount(p.power) * f.intensity, 1.3f);
      c.material("holo", {0.0f, 0.0f, W, H},
                 {easeInOut(age / T), std::sin(float(pi) * age / T) * k, g.angulo * float(pi) / 180.0f, g.ancho, g.purpurina, float(p.id % 31u),
                  red.r, red.g, red.b, gold.r, gold.g, gold.b, white.r, white.g, white.b},
                 {"noise"});
    }
  }
};
''';

const shaderSources = <String, String>{
  'holo': r'''
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform float uS;
uniform float uAmp;
uniform float uAngle;
uniform float uWidth;
uniform float uGlitter;
uniform float uSeed;
uniform vec3 uRed;
uniform vec3 uGold;
uniform vec3 uWhite;
uniform sampler2D uTex;
out vec4 fragColor;

float hash(float n) {
  return fract(sin(n * 12.9898) * 43758.5453);
}
float hash2(vec2 p) {
  return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// Arcoíris de la lámina: rojo, oro (sólo si es brillante), verde, azul y
// violeta, con relevos de unos 7 px; el relevo cálido-verde baja un poco de
// brillo para no pasar por oliva y el verde-azul no se agrisa.
vec4 foil(float h, float B) {
  h = fract(h) * 5.0;
  float i = floor(h);
  // Cada color sólo es puro en el centro de su franja (caída cos²).
  float t = 0.5 - 0.5 * cos(3.14159 * fract(h));
  vec3 red = mix(vec3(1.0, 0.165, 0.063), uRed / max(uRed.r, 0.01), 0.15);
  vec3 gold = mix(red, mix(vec3(1.0, 0.784, 0.0), uGold / max(uGold.r, 0.01), 0.15), smoothstep(0.62, 0.7, B));
  vec3 green = vec3(0.19, 1.0, 0.44);
  vec3 blue = vec3(0.227, 0.42, 1.0);
  vec3 violet = vec3(0.54, 0.165, 1.0);
  vec3 a = i < 0.5 ? red : (i < 1.5 ? gold : (i < 2.5 ? green : (i < 3.5 ? blue : violet)));
  vec3 b = i < 0.5 ? gold : (i < 1.5 ? green : (i < 2.5 ? blue : (i < 3.5 ? violet : red)));
  vec3 c = mix(a, b, t);
  float bump = 4.0 * t * (1.0 - t);
  float dip = i > 0.5 && i < 1.5 ? 1.0 - 0.87 * bump : 1.0;
  if (i > 1.5 && i < 2.5) c.r *= 1.0 - 0.5 * bump;
  return vec4(c, dip);
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  float px1 = uSize.x / 360.0;
  vec2 n = vec2(cos(uAngle), sin(uAngle));
  vec2 c = 0.5 * uSize;
  float w = uWidth * uSize.x;
  float span = 0.5 * (abs(uSize.x * n.x) + abs(uSize.y * n.y)) + w;
  float xp = (dot(p - c, n) - mix(-span, span, uS)) / px1;  // > 0 delante
  float along = dot(p - c, vec2(-n.y, n.x)) / px1;
  float d = abs(xp);
  // Brillo: pico +200..+220 a 6-10 px de la línea, +40 a 60 px y nada a
  // 100 px delante o 150 px detrás.
  float tail = xp > 0.0 ? 100.0 : 150.0;
  float B = d < 8.0 ? mix(0.55, 0.82, d / 8.0) : (d < 60.0 ? mix(0.82, 0.157, smoothstep(8.0, 60.0, d)) : mix(0.157, 0.0, smoothstep(60.0, tail, d)));
  // Microlíneas de la lámina: 3,5 px de paso a 25° de la banda, ±25 %, que
  // derivan 1 px por cuadro; grano fino de ±5 %.
  float g = 1.0 + 0.08 * sin(6.2832 * (xp + uS * 27.0) / 2.5);
  g *= 1.0 + 0.05 * (2.0 * hash2(floor(p) + floor(uS * 27.0)) - 1.0);
  float tex = texture(uTex, fract(p / uSize.x * 0.6 + vec2(uSeed * 0.07))).g;
  vec4 hue = foil(xp / 50.0 + along / 600.0 + tex * 0.15 + uS * 0.6 + uSeed * 0.13, B);
  vec3 film = hue.rgb * B * hue.a * g;
  // Línea especular: 2 px quemada y un brillo del color local hasta 6 px.
  float line = 1.25 * exp(-xp * xp / 1.4);
  float lg = 0.6 * exp(-d / 1.8) * (1.0 - smoothstep(4.0, 6.0, d));
  // Purpurina del color local, casi toda a ±30 px de la línea; cada copo
  // dura 1-3 cuadros y sólo es blanco en su núcleo de 1 px.
  vec2 cell = floor(p / (8.0 * px1));
  vec2 cp = (cell + vec2(hash2(cell + 1.3), hash2(cell + 4.7))) * 8.0 * px1;
  float on = step(hash2(cell + floor(uS * 13.5 + hash2(cell + 2.2) * 7.0)), 0.12 * uGlitter);
  float near = exp(-xp * xp / 484.0) * step(0.08, B);
  float rr = dot(p - cp, p - cp) / (px1 * px1);
  float flake = on * near * exp(-rr / 1.45) * 1.5 * max(B, 0.3);
  float wf = step(hash2(cell + 6.6), 0.3);
  vec3 light = film + line * mix(uWhite, vec3(1.0), 0.7) + lg * hue.rgb
             + mix(hue.rgb, vec3(1.0), wf * smoothstep(0.86, 0.95, flake)) * flake;
  // El amarillo sólo desde +170; por debajo, el tramo cálido pasa a naranja
  // (verde <= 0,45 del rojo entre +120 y +170, <= 0,30 por debajo).
  float Lf = max(light.r, max(light.g, light.b)) * uAmp;
  float gcap = Lf >= 0.667 ? 1.0 : mix(0.3, 0.45, smoothstep(0.43, 0.51, Lf));
  if (light.r >= light.g && light.b < 0.3 * light.r) light.g = min(light.g, gcap * light.r);
  light *= uAmp;
  vec3 tone = min(light, vec3(1.0));
  fragColor = vec4(tone, 0.1 * max(tone.r, max(tone.g, tone.b)));
}
''',

};
