// Reactiva · Chorro Criogénico — transparencia momentánea. En el golpe disparan desde el
// borde de abajo de dos a cuatro chorros de CO2, cada uno en su sitio, con su
// altura, su inclinación y un pequeño retraso: un núcleo blanco quemado que sale
// de la boquilla y una columna turbulenta que se abre hacia arriba con el filo
// violeta de la luz de contra. Al cortarse, la niebla sube y se deshace en
// jirones. Sólo suma luz. Referente: los cañones criogénicos de los festivales.
// Funciona encima de cualquier escena sin conocerla: sólo luz, sin objetos que
// se queden. Sin música no dibuja nada. Nunca más de tres destellos por segundo.
// Su detalle sale de una textura propia de alta calidad que el shader anima.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.choice('disparo', 'Lo dispara', options: ['Golpe grande', 'Cada frase', 'Subida de energía']),
  // FORMA: cuántos chorros.
  CreatorModifier.steps('chorros', 'Chorros', min: 1, max: 4, value: 3),
  // ATMÓSFERA: altura de los chorros.
  CreatorModifier.slider('altura', 'Altura', min: .4, max: 1, value: .78),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Muro de Niebla', {'chorros': 4, 'altura': 1}),
  CreatorVariation('Disparo Central', {'chorros': 1, 'altura': .7}),
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
    // El chorro dura un momento y la niebla se deshace después.
    const float on = 0.26f * 1.0f / pace(f);
    const float T = on + 0.7f * 1.0f / pace(f);
    const Color white = f.colors[1], violet = f.colors[2], deep = f.colors[3];
    for (const Pulse& p : slots) {
      const float a = float(now - p.start);
      if (a < 0.0f || a > T) continue;
      const float lv = std::min(f.intensity, 1.2f);
      const float sz = std::clamp(0.6f + 0.5f * p.power, 0.6f, 1.15f);
      // La Mejorada escala el número y la altura de los chorros con el volumen.
      const int n = 1.0f < 0.5f ? std::clamp(int(float(m.chorros) * (0.35f + 0.55f * sz) + 0.5f), 1, 4) : std::clamp(m.chorros, 1, 4);
      c.material("cryo", {0.0f, 0.0f, W, H},
                 {a, on, lv, float(n), g.altura * (1.0f < 0.5f ? sz : 1.0f), rnd(p.id * 5u + 3u), float(now),
                  white.r, white.g, white.b, violet.r, violet.g, violet.b, deep.r, deep.g, deep.b});
    }
  }
};
''';

const shaderSources = <String, String>{
  'cryo': r'''
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform float uAge;
uniform float uOn;
uniform float uAmp;
uniform float uCount;
uniform float uHeight;
uniform float uSeed;
uniform float uTime;
uniform vec3 uWhite;
uniform vec3 uViolet;
uniform vec3 uDeep;
out vec4 fragColor;

float hash(float n) {
  return fract(sin(n * 12.9898) * 43758.5453);
}
float hash2(vec2 p) {
  return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}
