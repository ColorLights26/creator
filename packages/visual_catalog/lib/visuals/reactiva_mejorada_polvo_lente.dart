// Reactiva Mejorada · Polvo de Lente Revelado — transparencia momentánea. Una luz cálida e intensa
// (naranja, rojo o ámbar, distinta en cada golpe) con el centro blanco cruza la
// lente en un arco suave y se apaga antes de salir, y revela a su alrededor,
// con la caída de la luz real, la suciedad del cristal: manchas grandes, huellas,
// vetas de grasa, fibras rizadas y motas desenfocadas con borde cromático. Una
// estela anamórfica azul nace de la fuente y se afina antes del borde; al otro
// lado del centro, los fantasmas del diafragma, casi transparentes, de esquinas
// redondeadas y borde suave más claro, de tamaños distintos, se mueven al revés
// que la luz. La luz se suma a la escena.
// Referente: lens dirt y flares de Optical Flares (Video Copilot).
// Versión mejorada: sigue el ritmo (cada golpe o cada tiempo) y su fuerza
// depende del volumen de la música.
// Funciona encima de cualquier escena sin conocerla: sólo luz, sin objetos que
// se queden. Sin música no dibuja nada. Nunca más de tres destellos por segundo.
// Su detalle sale de una textura propia de alta calidad que el shader anima.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // MÚSICA: qué momento enciende la luz.
  CreatorModifier.choice('disparo', 'Lo dispara', options: ['Golpes acentuados', 'Bombo', 'Cada dos tiempos']),
  // FORMA: cuánta suciedad tiene la lente.
  CreatorModifier.slider('suciedad', 'Suciedad', min: .3, max: 1, value: .75),
  // MOVIMIENTO: por dónde cruza la luz.
  CreatorModifier.choice('barrido', 'Barrido', options: ['Izquierda a derecha', 'Derecha a izquierda', 'De arriba abajo']),
  // ATMÓSFERA: cuánto tarda en cruzar.
  CreatorModifier.slider('caida', 'Duración', min: .5, max: 1.8, value: 1.1),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Lente Vieja', {'suciedad': 1, 'caida': 1.5}),
  CreatorVariation('Reflejo Rápido', {'suciedad': .45, 'caida': .6, 'barrido': 'De arriba abajo'}),
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
    fire(d == 0 ? h.big : d == 1 ? h.kick : every(h, 16), d);
  }
  void render(const Frame& f, Canvas& c) const override {
    auto g = glide(f);
    const float W = f.width, H = f.height;
    const float T = g.caida / pace(f);
    const float wl = g.barrido.weight(0), wr = g.barrido.weight(1), wt = g.barrido.weight(2);
    const Color blue = f.colors[0];
    for (const Pulse& p : slots) {
      const double age = now - p.start;
      if (age <= 0.0 || age >= double(T)) continue;
      const float q = float(age / double(T));
      // Brilla de inmediato (más del 60 % en el segundo cuadro) y se apaga suave.
      float e = clamp01(float(age) / 0.05f) * (1.0f - easeInOut((q - 0.6f) / 0.4f)) * std::min(amount(p.power) * f.intensity, 1.3f) * (p.kind == 1 ? 0.75f : 1.0f);
      // Un color intenso distinto en cada golpe; los fantasmas toman el siguiente.
      const Color tint = f.colors[size_t(1 + p.id % 3u)], ghost = f.colors[size_t(1 + (p.id + 1u) % 3u)];
      // Nace dentro del cuadro y cruza en un arco suave: arranca rápido y frena.
      const float s = 1.0f - (1.0f - q) * (1.0f - q), bow = 1.0f - (2.0f * s - 1.0f) * (2.0f * s - 1.0f);
      const float y = H * (0.25f + 0.45f * rnd(p.id * 13u)), x = W * (0.3f + 0.4f * rnd(p.id * 29u));
      const float tilt = (rnd(p.id * 41u) < 0.5f ? -1.0f : 1.0f) * 0.07f * H;
      const Vec2 L = {wl * W * (0.06f + 1.0f * s) + wr * W * (0.94f - 1.0f * s) + wt * (x + 0.06f * W * bow),
                      (wl + wr) * (y + tilt * (2.0f * s - 1.0f) - 0.05f * H * bow) + wt * H * (0.04f + 0.9f * s)};
      if (e < kMin) continue;
      c.material("dirt", {0.0f, 0.0f, W, H},
                 {L.x, L.y, 0.55f * W, e * g.suciedad, e, tint.r, tint.g, tint.b, ghost.r, ghost.g, ghost.b, blue.r, blue.g, blue.b},
                 {"dirt"});
    }
  }
};
''';

const shaderSources = <String, String>{
  'dirt': r'''
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec2 uLight;
uniform float uReach;
uniform float uAmount;
uniform float uGlow;
uniform vec3 uTint;
uniform vec3 uGhost;
uniform vec3 uBlue;
uniform sampler2D uTex;
out vec4 fragColor;

// Sensor: el color se satura en lo tenue y se quema a blanco en lo intenso.
vec3 sensor(vec3 c) {
  return c / max(max(c.r, c.g), max(c.b, 0.01)) * 0.86 + 0.14;
}

