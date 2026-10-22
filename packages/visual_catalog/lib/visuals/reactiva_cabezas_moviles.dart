// Reactiva · Mirada de Cabezas Móviles — transparencia momentánea. Con la caja, varias
// cabezas móviles de haz estrecho (como un Clay Paky Sharpy) escondidas en el
// borde inferior barren el humo: cada haz es un núcleo blanco de 2-3 px que
// quema aunque el haz sea de color, con el color sólo en un halo fino, y se
// apaga con la distancia entre manchas de humo que derivan. Giran hasta mirar
// a cámara: la lente se vuelve un disco nítido con su aro, dos anillos
// internos y una estrella de seis puntas, y durante dos cuadros florece a su
// alrededor; luego siguen girando y se retiran. Blanco, rojo y oro. La luz se
// suma a la escena. Referente: un drop de festival con Sharpies a cámara.
// Funciona encima de cualquier escena sin conocerla: sólo luz, sin objetos que
// se queden. Sin música no dibuja nada. Nunca más de tres destellos por segundo.
// Su detalle sale de una textura propia de alta calidad que el shader anima.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // MÚSICA: qué golpe los hace mirar.
  CreatorModifier.choice('disparo', 'Lo dispara', options: ['Caja', 'Primer tiempo', 'Golpe grande']),
  // FORMA: cuántas cabezas.
  CreatorModifier.steps('cabezas', 'Cabezas', min: 3, max: 5, value: 4),
  // ATMÓSFERA: cuánto ciegan al mirar a cámara.
  CreatorModifier.slider('deslumbre', 'Deslumbramiento', min: 0, max: 1, value: .6),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Festival', {'cabezas': 5, 'deslumbre': 1}),
  CreatorVariation('Discreto', {'cabezas': 3, 'deslumbre': .25, 'disparo': 'Primer tiempo'}),
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
    fire(d == 0 ? h.snare : d == 1 ? every(h, 4) : h.big, d);
  }
  void render(const Frame& f, Canvas& c) const override {
    auto g = glide(f);
    const float W = f.width, H = f.height;
    // La pasada más reciente: cuánto lleva y con qué fuerza.
    float age = 100.0f, amp = 0.0f;
    uint32_t id = 0u;
    for (const Pulse& p : slots) {
      const float a = float(now - p.start) * pace(f);
      if (a < 0.0f || a > 1.05f || a >= age) continue;
      age = a;
      amp = std::min(amount(p.power) * f.intensity, 1.3f);
      id = p.id;
    }
    if (amp <= 0.0f) return;
    const Color red = f.colors[1], gold = f.colors[2], white = f.colors[3];
    c.material("heads", {0.0f, 0.0f, W, H},
               {age, amp, std::clamp(std::round(g.cabezas), 3.0f, 5.0f), g.deslumbre, float(now), float(id % 2u),
                red.r, red.g, red.b, gold.r, gold.g, gold.b, white.r, white.g, white.b},
               {"smoke"});
  }
};
''';

const shaderSources = <String, String>{
  'heads': r'''
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform float uAge;
uniform float uAmp;
uniform float uCount;
uniform float uGlare;
uniform float uTime;
uniform float uFlip;
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

