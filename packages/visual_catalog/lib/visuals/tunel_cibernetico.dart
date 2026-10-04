// Túnel Cibernético — túnel de bloques con polígonos de neón y láseres.
// La cámara avanza por un túnel cuyas paredes son bloques tecnológicos
// iluminados en azul y violeta o en rojo (el tono cambia cada ocho golpes),
// con pequeños paneles dorados encendidos. Anillos de neón de diez lados con
// orbes en los vértices y radios interiores vienen hacia la cámara girando;
// rayos láser cian salen del centro y chispas doradas pasan volando. Cada
// golpe empuja la cámara y enciende los láseres, los graves avivan los orbes.
const nativeSource = r'''
class Visual final : public Scene {
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double travel = 0, spin = 0, beam = 0, sinceSwitch = 0;
  float boost = 0, theme = 0, themeTarget = 0, laser = 0;
  int beats = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    travel = rng.unit() * 20.0;
    spin = rng.unit() * 6.2831853;
    beam = rng.unit() * 6.2831853;
    sinceSwitch = 0;
    boost = laser = 0;
    theme = themeTarget = 0;
    beats = 0;
  }

  void update(const Frame& f) override {
    float dt = float(f.delta);
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
      beats++;
      boost = std::max(boost, hit);
      laser = std::max(laser, hit);
      if (beats % 8 == 0) themeTarget = 1.0f - themeTarget;
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    boost *= std::exp(-dt * 3.0f);
    laser *= std::exp(-dt * 2.2f);
    sinceSwitch += f.delta;
    if (!m.active && sinceSwitch > 10.0) {
      themeTarget = 1.0f - themeTarget;
      sinceSwitch = 0;
    }
    theme += (themeTarget - theme) * (1.0f - std::exp(-dt * 2.5f));
    travel += f.delta * f.speed * (0.8 + 1.6 * drive + 2.2 * boost);
    spin += f.delta * f.speed * (0.25 + 0.6 * drive);
    beam += f.delta * f.speed * (0.15 + 0.35 * drive);
  }

  void render(const Frame& f, Canvas& c) const override {
    float amp = f.intensity;
    std::vector<float> u;
    u.reserve(24);
    u.insert(u.end(), {float(std::fmod(travel, 1000.0)), bass * amp, kick * amp, energy});
    u.insert(u.end(), {theme, f.glow, spark * amp, flash * amp});
    u.insert(u.end(), {float(std::fmod(spin, 6.2831853)), float(std::fmod(beam, 6.2831853)), (0.25f + laser) * amp, 0.0f});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("cyber_tunnel", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'cyber_tunnel': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // avance, graves, golpe, energía
uniform vec4 uB;   // tema (0 azul, 1 rojo), glow, agudos, destello
uniform vec4 uR;   // giro de los anillos, giro de los láseres, fuerza de los láseres
uniform vec3 uC0;
uniform vec3 uC1;
uniform vec3 uC2;
uniform vec3 uC3;
out vec4 fragColor;

const float TAU = 6.2831853;
const float SIDES = 10.0;

float hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

float segment(vec2 p, vec2 a, vec2 b) {
  vec2 pa = p - a;
  vec2 ba = b - a;
  float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
  return length(pa - ba * h);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  float r = length(p) + 1e-4;
  float a = atan(p.y, p.x);
  float travel = uA.x;
  float kick = uA.z;
  float theme = uB.x;
  vec3 wallA = mix(uC1, uC2, theme);
  vec3 wallB = mix(vec3(0.75, 0.1, 1.0), vec3(1.0, 0.25, 0.1), theme);

  // Paredes de bloques: celdas en ángulo y profundidad con bisel.
  float z = 0.28 / r;
  float depth = z + travel;
  vec2 g = vec2(a / TAU * 36.0, depth * 3.0);
  vec2 cell = floor(g);
  vec2 lc = fract(g);
  float h = hash12(cell);
  float bevel = smoothstep(0.0, 0.12, min(min(lc.x, 1.0 - lc.x), min(lc.y, 1.0 - lc.y)));
  vec3 block = mix(wallA, wallB, step(0.6, h)) * (0.15 + 0.6 * h * h) * (0.4 + 0.6 * bevel);
  block *= 0.5 + 0.9 * uA.w + 0.4 * uA.y;
  // Paneles dorados encendidos.
  float panel = step(0.93, hash12(cell + 17.0));
  vec2 pr = abs(lc - 0.5);
  float panelShape = step(pr.x, 0.32) * step(pr.y, 0.18);
  block += vec3(1.0, 0.78, 0.15) * panel * panelShape * (1.2 + 0.8 * kick);
  float fog = exp(-z * 0.12);
  vec3 col = uC0 + block * fog * smoothstep(0.0, 0.06, r);

  // Anillos de neón de diez lados que vienen hacia la cámara.
  for (int k = 0; k < 3; k++) {
    float fk = float(k);
    float ringZ = fk + 1.0 - fract(travel * 0.35);
    float R = 0.34 / ringZ;
    float rot = uR.x * (mod(fk, 2.0) < 1.0 ? 1.0 : -1.0) + fk;
    float sector = TAU / SIDES;
    float ang = a - rot;
    float sa = mod(ang + 0.5 * sector, sector) - 0.5 * sector;
    // Distancia al lado del polígono (apotema R) en el sector plegado.
    float dEdge = abs(r * cos(sa) - R * cos(0.5 * sector));
    // Cada anillo aparece suave en el fondo y se apaga al pasar la cámara.
    float bright = smoothstep(3.0, 2.2, ringZ) * smoothstep(0.25, 0.6, ringZ);
    float w = 0.003 + 0.004 / ringZ;
    col += uC3 * (exp(-dEdge / (w * 0.5)) + 0.4 * exp(-dEdge / (w * 3.0))) * bright * uB.y;
    // Orbes en los vértices y radios hacia dentro.
    float vang = floor((ang) / sector + 0.5) * sector + rot;
    vec2 vtx = vec2(cos(vang - 0.5 * sector), sin(vang - 0.5 * sector)) * R / cos(0.5 * sector);
    float dOrb = length(p - vtx);
    vec3 orbCol = mix(uC2, vec3(1.0, 0.85, 0.3), 0.15);
    col += orbCol * (0.0004 + 0.0012 * uA.y) / (dOrb * dOrb + 0.00025 / ringZ) * bright * 0.08;
    vec2 inner = vec2(cos(vang + 0.9), sin(vang + 0.9)) * R * 0.35;
    float dSpoke = segment(p, vtx, inner);
    col += uC3 * exp(-dSpoke / (w * 0.6)) * bright * 0.6;
  }

  // Láseres cian que salen del centro.
  float beams = 0.0;
  for (int i = 0; i < 6; i++) {
    float ba = uR.y + float(i) * TAU / 6.0;
    float da = abs(sin(a - ba)) * r;
    float front = step(0.0, cos(a - ba));
    beams += exp(-da * (120.0 / (0.3 + r))) * front;
  }
  col += mix(uC3, vec3(1.0), 0.3) * beams * uR.z * smoothstep(0.03, 0.2, r) * 1.1;

  // Chispas doradas que pasan volando.
  vec2 sg = vec2(a / TAU * 60.0, z * 2.0 + travel * 2.0);
  vec2 sc = floor(sg);
  vec2 sl = fract(sg) - 0.5;
  float spark = step(0.92, hash12(sc + 5.0)) * exp(-(sl.x * sl.x * 40.0 + sl.y * sl.y * 6.0));
  col += vec3(1.0, 0.75, 0.2) * spark * fog * (0.8 + 0.8 * uB.z);
  col += mix(uC3, uC2, theme) * uB.w * 0.05;

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
