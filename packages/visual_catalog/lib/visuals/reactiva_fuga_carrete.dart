// Reactiva · Fuga de Luz de Carrete — transparencia momentánea. Al empezar una frase entra
// desde un borde la fuga de luz de una cámara de película: dos lóbulos de luz
// orgánicos, de borde irregular, que se deslizan a lo largo del borde,
// respiran y se van. Junto al borde la luz quema a amarillo blanco, se abre a
// naranja y termina en rojo vivo, y cae rápido para no dejar velo apagado;
// encima, grano de película y un leve parpadeo. La luz se suma a la escena.
// Referente: las fugas de luz de Kodak Super 8 y de Portra en 35 mm.
// Funciona encima de cualquier escena sin conocerla: sólo luz, sin objetos que
// se queden. Sin música no dibuja nada. Nunca más de tres destellos por segundo.
// Su detalle sale de una textura propia de alta calidad que el shader anima.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // MÚSICA: qué momento la deja entrar.
  CreatorModifier.choice('disparo', 'Lo dispara', options: ['Cambio de frase', 'Vuelta tras pausa', 'Golpe grande']),
  // FORMA: por qué borde entra.
  CreatorModifier.choice('lado', 'Lado', options: ['Alterna', 'Izquierda', 'Derecha', 'Arriba']),
  // ATMÓSFERA: cuánto ocupa.
  CreatorModifier.slider('tamano', 'Tamaño', min: .4, max: 1, value: .7),
  // Textura de película.
  CreatorModifier.slider('grano', 'Grano', min: 0, max: 1, value: .5),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Super 8', {'grano': 1, 'tamano': .9}),
  CreatorVariation('Rayo de Tarde', {'lado': 'Arriba', 'tamano': .55, 'grano': .2}),
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
    fire(d == 0 ? every(h, 16) : d == 1 ? h.back : h.big, d);
  }
  void render(const Frame& f, Canvas& c) const override {
    auto g = glide(f);
    const auto m = modifiers(f);
    const float W = f.width, H = f.height;
    const float T = 1.0f / pace(f);
    float age = 100.0f, amp = 0.0f;
    uint32_t id = 0u;
    for (const Pulse& p : slots) {
      const float a = float(now - p.start);
      if (a < 0.0f || a > T || a >= age) continue;
      age = a;
      amp = std::min(amount(p.power) * f.intensity, 1.3f);
      id = p.id;
    }
    if (amp <= 0.0f) return;
    const float q = age / T;
    // Entra en tres cuadros, deriva y se retira por el borde.
    const float e = (q < 0.08f ? easeOut(q / 0.08f) : 1.0f - 0.6f * easeInOut((q - 0.5f) / 0.5f)) * amp;
    if (e < kMin) return;
    const int side = m.lado == 0 ? int(id % 3u) : m.lado - 1;  // 0 izquierda, 1 derecha, 2 arriba
    const Color red = f.colors[1], orange = f.colors[2], hot = f.colors[3];
    c.material("leak", {0.0f, 0.0f, W, H},
               {float(side), q, e, g.tamano, g.grano, float(now), rnd(id * 7u + 1u),
                red.r, red.g, red.b, orange.r, orange.g, orange.b, hot.r, hot.g, hot.b},
               {"noise"});
  }
};
''';

const shaderSources = <String, String>{
  'leak': r'''
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform float uSide;
uniform float uQ;
uniform float uAmp;
uniform float uSizeK;
uniform float uGrain;
uniform float uTime;
uniform float uSeed;
uniform vec3 uRed;
uniform vec3 uOrange;
uniform vec3 uHot;
uniform sampler2D uTex;
out vec4 fragColor;

