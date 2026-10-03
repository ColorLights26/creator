// Magnetosfera — núcleos de energía rodeados de partículas en órbita.
// Tres núcleos luminosos se mueven despacio por una nebulosa; miles de
// partículas los orbitan en anillos inclinados en 3D, más rápido cuanto más
// cerca, y dejan estelas de puntos. Cada golpe las lanza hacia fuera como una
// supernova y vuelven con un muelle; los graves avivan los núcleos, la
// energía acelera las órbitas y los agudos hacen centellear las partículas.
const nativeSource = r'''
class Visual final : public Scene {
  struct Orbit { float radius, theta0, incl, node, speed, seed; int core; };
  std::vector<Orbit> orbits;
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double orbitClock = 0, coreClock = 0;
  float blast = 0, blastVel = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  // Posición del núcleo k en unidades del lado corto, centrada en la pantalla.
  void core(int k, float aspectY, float& x, float& y) const {
    double t = coreClock;
    float fk = float(k);
    x = 0.32f * float(std::sin(t * (0.21 + 0.05 * k) + fk * 2.1));
    y = (0.28f + 0.12f * aspectY) * float(std::cos(t * (0.17 + 0.04 * k) + fk * 1.3)) + (fk - 1.0f) * 0.12f * aspectY;
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    orbits.clear();
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    orbitClock = rng.unit() * 50.0;
    coreClock = rng.unit() * 50.0;
    blast = blastVel = 0;
  }

  void update(const Frame& f) override {
    float dt = float(f.delta);
    if (orbits.empty()) {
      Random rng(f.seed + 7);
      int count = int(1200.0f + 600.0f * std::clamp(f.detail, 0.25f, 2.0f));
      for (int i = 0; i < count; i++) {
        Orbit o;
        o.core = i % 3;
        float u = rng.unit();
        o.radius = 0.04f + 0.30f * u * u;
        o.theta0 = rng.unit() * 6.2831853f;
        o.incl = (rng.unit() - 0.5f) * 2.6f;
        o.node = rng.unit() * 6.2831853f;
        // Más rápido cerca del núcleo, como en una órbita de Kepler.
        o.speed = 0.06f / std::pow(o.radius, 1.5f) * (rng.unit() < 0.5f ? 1.0f : -1.0f) * 0.12f;
        o.seed = rng.unit();
        orbits.push_back(o);
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
    if (hit > kick + 0.2f) blastVel += 3.2f * hit;
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    // Supernova: las órbitas se abren con el golpe y vuelven con un muelle.
    blastVel += (-blast * 14.0f - blastVel * 4.5f) * dt;
    blast += blastVel * dt;
    orbitClock += f.delta * f.speed * (0.6 + 1.2 * drive + 0.6 * std::max(0.0f, blast));
    coreClock += f.delta * f.speed * (0.5 + 0.6 * drive);
  }

  void render(const Frame& f, Canvas& c) const override {
    float amp = f.intensity;
    float s = std::min(f.width, f.height);
    float aspectY = f.height / s - 1.0f;
    float cxs[3], cys[3];
    for (int k = 0; k < 3; k++) core(k, aspectY, cxs[k], cys[k]);
    std::vector<float> u;
    u.reserve(28);
    u.insert(u.end(), {float(std::fmod(coreClock, 1000.0)), bass * amp, kick * amp, energy});
    u.insert(u.end(), {f.glow, spark * amp, flash * amp, std::max(0.0f, blast) * amp});
    u.insert(u.end(), {cxs[0], cys[0], cxs[1], cys[1]});
    u.insert(u.end(), {cxs[2], cys[2], 0.0f, 0.0f});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("nebula_cores", {0, 0, f.width, f.height}, u);
    if (orbits.empty()) return;

    float t = float(std::fmod(orbitClock, 10000.0));
    float open = 1.0f + std::max(-0.3f, blast) * 0.9f;
    float W = f.width * 0.5f, H = f.height * 0.5f;
    // Tres muestras por partícula: la cabeza y dos puntos de estela detrás.
    std::array<std::vector<Vec2>, 3> heads, tails;
    for (const Orbit& o : orbits) {
      float r = o.radius * open * (1.0f + 0.5f * o.seed * std::max(0.0f, blast));
      float ci = std::cos(o.incl), si = std::sin(o.incl), cn = std::cos(o.node), sn = std::sin(o.node);
      for (int k = 0; k < 3; k++) {
        float th = o.theta0 + o.speed * (t - float(k) * 0.06f);
        float ox = r * std::cos(th), oy = r * std::sin(th);
        // Órbita inclinada: rotación por la inclinación y el nodo.
        float y3 = oy * ci, z3 = oy * si;
        float x = ox * cn - y3 * sn;
        float y = ox * sn + y3 * cn;
        float persp = 1.0f / (1.0f - z3 * 0.8f);
        Vec2 pt{W + (cxs[o.core] + x * persp) * s, H + (cys[o.core] + y * persp) * s};
        if (k == 0) heads[o.core].push_back(pt); else tails[o.core].push_back(pt);
      }
    }
    float px = s / 400.0f;
    float gain = std::clamp((0.8f + 0.5f * bass + 0.6f * kick) * amp, 0.0f, 1.6f);
    float tw = 0.75f + 0.25f * spark;
    for (int k = 0; k < 3; k++) {
      Color col = k == 2 ? Color{0.75f * f.colors[3].r + 0.25f * f.colors[1].r, 0.75f * f.colors[3].g + 0.25f * f.colors[1].g,
                                 0.75f * f.colors[3].b + 0.25f * f.colors[1].b, 1.0f}
                         : f.colors[1 + k];
      Paint tail;
      tail.blend = Blend::plus;
      tail.color = {col.r, col.g, col.b, std::clamp(0.28f * gain, 0.0f, 1.0f)};
      c.points(tails[k], 1.0f * px, tail);
      Paint halo;
      halo.blend = Blend::plus;
      halo.color = {col.r, col.g, col.b, std::clamp(0.07f * gain * f.glow, 0.0f, 1.0f)};
      c.points(heads[k], 4.0f * px, halo);
      Paint head;
      head.blend = Blend::plus;
      head.color = {std::min(1.0f, col.r * 0.7f + 0.3f), std::min(1.0f, col.g * 0.7f + 0.3f), std::min(1.0f, col.b * 0.7f + 0.3f),
                    std::clamp(0.85f * gain * tw, 0.0f, 1.0f)};
      c.points(heads[k], (1.3f + 0.5f * spark * amp) * px, head);
    }
  }
};
''';

