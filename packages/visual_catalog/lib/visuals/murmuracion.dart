// Murmuración — una bandada de miles de chispas que vuela como estorninos.
// La bandada es una lámina 3D de puntos que se ondula, se retuerce y gira
// mientras viaja por la pantalla; donde la lámina queda de canto los puntos
// se apilan y forman las franjas densas típicas de una murmuración. Cada
// golpe dispersa la bandada y la retuerce antes de que vuelva a juntarse,
// la energía acelera el vuelo y los graves aumentan los pliegues.
// Pliegues va de una lámina casi plana a una bandada muy plegada, Bruma del
// punto nítido a una nube luminosa y Espejo suma una bandada gemela
// reflejada. Pulso elige qué más hace la música: en Golpes la bandada se
// retuerce con más fuerza y sus chispas dan un salto de tamaño y brillo; en
// Graves la bandada crece, se pliega más y su halo respira con los graves;
// en Agudos tiembla finamente y se llena de chispas que centellean.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // FORMA: de una lámina casi plana a una bandada muy plegada.
  CreatorModifier.slider('pliegues', 'Pliegues', min: .2, max: 1.8, value: 1),
  // ATMÓSFERA: el halo de cada chispa, de puntos nítidos a una nube luminosa.
  CreatorModifier.slider('bruma', 'Bruma', min: 0, max: 3, value: 1),
  // MODO: una bandada gemela reflejada, como una mariposa.
  CreatorModifier.toggle('espejo', 'Espejo', value: false),
  // MÚSICA: qué parte de la bandada reacciona.
  CreatorModifier.choice('pulso', 'Pulso', options: ['Golpes', 'Graves', 'Agudos']),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Nube Dorada', {
    'bruma': 2.6,
    'pliegues': .6,
    'pulso': 'Graves',
    'speed': .7,
  }),
  CreatorVariation('Gemelas', {
    'espejo': true,
    'pliegues': 1.5,
    'bruma': .4,
    'pulso': 'Golpes',
  }),
];

