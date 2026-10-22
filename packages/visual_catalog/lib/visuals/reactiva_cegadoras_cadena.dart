// Reactiva · Cegadoras en Cadena — transparencia momentánea. Las «blinders» de un concierto
// miran al público, es decir, a cámara: módulos grandes de cuatro lámparas, como
// un Chauvet STRIKE 4, en dos filas escalonadas (la de arriba cortada por el
// borde), se encienden en cadena. Cada lámpara quema a blanco sólo en su centro,
// con dos resplandores suaves (1,5 y 6 veces su radio), su propio desfase y
// brillo, y una estrella de seis puntas igual en todas, como vista por una sola
// cámara. En el golpe, un resplandor cálido sube un instante; el brillo cae en
// unos tres cuadros y queda sólo el filamento, que se enfría de ámbar a naranja
// y rojo brasa sobre negro. Un cono de bruma suave baja de cada módulo.
// Referentes: Chauvet STRIKE 4 y Molefay en un drop, filmados por una cámara.
// Funciona encima de cualquier escena sin conocerla: sólo luz, sin objetos que
// se queden. Sin música no dibuja nada. Nunca más de tres destellos por segundo.
// Su detalle sale de una textura propia de alta calidad que el shader anima.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // MÚSICA: qué momento las enciende.
  CreatorModifier.choice('disparo', 'Lo dispara', options: ['Golpe grande', 'Primer tiempo', 'Caja']),
  // FORMA: cuántos módulos.
  CreatorModifier.steps('lamparas', 'Módulos', min: 3, max: 6, value: 4),
  // MOVIMIENTO: cómo se encienden.
  CreatorModifier.choice('cadena', 'Encendido', options: ['Desde el centro', 'De lado a lado', 'Todas a la vez']),
  // ATMÓSFERA: bruma en el aire bajo los módulos.
  CreatorModifier.slider('humo', 'Humo en el aire', min: 0, max: 1, value: .6),
  // Cuánto tarda en enfriarse el filamento.
  CreatorModifier.slider('enfriado', 'Enfriado', min: .25, max: .9, value: .55),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Estadio', {'lamparas': 6, 'cadena': 'De lado a lado', 'enfriado': .8, 'humo': 1}),
  CreatorVariation('Golpe Seco', {'cadena': 'Todas a la vez', 'enfriado': .3, 'lamparas': 3, 'humo': .3}),
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
    fire(d == 0 ? h.big : d == 1 ? every(h, 4) : h.snare, d == 2 ? 1 : 0);
  }
  void render(const Frame& f, Canvas& c) const override {
    auto g = glide(f);
    const float W = f.width, H = f.height;
    const int n = std::clamp(int(std::lround(g.lamparas)), 3, 6);
    const float cool = g.enfriado / pace(f), flash = 0.18f / pace(f), hit = 0.14f / pace(f);
    const float wc = g.cadena.weight(0), wl = g.cadena.weight(1);
    // Cada módulo sigue el último golpe que le llega: su edad y su fuerza. El
    // shader calcula cada lámpara con su propio desfase.
    std::array<float, 6> ages{}, amps{};
    ages.fill(100.0f);
    float punch = 0.0f;
    bool alive = false;
    for (const Pulse& p : slots) {
      const double age0 = now - p.start;
      if (age0 < -0.05 || age0 > 0.8 + 1.3 * double(cool)) continue;
      const bool odd = (p.id & 1u) != 0u;
      const float k = std::min(amount(p.power) * f.intensity, 1.3f);
      for (int i = 0; i < n; i++) {
        if (p.kind == 1 && ((i < n / 2) == odd)) continue;  // con la caja, un lado cada vez
        const float centerOrder = std::fabs(float(i) - 0.5f * float(n - 1));
        const float sideOrder = float(odd ? n - 1 - i : i);
        // En cadena: dos o tres cuadros entre módulos, con un poco de desorden.
        const float age = float(age0) - (wc * centerOrder + wl * sideOrder) * 0.08f - 0.015f * rnd(p.id * 17u + uint32_t(i));
        if (age < -0.05f || age > 0.3f + 1.3f * cool) continue;
        if (age < ages[size_t(i)]) {
          ages[size_t(i)] = age;
          amps[size_t(i)] = k;
        }
        punch = std::max(punch, env(double(age), 0.01f, hit) * k);
        alive = true;
      }
    }
    if (!alive) return;
    const Color ember = f.colors[1], orange = f.colors[2], white = f.colors[3];
    // En el golpe, un resplandor cálido sube un instante desde los módulos.
    if (punch > kMin) {
      const Color warm = mixc(orange, white, 0.6f);
      const float a = std::min(punch, 1.0f) * 0.25f;
      c.material("lift", {0.0f, 0.0f, W, H}, {warm.r * a, warm.g * a, warm.b * a, 0.5f * W, 0.18f * W, 0.9f * W});
    }
    // Lámparas y bruma: sólo la parte de arriba.
    const float band = std::min(H, 1.3f * W);
    c.material("blinders", {0.0f, 0.0f, W, band},
               {float(now), float(n), g.humo,
                ages[0], ages[1], ages[2], ages[3], ages[4], ages[5],
                amps[0], amps[1], amps[2], amps[3], amps[4], amps[5], cool, flash,
                ember.r, ember.g, ember.b, orange.r, orange.g, orange.b, white.r, white.g, white.b},
               {"smoke"});
  }
};
''';

const shaderSources = <String, String>{
  'lift': r'''
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec3 uLight;
uniform vec2 uCenter;
uniform float uRadius;
out vec4 fragColor;

