// Reactiva Mejorada · Bokeh 2 — copia de «Bokeh 2 Transparente» (bokeh_luces_2_transparente.dart, que no se toca).
// Sin música no dibuja nada. Con música, el visual original se ve tanto
// como suena la música y cada golpe lo enciende más: sigue el ritmo.
//
import 'package:scene_compositor/authoring.dart';

// Bokeh 2 Transparente — luces desenfocadas en rojo, naranja y amarillo intensos.
// Versión overlay: mismo movimiento y reacción a la música sin fondo opaco.
// Versión más viva del Bokeh: más discos, colores saturados con el centro
// encendido y mucha más reacción. Los graves hinchan las luces, cada golpe
// las empuja hacia la cámara desde el centro y las enciende, la energía
// acelera la deriva y los agudos hacen saltar chispas doradas.
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
  struct Disc { float x, y, vx, vy, size, depth, phase; int color; };
  struct Spark { float x, y, phase; };
  std::vector<Disc> discs;
  std::vector<Spark> sparks;
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Reloj en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double clock = 0;
  float zoom = 0, zoomVel = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  static float wrap(float v) { return v - std::floor(v); }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    discs.clear();
    sparks.clear();
    for (int i = 0; i < 90; i++) {
      Disc d;
      d.depth = rng.unit();
      d.size = 0.03f + 0.11f * d.depth * d.depth;
      d.x = rng.unit();
      d.y = rng.unit();
      float speed = 0.3f + d.depth;
      d.vx = (rng.unit() - 0.5f) * 0.02f * speed;
      d.vy = -(0.004f + 0.012f * rng.unit()) * speed;
      d.phase = rng.unit() * 6.2831853f;
      d.color = int(rng.unit() * 3.0f) % 3;
      discs.push_back(d);
    }
    // Lejos primero: los discos cercanos quedan delante.
    std::stable_sort(discs.begin(), discs.end(), [](const Disc& a, const Disc& b) { return a.depth < b.depth; });
    for (int i = 0; i < 90; i++) sparks.push_back({rng.unit(), rng.unit(), rng.unit() * 6.2831853f});
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    clock = rng.unit() * 100.0;
    zoom = zoomVel = 0;
  }

  void update(const Frame& f) override {
    float dt = float(f.delta);
    const Music& m = f.music;
    bass = follow(bass, m.bass, 18.0f, 3.5f, dt);
    body = follow(body, m.body, 12.0f, 3.0f, dt);
    spark = follow(spark, m.spark, 30.0f, 7.0f, dt);
    energy = follow(energy, m.energy, 6.0f, 1.8f, dt);
    drive = follow(drive, m.active ? std::pow(std::clamp(m.energy, 0.0f, 1.0f), 0.8f) : 0.0f, 3.0f, 0.7f, dt);

    float hit = 0, fl = 0;
    for (const auto& e : m.events[0]) hit = std::max(hit, e.strength);
    for (const auto& e : m.events[2]) hit = std::max(hit, e.strength * 0.85f);
    for (const auto& e : m.events[3]) fl = std::max(fl, e.strength);
    float onset = std::clamp((m.bass - slowBass - 0.15f) * 2.5f, 0.0f, 1.0f);
    slowBass = follow(slowBass, m.bass, 3.0f, 3.0f, dt);
    hit = std::min(std::max(hit, onset), 1.0f);
    // Cada golpe empuja las luces hacia la cámara y vuelven con un muelle.
    if (hit > kick + 0.2f) zoomVel += 2.4f * hit;
    zoomVel += (-zoom * 22.0f - zoomVel * 5.0f) * dt;
    zoom += zoomVel * dt;
    kick = std::max(kick * std::exp(-dt * 4.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    clock += f.delta * f.speed * (1.2 + 2.0 * drive);
  }

  void render(const Frame& f, Canvas& c) const override {
    float amp = f.intensity;
    float w = f.width, h = f.height, s = std::min(w, h);
    float t = float(std::fmod(clock, 100000.0));
    std::vector<float> u;
    u.reserve(20);
    u.insert(u.end(), {t, bass * amp, kick * amp, energy});
    u.insert(u.end(), {f.glow, spark * amp, flash * amp, 0.0f});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("bokeh_night", {0, 0, w, h}, u);

    for (const Disc& d : discs) {
      float x = (wrap(d.x + d.vx * t) * 1.3f - 0.15f) * w;
      float y = (wrap(d.y + d.vy * t) * 1.3f - 0.15f) * h;
      float near = d.depth;
      float push = 1.0f + 0.4f * std::max(-0.3f, zoom) * near;
      x = w * 0.5f + (x - w * 0.5f) * push;
      y = h * 0.5f + (y - h * 0.5f) * push;
      float pulse = 1.0f + (0.5f * bass + 0.4f * kick) * near * amp;
      float r = d.size * s * pulse;
      float twinkle = 0.75f + 0.25f * std::sin(t * 0.8f + d.phase);
      float a = (0.30f + 0.40f * near) * twinkle * (0.8f + 0.9f * bass + 1.4f * kick * near) * amp * f.glow;
      a = std::clamp(a, 0.0f, 0.95f);
      const Color& col = f.colors[1 + d.color];
      // Disco de lente: interior parejo, borde algo más brillante y canto suave.
      Paint disc = Paint::radial({x, y}, r,
                                 {Color{std::min(1.0f, col.r + 0.25f), std::min(1.0f, col.g + 0.25f), std::min(1.0f, col.b + 0.25f), a * 0.8f}, Color{col.r, col.g, col.b, a * 0.72f},
                                  Color{std::min(1.0f, col.r * 1.1f + 0.08f), std::min(1.0f, col.g * 1.1f + 0.08f),
                                        std::min(1.0f, col.b * 1.1f + 0.08f), a},
                                  Color{col.r, col.g, col.b, 0.0f}},
                                 {0.0f, 0.72f, 0.9f, 1.0f});
      disc.blend = Blend::plus;
      c.circle({x, y}, r, disc);
    }

    // Chispas diminutas que titilan con los agudos.
    std::vector<Vec2> pts;
    for (const Spark& sp : sparks) {
      float tw = std::sin(t * 2.3f + sp.phase * 3.0f);
      if (tw < 0.4f - 0.8f * spark) continue;
      pts.push_back({wrap(sp.x + 0.004f * t) * w, wrap(sp.y - 0.006f * t) * h});
    }
    if (!pts.empty()) {
      Paint p;
      p.blend = Blend::plus;
      p.color = {1.0f, 0.95f, 0.9f, std::clamp((0.35f + 0.6f * spark) * amp, 0.0f, 1.0f)};
      c.points(pts, (0.9f + 0.6f * spark) * s / 400.0f, p);
    }
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
  'bokeh_night': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // reloj, graves, golpe, energía
uniform vec4 uB;   // glow, agudos, destello
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

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  float t = uA.x;
  // Sin neblinas de fondo: sólo las luces desenfocadas sobre lo que haya detrás.
  vec3 col = uC0;
  col *= 1.0 - 0.4 * smoothstep(0.5, 1.3, length(p * vec2(0.9, 0.65)));
  // Fondo transparente: color premultiplicado y opacidad según el brillo; la
  // luz muy tenue se vuelve transparente del todo para no dejar velo.
  col = clamp(col, 0.0, 1.0);
  float veilPeak = max(col.r, max(col.g, col.b));
  float clearCut = smoothstep(0.04, 0.12, veilPeak);
  col *= clearCut;
  float alpha = clamp(veilPeak * 1.25, 0.0, 1.0) * clearCut;
  fragColor = vec4(col, alpha);
}
""",
};
