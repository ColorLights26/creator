// Reactiva · Proyección de Aceite — transparencia momentánea. Con el golpe florece sobre
// la escena una mancha de tintes de aceite de colores, como en los light
// shows de los 60: tres tintes (rojo, ámbar y violeta) con los centros muy
// juntos, cada uno una cadena curva de gotas fundidas con el contorno vivo
// que fluye, el color moteado por dentro sin un centro marcado y la luz
// sumándose donde se montan. Nace ya abierta en el golpe y se recoge
// encogiendo y juntando las cadenas. Sólo suma luz. Referente: Joshua Light
// Show, «Liquid Loops».
// Funciona encima de cualquier escena sin conocerla: sólo luz, sin objetos que
// se queden. Sin música no dibuja nada. Nunca más de tres destellos por segundo.
// Su detalle sale de una textura propia de alta calidad que el shader anima.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.choice('disparo', 'Lo dispara', options: ['Golpe grande', 'Cada frase', 'Subida de energía']),
  // FORMA: tamaño de las gotas de aceite.
  CreatorModifier.slider('celulas', 'Tamaño de las gotas', min: .6, max: 1.4, value: 1),
  // MOVIMIENTO: cuánto dura la proyección.
  CreatorModifier.slider('caida', 'Duración', min: .5, max: 1.6, value: 1),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Placa Grande', {'celulas': 1.35, 'caida': 1.5}),
  CreatorVariation('Gotas', {'celulas': .7, 'caida': .6}),
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
    const float W = f.width, H = f.height;
    const float px1 = W / 360.0f;
    const float T = g.caida * 1.0f / pace(f);
    const Color red = f.colors[1], amber = f.colors[2], violet = f.colors[3];
    for (const Pulse& p : slots) {
      const float a = float(now - p.start);
      if (a < 0.0f || a > T) continue;
      const float q = a / T;
      const float lv = std::min(f.intensity, 1.2f);
      const float sz = std::clamp(0.6f + 0.5f * p.power, 0.6f, 1.15f);
      // Tres tintes (rojo, ámbar y violeta) cuyos centros quedan a menos de
      // 50 px: cada uno es una cadena curva de cinco gotas fundidas. Nace ya
      // abierto (75 %) y se recoge encogiendo y juntando las cadenas.
      const float cx = W * (0.3f + 0.4f * rnd(p.id * 7u + 1u));
      const float cy = H * (0.28f + 0.44f * rnd(p.id * 9u + 2u));
      const float open = (0.75f + 0.25f * easeOut(clamp01(a * pace(f) / 0.15f))) * (1.0f - easeInOut((q - 0.45f) / 0.55f));
      if (open < 0.02f) continue;
      const float spin = (rnd(p.id * 3u + 4u) < 0.5f ? -1.0f : 1.0f) * 0.6f * a + 6.2832f * rnd(p.id * 5u + 6u);
      std::vector<float> u;
      u.reserve(32);
      for (int i = 0; i < 3; i++) {
        const uint32_t s = p.id * 41u + uint32_t(i) * 13u;
        const float th = spin + 2.0944f * float(i);
        // Centros a 60-80 px entre sí; mancha de 230-280 px.
        const float dist = 40.0f * px1 * sz * g.celulas;
        u.push_back(cx + std::cos(th) * dist);
        u.push_back(cy + std::sin(th) * dist);
        u.push_back(th + 1.5708f + (rnd(s + 1u) - 0.5f) * 1.2f);
        u.push_back((42.0f + 14.0f * rnd(s + 2u)) * px1 * sz * g.celulas);
      }
      u.push_back(lv);
      u.push_back(float(now));
      u.push_back(open);
      u.push_back(rnd(p.id * 11u + 7u));
      for (const Color& col : {red, amber, violet}) {
        u.push_back(col.r);
        u.push_back(col.g);
        u.push_back(col.b);
      }
      c.material("oil", {0.0f, 0.0f, W, H}, u);
    }
  }
};
''';

const shaderSources = <String, String>{
  'oil': r'''
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uD0;
uniform vec4 uD1;
uniform vec4 uD2;
uniform float uAmp;
uniform float uTime;
uniform float uOpen;
uniform float uSeed;
uniform vec3 uRed;
uniform vec3 uAmber;
uniform vec3 uViolet;
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