const nativeSource = r'''
class Visual final : public Scene {
  struct Bird { float u, v, su, cu, sv, cv, suv, cuv, sp, cp, size; int tone; };
  std::vector<Bird> birds;
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Reloj en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double clock = 0;
  float spread = 0, spreadVel = 0, twistKick = 0, twistVel = 0;
  // Reloj de las chispas de los agudos.
  double shimmer = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }
  static float hashU(uint32_t x) {
    x ^= x >> 16; x *= 0x7feb352dU; x ^= x >> 15; x *= 0x846ca68bU; x ^= x >> 16;
    return float(x & 0xffffffu) / 16777216.0f;
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    birds.clear();
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    clock = rng.unit() * 200.0;
    spread = spreadVel = twistKick = twistVel = 0;
    shimmer = 0;
  }

  void update(const Frame& f) override {
    auto mods = modifiers(f);
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
      // Golpes: la bandada se retuerce con más fuerza.
      const float burst = mods.pulso == 0 ? 1.5f : 1.0f;
      spreadVel += 2.6f * hit;
      twistVel += 3.0f * hit * ((int(clock * 10.0) % 2) ? 1.0f : -1.0f) * burst;
    }
    shimmer += f.delta;
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
    auto gl = glide(f);
    float amp = f.intensity;
    // Pulso: cada opción mueve algo distinto; sin música todo vale cero.
    const float kickP = std::min(kick * amp, 1.0f) * gl.pulso.weight(0);
    const float bassP = std::min(bass * amp, 1.0f) * gl.pulso.weight(1);
    const float sparkP = std::min(spark * amp, 1.0f) * gl.pulso.weight(2);
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
    // Graves: la lámina se pliega más; Pliegues da la profundidad de base.
    float fold = 0.45f + 0.25f * bass + 0.3f * bassP;
    fold *= gl.pliegues;
    float twist = 1.1f * float(std::sin(t * 0.31)) + twistKick;
    float ax = 0.9f * float(std::sin(t * 0.23));
    float ay = float(t * 0.15) + 0.6f * float(std::sin(t * 0.19));
    float cax = std::cos(ax), sax = std::sin(ax), cay = std::cos(ay), say = std::sin(ay);
    float scale = 0.62f * (1.0f + 0.2f * float(std::sin(t * 0.4))) * (1.0f + 0.6f * std::max(-0.3f, spread)) * (1.0f + 0.08f * bassP);
    float cx = 0.18f * float(std::sin(t * 0.13)), cy = (h / s - 1.0f) * 0.25f * float(std::sin(t * 0.11 + 1.0));
    // Agudos: la bandada tiembla finamente.
    float jitter = 0.004f + 0.05f * std::max(0.0f, spread) + 0.022f * sparkP;
    std::array<std::vector<Vec2>, 3> groups;
    for (auto& g : groups) g.reserve(birds.size() / 2 + 1);
    // Espejo: la bandada gemela reflejada.
    const float mirror = std::clamp(gl.espejo, 0.0f, 1.0f);
    std::array<std::vector<Vec2>, 3> twins;
    if (mirror > 0.001f) for (auto& g : twins) g.reserve(birds.size() / 2 + 1);
    // Agudos: chispas sueltas que cambian 14 veces por segundo.
    std::vector<Vec2> glints;
    const uint32_t tick = uint32_t(std::fmod(shimmer, 100000.0) * 14.0);
    if (sparkP > 0.002f) glints.reserve(birds.size() / 10 + 1);
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
      float persp = 2.6f / std::max(2.6f - z3 * scale, 0.6f);
      const Vec2 point{w * 0.5f + (cx + x3 * scale * persp) * s, h * 0.5f + (cy + y2 * scale * persp) * s};
      groups[size_t(b.tone)].push_back(point);
      if (mirror > 0.001f) twins[size_t(b.tone)].push_back({w - point.x, point.y});
      if (sparkP > 0.002f && hashU(uint32_t(&b - birds.data()) * 2654435761u + tick * 40503u) < 0.04f * sparkP) glints.push_back(point);
    }
    float px = s / 400.0f;
    float gain = std::clamp((0.85f + 0.4f * bass + 0.5f * kick) * amp, 0.0f, 1.6f);
    // Bruma: el halo de cada chispa; Graves lo hace respirar y Golpes lo agranda.
    const float haze = std::max(gl.bruma, 0.0f);
    for (int g = 0; g < 3; g++) {
      const Color& col = f.colors[1 + g];
      Paint halo;
      halo.blend = Blend::plus;
      halo.color = {col.r, col.g, col.b, std::clamp(0.025f * gain * f.glow * haze * (1.0f + 1.2f * bassP), 0.0f, 1.0f)};
      const float haloSize = 2.6f * px * std::max(haze, 0.3f) * (1.0f + 0.5f * kickP);
      c.points(groups[size_t(g)], haloSize, halo);
      Paint core;
      core.blend = Blend::plus;
      core.color = {col.r, col.g, col.b, std::clamp((g == 2 ? 0.7f : 0.38f) * gain * (0.8f + 0.2f * spark) * (1.0f + 0.4f * kickP), 0.0f, 1.0f)};
      // Golpes: las chispas dan un salto de tamaño.
      const float coreSize = (g == 2 ? 1.0f : 0.85f) * px * (1.0f + 0.6f * kickP);
      c.points(groups[size_t(g)], coreSize, core);
      if (mirror > 0.001f) {
        halo.color.a *= mirror;
        core.color.a *= mirror;
        c.points(twins[size_t(g)], haloSize, halo);
        c.points(twins[size_t(g)], coreSize, core);
      }
    }
    if (!glints.empty()) {
      const Color& col = f.colors[3];
      Paint gp;
      gp.blend = Blend::plus;
      gp.color = {col.r, col.g, col.b, std::clamp(0.8f * sparkP, 0.0f, 0.9f)};
      c.points(glints, 1.7f * px, gp);
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
  col += uC3 * uB.y * 0.03;
  col *= 1.0 - 0.4 * smoothstep(0.5, 1.4, length(p * vec2(0.9, 0.65)));
  col += (hash12(frag) - 0.5) / 255.0;
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