float hash(float n) {
  return fract(sin(n * 12.9898) * 43758.5453);
}
float hash2(vec2 p) {
  return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  float px1 = uSize.x / 360.0;
  // Coordenadas del borde en px: u a lo largo del borde, v hacia dentro.
  float u = (uSide < 1.5 ? p.y : p.x) / px1;
  float v = (uSide < 0.5 ? p.x : (uSide < 1.5 ? uSize.x - p.x : p.y)) / px1;
  float edgeLen = (uSide < 1.5 ? uSize.y : uSize.x) / px1;
  // Al final se retira: se encoge y sale por el borde a unos 10 px por cuadro.
  float rec = smoothstep(0.48, 1.0, uQ);
  float slide = max(uQ - 0.48, 0.0) / 0.52 * 160.0;
  float k = uSizeK * (1.0 - 0.45 * rec);
  // Un lóbulo grande (unos 250 px) y otro menor que derivan por el borde,
  // con una caída larga y suave.
  vec2 c1 = vec2(edgeLen * (0.32 + 0.2 * uSeed + 0.12 * uQ), -30.0 - slide);
  vec2 c2 = vec2(edgeLen * (0.68 - 0.15 * uSeed - 0.08 * uQ), -50.0 - slide);
  vec2 d1 = (vec2(u, v) - c1) / vec2(1.8, 1.0);
  vec2 d2 = (vec2(u, v) - c2) / vec2(1.6, 1.0);
  float q1 = length(d1) - 30.0;
  float q2 = length(d2) - 50.0;
  // Caída de potencia: blanco sólo en los primeros 15-20 px desde el borde,
  // oro y naranja en relevos de unos 12 px y una cola roja larga.
  float L1 = 185.0 * k;
  float L2 = 120.0 * k;
  float I = pow(1.0 + max(q1, 0.0) / L1, -1.2) * exp(-(q1 * q1) / (220.0 * 220.0 * k * k));
  I = max(I, 0.8 * pow(1.0 + max(q2, 0.0) / L2, -1.2) * exp(-(q2 * q2) / (150.0 * 150.0 * k * k)));
  // Bandas verticales tenues junto al borde (20-50 px de ancho, extremos
  // suaves), en rojo.
  float bands = 0.0;
  for (int i = 0; i < 3; i++) {
    float fi = float(i);
    float bv = 15.0 + 70.0 * hash(fi + uSeed * 3.0);
    float bw = 10.0 + 15.0 * hash(fi + uSeed * 7.0);
    float bu = edgeLen * (0.2 + 0.6 * hash(fi + 5.0 + uSeed));
    float bl = 90.0 + 80.0 * hash(fi + 9.0 + uSeed);
    float zv = (v + slide - bv) / bw;
    float zu = (u - bu) / bl;
    bands += exp(-zv * zv) * exp(-zu * zu * zu * zu) * 0.13;
  }
  bands *= 1.0 - rec;
  // Parpadeo de ±6 % por cuadro y variación suave a gran escala, sólo en el
  // brillo (no mueve los contornos de color).
  float frame = floor(uTime * 24.0);
  float n = texture(uTex, fract(vec2(u, v) / 600.0 + vec2(uSeed, uTime * 0.01))).g;
  float bright = (0.92 + 0.16 * n) * (1.0 + 0.06 * (2.0 * hash(frame + uSeed * 9.0) - 1.0)) * uAmp;
  // Rampa por intensidad: blanco cálido, oro, naranja, naranja rojizo y rojo.
  vec3 white = mix(vec3(1.0, 0.957, 0.878), uHot, 0.3);
  vec3 gold = vec3(1.0, 0.784, 0.314);
  vec3 orange = mix(vec3(1.0, 0.541, 0.063), uOrange, 0.1);
  vec3 orRed = vec3(1.0, 0.29, 0.063);
  vec3 red = vec3(1.0, 0.118, 0.063) * mix(vec3(1.0), uRed / max(uRed.r, 0.01), 0.2);
  vec3 col = mix(red, orRed, smoothstep(0.3, 0.55, I));
  col = mix(col, orange, smoothstep(0.6, 0.75, I));
  col = mix(col, gold, smoothstep(0.75, 0.82, I));
  col = mix(col, white, smoothstep(0.83, 0.9, I));
  // Grano de película fino.
  float grain = 1.0 + (hash2(p * 1.37 + frame) - 0.5) * 0.12 * uGrain;
  vec3 light = (col * min(I, 1.0) + bands * red) * bright * grain;
  fragColor = vec4(light, 0.1 * max(light.r, max(light.g, light.b)));
}
''',

};
