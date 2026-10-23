// Reactiva · Cáusticas Fugaces — transparencia momentánea. Cuando crecen los graves
// aparece por zonas la red de luz que el sol dibuja a través del agua de una
// piscina: filamentos finos y curvos que se cruzan, se estiran y se mueven,
// dorados en sus nudos más intensos y ámbar en los finos, con un borde
// prismático apenas separado, y se evapora cuando bajan los graves. Las zonas
// se abren y cierran como manchas de sol. La luz se suma a la escena.
// Referente: cáusticas de una piscina en una pared al atardecer.
// Funciona encima de cualquier escena sin conocerla: sólo luz, sin objetos que
// se queden. Sin música no dibuja nada. Nunca más de tres destellos por segundo.
// Su detalle sale de una textura propia de alta calidad que el shader anima.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // MÚSICA: qué la hace aparecer.
  CreatorModifier.choice('disparo', 'Lo dispara', options: ['Graves que crecen', 'Bombo', 'Cambio de frase']),
  // FORMA: tamaño de las celdas de la red.
  CreatorModifier.slider('escala', 'Tamaño de la red', min: .6, max: 1.6, value: 1),
  // MOVIMIENTO: cuánto se deforma.
  CreatorModifier.slider('ondulacion', 'Ondulación', min: 0, max: 1, value: .6),
  // MODO: borde de color separado.
  CreatorModifier.toggle('prisma', 'Borde prismático', value: true),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Piscina', {'escala': 1.4, 'ondulacion': 1}),
  CreatorVariation('Red Fina', {'escala': .7, 'ondulacion': .3, 'prisma': false}),
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
  float glowLevel = 0.0f;
  void resetOwn(uint32_t) { glowLevel = 0.0f; }
  void update(const Frame& f) override {
    const Hits h = listen(f);
    const int d = modifiers(f).disparo;
    const float x = d == 0 ? clamp01((bassSlow - 0.12f) / 0.33f) : 0.0f;
    glowLevel = x * x * (3.0f - 2.0f * x);
    if (d == 1) fire(h.kick, 1);
    if (d == 2) fire(every(h, 16), 2);
  }
  void render(const Frame& f, Canvas& c) const override {
    auto g = glide(f);
    const auto m = modifiers(f);
    const float W = f.width, H = f.height;
    float level = glowLevel * f.intensity;
    for (const Pulse& p : slots) {
      const double age = now - p.start;
      if (age < 0.0 || age > 1.4) continue;
      level = std::max(level, env(age, 0.12f / pace(f), 1.0f / pace(f)) * std::min(amount(p.power) * f.intensity, 1.3f));
    }
    if (level < kMin) return;
    const Color orange = f.colors[1], gold = f.colors[2], white = f.colors[3];
    c.material("caustics", {0.0f, 0.0f, W, H},
               {float(now) * pace(f), level, g.escala, g.ondulacion, m.prisma ? 1.0f : 0.0f,
                orange.r, orange.g, orange.b, gold.r, gold.g, gold.b, white.r, white.g, white.b},
               {"noise"});
  }
};
''';

const shaderSources = <String, String>{
  'caustics': r'''
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform float uTime;
uniform float uLevel;
uniform float uScale;
uniform float uWave;
uniform float uPrism;
uniform vec3 uOrange;
uniform vec3 uGold;
uniform vec3 uWhite;
uniform sampler2D uTex;
out vec4 fragColor;