// Como el sensor, pero el canal dominante se satura antes: la luz cálida pasa
// de blanco a ámbar, naranja y rojo sin volverse beige.
vec3 warmSensor(vec3 c) {
  vec3 n = c / max(max(c.r, c.g), max(c.b, 0.01));
  return (pow(n, vec3(1.5)) * 0.95 + 0.05) * mix(vec3(1.0), vec3(2.5), step(0.99, n));
}

// Fantasma del diafragma: el relleno sube del 50 % en el centro al 100 % a
// 0,85 del radio, el aro apenas más claro (1,4 veces el relleno) y el borde
// se apaga en lo mayor de 3 px o el 10 % del radio, todo con 1 px de suavizado.
float ghost(vec2 p, float rad, float px1) {
  float d = length(p) / rad;
  float fe = max(3.0 * px1 / rad, 0.1);
  float fill = mix(0.5, 1.0, smoothstep(0.0, 0.85, d)) * (1.0 - smoothstep(1.0 - fe, 1.0 + px1 / rad, d));
  float rz = (d - 0.9) / (0.035 + px1 / rad);
  return 0.22 * fill * (1.0 + 0.4 * exp(-rz * rz));
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  vec2 d = (p - uLight) / uReach;
  float r2 = dot(d, d);
  // Distancia a la luz en píxeles de una pantalla de 360.
  float rpx = length(p - uLight) * 360.0 / uSize.x;
  // La suciedad se enciende de lleno hasta unos 120 px de la luz y se apaga
  // antes de 180 px; lejos no queda velo.
  float reveal = 1.0 - smoothstep(90.0, 190.0, rpx);
  // Borde cromático en la suciedad: el rojo un poco más grande que el azul.
  vec2 st = p / uSize.x * 0.9;
  vec2 c = 0.45 * uSize / uSize.x;
  float dr = texture(uTex, fract(c + (st - c) * 0.995)).r;
  vec4 t = texture(uTex, fract(st));
  float db = texture(uTex, fract(c + (st - c) * 1.005)).r;
  vec3 kT = warmSensor(uTint);
  // La suciedad lleva la luz: en ámbar claro, más brillante que el resplandor.
  vec3 kD = vec3(1.6, 0.75, 0.22) * mix(vec3(1.0), uTint / max(max(uTint.r, uTint.g), max(uTint.b, 0.01)), 0.3);
  // Entre las manchas no queda velo: sólo brilla lo que sobresale.
  vec3 dirt = max(vec3(dr, t.r, db) - 0.08, 0.0) / 0.92;
  vec3 light = pow(dirt, vec3(1.5)) * kD * (1.4 * reveal * uAmount) + kD * (t.g * t.g * reveal * uAmount * 0.25);
  // La fuente: núcleo blanco y una caída suave sin meseta (rojo +230 a 20 px,
  // +170 a 35, +115 a 50, +55 a 80, +22 a 120 y nada a 180).
  float a1 = rpx / 6.0;
  light += kT * uGlow * (8.0 * exp(-a1 * a1) + 0.93 * pow(20.0 / max(rpx, 3.0), 1.6) * (1.0 - smoothstep(100.0, 180.0, rpx)));
  // Estela anamórfica azul: núcleo casi blanco de 3-4 px y resplandor vertical
  // suave; máxima en la fuente y apagada antes del borde.
  float ax = abs(p.x - uLight.x) / uSize.x;
  float dy = abs(p.y - uLight.y) / uSize.x;
  float taper = exp(-ax / 0.2) * smoothstep(0.0, 0.08, min(p.x, uSize.x - p.x) / uSize.x);
  light += sensor(uBlue) * uGlow * taper * (3.5 * exp(-dy / 0.004) + 0.5 * exp(-dy / 0.022));
  // Fantasmas sobre el eje que pasa por el centro: se mueven al revés que la luz.
  vec2 C = 0.5 * uSize;
  vec2 axis = C - uLight;
  vec3 kG = sensor(uGhost);
  float px1 = uSize.x / 360.0;
  for (int i = 0; i < 4; i++) {
    float s = i == 0 ? 0.4 : (i == 1 ? 0.9 : (i == 2 ? 1.45 : 2.1));
    float rad = px1 * (i == 0 ? 6.0 : (i == 1 ? 13.0 : (i == 2 ? 24.0 : 45.0)));
    vec2 q = p - (C + axis * s);
    // Filo de color de 1 px: el rojo un píxel más grande que el azul.
    vec3 shape = vec3(ghost(q, rad + px1, px1), ghost(q, rad, px1), ghost(q, rad - px1, px1));
    // Recubrimientos de la lente: azul intenso y el color siguiente, saturados.
    vec3 gc = i == 1 || i == 3 ? uBlue : uGhost;
    gc = pow(gc / max(max(gc.r, gc.g), max(gc.b, 0.01)), vec3(1.3)) * 0.9 + 0.05;
    light += shape * gc * uGlow;
  }
  vec3 col = vec3(1.0) - exp(-light);
  fragColor = vec4(col, 0.1 * max(col.r, max(col.g, col.b)));
}
''',

};
