// Reactiva · Celuloide Quemado — transparencia momentánea. La película se quema en la
// ventanilla del proyector: en el golpe prende con un destello mínimo en una
// esquina o un borde y en dos focos más que se unen, y un frente de lóbulos y
// dedos finos (ruido deformado en varias escalas) barre la imagen sin pararse.
// El frente quema a blanco y en pocos píxeles pasa a amarillo, naranja y rojo,
// con ampollas que destellan justo delante y chispas por delante de ellas; lo ya
// quemado brilla naranja y rojo y se aclara en unos cuadros, así que la
// quemadura es un anillo de fuego que avanza. Por fuera, un borde de carbón que
// oscurece sin color. Grano fino nuevo en cada cuadro, parpadeo de la
// ventanilla y temblor del proyector. Sólo suma luz.
// Referentes: film burn de Motion Array y quemaduras reales de 16 mm.
// Funciona encima de cualquier escena sin conocerla: sólo luz, sin objetos que
// se queden. Sin música no dibuja nada. Nunca más de tres destellos por segundo.
// Su detalle sale de una textura propia de alta calidad que el shader anima.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // MÚSICA: qué momento la quema.
  CreatorModifier.choice('disparo', 'Lo dispara', options: ['Golpe grande', 'Cambio de frase', 'Vuelta tras pausa']),
  // FORMA: desde dónde nace.
  CreatorModifier.choice('origen', 'Origen', options: ['Alterna', 'Esquinas', 'Bordes']),
  // ATMÓSFERA: hasta dónde llega la quemadura.
  CreatorModifier.slider('tamano', 'Tamaño', min: .4, max: 1, value: .7),
  // MOVIMIENTO: cuánto tarda en apagarse.
  CreatorModifier.slider('caida', 'Caída', min: .3, max: 1, value: .5),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Proyector', {'origen': 'Bordes', 'tamano': 1, 'caida': .8}),
  CreatorVariation('Chispazo', {'origen': 'Esquinas', 'tamano': .5, 'caida': .3}),
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
  static constexpr float kGrow = 0.42f;  // lo que tarda el frente en llegar a su tamaño
  void resetOwn(uint32_t) {}
  void update(const Frame& f) override {
    const Hits h = listen(f);
    const int d = modifiers(f).disparo;
    fire(d == 0 ? h.big : d == 1 ? every(h, 16) : h.back, d);
  }
  void render(const Frame& f, Canvas& c) const override {
    auto g = glide(f);
    const auto m = modifiers(f);
    const float W = f.width, H = f.height;
    const float fade = g.caida / pace(f);
    const Color red = f.colors[1], orange = f.colors[2], yellow = f.colors[3];
    for (const Pulse& p : slots) {
      const float age = float(now - p.start);
      if (age < 0.0f || age > 0.5f + fade) continue;
      // Arde mientras el frente avanza; luego se apaga.
      const float temp = age < 0.5f ? 1.0f : clamp01(1.0f - (age - 0.5f) / fade);
      if (temp <= 0.0f) continue;
      const float k = std::min(amount(p.power) * f.intensity, 1.2f);
      // Origen: cuatro esquinas y los centros de los cuatro bordes.
      int spot = int(p.id % 8u);
      if (m.origen == 1) spot = int(p.id % 4u);
      if (m.origen == 2) spot = 4 + int(p.id % 4u);
      const float cx[8] = {0.0f, W, 0.0f, W, 0.5f * W, W, 0.5f * W, 0.0f};
      const float cy[8] = {0.0f, 0.0f, H, H, 0.0f, 0.5f * H, H, 0.5f * H};
      // Dos focos más sobre los bordes que tocan el origen; se unen al primero.
      std::array<Vec2, 3> o{};
      o[0] = {cx[spot], cy[spot]};
      const float a1 = W * (0.18f + 0.2f * rnd(p.id * 5u + 1u)), a2 = W * (0.18f + 0.2f * rnd(p.id * 5u + 2u));
      if (spot < 4) {
        const float sx = spot % 2 == 0 ? 1.0f : -1.0f, sy = spot < 2 ? 1.0f : -1.0f;
        o[1] = {o[0].x + sx * a1, o[0].y};
        o[2] = {o[0].x, o[0].y + sy * a2 * 1.4f};
      } else if (spot == 4 || spot == 6) {
        o[1] = {o[0].x - a1, o[0].y};
        o[2] = {o[0].x + a2, o[0].y};
      } else {
        o[1] = {o[0].x, o[0].y - a1 * 1.4f};
        o[2] = {o[0].x, o[0].y + a2 * 1.4f};
      }
      // Tamaño final y retardo de cada foco; el frente avanza sin pararse.
      const float P = g.tamano * 1.45f * (p.kind == 1 ? 0.8f : 1.0f) * (0.75f + 0.25f * std::min(k, 1.0f));
      std::array<float, 3> size{}, delay{};
      float reach = 0.0f;
      for (int j = 0; j < 3; j++) {
        delay[size_t(j)] = j == 0 ? 0.0f : 0.03f + 0.07f * rnd(p.id * 9u + uint32_t(j));
        size[size_t(j)] = P * (j == 0 ? 1.0f : 0.55f + 0.25f * rnd(p.id * 13u + uint32_t(j)));
        if (age >= delay[size_t(j)])
          reach = std::max(reach, size[size_t(j)] * (0.06f + 0.94f * clamp01((age - delay[size_t(j)]) / kGrow)));
      }
      // Sólo se pinta alrededor de los focos: la quemadura y su resplandor.
      reach = (reach * 2.0f + 0.15f) * W;
      const float x0 = std::max(0.0f, std::min(o[0].x, std::min(o[1].x, o[2].x)) - reach);
      const float y0 = std::max(0.0f, std::min(o[0].y, std::min(o[1].y, o[2].y)) - reach);
      const float x1 = std::min(W, std::max(o[0].x, std::max(o[1].x, o[2].x)) + reach);
      const float y1 = std::min(H, std::max(o[0].y, std::max(o[1].y, o[2].y)) + reach);
      if (x1 <= x0 || y1 <= y0) continue;
      c.material("burn", {x0, y0, x1 - x0, y1 - y0},
                 {x0, y0, W, o[0].x, o[0].y, o[1].x, o[1].y, o[2].x, o[2].y,
                  size[0], size[1], size[2], delay[0], delay[1], delay[2], age, kGrow, temp,
                  rnd(p.id * 7u + 3u), reach / W,
                  red.r, red.g, red.b, orange.r, orange.g, orange.b, yellow.r, yellow.g, yellow.b},
                 {"burn"});
    }
  }
};
''';

const shaderSources = <String, String>{
  'burn': r'''
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec2 uOffset;
uniform float uWidth;
uniform vec2 uO0;
uniform vec2 uO1;
uniform vec2 uO2;
uniform vec3 uP;
uniform vec3 uDelay;
uniform float uAge;
uniform float uGrow;
uniform float uTemp;
uniform float uSeed;
uniform float uReach;
uniform vec3 uRed;
uniform vec3 uOrange;
uniform vec3 uYellow;
uniform sampler2D uTex;
out vec4 fragColor;