void main() {
  vec2 p = FlutterFragCoord().xy;
  float W = uSize.x;
  float px1 = W / 360.0;
  vec3 light = vec3(0.0);
  vec3 glare = vec3(0.0);
  // Sólo la cabeza que más mira a cámara da el resplandor ancho.
  float best = -1.0;
  float bestFace = 0.0;
  for (int i = 0; i < 5; i++) {
    float fi = float(i);
    if (fi >= uCount) continue;
    float az = (uAge - fi * 0.035 - 0.22) / 0.09;
    float fc = exp(-az * az);
    if (fc > bestFace) {
      bestFace = fc;
      best = fi;
    }
  }
  for (int i = 0; i < 5; i++) {
    float fi = float(i);
    if (fi >= uCount) continue;
    float a = uAge - fi * 0.035;  // un poco escalonadas
    if (a < 0.0) continue;
    float side = mod(fi + uFlip, 2.0) < 0.5 ? -1.0 : 1.0;
    vec2 S = vec2((fi + 0.5) / uCount * W, uSize.y - 0.035 * W);
    // Barren, miran a cámara hacia los 0,22 s y siguen girando.
    float th = mix(side * (0.45 + 0.15 * hash(fi)), -side * 0.3, smoothstep(0.0, 0.55, a));
    float fz = (a - 0.22) / 0.09;
    float face = exp(-fz * fz);
    float on = smoothstep(0.0, 0.04, a) * (1.0 - smoothstep(0.65, 1.0, a)) * uAmp;
    vec3 col = i == 0 || i == 3 ? uRed : (i == 1 || i == 4 ? uGold : uWhite);
    float haze = 1.0;
    vec2 dir = vec2(sin(th), -cos(th));
    vec2 q = p - S;
    float along = dot(q, dir);
    float across = abs(q.x * dir.y - q.y * dir.x) / px1;
    // Haz: núcleo blanco de 2-3 px y el color sólo en un halo de 4 px; nada
    // más allá de 12 px. Se acorta cuando apunta a cámara.
    float len = ((1.0 - face) * 2.2 + 0.02) * W;
    float vis = smoothstep(-2.0 * px1, 2.0 * px1, along) * smoothstep(len, len * 0.6, along);
    float dim = 1.0 / (1.0 + max(along, 0.0) / (400.0 * px1));
    // Se ensancha de 3 px junto a la lente a 7-9 px a 700 px; el núcleo es
    // blanco sólo cerca de la lente y luego toma el color del haz.
    float alongPx = max(along, 0.0) / px1;
    float wk = 1.0 + alongPx / 700.0 * 1.8;
    float acr = across / wk;
    float core = exp(-acr * acr / 1.4);
    float halo = 0.9 * exp(-acr * acr / 16.0) * step(acr, 12.0);
    vec3 csat = pow(col / max(max(col.r, col.g), max(col.b, 0.01)), vec3(1.5));
    vec3 coreCol = mix(vec3(1.0), mix(csat, vec3(1.0), 0.1), smoothstep(80.0, 160.0, alongPx));
    float hz = texture(uTex, fract(vec2(q.x / W * 1.5 + fi * 0.17, along / W * 0.35 - uTime * 0.18))).r;
    haze = 1.0 + 0.5 * (hz * hz * 2.0 - 0.6);
    vec3 beam = (core * 2.4 * coreCol + halo * csat) * dim * haze * vis * (1.0 - 0.7 * face);
    // La lente mirando a cámara: disco de 17 px con aro nítido de 1,5 px, dos
    // anillos internos tenues, núcleo quemado y estrella de seis puntas.
    vec3 lens = vec3(0.0);
    float r = length(q) / px1;
    // Cuando mira casi de frente el disco crece de 6 a 17 px a pleno brillo;
    // antes, sólo un punto de 3 px.
    float f4 = face * face * face * face;
    lens += exp(-r * r / 4.5) * smoothstep(0.05, 0.3, face) * 2.0 * mix(col, vec3(1.0), 0.7);
    if (face > 0.6) {
      float dr = mix(6.0, 17.0, smoothstep(0.6, 1.0, face));
      float rz = (r - dr) / 0.75;
      float disc = smoothstep(dr + 0.75, dr - 0.75, r) * 0.75 + exp(-rz * rz) * 0.15;
      float i1 = (r - 7.0) / 0.6;
      float i2 = (r - 12.0) / 0.6;
      disc += 0.15 * exp(-i1 * i1) + 0.15 * exp(-i2 * i2) + 8.0 * exp(-r * r / 16.0);
      float spikes = 0.0;
      float lenS = 80.0 + 60.0 * hash(fi + 4.0);
      for (int k = 0; k < 3; k++) {
        float ang = fi * 0.26 + float(k) * 1.0472;
        vec2 dk = vec2(cos(ang), sin(ang));
        float sa = abs(dot(q, dk)) / px1;
        float sx = abs(q.x * dk.y - q.y * dk.x) / px1;
        float taper = max(1.0 - sa / lenS, 0.0);
        float w = 1.0 * taper + 0.05;
        spikes += exp(-sx * sx / (w * w)) * taper * 1.6;
      }
      lens += (disc + spikes * f4) * mix(col, vec3(1.0), 0.7);
    }
    // Durante dos cuadros, un resplandor sobre la lente: blanco hasta 30 px y
    // luego cae teñido (blanco hacia azul, rojo, oro hacia naranja) hasta 200 px.
    float bz = (a - 0.22) / 0.035;
    // Sólo en los dos cuadros en que mira de frente: nada de velo alrededor.
    float bloomAmt = max(exp(-bz * bz) - 0.06, 0.0) / 0.94 * (0.5 + 0.5 * uGlare);
    float gp = r < 30.0 ? 1.0 : (r < 60.0 ? mix(1.0, 0.92, (r - 30.0) / 30.0) : (r < 100.0 ? mix(0.92, 0.67, (r - 60.0) / 40.0)
             : (r < 150.0 ? mix(0.67, 0.31, (r - 100.0) / 50.0) : mix(0.31, 0.0, clamp((r - 150.0) / 50.0, 0.0, 1.0)))));
    vec3 fallCol = i == 2 ? vec3(0.23, 0.42, 1.0) : (i == 1 || i == 4 ? vec3(1.0, 0.42, 0.06) : csat);
    // Las demás, como mucho 80 px; los resplandores no se suman, manda el mayor.
    if (fi != best) gp *= smoothstep(80.0, 40.0, r);
    vec3 bloom = gp * bloomAmt * mix(fallCol, vec3(1.0), smoothstep(100.0, 30.0, r));
    glare = max(glare, bloom * on);
    light += (beam + lens) * on;
  }
  light += glare;
  vec3 tone = min(light, vec3(1.0)) * 0.6 + (vec3(1.0) - exp(-light)) * 0.4;
  fragColor = vec4(tone, 0.1 * max(tone.r, max(tone.g, tone.b)));
}
''',

};
