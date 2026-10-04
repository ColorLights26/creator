// Bokeh 2 Transparente — luces desenfocadas en rojo, naranja y amarillo intensos.
// Versión overlay: mismo movimiento y reacción a la música sin fondo opaco.
// Versión más viva del Bokeh: más discos, colores saturados con el centro
// encendido y mucha más reacción. Los graves hinchan las luces, cada golpe
// las empuja hacia la cámara desde el centro y las enciende, la energía
// acelera la deriva y los agudos hacen saltar chispas doradas.
const nativeSource = r'''
class Visual final : public Scene {
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
