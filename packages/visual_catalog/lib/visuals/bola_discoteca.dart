// Bola de Discoteca — bola de espejos que gira y llena la sala de luces.
// Cada faceta de la bola es un espejo plano que refleja tres focos: cuando
// uno queda alineado, la faceta destella. Los reflejos barren la sala como
// cientos de puntos de luz que viajan con el giro. La energía de la música
// acelera el giro, cada golpe hace destellar las facetas y crecer los puntos,
// los graves avivan las luces y los agudos encienden chispas en la bola.
const nativeSource = r'''
class Visual final : public Scene {
  struct Spot { float lon, lat, size, phase; int tone; };
  std::vector<Spot> spots;
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Giro en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double spin = 0, clock = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    spots.clear();
    for (int i = 0; i < 220; i++) {
      Spot s;
      s.lon = rng.unit() * 6.2831853f;
      s.lat = (rng.unit() - 0.5f) * 1.9f;
      s.size = 0.5f + rng.unit() * 0.9f;
      s.phase = rng.unit() * 6.2831853f;
      s.tone = int(rng.unit() * 3.0f) % 3;
      spots.push_back(s);
    }
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    spin = rng.unit() * 6.2831853;
    clock = 0;
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
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    spin += f.delta * f.speed * (0.22 + 0.5 * drive);
    clock += f.delta;
  }

  void render(const Frame& f, Canvas& c) const override {
    float amp = f.intensity;
    float s = std::min(f.width, f.height);
    float cx = f.width * 0.5f, cy = f.height * 0.38f;
    float R = s * 0.27f;
    std::vector<float> u;
    u.reserve(20);
    u.insert(u.end(), {float(std::fmod(spin, 6.2831853)), bass * amp, kick * amp, energy});
    u.insert(u.end(), {f.glow, spark * amp, flash * amp, cy / f.height});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("disco_room", {0, 0, f.width, f.height}, u);

    // Puntos de luz reflejados en la sala: viajan con el giro de la bola.
    std::array<std::vector<Vec2>, 3> groups;
    float sp = float(std::fmod(spin, 6.2831853));
    for (const Spot& spot : spots) {
      float a = spot.lon + sp;
      a -= 6.2831853f * std::floor(a / 6.2831853f);
      float x = (a / 6.2831853f) * 1.3f - 0.15f;
      if (x < -0.05f || x > 1.05f) continue;
      // Cada reflejo parpadea al pasar las juntas entre facetas.
      float blink = 0.5f + 0.5f * std::sin(spot.phase + a * 23.0f);
      if (blink < 0.25f) continue;
      groups[spot.tone].push_back({x * f.width, f.height * 0.5f + spot.lat * f.height * 0.5f});
    }
    float gain = std::clamp((0.7f + 0.5f * bass + 0.7f * kick + 0.3f * flash) * amp, 0.0f, 1.6f);
    float px = s / 400.0f;
    for (int g = 0; g < 3; g++) {
      if (groups[g].empty()) continue;
      const Color& col = f.colors[1 + g];
      Paint halo;
      halo.blend = Blend::plus;
      halo.color = {col.r, col.g, col.b, std::clamp(0.10f * gain * f.glow, 0.0f, 1.0f)};
      c.points(groups[g], (11.0f + 5.0f * kick * amp) * px, halo);
      Paint core;
      core.blend = Blend::plus;
      core.color = {std::min(1.0f, col.r * 0.6f + 0.4f), std::min(1.0f, col.g * 0.6f + 0.4f),
                    std::min(1.0f, col.b * 0.6f + 0.4f), std::clamp(0.75f * gain, 0.0f, 1.0f)};
      c.points(groups[g], (3.2f + 1.8f * kick * amp) * px, core);
    }

    // La bola, dibujada encima de los reflejos de la pared.
    std::vector<float> b;
    b.reserve(20);
    b.insert(b.end(), {float(std::fmod(spin, 6.2831853)), bass * amp, kick * amp, energy});
    b.insert(b.end(), {f.glow, spark * amp, flash * amp, float(std::fmod(clock, 1000.0))});
    for (int i = 0; i < 4; i++) b.insert(b.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("mirror_ball", {cx - R * 1.6f, cy - R * 1.6f, R * 3.2f, R * 3.2f}, b);
  }
};
''';

