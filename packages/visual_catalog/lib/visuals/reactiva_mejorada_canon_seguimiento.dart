// Reactiva Mejorada · Cañón de Seguimiento — transparencia momentánea. Tras una pausa, en el primer
// golpe el iris de un cañón de seguimiento se abre en cuatro cuadros: doce
// láminas rectas que giran unos 10° y dejan un círculo de luz blanca cálida
// con el centro quemado y una caída suave hasta el borde, que se apaga en
// 3 px con un filo azul de la lente en parte de su contorno. El operador lo
// sigue con un vaivén de unos 10 px y un pequeño rebote al abrir; flota polvo
// en la luz y el haz baja desde arriba entre el humo. Fuera, la escena se
// oscurece sin color, más lejos del círculo. El iris se cierra en cinco
// cuadros. Referente: el follow spot de un concierto sobre el solista.
// Versión mejorada: sigue el ritmo (cada golpe o cada tiempo) y su fuerza
// depende del volumen de la música.
// Funciona encima de cualquier escena sin conocerla: sólo luz, sin objetos que
// se queden. Sin música no dibuja nada. Nunca más de tres destellos por segundo.
// Su detalle sale de una textura propia de alta calidad que el shader anima.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // MÚSICA: qué momento abre el iris.
  CreatorModifier.choice('disparo', 'Lo dispara', options: ['Cada golpe', 'Golpes acentuados', 'Cada dos tiempos']),
  // FORMA: tamaño del círculo de luz.
  CreatorModifier.slider('tamano', 'Tamaño del círculo', min: .2, max: .45, value: .3),
  // ATMÓSFERA: cuánto se oscurece fuera.
  CreatorModifier.slider('oscuridad', 'Oscuridad fuera', min: .2, max: .6, value: .4),
  // MOVIMIENTO: dónde se abre.
  CreatorModifier.choice('posicion', 'Posición', options: ['Centro', 'Tercio superior']),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Solista', {'tamano': .25, 'oscuridad': .6, 'posicion': 'Tercio superior'}),
  CreatorVariation('Escenario', {'tamano': .45, 'oscuridad': .25, 'disparo': 'Golpes acentuados'}),
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
    // El iris se abre con un golpe y se cierra antes del siguiente: no parpadea.
    if (now - lastFire < 0.95) return;
    const int d = modifiers(f).disparo;
    fire(d == 0 ? h.back : d == 1 ? h.big : every(h, 16), d);
  }
  void render(const Frame& f, Canvas& c) const override {
    auto g = glide(f);
    const auto m = modifiers(f);
    const float W = f.width, H = f.height;
    // La apertura más reciente.
    float age = 100.0f, amp = 0.0f;
    for (const Pulse& p : slots) {
      const float a = float(now - p.start) * pace(f);
      if (a < 0.0f || a > 1.0f || a >= age) continue;
      age = a;
      amp = std::min(amount(p.power) * f.intensity, 1.2f);
    }
    if (amp <= 0.0f) return;
    const Color shadow = f.colors[1], cool = f.colors[2], warm = f.colors[3];
    c.material("spot", {0.0f, 0.0f, W, H},
               {age, amp, 0.5f * W, (m.posicion == 1 ? 0.33f : 0.5f) * H, g.tamano * W, g.oscuridad,
                shadow.r, shadow.g, shadow.b, cool.r, cool.g, cool.b, warm.r, warm.g, warm.b},
               {"smoke"});
  }
};
''';

const shaderSources = <String, String>{
  'spot': r'''
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform float uAge;
uniform float uAmp;
uniform vec2 uCenter;
uniform float uRadius;
uniform float uDark;
uniform vec3 uShadow;
uniform vec3 uCool;
uniform vec3 uWarm;
uniform sampler2D uTex;
out vec4 fragColor;

