// Murmuración Transparente — una bandada de miles de chispas que vuela como estorninos.
// Versión overlay: mismo movimiento y reacción a la música sin fondo opaco.
// La bandada es una lámina 3D de puntos que se ondula, se retuerce y gira
// mientras viaja por la pantalla; donde la lámina queda de canto los puntos
// se apilan y forman las franjas densas típicas de una murmuración. Cada
// golpe dispersa la bandada y la retuerce antes de que vuelva a juntarse,
// la energía acelera el vuelo y los graves aumentan los pliegues.
const nativeSource = r'''
class Visual final : public Scene {
  struct Bird { float u, v, su, cu, sv, cv, suv, cuv, sp, cp, size; int tone; };
  std::vector<Bird> birds;
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Reloj en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double clock = 0;
  float spread = 0, spreadVel = 0, twistKick = 0, twistVel = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    birds.clear();
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    clock = rng.unit() * 200.0;
    spread = spreadVel = twistKick = twistVel = 0;
  }

  void update(const Frame& f) override {
    float dt = float(f.delta);
    if (birds.empty()) {
      Random rng(f.seed + 11);
      int count = int(4000.0f + 2000.0f * std::clamp(f.detail, 0.25f, 2.0f));
      birds.resize(size_t(count));
      for (int i = 0; i < count; i++) {
        Bird& b = birds[size_t(i)];
        // Lámina elíptica, más densa en el centro.
        float r = std::sqrt(rng.unit());
        float a = rng.unit() * 6.2831853f;
        b.u = r * std::cos(a);
        b.v = r * std::sin(a);
        // Senos fijos de cada punto: los pliegues se animan sin trigonometría
        // por punto en cada cuadro (suma de ángulos).
        b.su = std::sin(b.u * 2.1f);
        b.cu = std::cos(b.u * 2.1f);
        b.sv = std::sin(b.v * 3.0f);
        b.cv = std::cos(b.v * 3.0f);
        b.suv = std::sin((b.u + b.v) * 1.7f);
        b.cuv = std::cos((b.u + b.v) * 1.7f);
        float ph = rng.unit() * 6.2831853f;
        b.sp = std::sin(ph);
        b.cp = std::cos(ph);
        b.size = 0.7f + rng.unit() * 0.6f;
        b.tone = rng.unit() < 0.12f ? 2 : (i % 2);
      }
    }
    const Music& m = f.music;
    bass = follow(bass, m.bass, 22.0f, 4.5f, dt);
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
    if (hit > kick + 0.2f) {
      spreadVel += 2.6f * hit;
      twistVel += 3.0f * hit * ((int(clock * 10.0) % 2) ? 1.0f : -1.0f);
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    // La bandada se dispersa con el golpe y se vuelve a juntar con un muelle.
    spreadVel += (-spread * 10.0f - spreadVel * 3.2f) * dt;
    spread += spreadVel * dt;
    twistVel += (-twistKick * 6.0f - twistVel * 2.5f) * dt;
    twistKick += twistVel * dt;
    clock += f.delta * f.speed * (0.55 + 0.9 * drive);
  }

  void render(const Frame& f, Canvas& c) const override {
    float amp = f.intensity;
    float w = f.width, h = f.height, s = std::min(w, h);
    double t = clock;
    std::vector<float> u;
    u.reserve(20);
    u.insert(u.end(), {bass * amp, kick * amp, energy, f.glow});
    u.insert(u.end(), {spark * amp, flash * amp, 0.0f, 0.0f});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("dusk_glow", {0, 0, w, h}, u);
    if (birds.empty()) return;

    // Términos que cambian una vez por cuadro.
    float c1 = float(std::cos(t * 0.7)), s1 = float(std::sin(t * 0.7));
    float c2 = float(std::cos(t * 0.9)), s2 = float(std::sin(t * 0.9));
    float c3 = float(std::cos(t * 0.5)), s3 = float(std::sin(t * 0.5));
    float cw = float(std::cos(t * 3.0)), sw = float(std::sin(t * 3.0));
    float fold = 0.45f + 0.25f * bass;
    float twist = 1.1f * float(std::sin(t * 0.31)) + twistKick;
    float ax = 0.9f * float(std::sin(t * 0.23));
    float ay = float(t * 0.15) + 0.6f * float(std::sin(t * 0.19));
    float cax = std::cos(ax), sax = std::sin(ax), cay = std::cos(ay), say = std::sin(ay);
    float scale = 0.62f * (1.0f + 0.2f * float(std::sin(t * 0.4))) * (1.0f + 0.6f * std::max(-0.3f, spread));
    float cx = 0.18f * float(std::sin(t * 0.13)), cy = (h / s - 1.0f) * 0.25f * float(std::sin(t * 0.11 + 1.0));
    float jitter = 0.004f + 0.05f * std::max(0.0f, spread);
    std::array<std::vector<Vec2>, 3> groups;
    for (auto& g : groups) g.reserve(birds.size() / 2 + 1);
    for (const Bird& b : birds) {
      float x = b.u * 1.0f;
      float y = b.v * 0.55f;
      // Pliegues de la lámina: sin(a + t) = sin(a)cos(t) + cos(a)sin(t).
      float z = fold * ((b.su * c1 + b.cu * s1) + 0.75f * (b.sv * c2 - b.cv * s2) + 0.6f * (b.suv * c3 + b.cuv * s3));
      // Torsión a lo largo de la lámina.
      float ta = twist * b.u;
      float ct = std::cos(ta), st = std::sin(ta);
      float y1 = y * ct - z * st, z1 = y * st + z * ct;
      // Giro del conjunto.
      float y2 = y1 * cax - z1 * sax, z2 = y1 * sax + z1 * cax;
      float x3 = x * cay + z2 * say, z3 = -x * say + z2 * cay;
      // Aleteo individual.
      float wob = (b.sp * cw + b.cp * sw) * jitter;
      x3 += wob;
      y2 += wob * 0.7f;
      float persp = 2.6f / (2.6f - z3 * scale);
      groups[size_t(b.tone)].push_back({w * 0.5f + (cx + x3 * scale * persp) * s, h * 0.5f + (cy + y2 * scale * persp) * s});
    }
    float px = s / 400.0f;
    float gain = std::clamp((0.85f + 0.4f * bass + 0.5f * kick) * amp, 0.0f, 1.6f);
    for (int g = 0; g < 3; g++) {
      const Color& col = f.colors[1 + g];
      Paint halo;
      halo.blend = Blend::plus;
      halo.color = {col.r, col.g, col.b, std::clamp(0.025f * gain * f.glow, 0.0f, 1.0f)};
      c.points(groups[size_t(g)], 2.6f * px, halo);
      Paint core;
      core.blend = Blend::plus;
      core.color = {col.r, col.g, col.b, std::clamp((g == 2 ? 0.7f : 0.38f) * gain * (0.8f + 0.2f * spark), 0.0f, 1.0f)};
      c.points(groups[size_t(g)], (g == 2 ? 1.0f : 0.85f) * px, core);
    }
  }
};
''';

const shaderSources = <String, String>{
  'dusk_glow': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // graves, golpe, energía, glow
uniform vec4 uB;   // agudos, destello
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
  vec2 uv = frag / uSize;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  // Negro con un resplandor de brasa abajo que late con los graves.
  vec3 col = uC0 + uC2 * smoothstep(0.55, 1.0, uv.y) * (0.06 + 0.06 * uA.x + 0.08 * uA.y) * uA.w;
  col += uC1 * exp(-dot(p, p) * 2.5) * (0.02 + 0.06 * uA.y) * uA.w;
  col *= 1.0 - 0.4 * smoothstep(0.5, 1.4, length(p * vec2(0.9, 0.65)));
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
