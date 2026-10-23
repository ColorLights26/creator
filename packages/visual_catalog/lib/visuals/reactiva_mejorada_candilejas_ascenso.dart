// Reactiva Mejorada · Candilejas en Ascenso — transparencia momentánea. Durante la subida de
// energía cada bombo enciende una fila de focos escondidos en el borde inferior
// que lanzan conos de luz blanca cálida hacia arriba, de unos 12° y borde
// suave de 5 px, que se suman donde se cruzan, con el humo vivo sólo dentro de
// ellos. Cuanto más sube la energía, más alto trepan y más blancos son; cada
// cono se recoge hacia abajo en vez de apagarse, y en el drop se corta en seco.
// Lo tenue de los bordes es rojo vivo, nunca cobre. La luz se suma a la escena.
// Referente: candilejas de teatro y uplights de festival en una subida.
// Versión mejorada: sigue el ritmo (cada golpe o cada tiempo) y su fuerza
// depende del volumen de la música.
// Funciona encima de cualquier escena sin conocerla: sólo luz, sin objetos que
// se queden. Sin música no dibuja nada. Nunca más de tres destellos por segundo.
// Su detalle sale de una textura propia de alta calidad que el shader anima.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // MÚSICA: cuándo pulsan.
  CreatorModifier.choice('disparo', 'Lo dispara', options: ['Bombo con la energía', 'Cada bombo', 'Cada tiempo']),
  // FORMA: cuántas candilejas.
  CreatorModifier.steps('luces', 'Luces', min: 4, max: 8, value: 6),
  // MOVIMIENTO: hasta dónde suben los conos.
  CreatorModifier.slider('altura', 'Altura', min: .3, max: .8, value: .55),
  // ATMÓSFERA: humo bajo.
  CreatorModifier.slider('humo', 'Humo', min: 0, max: 1, value: .6),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Teatro', {'luces': 8, 'altura': .4, 'humo': 1}),
  CreatorVariation('Rampa', {'luces': 5, 'altura': .8, 'disparo': 'Cada bombo'}),
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
    if (h.drop) {  // corte seco: en el drop la capa ya no está
      slots = {};
      return;
    }
    float s = 0.0f;
    if (d == 0) s = h.kick;
    else if (d == 1) s = h.kick;
    else s = every(h, 4);
    fire(s, int(std::max(build, std::min(loud, 1.0f)) * 100.0f));
  }
  void render(const Frame& f, Canvas& c) const override {
    auto g = glide(f);
    const float W = f.width, H = f.height;
    // El pulso más reciente: los conos suben, se mantienen un instante y se
    // recogen hacia abajo (unos 40 px por cuadro) sin perder brillo.
    float amp = 0.0f, heat = 0.0f, top = 0.0f;
    float newest = 100.0f;
    const float px1 = W / 360.0f;
    for (const Pulse& p : slots) {
      const float a = float(now - p.start) * pace(f);
      if (a < 0.0f || a > 1.0f || a >= newest) continue;
      const float b = clamp01(float(p.kind) / 100.0f);
      const float peak = g.altura * H * (0.6f + 0.4f * b);
      const float h = peak * easeOut(a / 0.1f) - std::max(0.0f, a - 0.12f) * 1200.0f * px1;
      if (h <= 0.0f) continue;
      newest = a;
      amp = std::min(amount(p.power) * f.intensity, 1.3f);
      heat = b;
      top = h;
    }
    if (amp <= 0.0f) return;
    // Sólo la franja de abajo hasta donde llegan los conos.
    const float band = std::min(H, top + 0.08f * W);
    const Color red = f.colors[1], amber = f.colors[2], white = f.colors[3];
    c.material("footlights", {0.0f, H - band, W, band},
               {H - band, W, H, std::clamp(std::round(g.luces), 4.0f, 8.0f), amp, top, heat, g.humo, float(now),
                red.r, red.g, red.b, amber.r, amber.g, amber.b, white.r, white.g, white.b},
               {"smoke"});
  }
};
''';

const shaderSources = <String, String>{
  'footlights': r'''
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform float uTop;
uniform float uWidth;
uniform float uHeight;
uniform float uCount;
uniform float uAmp;
uniform float uReach;
uniform float uHeat;
uniform float uSmoke;
uniform float uTime;
uniform vec3 uRed;
uniform vec3 uAmber;
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
  vec2 px = FlutterFragCoord().xy + vec2(0.0, uTop);
  float px1 = uWidth / 360.0;
  float up = uHeight - px.y;  // altura sobre el borde inferior
  float upx = up / px1;
  // Humo de dos octavas (25-60 px, ±25 %) que sube unos 2 px por cuadro.
  vec2 hp = vec2(px.x, px.y + uTime * 60.0 * px1) / px1;
  float n1 = texture(uTex, fract(hp / 200.0)).r;
  float n2 = texture(uTex, fract(hp / 90.0 + 0.37)).r;
  float H = 1.0 + mix(0.0, 0.2 * (0.6 * (2.0 * n1 - 1.0) + 0.4 * (2.0 * n2 - 1.0)), uSmoke);
  // Con más energía, todo un poco más blanco y un núcleo oro-blanco en el
  // eje hasta unos 90 px sobre la lente.
  float energy = clamp((uAmp - 0.6) / 0.6, 0.0, 1.0);
  float gain = mix(1.0, 1.15, energy);
  float I = 0.0;
  for (int i = 0; i < 8; i++) {
    float fi = float(i);
    if (fi >= uCount) continue;
    float x0 = (fi + 0.5) / uCount * uWidth;
    float ax = px.x - x0 + up * (hash(fi + 3.7) - 0.5) * 0.12;
    // Paredes rectas: 24 px en la base y unos 110 px a 300 px, con el borde
    // desvaneciéndose en 5 px.
    float hw = 12.0 * px1 + max(up, 0.0) * 0.158;
    float edge = smoothstep(hw + 2.5 * px1, hw - 2.5 * px1, abs(ax));
    float rel = clamp(abs(ax) / hw, 0.0, 1.0);
    // Recorrido de la luz a través del cono.
    float C = sqrt(max(1.0 - rel * rel, 0.0));
    // Altura de cada cono (escalonadas): del 100 % junto a la lente al 65 % a
    // tres cuartos y a 0 en el último cuarto (al menos 60 px).
    float topPx = (uReach + (hash(fi + 9.1) - 0.5) * 80.0 * px1) / px1;
    float fadeStart = min(0.75 * topPx, topPx - 60.0);
    float A = upx < fadeStart ? mix(1.0, 0.65, smoothstep(0.0, fadeStart, upx))
                              : 0.65 * (1.0 - smoothstep(fadeStart, topPx, upx));
    A *= step(-2.0, upx);
    // Quemado a blanco sólo en los primeros 20 px sobre la lente.
    float lens = 0.4 * (1.0 - smoothstep(0.0, 20.0, upx));
    float hot = 0.18 * energy * (1.0 - smoothstep(60.0, 110.0, upx)) * C * C;
    // El humo no entra en el color: sólo cambia el brillo al final.
    I += (0.72 * A * gain + lens + hot) * C * edge;
  }
  // Color sólo por el brillo sumado: blanco cálido, oro, naranja, naranja
  // rojizo y rojo vivo; el brillo visible se mantiene alto (+150 desde 0,5).
  vec3 cWhite = mix(uWhite, vec3(1.0, 0.957, 0.878), 1.0 - uHeat);
  vec3 cGold = vec3(1.0, 0.816, 0.314) * mix(vec3(1.0), uAmber / max(uAmber.r, 0.01), 0.15);
  vec3 cOrange = vec3(1.0, 0.541, 0.063);
  vec3 cOrRed = vec3(1.0, 0.29, 0.063);
  vec3 cRed = vec3(1.0, 0.165, 0.063) * mix(vec3(1.0), uRed / max(uRed.r, 0.01), 0.2);
  vec3 col = mix(cRed, cOrRed, smoothstep(0.44, 0.56, I));
  col = mix(col, cOrange, smoothstep(0.66, 0.78, I));
  col = mix(col, cGold, smoothstep(0.8, 0.9, I));
  col = mix(col, cWhite, smoothstep(0.88, 0.96, I));
  vec3 light = col * min(1.3 * I * H, 1.0);
  light *= smoothstep(0.0, uSize.y * 0.12, FlutterFragCoord().y);
  fragColor = vec4(light, 0.1 * max(light.r, max(light.g, light.b)));
}
''',

};