float hash2(vec2 p) {
  return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// Punto de cada celda, que se mueve despacio.
vec2 cellPt(vec2 c, float t, float s) {
  float h = hash2(c + s);
  return c + 0.5 + 0.4 * vec2(sin(t * 1.3 + 6.2832 * h), cos(t * 1.1 + 6.2832 * hash2(c + s + 3.1)));
}

// Distancia real (en celdas) al borde más cercano entre celdas y la dirección
// hacia él.
vec3 border(vec2 x, float t, float s) {
  vec2 ip = floor(x);
  vec2 mr = vec2(0.0);
  vec2 mc = vec2(0.0);
  float md = 9.0;
  for (int j = -1; j <= 1; j++) {
    for (int i = -1; i <= 1; i++) {
      vec2 c = ip + vec2(float(i), float(j));
      vec2 r = cellPt(c, t, s) - x;
      float d = dot(r, r);
      if (d < md) {
        md = d;
        mr = r;
        mc = c;
      }
    }
  }
  md = 9.0;
  vec2 dir = vec2(0.0, 1.0);
  for (int j = -1; j <= 1; j++) {
    for (int i = -1; i <= 1; i++) {
      vec2 c = mc + vec2(float(i), float(j));
      vec2 r = cellPt(c, t, s) - x;
      vec2 e = r - mr;
      if (dot(e, e) > 0.00001) {
        vec2 n = normalize(e);
        float d = dot(0.5 * (mr + r), n);
        if (d < md) {
          md = d;
          dir = n;
        }
      }
    }
  }
  return vec3(md, dir);
}

void main() {
  vec2 px = FlutterFragCoord().xy;
  float px1 = uSize.x / 360.0;
  vec2 q = px / px1;
  float Hpx = uSize.y / px1;
  float t = uTime * (0.35 + 0.5 * uWave);
  // Dos o tres manchas de 100-160 px que derivan unos 2,5 px por cuadro; con
  // menos nivel se encogen: se apaga por área, no bajando el brillo.
  float shrink = sqrt(clamp(uLevel, 0.0, 1.0));
  float mask = 0.0;
  for (int k = 0; k < 2; k++) {
    float fk = float(k);
    float ph1 = uTime * 0.65 + fk * 2.6 + 0.3;
    float ph2 = uTime * 0.26 + fk * 3.1 + 1.1;
    vec2 c = vec2(180.0 + 100.0 * sin(ph1), Hpx * (0.5 + 0.3 * sin(ph2)));
    // Alargada 1,45 veces en la dirección en que deriva.
    vec2 vel = normalize(vec2(65.0 * cos(ph1), Hpx * 0.078 * cos(ph2)) + vec2(0.001));
    vec2 dq = q - c;
    vec2 lq = vec2(dot(dq, vel) / 1.45, dot(dq, vec2(-vel.y, vel.x)) * 1.2);
    float ang = atan(lq.y, lq.x);
    // Contorno orgánico: ±30 % en 3-5 lóbulos que giran despacio.
    float lob = 1.0 + 0.3 * (0.6 * sin(3.0 * ang + uTime * 0.4 + fk * 1.7) + 0.4 * sin(5.0 * ang - uTime * 0.3 + fk * 2.9));
    float R = (55.0 + 10.0 * hash2(vec2(fk, 3.0))) * (0.35 + 0.65 * shrink) * step(0.02, uLevel) * lob;
    mask = max(mask, smoothstep(R + 50.0, R - 10.0, length(lq)));
  }
  if (mask < 0.003) {
    fragColor = vec4(0.0);
    return;
  }
  // Agua que ondula (6-8 px a escala de 60-90 px) y la red que fluye unos
  // 1,5 px por cuadro.
  vec2 w = q + vec2(36.0, -24.0) * uTime;
  w += vec2(7.0 * sin(w.y / 11.0 + t * 1.3) + 2.0 * sin(w.y / 5.0 - t), 7.0 * sin(w.x / 12.0 - t * 1.1) + 2.0 * sin(w.x / 6.0 + t)) * (0.5 + 0.5 * uWave);
  float cell = 30.0 * uScale;
  vec3 b1 = border(w / cell, t, 0.0);
  vec3 b2 = border((w * 1.3 + vec2(17.0, 5.0)) / cell, t * 1.2, 7.0);
  float d1 = b1.x * cell;
  float d2 = b2.x * cell / 1.3;
  // Ancho y brillo que cambian a lo largo de cada pared: fina y brillante
  // donde enfoca, más ancha y suave en el resto.
  float v1 = texture(uTex, fract(w / 90.0)).r;
  float v2 = texture(uTex, fract(w / 80.0 + 0.5)).r;
  float f1 = mix(0.72, 1.0, v1);
  float f2 = mix(0.72, 1.0, v2) * 0.85;
  float s1 = mix(1.1, 0.45, v1);
  float s2 = mix(1.1, 0.45, v2);
  float c1 = exp(-d1 * d1 / (2.0 * s1 * s1)) * f1;
  float c2 = exp(-d2 * d2 / (2.0 * s2 * s2)) * f2;
  // Nudos donde se cruzan las dos redes: quemados en 1,5 px y con brillo
  // hasta 5 px.
  float rr = d1 * d1 + d2 * d2;
  float kn = 1.3 * exp(-rr / 2.0) + 0.35 * exp(-rr / 9.0);
  // El color sale del brillo final (con la mancha), así el borde de la mancha
  // cae por naranja y rojo, nunca a gris.
  float I = (max(c1, c2) + kn) * mask;
  // Color por intensidad: blanco en los nudos, amarillo en los filamentos y
  // naranja y rojo al caer (verde <= 0,30 del rojo en lo tenue).
  vec3 red = vec3(1.0, 0.26, 0.0);
  vec3 orange = mix(vec3(1.0, 0.55, 0.0), uOrange / max(uOrange.r, 0.01), 0.1);
  vec3 yellow = mix(vec3(1.0, 0.8, 0.02), uGold / max(uGold.r, 0.01), 0.15);
  vec3 white = mix(vec3(1.0, 0.97, 0.9), uWhite, 0.3);
  vec3 col = mix(red, orange, smoothstep(0.47, 0.62, I));
  col = mix(col, yellow, smoothstep(0.62, 0.75, I));
  col = mix(col, white, smoothstep(0.92, 1.0, I));
  // Prisma sólo en los filamentos más brillantes: 1 px azul a un lado y
  // rojo anaranjado al otro.
  float fr = exp(-(d1 - 1.6) * (d1 - 1.6) / 0.5) * smoothstep(0.78, 0.9, f1 * mask) * uPrism;
  float side = dot(b1.yz, vec2(0.6, -0.8));
  vec3 prism = fr * (side > 0.0 ? vec3(0.28, 0.48, 1.0) : vec3(1.0, 0.25, 0.04)) * 0.55;
  vec3 light = side > 0.0 ? col * min(I, 1.0) * (1.0 - min(fr * 1.5, 1.0)) + prism : col * min(I, 1.0) + prism;
  vec3 tone = min(light, vec3(1.0));
  fragColor = vec4(tone, 0.1 * max(tone.r, max(tone.g, tone.b)));
}
''',

};