const shaderSources = <String, String>{
  'disco_room': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // giro, graves, golpe, energía
uniform vec4 uB;   // glow, agudos, destello, altura de la bola
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
  vec2 p = (frag - vec2(0.5 * uSize.x, uB.w * uSize.y)) / scale;
  // Sala oscura: resplandor cálido alrededor de la bola y suelo en penumbra.
  vec3 col = uC0;
  col += mix(uC1, uC2, 0.4) * exp(-dot(p, p) * 3.0) * (0.10 + 0.08 * uA.y + 0.15 * uA.z) * uB.x;
  // Haces tenues que salen de la bola y giran con ella.
  float ang = atan(p.y, p.x) + uA.x;
  float beams = smoothstep(0.75, 1.0, sin(ang * 9.0)) * smoothstep(0.75, 1.0, sin(ang * 4.0 + 1.3));
  col += mix(uC1, uC2, 0.5 + 0.5 * sin(ang * 3.0)) * beams * exp(-length(p) * 1.3) * smoothstep(0.25, 0.4, length(p)) *
         (0.05 + 0.08 * uA.y + 0.12 * uA.z) * uB.x;
  float floorY = (frag.y / uSize.y);
  col += uC3 * smoothstep(0.7, 1.0, floorY) * 0.03;
  col += mix(uC1, uC3, 0.5) * uB.z * 0.04;
  col *= 1.0 - 0.45 * smoothstep(0.5, 1.4, length((frag - 0.5 * uSize) / scale * vec2(0.9, 0.65)));
  col += (hash12(frag) - 0.5) / 255.0;
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
  'mirror_ball': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // giro, graves, golpe, energía
uniform vec4 uB;   // glow, agudos, destello, reloj
uniform vec3 uC0;
uniform vec3 uC1;
uniform vec3 uC2;
uniform vec3 uC3;
out vec4 fragColor;

const float PI = 3.14159265;

float hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 c = 0.5 * uSize;
  float R = uSize.x / 3.2;
  vec2 p = (frag - c) / R;
  float r = length(p);
  float kick = uA.z;

  // Halo de luz alrededor de la bola.
  vec3 haloCol = mix(uC1, uC3, 0.5) * exp(-max(r - 1.0, 0.0) * 6.0) * (0.12 + 0.3 * kick + 0.1 * uA.y) * uB.x;
  haloCol *= smoothstep(1.6, 1.25, r);
  vec3 ball = vec3(0.0);
  float edge = smoothstep(1.0, 0.985, r);
  if (r < 1.0) {
    float z = sqrt(1.0 - r * r);
    vec3 n = vec3(p.x, -p.y, z);
    float cs = cos(uA.x);
    float sn = sin(uA.x);
    vec3 m = vec3(cs * n.x + sn * n.z, n.y, -sn * n.x + cs * n.z);
    // Facetas: filas de latitud y columnas que se estrechan hacia los polos.
    float lat = asin(clamp(m.y, -1.0, 1.0));
    float lon = atan(m.z, m.x);
    const float ROWS = 22.0;
    float latStep = PI / ROWS;
    float fr = (lat + 0.5 * PI) / latStep;
    float row = floor(fr);
    float latc = (row + 0.5) * latStep - 0.5 * PI;
    float cols = max(6.0, floor(2.0 * ROWS * cos(latc)));
    float lonStep = 2.0 * PI / cols;
    float fc = (lon + PI) / lonStep;
    float col = floor(fc);
    float lonc = (col + 0.5) * lonStep - PI;
    // Normal plana de la faceta, devuelta al espacio de la cámara.
    vec3 mc = vec3(cos(latc) * cos(lonc), sin(latc), cos(latc) * sin(lonc));
    vec3 nc = vec3(cs * mc.x - sn * mc.z, mc.y, sn * mc.x + cs * mc.z);
    vec3 refl = reflect(vec3(0.0, 0.0, -1.0), nc);
    float h = hash12(vec2(row, col));
    vec3 L1 = normalize(vec3(-0.6, 0.65, 0.45));
    vec3 L2 = normalize(vec3(0.7, 0.45, 0.55));
    vec3 L3 = normalize(vec3(0.05, 0.95, 0.25));
    float s1 = pow(max(dot(refl, L1), 0.0), 28.0);
    float s2 = pow(max(dot(refl, L2), 0.0), 28.0);
    float s3 = pow(max(dot(refl, L3), 0.0), 40.0);
    float twinkle = 0.7 + 0.3 * sin(h * 50.0 + uB.w * (3.0 + 6.0 * h));
    vec3 spec = (uC1 * s1 + uC2 * s2 + uC3 * s3) * (1.4 + 1.8 * kick + 0.6 * uA.y) * twinkle;
    // Espejo oscuro que refleja la sala, más claro hacia arriba.
    vec3 base = uC3 * (0.10 + 0.30 * h * h) * (0.45 + 0.55 * smoothstep(-0.6, 0.9, refl.y));
    // Destellos sueltos que saltan de faceta en faceta.
    float sparkle = step(0.93, hash12(vec2(row, col) + floor(uB.w * 6.0 + h * 3.0)));
    base += mix(uC1, uC3, h) * sparkle * (0.5 + 0.8 * kick);
    vec3 facet = base + spec;
    // Chispas en las facetas con los agudos.
    float glint = step(0.985 - 0.03 * uB.y, hash12(vec2(row, col) + floor(uB.w * 9.0)));
    facet += vec3(1.0) * glint * uB.y * 1.2;
    // Juntas oscuras entre facetas.
    float gx = min(fract(fc), 1.0 - fract(fc)) * lonStep * cos(lat);
    float gy = min(fract(fr), 1.0 - fract(fr)) * latStep;
    float grout = smoothstep(0.0, 0.012, min(gx, gy));
    facet *= mix(0.15, 1.0, grout);
    // Borde de la esfera más oscuro.
    facet *= 0.55 + 0.45 * z;
    ball = facet;
  }
  vec3 outCol = mix(haloCol, ball, edge);
  float peak = max(outCol.r, max(outCol.g, outCol.b));
  if (peak > 0.85) {
    float e = (peak - 0.85) / 0.15;
    outCol *= (0.85 + 0.15 * e / (1.0 + e)) / peak;
  }
  float alpha = max(edge, clamp(max(haloCol.r, max(haloCol.g, haloCol.b)), 0.0, 1.0));
  outCol = min(outCol, vec3(alpha));
  fragColor = vec4(outCol, alpha);
}
""",
};