const shaderSources = <String, String>{
  'nebula_cores': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // reloj, graves, golpe, energía
uniform vec4 uB;   // glow, agudos, destello, supernova
uniform vec4 uK0;  // núcleos 1 y 2 (en unidades del lado corto, centrados)
uniform vec4 uK1;  // núcleo 3
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

// Núcleo: brillo central, corona y rayos que salen en todas direcciones.
vec3 coreLight(vec2 p, vec2 c, vec3 col, float t) {
  vec2 d = p - c;
  float r = length(d) + 0.001;
  float glow = (0.0015 + 0.003 * uA.y + 0.006 * uA.z) / (r * r + 0.002);
  vec3 light = col * glow + vec3(1.0) * glow * 0.3;
  // Los rayos sólo se calculan cerca del núcleo: lejos no se ven.
  if (r < 0.45) {
    vec2 dir = d / r;
    float rays = noise(dir * 7.0 + t * 0.3);
    float corona = exp(-r * 9.0) * (0.25 + 0.6 * rays) * (0.5 + 0.8 * uA.y + 0.6 * uB.w);
    light += col * corona;
  }
  return light;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  float t = uA.x;
  // Nebulosa tenue teñida por los núcleos.
  float n = noise(p * 2.5 + vec2(t * 0.03, -t * 0.02));
  vec3 neb = mix(uC2, uC1, smoothstep(0.3, 0.75, noise(p * 1.3 + 4.0 + t * 0.01)));
  vec3 col = uC0 + neb * smoothstep(0.3, 1.0, n) * (0.05 + 0.04 * uA.w + 0.08 * uA.z) * uB.x;
  col += coreLight(p, uK0.xy, uC1, t) * uB.x;
  col += coreLight(p, uK0.zw, uC2, t + 3.0) * uB.x;
  col += coreLight(p, uK1.xy, mix(uC3, uC1, 0.3), t + 6.0) * uB.x;
  col += mix(uC1, uC2, 0.5) * uB.z * 0.04;
  col *= 1.0 - 0.4 * smoothstep(0.5, 1.3, length(p * vec2(0.9, 0.65)));
  float peak = max(col.r, max(col.g, col.b));
  if (peak > 0.85) {
    float e = (peak - 0.85) / 0.15;
    col *= (0.85 + 0.15 * e / (1.0 + e)) / peak;
  }
  col += (hash12(frag) - 0.5) / 255.0;
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
