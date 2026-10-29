// Reactiva · Relámpago Fuera de Campo — transparencia momentánea. No se ve el rayo: en el
// golpe grande entra rasante desde una esquina la luz de una tormenta fuera de
// plano, con la curva real de un relámpago (descarga, re-descarga a los 85 ms,
// un segundo rayo desde otro punto del borde y una cola que titila). La luz es
// blanca junto a la esquina, azul a media distancia y violeta lejos; dos o tres
// nubes grandes arriba se encienden por el lado que mira a la esquina, con su
// interior oscurecido sin color, y entre ellas salen rayos de luz suaves.
// Como mucho un relámpago por segundo. La luz se suma a la escena. Referente:
// tormentas nocturnas filmadas en cámara lenta.
// Funciona encima de cualquier escena sin conocerla: sólo luz, sin objetos que
// se queden. Sin música no dibuja nada. Nunca más de tres destellos por segundo.
// Su detalle sale de una textura propia de alta calidad que el shader anima.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // MÚSICA: qué momento lanza la tormenta.
  CreatorModifier.choice('disparo', 'Lo dispara', options: ['Golpe grande', 'Vuelta tras pausa', 'Cambio de frase']),
  // FORMA: por qué esquina entra.
  CreatorModifier.choice('esquina', 'Esquina', options: ['Alterna', 'Arriba izquierda', 'Arriba derecha']),
  // ATMÓSFERA: cuánto se ven las nubes.
  CreatorModifier.slider('nubes', 'Nubes', min: 0, max: 1, value: .6),
  // MODO: un segundo rayo justo después.
  CreatorModifier.toggle('segundo', 'Segundo rayo', value: true),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Tormenta', {'nubes': 1, 'segundo': true}),
  CreatorVariation('Rayo Seco', {'nubes': .15, 'segundo': false, 'esquina': 'Arriba derecha'}),
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
    // Cada relámpago trae dos destellos: como mucho uno por segundo.
    if (now - lastFire < 1.0) return;
    const int d = modifiers(f).disparo;
    fire(d == 0 ? h.big : d == 1 ? h.back : every(h, 16), d);
  }
  void render(const Frame& f, Canvas& c) const override {
    auto g = glide(f);
    const auto m = modifiers(f);
    const float W = f.width, H = f.height;
    // El relámpago más reciente; su curva va en tiempo real.
    float age = 100.0f, amp = 0.0f;
    uint32_t id = 0u;
    for (const Pulse& p : slots) {
      const float a = float(now - p.start);
      if (a < 0.0f || a > 0.8f || a >= age) continue;
      age = a;
      amp = std::min(amount(p.power) * f.intensity, 1.3f);
      id = p.id;
    }
    if (amp <= 0.0f) return;
    const float right = m.esquina == 2 ? 1.0f : m.esquina == 1 ? 0.0f : float(id % 2u);
    const Color violet = f.colors[1], blue = f.colors[2], white = f.colors[3];
    c.material("storm", {0.0f, 0.0f, W, H},
               {age, amp, right, g.nubes, m.segundo ? 1.0f : 0.0f, rnd(id * 13u + 5u), H / W,
                violet.r, violet.g, violet.b, blue.r, blue.g, blue.b, white.r, white.g, white.b},
               {"smoke"});
  }
};
''';

const shaderSources = <String, String>{
  'storm': r'''
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform float uAge;
uniform float uAmp;
uniform float uRight;
uniform float uClouds;
uniform float uSecond;
uniform float uSeed;
uniform float uAspect;
uniform vec3 uViolet;
uniform vec3 uBlue;
uniform vec3 uWhite;
uniform sampler2D uTex;
out vec4 fragColor;

