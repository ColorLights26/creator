// Planeta Anillado — gigante gaseoso con anillos que escuchan la música.
// Cada radio de los anillos corresponde a una banda del espectro, así que se
// encienden como un ecualizador natural. Los golpes lanzan una onda por los
// anillos y encienden auroras polares; los graves avivan la atmósfera.
const nativeSource = r'''
class Visual final : public Scene {
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0, push = 0;
  std::array<float, 8> bands{};
  float spin = 0, orbit = 0, storm = 0;
  std::array<float, 4> waves{};  // radio, amplitud, radio, amplitud

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = push = 0;
    bands.fill(0);
    spin = rng.unit() * 6.2831853f;
    orbit = rng.unit() * 0.6f - 0.3f;
    storm = rng.unit() * 10.0f;
    waves = {3.0f, 0.0f, 3.0f, 0.0f};
  }

  void update(const Frame& f) override {
    float dt = float(f.delta);
    const Music& m = f.music;
    bass = follow(bass, m.bass, 20.0f, 4.0f, dt);
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
      waves[2] = waves[0];
      waves[3] = waves[1];
      waves[0] = 0.0f;
      waves[1] = hit;
    }
    kick = std::max(kick * std::exp(-dt * 4.5f), hit);
    flash = std::max(flash * std::exp(-dt * 6.0f), std::min(fl, 1.0f));
    for (int i = 0; i < 4; i += 2) {
      waves[i] += dt * 1.1f;
      waves[i + 1] *= std::exp(-dt * 1.3f);
    }

    static const int edges[9] = {0, 3, 6, 9, 13, 17, 21, 26, 31};
    for (int b = 0; b < 8; b++) {
      float v = 0;
      for (int i = edges[b]; i < edges[b + 1]; i++) v = std::max(v, m.smoothSpectrum[i]);
      bands[b] = follow(bands[b], v, 18.0f, 3.5f, dt);
    }

    spin += dt * f.speed * (0.04f + 0.25f * drive + 0.3f * kick);
    orbit += dt * f.speed * (0.015f + 0.05f * drive);
    storm += dt * f.speed * (0.05f + 0.6f * bass);
    push = follow(push, kick, 14.0f, 2.2f, dt);
  }

  void render(const Frame& f, Canvas& c) const override {
    float amp = f.intensity;
    std::vector<float> u;
    u.reserve(40);
    u.insert(u.end(), {spin, orbit, storm, push * amp});
    u.insert(u.end(), {bass * amp, kick * amp, energy, spark * amp});
    u.insert(u.end(), {waves[0], waves[1] * amp, waves[2], waves[3] * amp});
    u.insert(u.end(), {bands[0], bands[1], bands[2], bands[3]});
    u.insert(u.end(), {bands[4], bands[5], bands[6], bands[7]});
    u.insert(u.end(), {flash, f.glow, f.detail, 0.0f});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("planet", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'planet': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // giro del planeta, órbita de cámara, tormentas, empuje
uniform vec4 uB;   // graves, golpe, energía, agudos
uniform vec4 uW;   // ondas en los anillos: radio, amplitud, radio, amplitud
uniform vec4 uBands0;
uniform vec4 uBands1;
uniform vec4 uX;   // destello, glow, detalle
uniform vec3 uC0;
uniform vec3 uC1;
uniform vec3 uC2;
uniform vec3 uC3;
out vec4 fragColor;

// Campana gaussiana segura: pow() con base negativa no está definido en GLSL.
float gauss(float x) {
  return exp(-x * x);
}

const float RING_IN = 1.38;
const float RING_OUT = 2.45;

float hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

float hash13(vec3 p3) {
  p3 = fract(p3 * 0.1031);
  p3 += dot(p3, p3.zyx + 31.32);
  return fract((p3.x + p3.y) * p3.z);
}

float noise3(vec3 x) {
  vec3 i = floor(x);
  vec3 f = fract(x);
  f = f * f * (3.0 - 2.0 * f);
  return mix(mix(mix(hash13(i), hash13(i + vec3(1.0, 0.0, 0.0)), f.x),
                 mix(hash13(i + vec3(0.0, 1.0, 0.0)), hash13(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
             mix(mix(hash13(i + vec3(0.0, 0.0, 1.0)), hash13(i + vec3(1.0, 0.0, 1.0)), f.x),
                 mix(hash13(i + vec3(0.0, 1.0, 1.0)), hash13(i + vec3(1.0, 1.0, 1.0)), f.x), f.y), f.z);
}

float fbm3(vec3 p) {
  float s = 0.0;
  float a = 0.5;
  for (int i = 0; i < 4; i++) {
    s += a * noise3(p);
    p = p * 2.07 + vec3(3.1, 1.7, -2.3);
    a *= 0.5;
  }
  return s;
}

float noise1(float x) {
  float i = floor(x);
  float f = fract(x);
  return mix(hash12(vec2(i, 1.7)), hash12(vec2(i + 1.0, 1.7)), f * f * (3.0 - 2.0 * f));
}

float pick(float i) {
  if (i < 0.5) return uBands0.x;
  if (i < 1.5) return uBands0.y;
  if (i < 2.5) return uBands0.z;
  if (i < 3.5) return uBands0.w;
  if (i < 4.5) return uBands1.x;
  if (i < 5.5) return uBands1.y;
  if (i < 6.5) return uBands1.z;
  return uBands1.w;
}

float bandAt(float x) {
  float m = clamp(x, 0.0, 1.0) * 7.0;
  float i = floor(m);
  return mix(pick(i), pick(min(i + 1.0, 7.0)), smoothstep(0.0, 1.0, m - i));
}

// Densidad de los anillos: divisiones, huecos y ondas del golpe.
float ringDensity(float rho) {
  float inside = smoothstep(RING_IN, RING_IN + 0.06, rho) * smoothstep(RING_OUT, RING_OUT - 0.08, rho);
  float fine = 0.55 + 0.45 * noise1(rho * 46.0) * (0.7 + 0.3 * sin(rho * 180.0));
  float coarse = 0.6 + 0.4 * noise1(rho * 9.0 + 3.0);
  float gap = 1.0 - 0.92 * smoothstep(0.035, 0.0, abs(rho - 1.97));
  gap *= 1.0 - 0.6 * smoothstep(0.02, 0.0, abs(rho - 2.28));
  return inside * fine * coarse * gap;
}

vec3 rotateAxis(vec3 v, vec3 k, float a) {
  return v * cos(a) + cross(k, v) * sin(a) + k * dot(k, v) * (1.0 - cos(a));
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 uv = (frag - 0.5 * uSize) / scale;
  uv.y = -uv.y;

  vec3 axis = normalize(vec3(0.42, 1.0, 0.12));
  float az = 0.55 + uA.y;
  float el = 0.30;
  float dist = 6.2 - 0.9 * uA.w;
  vec3 ro = dist * vec3(cos(el) * sin(az), sin(el), -cos(el) * cos(az));
  vec3 fw = normalize(-ro);
  vec3 rt = normalize(cross(vec3(0.0, 1.0, 0.0), fw));
  vec3 up = cross(fw, rt);
  vec3 rd = normalize(fw * 2.0 + rt * uv.x + up * (uv.y + 0.04));
  vec3 sun = normalize(vec3(-0.8, 0.62, -0.35));
  float kick = uB.y;

  // Fondo: estrellas, polvo galáctico y resplandor del sol fuera de cuadro.
  vec3 col = uC0;
  vec2 g = uv * 110.0;
  float h = hash12(floor(g));
  float star = smoothstep(0.985, 1.0, h) * smoothstep(0.35, 0.0, length(fract(g) - 0.5));
  col += vec3(0.9, 0.93, 1.0) * star * (0.6 + 0.6 * sin(uA.x * 3.0 + h * 50.0) * uB.w + 0.4);
  col += uC2 * 0.05 * exp(-abs(uv.y + uv.x * 0.6 - 0.15) * 5.0);
  float sunGlow = pow(max(dot(rd, sun), 0.0), 12.0);
  col += uC3 * sunGlow * (0.15 + 0.2 * uX.x);

  // Planeta.
  float b = dot(ro, rd);
  float c = dot(ro, ro) - 1.0;
  float disc = b * b - c;
  float tP = disc > 0.0 ? -b - sqrt(disc) : 1e9;

  // Plano de los anillos.
  float denom = dot(rd, axis);
  float tR = abs(denom) > 1e-4 ? -dot(ro, axis) / denom : -1.0;
  vec3 hp = ro + rd * tR;
  float rho = length(hp);
  bool ringHit = tR > 0.0 && rho > RING_IN && rho < RING_OUT;

  if (tP < 1e8) {
    vec3 pos = ro + rd * tP;
    vec3 n = normalize(pos);
    float lat = dot(n, axis);
    vec3 nr = rotateAxis(n, axis, uA.x);
    float turb = fbm3(nr * vec3(2.2, 6.5, 2.2) + vec3(0.0, 0.0, uA.z * 0.15));
    float latw = lat + (turb - 0.5) * (0.07 + 0.06 * uB.x);
    float band = noise1(latw * 14.0 + 4.0) * 0.6 + noise1(latw * 37.0) * 0.4;
    vec3 surf = mix(uC1 * 0.65, uC3, smoothstep(0.2, 0.8, band));
    surf *= 0.85 + 0.3 * noise1(latw * 70.0 + 2.0);
    surf = mix(surf, mix(uC2, uC3, 0.5), smoothstep(0.62, 0.9, noise1(latw * 5.0 + 9.0)) * 0.25);
    // Gran tormenta ovalada que gira con el planeta.
    vec3 spotDir = normalize(vec3(0.62, -0.30, 0.72));
    vec3 sd = (nr - spotDir) * vec3(1.0, 2.4, 1.0);
    float spot = length(sd);
    surf = mix(surf, mix(uC1, uC3, 0.25) * 1.1, smoothstep(0.20, 0.12, spot));
    surf *= 1.0 - 0.35 * gauss((spot - 0.2) / 0.03);
    float diff = clamp(dot(n, sun) * 0.9 + 0.1, 0.0, 1.0);
    // Sombra de los anillos sobre el planeta.
    float ts = -dot(pos, axis) / dot(sun, axis);
    float shade = 1.0;
    if (ts > 0.0) {
      float rs = length(pos + sun * ts);
      shade = 1.0 - 0.75 * ringDensity(rs);
    }
    float limb = mix(0.5, 1.0, pow(max(dot(n, -rd), 0.0), 0.4));
    vec3 lit = surf * diff * shade * limb * 1.3;
    lit += surf * 0.03;
    float limbGlow = pow(1.0 - max(dot(n, -rd), 0.0), 5.0);
    lit += uC2 * limbGlow * (0.5 + 0.6 * uB.x + 0.9 * kick) * (0.3 + 0.7 * diff) * uX.y;
    // Óvalo auroral alrededor del polo, con cortinas suaves.
    float oval = gauss((abs(lat) - 0.86) / 0.035);
    float curtain = 0.4 + 0.6 * noise3(nr * 14.0 + vec3(0.0, uA.z * 0.8, 0.0));
    lit += mix(uC2, vec3(0.4, 1.0, 0.7), 0.5) * oval * curtain * (1.0 - diff) * (0.05 + 1.2 * kick) * uX.y;
    col = lit;
  }

  if (ringHit && tR < tP) {
    float dens = ringDensity(rho);
    float x = (rho - RING_IN) / (RING_OUT - RING_IN);
    float eq = bandAt(x);
    float wave = uW.y * gauss((rho - RING_IN - uW.x) * 10.0) +
                 uW.w * gauss((rho - RING_IN - uW.z) * 10.0);
    // Sombra del planeta sobre los anillos.
    float bb = dot(hp, sun);
    float cc = dot(hp, hp) - 1.0;
    float shadow = (bb < 0.0 && bb * bb - cc > 0.0) ? 0.12 : 1.0;
    float light = 0.45 + 0.55 * abs(dot(sun, axis));
    vec3 ringCol = mix(uC3, mix(uC1, uC2, x), 0.25 + 0.35 * eq);
    float glint = smoothstep(0.975, 1.0, hash12(floor(vec2(rho * 260.0, atan(hp.z, hp.x) * 140.0)) +
                                                floor(uA.x * 4.0))) * uB.w;
    // El ecualizador: cada banda enciende su anillo con un color propio.
    vec3 eqCol = mix(uC2, uC1, smoothstep(0.0, 1.0, x));
    vec3 rc = ringCol * dens * light * shadow * (0.5 + 0.3 * eq) +
              eqCol * dens * (eq * eq * 0.9 + wave * 1.6) +
              vec3(1.0) * glint * dens * 0.8;
    float alpha = clamp(dens * (0.75 + 0.25 * eq), 0.0, 0.95);
    col = mix(col, rc, alpha);
  }

  col += uC3 * uX.x * 0.12 * exp(-abs(uv.y - 0.3) * 18.0);
  col *= 1.0 - 0.35 * smoothstep(0.5, 1.3, length(uv * vec2(0.85, 0.7)));
  col = clamp((col * (2.51 * col + 0.03)) / (col * (2.43 * col + 0.59) + 0.14), 0.0, 1.0);
  col = pow(col, vec3(0.4545));
  col += (hash12(frag) - 0.5) / 255.0;
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
