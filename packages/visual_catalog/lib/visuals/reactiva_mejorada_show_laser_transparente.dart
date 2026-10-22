// Reactiva Mejorada · Show Láser — copia de «Show Láser Transparente» (show_laser_transparente.dart, que no se toca).
// Sin música no dibuja nada. Con música, el visual original se ve tanto
// como suena la música y cada golpe lo enciende más: sigue el ritmo.
//
import 'package:scene_compositor/authoring.dart';

// Show Láser Transparente — espectáculo de láseres de festival en una sala con humo.
// Versión overlay: mismo movimiento y reacción a la música sin fondo opaco.
// Cuatro proyectores lanzan abanicos de rayos que barren, se abren y se cruzan;
// el humo hace visibles los haces. Cada golpe abre los abanicos de golpe,
// cambia su color y destella; el proyector central sigue los graves, los
// laterales los medios y agudos, y el superior aparece con la energía.
// Ajustes de la versión reactiva. Studio los muestra en Ajustes.
const modifiers = [
  // MÚSICA (versión mejorada): qué la enciende. «Ritmo y volumen»: se ve
  // tanto como suena la música y cada golpe la enciende más.
  CreatorModifier.choice('aparece', 'Aparece con', options: ['Ritmo y volumen', 'Cada golpe', 'Cada tiempo', 'Caja']),
  // Cuánto dura cada golpe de luz.
  CreatorModifier.slider('permanencia', 'Cuánto se queda', min: .5, max: 2, value: 1),
];

