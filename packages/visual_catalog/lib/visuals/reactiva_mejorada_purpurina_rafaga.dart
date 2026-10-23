// Reactiva Mejorada · Purpurina en Ráfaga — transparencia momentánea. Con los platillos una onda de
// luz recorre miles de microfacetas que sólo destellan cuando su ángulo
// coincide con la luz, como lentejuelas bajo un foco: cada faceta brilla un
// instante en su color (rojo, oro o azul de la paleta), las más fuertes abren
// una cruz fina de cuatro puntas que se apaga con ella, y la onda pasa en
// medio segundo. La luz se suma a la escena. Referente: un vestido de
// lentejuelas cruzado por un cañón de luz en un videoclip.
// Versión mejorada: sigue el ritmo (cada golpe o cada tiempo) y su fuerza
// depende del volumen de la música.
// Funciona encima de cualquier escena sin conocerla: sólo luz, sin objetos que
// se queden. Sin música no dibuja nada. Nunca más de tres destellos por segundo.
// Su detalle sale de una textura propia de alta calidad que el shader anima.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // MÚSICA: qué golpe hace destellar.
  CreatorModifier.choice('disparo', 'Lo dispara', options: ['Platillos', 'Caja', 'Golpes acentuados']),
  // FORMA: cuántas facetas.
  CreatorModifier.slider('destellos', 'Destellos', min: .3, max: 1, value: .8),
  // MOVIMIENTO: por dónde pasa la luz.
  CreatorModifier.choice('direccion', 'Dirección', options: ['Diagonal', 'Horizontal', 'Desde el centro']),
  // ATMÓSFERA: cuánto tarda en cruzar.
  CreatorModifier.slider('caida', 'Duración', min: .2, max: .9, value: .45),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Lentejuelas', {'destellos': 1, 'direccion': 'Desde el centro', 'caida': .7}),
  CreatorVariation('Escarcha', {'destellos': .4, 'caida': .25}),
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
  float eFast = 0.0f, eMid = 0.0f, eSlow = 0.0f, bassSlow = 0.0f, build = 0.0f, impactMean = 0.0f, hatMean = 0.0f, loud = 0.0f, peak = 0.0f;
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
      // Volumen: cuánto suena ahora, mezcla del nivel absoluto y del relativo
      // al pico reciente. En silencio vuelve a cero.
      peak = std::max(peak * 0.9985f, eFast);
      const float loudTarget = std::clamp(0.5f * eFast / std::max(peak, 0.05f) + 1.2f * eFast, 0.0f, 1.3f);
      loud += (loudTarget - loud) * (loudTarget > loud ? 0.35f : 0.06f);
      bassSlow += (mu.bass - bassSlow) * (mu.bass > bassSlow ? 0.15f : 0.047f);
      // Subida: la energía de medio plazo crece por encima de la lenta.
      if (eMid > eSlow * 1.12f + 0.015f) build = std::min(1.0f, build + float(kStep) * 0.7f);
      else build = std::max(0.0f, build - float(kStep) * 0.9f);
    }
    for (const Event& e : mu.events[0]) {  // bombo
      const float s = std::max(e.strength, 0.05f);
      h.kick = std::max(h.kick, s);
      // Golpe grande: el primero tras una pausa o uno claramente más fuerte que los últimos.
      // Golpe acentuado: igual o más fuerte que la media reciente. En un ritmo
      // regular son casi todos; si unos suenan más, sólo esos.
      if (now - lastImpact > 1.5 || s >= impactMean * 0.98f) h.big = std::max(h.big, std::clamp(s / std::max(impactMean, 0.05f) * 0.6f, 0.3f, 1.2f));
      // Vuelta tras una pausa: el primer golpe después de un silencio.
      // Cada golpe, con más fuerza si llega tras un silencio.
      h.back = std::max(h.back, quiet > 1.2 ? std::max(s, 0.8f) : s);
      impactMean = impactMean <= 0.0f ? s : impactMean + (s - impactMean) * 0.25f;
      lastImpact = now;
    }
    for (const Event& e : mu.events[1]) {  // caja o palmada; platillos en la banda alta
      const float s = std::max(e.strength, 0.05f);
      if (e.band == 3) {
        h.hat = std::max(h.hat, s);
        if (s >= hatMean * 0.98f && now - lastHatBig > 0.2) {
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
      if (now - lastBig < 0.3) {
        h.big = 0.0f;
      } else {
        lastBig = now;
        if (build > 0.5f) {  // golpe grande al final de una subida: el drop
          h.drop = true;
          build = 0.0f;
        }
      }
    }
    // Golpes en la subida: cada golpe mientras la energía crece.
    if (h.kick > 0.0f && eFast > eSlow * 1.05f) h.jump = h.kick;
    if (!bassHigh && mu.bass > 0.45f) {
      bassHigh = true;
      h.bassUp = mu.bass;
    } else if (bassHigh && mu.bass < 0.3f) {
      bassHigh = false;
    }
    if (mu.active && (mu.energy > 0.06f || !mu.events[0].empty() || !mu.events[1].empty())) lastSound = now;
    return h;
  }

  // Guarda un momento. Con gated respeta la pausa mínima entre destellos.
  bool fire(float power, int kind = 0, double delay = 0.0, bool gated = true) {
    if (power <= 0.0f) return false;
    power *= 0.3f + 0.9f * loud;  // el volumen decide cuánto se ve
    if (gated) {
      if (now - lastFire < kGap) return false;
      lastFire = now + delay;
    }
    slots[cursor] = Pulse{now + delay, power, kind, fired++};
    cursor = (cursor + 1) % kSlots;
    return true;
  }
  // Con el ritmo: n = 4 (antes cada compás) es cada tiempo y n = 16 (antes
  // cada frase) es cada dos tiempos.
  static float every(const Hits& h, int n) {
    const int m = n >= 16 ? 2 : 1;
    for (int i = 0; i < h.beats; i++)
      if (h.tick[i] % m == 0) return std::max(h.beat, 0.5f);
    return 0.0f;
  }

  static uint32_t mixh(uint32_t x) {
    x ^= x >> 16; x *= 0x7feb352du; x ^= x >> 15; x *= 0x846ca68bu; x ^= x >> 16;
    return x;
  }
  static float rnd(uint32_t x) { return float(mixh(x) & 0xffffffu) / 16777216.0f; }
  // Cuanto más fuerte suena el golpe, más se nota.
  static float amount(float power) { return std::clamp(0.25f + 0.85f * power, 0.15f, 1.45f); }
  static float pace(const Frame& f) { return 1.6f * std::clamp(f.speed, 0.5f, 2.0f); }
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
    eFast = eMid = eSlow = bassSlow = build = impactMean = hatMean = loud = peak = 0.0f;
    bassHigh = false;
    for (auto& b : bins_) b.reserve(2048);
    resetOwn(seed);
  }
  void resetOwn(uint32_t) {}
  void update(const Frame& f) override {
    const Hits h = listen(f);
    const int d = modifiers(f).disparo;
    fire(d == 0 ? h.hat : d == 1 ? h.snare : h.big, d);
  }
  void render(const Frame& f, Canvas& c) const override {
    auto g = glide(f);
    const auto m = modifiers(f);
    const float W = f.width, H = f.height;
    // La onda cruza a unos 58 px por cuadro con la duración por defecto.
    const float speed = 0.45f / std::max(g.caida, 0.1f) * pace(f);
    const float T = 0.8f / speed;
    const Color red = f.colors[1], gold = f.colors[2], blue = f.colors[3];
    for (const Pulse& p : slots) {
      const float age = float(now - p.start);
      if (age < 0.0f || age > T) continue;
      const float k = std::min(amount(p.power) * f.intensity, 1.3f);
      c.material("glitter", {0.0f, 0.0f, W, H},
                 {age * speed, k, g.destellos, float(m.direccion), float(p.id % 97u), float(now),
                  red.r, red.g, red.b, gold.r, gold.g, gold.b, blue.r, blue.g, blue.b});
    }
  }
};
''';

const shaderSources = <String, String>{
  'glitter': r'''
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform float uT;
uniform float uAmp;
uniform float uDensity;
uniform float uDir;
uniform float uSeed;
uniform float uTime;
uniform vec3 uRed;
uniform vec3 uGold;
uniform vec3 uBlue;
out vec4 fragColor;