// Resplandor cálido del golpe, centrado en los módulos.
void main() {
  vec2 p = FlutterFragCoord().xy;
  vec2 d = (p - uCenter) / uRadius;
  vec3 c = uLight * exp(-dot(d, d)) * (1.0 - 0.3 * p.y / uSize.y);
  fragColor = vec4(c, 0.1 * max(c.r, max(c.g, c.b)));
}
''',

  'blinders': r'''
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform float uTime;
uniform float uCount;
uniform float uSmoke;
uniform vec4 uAgeA;
uniform vec2 uAgeB;
uniform vec4 uAmpA;
uniform vec2 uAmpB;
uniform float uCool;
uniform float uFlash;
uniform vec3 uEmber;
uniform vec3 uOrange;
uniform vec3 uWhite;
uniform sampler2D uTex;
out vec4 fragColor;

// Entra en attack segundos y se apaga en dur (caída cuadrática), como en C++.
float env(float age, float attack, float dur) {
  if (age < 0.0) return 0.0;
  if (age < attack) return age / attack;
  float k = 1.0 - clamp((age - attack) / dur, 0.0, 1.0);
  return k * k;
}

float hash(float n) {
  return fract(sin(n * 12.9898) * 43758.5453);
}

void main() {
  vec2 px = FlutterFragCoord().xy;
  vec2 uv = px / uSize.x;
  float ages[6];
  float amps[6];
  ages[0] = uAgeA.x; ages[1] = uAgeA.y; ages[2] = uAgeA.z; ages[3] = uAgeA.w; ages[4] = uAgeB.x; ages[5] = uAgeB.y;
  amps[0] = uAmpA.x; amps[1] = uAmpA.y; amps[2] = uAmpA.z; amps[3] = uAmpA.w; amps[4] = uAmpB.x; amps[5] = uAmpB.y;
  // Módulos 2x2 grandes en dos filas escalonadas; más pequeños si hay muchos.
  float unit = min(1.0, 4.5 / max(uCount, 1.0));
  float off = 0.075 * unit;  // del centro del módulo a cada lámpara
  float Rc = 0.06 * unit;    // radio de cada lámpara
  float spacing = 0.72 / max(uCount - 1.0, 1.0);
  // Sensor según la temperatura del filamento: caliente, ámbar que quema a
  // blanco; frío, rojo brasa saturado.
  vec3 m = mix(uOrange, uWhite, 0.3);
  vec3 kHot = vec3(1.0, m.g / max(m.r, 0.01), 0.25 * m.b / max(m.r, 0.01));
  vec3 kCold = vec3(2.0, 2.0 * uEmber.g / max(uEmber.r, 0.01), 0.02);
  vec3 light = vec3(0.0);
  for (int i = 0; i < 6; i++) {
    float age = ages[i];
    float amp = amps[i];
    if (float(i) >= uCount || amp <= 0.0) continue;
    float eM = env(age, 0.02, uCool) * amp;
    float hM = env(age, 0.015, uFlash) * amp;
    if (eM < 0.003 && hM < 0.003 && age > 0.1) continue;
    vec3 k = mix(kCold, kHot, smoothstep(0.15, 0.7, max(eM, hM)));
    float y = mod(float(i), 2.0) < 0.5 ? 0.07 : 0.29;
    vec2 d = vec2(uv.x - (0.14 + float(i) * spacing), uv.y - y);
    float r2 = dot(d, d);
    float L = 0.0;
    // Las cuatro lámparas, cada una con su desfase (±40 ms) y su brillo (±15 %).
    if (r2 < 0.1) {
      for (int c = 0; c < 4; c++) {
        vec2 o = vec2(c == 0 || c == 2 ? -off : off, c < 2 ? -off : off);
        float jit = hash(float(i * 4 + c) + 1.7);
        float a = age - (jit - 0.5) * 0.08;
        float gain = amp * (0.85 + 0.3 * hash(float(i * 4 + c) + 9.1));
        float e = env(a, 0.02, uCool * (0.85 + 0.3 * jit)) * gain;
        float h = env(a, 0.015, uFlash) * gain;
        vec2 dc = d - o;
        float q2 = dot(dc, dc) / (Rc * Rc);
        // Blanco puro sólo en el centro, y el resplandor de 1,5 veces el radio.
        L += 60.0 * h * h * exp(-q2 / 0.12) + 1.6 * h * exp(-q2 / 2.25);
        // Filamento: una espiral pequeña y horizontal que sigue brillando al
        // enfriarse, con el reflector apenas encendido alrededor.
        vec2 fl = dc / (vec2(0.0085, 0.003) * unit);
        L += 9.0 * e * exp(-dot(fl, fl)) + 0.7 * e * exp(-q2 / 0.5);
      }
    }
    // Resplandor ancho del módulo (6 veces el radio): cae en unos tres cuadros.
    L += 0.7 * hM * exp(-r2 / (36.0 * Rc * Rc));
    // Estrella de seis puntas, igual en todas, que se afina con la distancia.
    if (hM > 0.05) {
      float rr = sqrt(r2);
      float sp = abs(cos(3.0 * (atan(d.y, d.x) + 0.26)));
      sp *= sp; sp *= sp; sp *= sp; sp *= sp; sp *= sp; sp *= sp; sp *= sp;
      L += hM * sp * 0.02 / (rr + 0.004) * exp(-rr / (0.2 * hM * unit));
    }
    // Cono de bruma suave hacia abajo.
    if (d.y > 0.0 && uSmoke > 0.0) {
      float cone = clamp(1.0 - abs(d.x) / (d.y * 0.8 + 0.06), 0.0, 1.0);
      if (cone > 0.0) {
        float sm = texture(uTex, fract(vec2(d.x * 0.6 + float(i) * 0.23, d.y * 0.35 - uTime * 0.04))).r;
        L += uSmoke * max(hM, 0.25 * eM) * cone * cone * (0.75 + 0.5 * sm) * 0.35 / (1.0 + d.y * d.y * 8.0);
      }
    }
    light += L * k;
  }
  light *= smoothstep(uSize.y, uSize.y * 0.6, px.y);  // nada llega al borde de la zona pintada
  vec3 tone = vec3(1.0) - exp(-light);
  fragColor = vec4(tone, 0.1 * max(tone.r, max(tone.g, tone.b)));
}
''',

};