const nativeSource = r'''
class Base_ final : public Scene {
  struct Fan { float axis, spread, spreadVel, power, hue, hueGoal; };
  std::array<Fan, 4> fans{};
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0, mids = 0, highs = 0, lows = 0;
  float phase = 0, haze = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    for (int i = 0; i < 4; i++) {
      float h = float(i) / 3.0f + rng.unit() * 0.1f;
      fans[i] = {0.0f, 0.4f, 0.0f, 0.0f, h, h};
    }
    bass = body = spark = energy = slowBass = kick = flash = drive = mids = highs = lows = 0;
    phase = rng.unit() * 20.0f;
    haze = rng.unit() * 10.0f;
  }

  void update(const Frame& f) override {
    float dt = float(f.delta);
    const Music& m = f.music;
    bass = follow(bass, m.bass, 22.0f, 4.5f, dt);
    body = follow(body, m.body, 12.0f, 3.0f, dt);
    spark = follow(spark, m.spark, 30.0f, 7.0f, dt);
    energy = follow(energy, m.energy, 6.0f, 1.8f, dt);
    drive = follow(drive, m.active ? std::pow(std::clamp(m.energy, 0.0f, 1.0f), 0.8f) : 0.0f, 3.0f, 0.7f, dt);
    float lo = 0, mi = 0, hi = 0;
    for (int i = 0; i < 9; i++) lo = std::max(lo, m.smoothSpectrum[i]);
    for (int i = 9; i < 21; i++) mi = std::max(mi, m.smoothSpectrum[i]);
    for (int i = 21; i < 31; i++) hi = std::max(hi, m.smoothSpectrum[i]);
    lows = follow(lows, lo, 20.0f, 4.0f, dt);
    mids = follow(mids, mi, 20.0f, 4.0f, dt);
    highs = follow(highs, hi, 20.0f, 4.0f, dt);

    float hit = 0, fl = 0;
    for (const auto& e : m.events[0]) hit = std::max(hit, e.strength);
    for (const auto& e : m.events[2]) hit = std::max(hit, e.strength * 0.85f);
    for (const auto& e : m.events[3]) fl = std::max(fl, e.strength);
    float onset = std::clamp((m.bass - slowBass - 0.15f) * 2.5f, 0.0f, 1.0f);
    slowBass = follow(slowBass, m.bass, 3.0f, 3.0f, dt);
    hit = std::min(std::max(hit, onset), 1.0f);
    bool strike = hit > kick + 0.2f;
    kick = std::max(kick * std::exp(-dt * 5.5f), hit);
    flash = std::max(flash * std::exp(-dt * 9.0f), std::min(fl, 1.0f));

    phase += dt * f.speed * (0.25f + 1.2f * drive + 0.5f * kick);
    haze += dt * f.speed * (0.15f + 0.3f * drive);

    // Coreografía: barridos suaves; el lateral derecho es espejo del izquierdo.
    float sweepA = std::sin(phase * 0.6f) * 0.55f;
    float sweepB = 0.62f + std::sin(phase * 0.8f + 1.0f) * 0.42f;
    float sweepD = 3.14159265f + std::sin(phase * 0.5f + 2.0f) * 0.6f;
    float axisGoal[4] = {sweepA, sweepB, -sweepB, sweepD};
    float spreadBase[4] = {0.45f + 0.55f * lows, 0.35f + 0.45f * mids, 0.35f + 0.45f * highs, 0.8f};
    float powerGoal[4] = {0.35f + 1.1f * lows + 0.6f * kick,
                          0.22f + 1.0f * mids + 0.5f * kick,
                          0.22f + 1.0f * highs + 0.5f * kick,
                          (0.9f * drive + 0.7f * kick) * (m.active ? 1.0f : 0.0f)};
    for (int i = 0; i < 4; i++) {
      Fan& fan = fans[i];
      fan.axis += (axisGoal[i] - fan.axis) * (1.0f - std::exp(-dt * 6.0f));
      if (strike) {
        fan.spreadVel += 3.2f * hit;
        fan.hueGoal += 1.0f / 3.0f;
      }
      // Muelle: el abanico se abre con el golpe y vuelve a su apertura base.
      float target = spreadBase[i];
      fan.spreadVel += ((target - fan.spread) * 40.0f - fan.spreadVel * 7.0f) * dt;
      fan.spread = std::clamp(fan.spread + fan.spreadVel * dt, 0.05f, 2.6f);
      fan.power = follow(fan.power, powerGoal[i], 18.0f, 4.0f, dt);
      fan.hue += (fan.hueGoal - fan.hue) * (1.0f - std::exp(-dt * 10.0f));
    }
  }

  void render(const Frame& f, Canvas& c) const override {
    float amp = f.intensity;
    const float counts[4] = {9.0f, 7.0f, 7.0f, 9.0f};
    std::vector<float> u;
    u.reserve(40);
    u.insert(u.end(), {phase, bass * amp, kick * amp, energy});
    for (int i = 0; i < 4; i++)
      u.insert(u.end(), {fans[i].axis, fans[i].spread, counts[i], std::min(fans[i].power * amp, 2.0f)});
    u.insert(u.end(), {fans[0].hue, fans[1].hue, fans[2].hue, fans[3].hue});
    u.insert(u.end(), {spark * amp, flash, f.glow, haze});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("lasers", {0, 0, f.width, f.height}, u);
  }
};

// Versión reactiva mejorada: el visual original sigue vivo por debajo y se
// deja ver con el ritmo de la música. Cada golpe lo enciende y el volumen
// decide cuánto se ve. Sin música no dibuja nada.
class Visual final : public Scene {
  static constexpr double kGap_ = 0.3;  // como mucho unos 3 golpes de luz por segundo
  static constexpr double kStep_ = 1.0 / 60.0;
  static constexpr float kMin_ = 0.004f;
  static constexpr int kShows_ = 8;
  struct Show_ { double start = -100.0; float power = 0.0f; float span = 0.0f; };
  Base_ base_;
  std::array<Show_, kShows_> shows_{};
  int cursor_ = 0;
  double now_ = 0.0, acc_ = 0.0, last_ = -100.0;
  float eFast_ = 0.0f, peak_ = 0.0f, loud_ = 0.0f, kickMean_ = 0.0f;

  // Golpes de luz: entran en 40 ms y se apagan suave.
  float pulses_() const {
    float v = 0.0f;
    for (const Show_& s : shows_) {
      const double age = now_ - s.start;
      if (age < 0.0 || age >= double(s.span)) continue;
      float e = 1.0f;
      if (age < 0.04) {
        e = float(age / 0.04);
      } else {
        const float x = std::clamp(float((age - 0.04) / std::max(double(s.span) - 0.04, 0.05)), 0.0f, 1.0f);
        const float k = 1.0f - x;
        e = k * std::sqrt(k);
      }
      v = std::max(v, e * s.power);
    }
    return v;
  }

 public:
  void reset(uint32_t seed) override {
    Scene& base = base_;
    base.reset(seed);
    shows_ = {};
    cursor_ = 0;
    now_ = acc_ = 0.0;
    last_ = -100.0;
    eFast_ = peak_ = loud_ = kickMean_ = 0.0f;
  }
  void update(const Frame& f) override {
    Scene& base = base_;
    base.update(f);
    const Music& mu = f.music;
    now_ += f.delta;
    acc_ += f.delta;
    while (acc_ >= kStep_) {
      acc_ -= kStep_;
      eFast_ += (mu.energy - eFast_) * 0.19f;
      // Volumen: nivel absoluto y relativo al pico reciente; en silencio, cero.
      peak_ = std::max(peak_ * 0.9985f, eFast_);
      const float target = std::clamp(0.5f * eFast_ / std::max(peak_, 0.05f) + 1.2f * eFast_, 0.0f, 1.3f);
      loud_ += (target - loud_) * (target > loud_ ? 0.3f : 0.05f);
    }
    const auto m = modifiers(f);
    float kick = 0.0f, snare = 0.0f;
    bool beat = false;
    for (const Event& e : mu.events[0]) {
      const float s = std::max(e.strength, 0.05f);
      kick = std::max(kick, s);
      kickMean_ = kickMean_ <= 0.0f ? s : kickMean_ + (s - kickMean_) * 0.2f;
    }
    for (const Event& e : mu.events[1])
      if (e.band != 3) snare = std::max(snare, std::max(e.strength, 0.05f));
    if (!mu.events[2].empty()) beat = true;
    const int which = std::clamp(m.aparece, 0, 3);
    float s = 0.0f;
    if (which <= 1) s = kick > 0.0f ? kick / std::max(kickMean_, 0.05f) * 0.65f : 0.0f;  // golpe más fuerte, más luz
    else if (which == 2) s = beat ? 0.7f : 0.0f;
    else s = snare > 0.0f ? 0.8f : 0.0f;
    if (s <= 0.0f || now_ - last_ < kGap_) return;
    last_ = now_;
    shows_[size_t(cursor_)] = Show_{now_, std::clamp(s, 0.3f, 1.3f) * (0.35f + 0.8f * loud_), 0.45f * m.permanencia};
    cursor_ = (cursor_ + 1) % kShows_;
  }
  void render(const Frame& f, Canvas& c) const override {
    float v = pulses_();
    // «Ritmo y volumen»: mientras suena se ve en proporción al volumen.
    if (modifiers(f).aparece == 0) v = std::max(v, 0.6f * std::min(loud_, 1.0f));
    v = std::min(v, 1.0f);
    if (v < kMin_) return;
    const Scene& base = base_;
    if (v > 0.995f) {
      base.render(f, c);
      return;
    }
    c.saveLayer(v);
    base.render(f, c);
    c.restore();
  }
};
''';