float hash(float n) {
  return fract(sin(n * 12.9898) * 43758.5453);
}
float hash2(vec2 p) {
  return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// Perfil del círculo por radio relativo: centro quemado (+255) y caída
// suave hasta +200 junto al borde.
float pool(float rn) {
  if (rn < 0.23) return 1.0;
  if (rn < 0.46) return mix(1.0, 0.92, smoothstep(0.23, 0.46, rn));
  if (rn < 0.74) return mix(0.92, 0.84, (rn - 0.46) / 0.28);
  return mix(0.84, 0.78, clamp((rn - 0.74) / 0.19, 0.0, 1.0));
}

void main() {
  vec2 px = FlutterFragCoord().xy;
  float W = uSize.x;
  float px1 = W / 360.0;
  float a = uAge;
  // Abre en cuatro cuadros con un leve rebote; cierra en cinco.
  float ko = 1.0 - clamp(a / 0.133, 0.0, 1.0);
  float open = 1.0 - ko * ko * ko;
  open *= 1.0 + 0.06 * sin(3.14159 * clamp((a - 0.133) / 0.15, 0.0, 1.0));
  float close = 1.0 - smoothstep(0.8, 0.967, a);
  float R = uRadius * open * close;
  float vis = smoothstep(0.0, 0.03, a) * step(0.01, close);
  // Láminas rectas al abrir y al cerrar, girando unos 10°.
  float poly = clamp(1.0 - smoothstep(0.133, 0.23, a) + smoothstep(0.8, 0.85, a), 0.0, 1.0);
  float rot = 0.17 * max(1.0 - open, 1.0 - close);
  // Vaivén del operador (unos 10 px) y rebote al abrir.
  vec2 c = uCenter + vec2(sin(6.2832 * a / 1.5) * 10.0 + 6.0 * exp(-a / 0.15) * sin(a * 25.0), cos(6.2832 * a / 2.33) * 8.0) * px1;
  vec2 q = px - c;
  float d = length(q);
  float ang = atan(q.y, q.x) + rot;
  float seg = 6.28318 / 12.0;
  float pf = cos(seg * 0.5) / cos(mod(ang, seg) - seg * 0.5);
  float dd = mix(d, d / pf, poly);
  float rn = dd / max(R, 1.0);
  float edge = smoothstep(R + 1.5 * px1, R - 1.5 * px1, dd);
  float edgeSoft = smoothstep(R + 2.0 * px1, R - 2.0 * px1, dd);
  // Polvo que flota en la luz.
  vec2 drift = vec2(a * 9.0, -a * 16.0) * px1;
  vec2 cell = floor((px + drift) / (7.0 * px1));
  vec2 cp = (cell + vec2(hash2(cell), hash2(cell + 4.1))) * 7.0 * px1 - drift;
  float dust = step(0.975, hash2(cell + 9.3)) * exp(-dot(px - cp, px - cp) / (px1 * px1 * 0.8)) * 0.35
             * (1.0 - edge) * step(px.y, c.y - R * 0.3);
  // Haz que baja desde arriba entre el humo, que deriva.
  vec2 apex = vec2(c.x + 0.12 * W, -0.35 * uSize.y);
  vec2 ax = normalize(c - apex);
  float tt = clamp(dot(px - apex, ax) / length(c - apex), 0.0, 1.0);
  float off = abs((px.x - apex.x) * ax.y - (px.y - apex.y) * ax.x);
  float shaft = smoothstep(R * tt * 1.05, R * tt * 0.6, off) * smoothstep(0.0, 0.8, tt) * (1.0 - edge) * step(px.y, c.y);
  float haze = texture(uTex, fract(px / W * vec2(0.5, 0.25) + vec2(0.3, -a * 0.12))).r;
  // Luz blanca cálida (azul = 0,85 del rojo) y filo azul de 1,5 px fuera del
  // borde en parte del contorno.
  vec3 warm = vec3(1.0, 0.94, 0.85) * mix(vec3(1.0), uWarm, 0.3);
  // Filo azul: los últimos 2 px de la caída del propio círculo se tiñen de
  // azul en un tercio del contorno, apagándose en los extremos.
  float arc = smoothstep(0.4, 0.8, cos(ang - 0.8));
  float zone = smoothstep(R - 2.0 * px1, R, dd) * arc;
  vec3 blue = vec3(0.47, 0.67, 1.0) * mix(vec3(1.0), uCool / max(max(uCool.r, uCool.g), uCool.b), 0.3);
  vec3 poolCol = mix(warm, blue, zone);
  vec3 light = poolCol * pool(rn) * edgeSoft + warm * (shaft * (0.05 + 0.1 * haze) + dust);
  light *= min(uAmp, 1.0) * vis;
  // Fuera, la escena se oscurece sin color: x0,70 junto al círculo y x0,60 a 250 px.
  float shade = (0.3 + 0.1 * smoothstep(0.0, 250.0 * px1, dd - R)) * (1.0 - edge) * vis * (uDark / 0.4);
  vec3 tone = min(light, vec3(1.0));
  float m = max(tone.r, max(tone.g, tone.b));
  fragColor = vec4(tone + uShadow * shade, clamp(max(shade * (1.0 - m), 0.1 * m), 0.0, 1.0));
}
''',

};