// Distancia aproximada (px) al contorno de un tinte: cadena curva de cinco
// gotas de 14-40 px que se juntan al recogerse.
float dye(vec2 p, vec4 d, float k0, float px1) {
  vec2 dir = vec2(cos(d.z), sin(d.z));
  vec2 nrm = vec2(-dir.y, dir.x);
  float bend = (hash(k0 + 7.0) - 0.5) * 1.4;
  float chain = d.w * (0.4 + 0.6 * uOpen);
  float f = 0.0;
  for (int k = 0; k < 5; k++) {
    float t = (float(k) - 2.0) / 2.0;
    vec2 ck = d.xy + dir * t * chain * 1.1 + nrm * t * t * bend * chain * 0.6;
    float rk = d.w * uOpen * (0.35 + 0.65 * hash(k0 + float(k) * 3.1));
    vec2 dv = p - ck;
    f += rk * rk / (dot(dv, dv) + 1.0);
  }
  float rr = 0.8 * d.w * uOpen;
  return rr * (1.0 / sqrt(max(f, 1e-4)) - 1.0) / px1;
}

// Tinte con densidad viva (0,62-1, manchas de 20-40 px que se desplazan):
// del borde exterior al relleno en 6 px y un menisco que no pasa de 1,08
// veces el relleno.
float body(float dd, float dens) {
  float ramp = smoothstep(3.0, -3.0, dd);
  float men = 1.0 + 0.08 * exp(-(dd + 5.0) * (dd + 5.0) / 6.0);
  return dens * ramp * men;
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  float px1 = uSize.x / 360.0;
  // Contornos deformados (16 px a 65 px de onda) que fluyen unos 4 px por
  // cuadro.
  vec2 w = vec2(vnoise2(p / (65.0 * px1) + vec2(uTime * 3.7, uSeed * 9.0)), vnoise2(p / (65.0 * px1) + vec2(uSeed * 4.0 + 5.3, uTime * 3.2))) - 0.5;
  vec2 pw = p + w * 32.0 * px1;
  vec2 dq = pw / (30.0 * px1);
  // Los tres tintes con la misma densidad viva (0,5-0,88): ninguno manda.
  float dR = 0.5 + 0.38 * vnoise2(dq + vec2(uTime * 0.9, uSeed * 3.0));
  float dA = 0.5 + 0.38 * vnoise2(dq + vec2(uSeed * 5.0 + 2.0, uTime * 0.8));
  float dV = 0.5 + 0.38 * vnoise2(dq + vec2(-uTime * 0.7 + 4.0, uSeed * 7.0));
  float Lr = body(dye(pw, uD0, uSeed * 31.0, px1), dR) * uAmp;
  float La = body(dye(pw, uD1, uSeed * 31.0 + 17.0, px1), dA) * uAmp;
  float Lv = body(dye(pw, uD2, uSeed * 31.0 + 41.0, px1), dV) * uAmp;
  // Color por el brillo final de cada tinte: el ámbar es oro por encima de
  // 0,78 y naranja sólo en su borde.
  vec3 cR = mix(vec3(1.0, 0.12, 0.06), uRed / max(uRed.r, 0.01), 0.15);
  // Naranja sólo por encima de +170 y oro desde 0,75 (nada pardo abajo).
  vec3 cA = mix(vec3(1.0, 0.27, 0.04), vec3(1.0, 0.45, 0.05), smoothstep(0.62, 0.7, La));
  cA = mix(cA, mix(vec3(1.0, 0.62, 0.06), uAmber / max(uAmber.r, 0.01), 0.1), smoothstep(0.72, 0.8, La));
  vec3 cV = mix(vec3(0.42, 0.16, 1.0), uViolet / max(uViolet.b, 0.01), 0.15);
  // Donde se cruzan, el más fuerte da el tono y la luz se suma en parte.
  float wr = Lr * Lr * Lr * Lr;
  float wa = La * La * La * La;
  float wv = Lv * Lv * Lv * Lv;
  vec3 hue = (cR * wr + cA * wa + cV * wv) / max(wr + wa + wv, 1e-5);
  // Mezclas saturadas: rojo y violeta dan magenta, ámbar y violeta rosa
  // intenso (se quita el gris de la mezcla).
  hue -= 0.8 * min(hue.r, min(hue.g, hue.b));
  hue /= max(max(hue.r, max(hue.g, hue.b)), 1e-4);
  float mx = max(Lr, max(La, Lv));
  float L = mx + 0.25 * (Lr + La + Lv - mx);
  L = L < 0.9 ? L : 0.9 + 0.1 * (1.0 - exp(-(L - 0.9) / 0.1));
  vec3 tone = min(hue * L, vec3(1.0));
  fragColor = vec4(tone, 0.1 * max(tone.r, max(tone.g, tone.b)));
}
''',

};