const shaderSources = <String, String>{
  'lasers': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;    // tiempo, graves, golpe, energía
uniform vec4 uF0;   // abanico central: eje, apertura, rayos, potencia
uniform vec4 uF1;   // esquina izquierda
uniform vec4 uF2;   // esquina derecha
uniform vec4 uF3;   // superior
uniform vec4 uH;    // tono de cada abanico
uniform vec4 uM;    // agudos, destello, glow, reloj del humo
uniform vec3 uC0;
uniform vec3 uC1;
uniform vec3 uC2;
uniform vec3 uC3;
out vec4 fragColor;

float hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
             mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
  float s = 0.0;
  float a = 0.5;
  for (int i = 0; i < 3; i++) {
    s += a * noise(p);
    p = mat2(1.6, 1.2, -1.2, 1.6) * p;
    a *= 0.5;
  }
  return s / 0.875;
}

// Ciclo de color vivo por la paleta: c1 -> c2 -> c3 -> c1.
vec3 cycle(float x) {
  float f = fract(x) * 3.0;
  vec3 a = f < 1.0 ? uC1 : (f < 2.0 ? uC2 : uC3);
  vec3 b = f < 1.0 ? uC2 : (f < 2.0 ? uC3 : uC1);
  return mix(a, b, smoothstep(0.0, 1.0, fract(f)));
}

// Contribución de un rayo del abanico a distancia angular `da` del píxel.
vec2 beam(float r, float da) {
  float d = r * sin(min(abs(da), 1.5));
  float w = 0.0018 + r * 0.0028;
  float core = exp(-d * d / (w * w));
  float glow = 0.00012 / (d * d + 0.00018);
  return vec2(core, glow);
}