float hash(float n) {
  return fract(sin(n * 12.9898) * 43758.5453);
}
float hash2(vec2 p) {
  return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// Curva de un relámpago: descarga, re-descarga, segundo rayo y cola.
float flash(float a) {
  float f = step(0.0, a) * exp(-max(a, 0.0) / 0.035);
  f += 0.6 * step(0.085, a) * exp(-max(a - 0.085, 0.0) / 0.03);
  f += uSecond * step(0.27, a) * exp(-max(a - 0.34, 0.0) / 0.04);
  float tail = smoothstep(0.3, 0.36, a) * (1.0 - smoothstep(0.45, 0.75, a));
  return f + tail * 0.1 * (0.6 + 0.4 * sin(a * 63.0) * sin(a * 37.0));
}

// Color por distancia a la fuente (px de 360): blanco, azul y violeta.
vec3 tint(float r) {
  vec3 c1 = mix(vec3(0.59, 0.69, 1.0), uWhite, 0.1);
  vec3 c2 = mix(uBlue, uViolet, 0.25) * vec3(0.3, 0.32, 0.8);
  vec3 c3 = uViolet * 0.47;
  if (r < 80.0) return mix(vec3(1.0), c1, smoothstep(40.0, 80.0, r));
  if (r < 200.0) return mix(c1, c2, (r - 80.0) / 120.0);
  if (r < 400.0) return mix(c2, c3, (r - 200.0) / 200.0);
  // Cola convexa: sin arco visible.
  return c3 * exp(-(r - 400.0) / 185.0);
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  float W = uSize.x;
  float px1 = W / 360.0;
  vec2 uv = p / W;
  float fl = flash(uAge) * uAmp;
  // El segundo rayo cae desde otro punto del borde, con los rayos girados y
  // otras nubes encendidas.
  float second = uSecond * step(0.25, uAge);
  float dirX = uRight > 0.5 ? -1.0 : 1.0;
  vec2 C = vec2(mix(-0.12, 1.12, uRight) + dirX * 0.17 * second, -0.15) * W;
  float seed = uSeed + 0.37 * second;
  vec2 v = p - C;
  float r = length(v) / px1;
  vec2 toL = -v / max(length(v), 0.001);
  // Rayos suaves de 2-6 px entre las nubes: once, de anchos y brillos distintos.
  float ang = atan(v.y, v.x) + 0.14 * second;
  float rays = 0.0;
  for (int i = 0; i < 11; i++) {
    float fi = float(i);
    float ra = mix(0.25, 1.3, hash(fi + seed * 7.0));
    float rc = uRight > 0.5 ? 3.14159 - ra : ra;
    float wpx = 2.0 + 4.0 * hash(fi + 3.3 + seed);
    float da = (ang - rc) * r;
    rays += exp(-da * da / (wpx * wpx)) * (0.5 + 0.5 * hash(fi + 8.1 + seed)) * (1.0 - smoothstep(250.0, 500.0, r));
  }
  // Bruma abstracta en vez de nubes: ruido de dos octavas (120-250 px y
  // 40-60 px) que modula la luz entre x0,75 y x1,25, un poco más clara donde
  // mira a la fuente. Nada más fino que 20 px.
  vec2 hs = p / (185.0 * px1) + vec2(seed, seed * 0.37);
  float n1 = texture(uTex, fract(hs * 0.25)).r;
  float n2 = texture(uTex, fract(hs * 0.85 + 0.5)).r;
  float hazeN = 0.7 * n1 + 0.3 * n2;
  float hazeB = 0.7 * texture(uTex, fract((p - toL * 20.0 * px1) / (185.0 * px1) * 0.25 + vec2(seed, seed * 0.37) * 0.25)).r + 0.3 * n2;
  float faces = clamp((hazeN - hazeB) * 6.0, 0.0, 1.0) * uClouds;
  vec3 light = tint(r) * fl * (1.0 + 0.9 * rays) * mix(1.0, 0.75 + 0.5 * hazeN, uClouds) + tint(r * 0.6) * fl * faces * 0.1;
  // El color sigue a la intensidad: por debajo de +170 de azul, azul
  // saturado; sólo el núcleo quemado es blanco.
  float lowB = 1.0 - smoothstep(0.62, 0.7, light.b);
  light.r = mix(light.r, min(light.r, 0.25 * light.b), lowB);
  light.g = mix(light.g, min(light.g, 0.35 * light.b), lowB);
  vec3 tone = min(light, vec3(1.0));
  float shade = 0.0;
  float m = max(tone.r, max(tone.g, tone.b));
  fragColor = vec4(tone, clamp(max(shade * (1.0 - m), 0.1 * m), 0.0, 1.0));
}
''',

};