float hash(float n) {
  return fract(sin(n * 12.9898) * 43758.5453);
}
float hash2(vec2 p) {
  return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// Posición (px) a lo largo de la onda de luz, con el frente un poco curvado.
float sweep(vec2 q, vec2 sz, float dir) {
  if (dir < 0.5) {
    vec2 a = normalize(vec2(1.0, 1.0));
    float perp = dot(q - 0.5 * sz, vec2(-a.y, a.x));
    return dot(q, a) + perp * perp / 1400.0;
  }
  if (dir < 1.5) {
    float perp = q.y - 0.5 * sz.y;
    return q.x + perp * perp / 1400.0;
  }
  return length(q - 0.5 * sz) * 1.6;
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  float px1 = uSize.x / 360.0;
  vec2 q = p / px1;
  vec2 sz = uSize / px1;
  // Frente de la onda (58 px por cuadro).
  float front = -150.0 + 1740.0 * uT;
  float sp = sweep(q, sz, uDir);
  if (abs(sp - front) > 320.0) {
    fragColor = vec4(0.0);
    return;
  }
  // Lóbulos a lo largo de la onda (±35 %).
  float perp = uDir < 0.5 ? dot(q - 0.5 * sz, normalize(vec2(-1.0, 1.0))) : q.y;
  float lobe = 1.0 + 0.35 * sin(6.2832 * perp / 320.0 + uSeed + 0.5 * uTime);
  vec3 pal0 = mix(vec3(1.0, 0.165, 0.227), uRed / max(uRed.r, 0.01), 0.2);
  vec3 pal1 = vec3(0.19, 1.0, 0.44);
  vec3 pal2 = mix(vec3(0.227, 0.42, 1.0), uBlue / max(uBlue.b, 0.01), 0.2);
  vec3 pal3 = vec3(0.63, 0.227, 1.0);
  vec3 gold = mix(vec3(1.0, 0.784, 0.0), uGold / max(uGold.r, 0.01), 0.15);
  float cs = 10.0;
  vec2 cell0 = floor(q / cs);
  vec3 light = vec3(0.0);
  for (int j = -2; j <= 2; j++) {
    for (int i = -2; i <= 2; i++) {
      vec2 cell = cell0 + vec2(float(i), float(j));
      if (hash2(cell + uSeed) > mix(0.5, 1.0, uDensity)) continue;
      vec2 fc = (cell + vec2(hash2(cell + 3.1), hash2(cell + 7.7))) * cs;
      // Cada faceta destella al pasar la luz (con un adelanto o retraso
      // propio) durante 1-3 cuadros.
      float h1 = hash2(cell + 11.3);
      float h2 = hash2(cell + 12.9);
      float h3 = hash2(cell + 14.7);
      float jit = hash2(cell + 19.1) < 0.03 ? (h1 - 0.5) * 240.0 : (h1 + h2 + h3 - 1.5) * 40.0;
      float litLen = 58.0 * (3.0 + hash2(cell + 23.3));
      float x = front - (sweep(fc, sz, uDir) + jit);
      float on = smoothstep(0.0, 12.0, x) * (1.0 - smoothstep(litLen - 12.0, litLen, x));
      if (on < 0.01) continue;
      // 75 % tenues, 20 % fuertes y 5 % las más fuertes (con cruz).
      float cls = hash2(cell + 5.5);
      float lv = cls < 0.75 ? mix(0.43, 0.67, hash2(cell + 6.1)) : (cls < 0.95 ? mix(0.75, 0.94, hash2(cell + 6.1)) : 1.15);
      // Donde pasa el frente brillan más (una cresta de luz); lejos, menos.
      float dF = abs(sweep(fc, sz, uDir) - front);
      lv *= on * lobe * uAmp * mix(1.5, 0.6, smoothstep(20.0, 60.0, dF));
      float sel = hash2(cell + 9.9);
      vec3 col = sel < 0.25 ? pal0 : (sel < 0.5 ? pal1 : (sel < 0.75 ? pal2 : pal3));
      if (lv > 0.67 && hash2(cell + 8.8) < 0.35) col = gold;
      vec2 d = q - fc;
      float r2 = dot(d, d);
      float core = exp(-r2 / 1.44) * lv;
      float glow = 0.3 * exp(-r2 / 2.9) * lv;
      // Núcleo blanco sólo en 1 px y desde +220.
      light += mix(col, vec3(1.0), smoothstep(0.86, 0.95, core)) * core + col * glow;
      if (cls >= 0.95) {
        float len = 8.0 + 12.0 * hash2(cell + 2.2);
        float ax = abs(d.x);
        float ay = abs(d.y);
        float armX = pow(max(1.0 - ax / len, 0.0), 2.0) * exp(-d.y * d.y / 0.32) * smoothstep(0.5, 1.5, ax);
        float armY = pow(max(1.0 - ay / len, 0.0), 2.0) * exp(-d.x * d.x / 0.32) * smoothstep(0.5, 1.5, ay);
        float wx = 1.0 - smoothstep(1.5, 2.5, ax);
        float wy = 1.0 - smoothstep(1.5, 2.5, ay);
        light += 0.6 * lv * (armX * mix(col, vec3(1.0), wx) + armY * mix(col, vec3(1.0), wy));
      }
    }
  }
  vec3 tone = min(light, vec3(1.0));
  fragColor = vec4(tone, 0.1 * max(tone.r, max(tone.g, tone.b)));
}
''',

};