// Abanico de rayos desde `origin`: se resuelve con el rayo más cercano y su
// vecino, sin recorrer todos los rayos. Devuelve el color acumulado.
vec3 fan(vec2 p, vec2 origin, vec4 F, float hue) {
  if (F.w < 0.01) return vec3(0.0);
  vec2 v = p - origin;
  float r = length(v);
  float a = atan(v.x, v.y) - F.x;
  a -= 6.2831853 * floor((a + 3.14159265) / 6.2831853);
  float count = F.z;
  float spacing = max(F.y / max(count - 1.0, 1.0), 0.001);
  float start = -0.5 * F.y;
  float x = (a - start) / spacing;
  float i0 = clamp(floor(x), 0.0, count - 1.0);
  float i1 = clamp(i0 + 1.0, 0.0, count - 1.0);
  vec2 b0 = beam(r, a - (start + i0 * spacing));
  vec2 b1 = i1 != i0 ? beam(r, a - (start + i1 * spacing)) : vec2(0.0);
  // Degradado de color a lo ancho del abanico.
  vec3 c0 = cycle(hue + i0 / max(count, 1.0) * 0.35);
  vec3 c1 = cycle(hue + i1 / max(count, 1.0) * 0.35);
  float fade = exp(-r * 0.35);
  vec3 coreCol = mix(c0, vec3(1.0), 0.18) * b0.x + mix(c1, vec3(1.0), 0.18) * b1.x;
  vec3 glowCol = c0 * b0.y + c1 * b1.y;
  // Destello del proyector en su origen.
  float lens = 0.002 / (r * r + 0.002);
  return (coreCol * 1.8 + glowCol * 0.9) * F.w * fade + mix(c0, vec3(1.0), 0.5) * lens * F.w * 0.6;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  p.y = -p.y;
  vec2 hs = 0.5 * uSize / scale;
  float kick = uA.z;

  // Humo que sube despacio: hace visibles los haces.
  float smoke = fbm(p * 1.7 + vec2(uM.w * 0.15, -uM.w * 0.35));
  float haze = 0.18 + 1.1 * smoothstep(0.3, 0.82, smoke);

  vec3 light = vec3(0.0);
  light += fan(p, vec2(0.0, -hs.y - 0.03), uF0, uH.x);
  light += fan(p, vec2(-hs.x - 0.03, -hs.y - 0.03), uF1, uH.y);
  light += fan(p, vec2(hs.x + 0.03, -hs.y - 0.03), uF2, uH.z);
  light += fan(p, vec2(0.0, hs.y + 0.03), uF3, uH.w);

  vec3 col = uC0;
  col += light * haze * uM.z;
  // El humo devuelve un poco de la luz de los láseres.
  col += light * 0.02 * smoke;
  // Chispas en el humo con los agudos, sólo donde hay haz.
  vec2 g = p * 90.0 + vec2(0.0, uM.w * 6.0);
  float glint = smoothstep(0.08, 0.0, length(fract(g) - 0.5)) * step(0.985 - 0.02 * uM.x, hash12(floor(g)));
  col += glint * clamp(dot(light, vec3(0.333)), 0.0, 1.0) * (0.6 + 2.0 * uM.x);
  // Estrobo del golpe y del flash.
  col += vec3(1.0) * (uM.y * 0.12 + kick * 0.03) * clamp(dot(light, vec3(0.333)), 0.0, 1.0);

  col *= 1.0 - 0.3 * smoothstep(0.6, 1.4, length(p * vec2(0.9, 0.6)));
  col = clamp((col * (2.51 * col + 0.03)) / (col * (2.43 * col + 0.59) + 0.14), 0.0, 1.0);
  col = pow(col, vec3(0.4545));
  // Fondo transparente: el color va premultiplicado y la opacidad sale del
  // brillo, así la luz se compone sobre lo que haya debajo.
  col = clamp(col, 0.0, 1.0);
  // La luz muy tenue se vuelve transparente del todo: sin velo sobre la app.
  float veilPeak = max(col.r, max(col.g, col.b));
  float clearCut = smoothstep(0.08, 0.2, veilPeak);
  col *= clearCut;
  float alpha = clamp(veilPeak * 1.25, 0.0, 1.0) * clearCut;
  fragColor = vec4(col, alpha);
}
""",
};