float vnoise2(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), u.x), mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), u.x), u.y);
}
// Humo sin costuras (antes una textura que dejaba bordes de 1-3 px).
float fbm(vec2 p) {
  float s = 0.0;
  float am = 0.5;
  for (int i = 0; i < 4; i++) {
    s += am * vnoise2(p);
    p = p * 2.03 + vec2(1.7, 9.2);
    am *= 0.5;
  }
  return s;
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  float px1 = uSize.x / 360.0;
  float Wpx = uSize.x / px1;
  float Hpx = uSize.y / px1;
  float x = p.x / px1;
  float up = (uSize.y - p.y) / px1;
  float a = uAge;
  // Turbulencia: humo que sube deprisa.
  float sm = fbm(vec2(x / 60.0 + uSeed * 9.0, (up - a * 900.0) / 90.0));
  float sm2 = fbm(vec2(x / 30.0 + uSeed * 4.0, (up - a * 1300.0) / 45.0));
  float turb = 0.6 * sm + 0.4 * sm2;
  float fog = 0.0;
  float core = 0.0;
  float rim = 0.0;
  float whiteW = 0.0;
  for (int i = 0; i < 4; i++) {
    float fi = float(i);
    if (fi >= uCount) continue;
    // Cada chorro con su sitio, su altura, su inclinación y su retraso.
    // Ejes a 40 px o más de los bordes, también arriba con la inclinación.
    float x0 = 40.0 + (Wpx - 80.0) * (fi + 0.2 + 0.6 * hash(fi + uSeed * 7.0)) / uCount;
    float hj = uHeight * (0.78 + 0.22 * hash(fi + 3.0 + uSeed));
    float top = max(Hpx * hj, 1.0);
    float tilt = clamp((hash(fi + 5.0 + uSeed) - 0.5) * 0.3, (40.0 - x0) / top, (Wpx - 40.0 - x0) / top);
    float aj = a - (fi < 0.5 ? 0.0 : 0.03 * hash(fi + 9.0 + uSeed));
    if (aj < 0.0) continue;
    // Ya entero en el cuadro del golpe.
    float len = Hpx * hj * (1.0 - exp(-(aj + 0.12) / 0.06));
    float after = max(aj - uOn, 0.0);
    float base = after * 420.0;
    float hw = 4.0 + 0.078 * up;
    float dx = abs(x - x0 - up * tilt + (turb - 0.5) * hw * 0.9);
    float across = smoothstep(hw, hw * 0.25, dx);
    float along = smoothstep(len + 20.0, len - 70.0, up + (turb - 0.5) * 60.0) * smoothstep(base - 10.0, base + 40.0, up);
    float prof = mix(1.0, 0.45, clamp(up / max(len, 1.0), 0.0, 1.0));
    // Al cortarse, la niebla se deshace en jirones (se encoge por área).
    float erode = smoothstep(0.0, 0.32, after);
    float body = across * along * prof;
    // Bordes del humo suaves (8 px o más) también al deshacerse.
    fog = max(fog, smoothstep(erode * 0.8, erode * 0.8 + 0.6, body * (0.4 + 0.9 * turb)) * body);
    // Núcleo fino (quemado sólo a 2-3 px del eje) en la mitad de abajo, roto
    // por la turbulencia, mientras dispara; alrededor, un halo más ancho.
    // Núcleo en cono (4 px en la boquilla, 20-30 px al 40 % de la altura) de
    // sección gaussiana; la turbulencia sólo cambia su brillo a lo largo del
    // eje (30-60 px), nunca su borde.
    float on = 1.0 - smoothstep(0.0, 0.12, after);
    float dxc = x - x0 - up * tilt;
    // Núcleo blanco continuo de la boquilla a la punta: 3 px abajo, como
    // mucho 8 px arriba y afinándose en 60 px; las ondas de 37 y 61 px sólo
    // cambian el halo, nunca el ancho del blanco.
    float uc = clamp(up / max(0.6 * len, 1.0), 0.0, 1.0);
    // Perfil en pico (exponencial): blanco estrecho (2-3 px abajo, 6-8 px
    // arriba) y una caída a violeta de 6 px o más a cada lado.
    float lam = 4.5 + 8.5 * uc;
    float sh = 9.0 + 5.0 * uc;
    float br = 1.0 + 0.12 * sin(up / 5.9 + fi * 2.0 + uSeed * 6.0) + 0.08 * sin(up / 9.7 + uSeed * 3.0 + fi);
    float lower = smoothstep(0.62 * len, 0.62 * len - 60.0, up) * along * on;
    float wcore = exp(-abs(dxc) / lam) * lower;
    whiteW = max(whiteW, wcore);
    core = max(core, 1.4 * wcore + 0.4 * br * exp(-dxc * dxc / (2.0 * sh * sh)) * lower);
    // Filo violeta de la luz de contra.
    rim = max(rim, smoothstep(0.55 * hw, 0.85 * hw, dx) * smoothstep(1.1 * hw, 0.85 * hw, dx) * along * (1.0 - erode));
  }
  float L0 = (fog * (0.4 + 0.55 * turb) + core + rim * 0.32) * uAmp;
  // Rodilla suave: sólo el eje del núcleo se acerca al blanco.
  float L = 1.0 - exp(-1.4 * L0);
  // Color por el brillo final: blanco frío en el núcleo, violeta saturado en
  // la niebla y en el filo.
  vec3 thin = mix(vec3(0.42, 0.16, 1.0), uDeep / max(uDeep.b, 0.01), 0.15);
  vec3 midC = mix(vec3(0.45, 0.22, 1.0), uViolet / max(uViolet.b, 0.01), 0.15);
  vec3 col = mix(thin, midC, smoothstep(0.45, 0.7, L));
  // El blanco sólo en el núcleo, con un paso a violeta de 6 px o más.
  col = mix(col, mix(uWhite, vec3(0.95, 0.97, 1.0), 0.5), whiteW * smoothstep(0.5, 0.9, L));
  vec3 tone = min(col * L, vec3(1.0));
  fragColor = vec4(tone, 0.1 * max(tone.r, max(tone.g, tone.b)));
}
''',

};