float hash(vec2 p) {
  return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void main() {
  vec2 px = FlutterFragCoord().xy + uOffset;
  float W = uWidth;
  // Temblor del proyector y el calor que hace temblar el borde.
  vec2 g = px + vec2(sin(px.y * 0.09 + uAge * 23.0) * 0.0015 * W, sin(uAge * 9.0) * 0.002 * W);
  vec2 st = g / W;
  vec2 seed = vec2(uSeed, fract(uSeed * 7.31));
  // Ruido deformado en varias escalas: lóbulos grandes, medianos y dedos finos.
  vec4 big = texture(uTex, fract(st * 0.38 + seed));
  vec2 wst = st + (big.rg - 0.5) * 0.12;
  vec4 mid = texture(uTex, fract(wst * 1.1 + seed.yx));
  vec4 t = texture(uTex, fract(wst * 2.3 + seed * 1.7));
  float warp = 0.62 + 0.55 * big.g + 0.25 * (mid.g - 0.5);
  vec3 r = vec3(length(g - uO0), length(g - uO1), length(g - uO2)) / W;
  vec3 rw = r * warp;
  // Distancia al frente de cada foco (positivo = ya quemado).
  vec3 lit = step(uDelay, vec3(uAge));
  vec3 prog = mix(vec3(-1.0), uP * (0.06 + 0.94 * clamp((vec3(uAge) - uDelay) / uGrow, 0.0, 1.0)), lit);
  vec3 ev = prog - rw;
  float e = max(ev.x, max(ev.y, ev.z)) - 0.035 * (mid.r - 0.5) - 0.014 * (t.r - 0.5);
  float aa = 1.5 / W;
  float inside = smoothstep(-aa, aa, e);
  // Los exponentes van acotados: lejos del frente un exp() desbordado daría NaN.
  float ein = max(e, 0.0), eout = min(e, 0.0);
  // Cuánto hace que pasó el frente por aquí (distancia / velocidad): lo
  // quemado se aclara en unos cuadros, sin escalones entre focos.
  float ago = ein * uGrow / (0.94 * max(max(uP.x, max(uP.y, uP.z)), 0.001));
  float rmin = min(r.x, min(r.y, r.z));
  float edge = smoothstep(uReach, uReach - 0.12, rmin);
  // Grano fino nuevo en cada cuadro y parpadeo de la ventanilla.
  float frame = floor(uAge * 24.0);
  float grain = hash(floor(px) + frame * 7.13);
  float gate = 0.9 + 0.2 * hash(vec2(frame, uSeed * 13.0));
  // Frente: blanco en la línea y, en pocos píxeles, amarillo, naranja y rojo.
  float L = 32.0 * exp(eout / 0.006) * (1.0 - inside) + 32.0 * exp(-ein / 0.006) * inside;
  // Lo ya quemado brilla naranja y rojo y se aclara en unos cuadros.
  L += inside * (1.2 + 1.6 * big.g) * (0.85 + 0.3 * mid.r) * exp(-ago / 0.09);
  // Ampollas llenas agrupadas justo delante del frente: destellan y revientan al pasar.
  L += 14.0 * smoothstep(0.08, 0.3, big.b) * smoothstep(-0.03, -0.004, e) * (1.0 - inside);
  // Chispas por delante.
  float spark = step(0.985, hash(floor(px / 2.0) + frame));
  L += spark * 6.0 * smoothstep(-0.08, -0.03, e) * (1.0 - smoothstep(-0.025, -0.012, e));
  L *= (0.92 + 0.16 * grain) * gate;
  // Destello mínimo en cada foco al prender.
  vec3 ig = clamp(1.0 - (vec3(uAge) - uDelay) / 0.07, 0.0, 1.0) * lit;
  L += 10.0 * dot(ig, exp(-r / 0.05));
  float alive = smoothstep(0.0, 0.6, uTemp) * edge;
  L *= alive;
  // Sensor: el rojo se satura primero, así lo menos intenso es rojo vivo.
  vec3 k = vec3(2.0, 0.5 * (2.0 * uRed.g / max(uRed.r, 0.01) + 0.6 * uOrange.g), 0.06 * uYellow.b);
  vec3 emit = vec3(1.0) - exp(-L * k);
  // Borde de carbón: oscurece un 20 % sin color, justo fuera del rojo.
  float charA = smoothstep(-0.045, -0.032, e) * (1.0 - smoothstep(-0.024, -0.016, e)) * 0.2 * alive;
  float mx = max(emit.r, max(emit.g, emit.b));
  fragColor = vec4(emit, clamp(max(charA, 0.1 * mx), 0.0, 1.0));
}
''',

};
