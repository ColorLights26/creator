// Cáusticas Profundas — fondo marino bajo la luz que atraviesa el oleaje.
// La red de cáusticas se calcula por píxel con dispersión cromática; los
// graves intensifican el oleaje, cada golpe produce una salpicadura que
// deforma la luz y los agudos encienden el plancton bioluminiscente.
const nativeSource = r'''
class Visual final : public Scene {
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  float phase = 0, wave = 0, drift = 0;
  std::array<float, 4> splash{};  // x, z, radio, amplitud
  Random rng{7};

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

 public:
  void reset(uint32_t seed) override {
    rng = Random(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    phase = rng.unit() * 40.0f;
    wave = 0;
    drift = 0;
    splash = {0.0f, 2.0f, 4.0f, 0.0f};
  }

  void update(const Frame& f) override {
    float dt = float(f.delta);
    const Music& m = f.music;
    bass = follow(bass, m.bass, 20.0f, 4.0f, dt);
    body = follow(body, m.body, 12.0f, 3.0f, dt);
    spark = follow(spark, m.spark, 30.0f, 6.0f, dt);
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
      splash = {(rng.unit() - 0.5f) * 1.6f, 1.2f + rng.unit() * 1.6f, 0.0f, hit};
    }
    kick = std::max(kick * std::exp(-dt * 4.5f), hit);
    flash = std::max(flash * std::exp(-dt * 6.0f), std::min(fl, 1.0f));
    splash[2] += dt * 1.6f;
    splash[3] *= std::exp(-dt * 1.6f);

    phase += dt * f.speed * (0.35f + 1.3f * drive + 1.0f * kick);
    wave = follow(wave, 0.35f + 0.9f * bass + 0.6f * kick, 10.0f, 2.0f, dt);
    drift += dt * f.speed * (0.04f + 0.12f * drive);
  }

  void render(const Frame& f, Canvas& c) const override {
    float amp = f.intensity;
    std::vector<float> u;
    u.reserve(32);
    u.insert(u.end(), {phase, wave * amp, kick * amp, energy});
    u.insert(u.end(), {splash[0], splash[1], splash[2], splash[3] * amp});
    u.insert(u.end(), {spark * amp, body, flash, f.glow});
    u.insert(u.end(), {drift, f.detail, 0.0f, 0.0f});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("caustics", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'caustics': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // tiempo, oleaje, golpe, energía
uniform vec4 uS;   // salpicadura: x, z, radio, amplitud
uniform vec4 uM;   // agudos, medios, destello, glow
uniform vec4 uX;   // deriva, detalle
uniform vec3 uC0;
uniform vec3 uC1;
uniform vec3 uC2;
uniform vec3 uC3;
out vec4 fragColor;

// Campana gaussiana segura: pow() con base negativa no está definido en GLSL.
float gauss(float x) {
  return exp(-x * x);
}

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

// Cáustica de agua periódica (iteración de Hoskins).
float caustic(vec2 uv, float time) {
  vec2 p = mod(uv * 6.2831853, 6.2831853) - 250.0;
  vec2 i = p;
  float c = 1.0;
  float inten = 0.005;
  for (int n = 0; n < 5; n++) {
    float t = time * (1.0 - (3.5 / float(n + 1)));
    i = p + vec2(cos(t - i.x) + sin(t + i.y), sin(t - i.y) + cos(t + i.x));
    c += 1.0 / length(vec2(p.x / (sin(i.x + t) / inten), p.y / (cos(i.y + t) / inten)));
  }
  c /= 5.0;
  c = 1.17 - pow(c, 1.4);
  return pow(abs(c), 8.0);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 uv = (frag - 0.5 * uSize) / scale;
  uv.y = -uv.y;
  float t = uA.x;

  // Refracción de la superficie: toda la imagen ondula un poco con los graves.
  uv += vec2(sin(uv.y * 9.0 + t * 1.3), cos(uv.x * 7.0 - t * 1.1)) * 0.004 * (0.5 + uA.y);

  vec3 ro = vec3(0.0, 1.25, 0.0);
  float pitch = -0.62;
  vec3 fw = vec3(0.0, sin(pitch), cos(pitch));
  vec3 rt = vec3(1.0, 0.0, 0.0);
  vec3 up = cross(fw, rt);
  vec3 rd = normalize(fw * 1.5 + rt * uv.x + up * uv.y);

  vec3 water = mix(uC0, uC1, smoothstep(-0.6, 0.6, uv.y) * 0.8);
  vec3 col = water;
  float ct = t * 0.55 + 20.0;

  if (rd.y < -0.02) {
    float dist = -ro.y / rd.y;
    vec2 xz = (ro + rd * dist).xz + vec2(uX.x, -uX.x * 0.6);
    // Salpicadura: un anillo que deforma la luz alrededor del golpe.
    vec2 toS = xz - uS.xy;
    float ds = length(toS);
    float ring = gauss((ds - uS.z) * 5.0) * uS.w;
    xz += toS / max(ds, 0.001) * sin((ds - uS.z) * 18.0) * ring * 0.06;

    vec2 cuv = xz * 0.75;
    float spread = 0.0025 + 0.003 * uM.x;
    vec3 caus = vec3(caustic(cuv, ct), caustic(cuv + spread, ct), caustic(cuv + 2.0 * spread, ct));
    float strength = 0.35 + 1.1 * uA.y + 1.6 * uA.z;
    // Arena con ondas suaves, teñida por el agua.
    float rip = sin(dot(xz, vec2(3.1, 1.4)) * 6.0 + noise(xz * 3.0) * 4.0);
    vec3 sand = mix(uC3, uC1, 0.55) * (0.07 + 0.02 * rip + 0.03 * noise(xz * 18.0));
    vec3 light = mix(uC2, uC3, 0.55);
    vec3 floorCol = sand * (0.7 + 0.5 * uM.y) + light * caus * strength * 0.45 + light * ring * 0.25;
    float fog = exp(-dist * (0.30 - 0.04 * uX.y));
    col = mix(water, floorCol, fog);
  }

  // Haces de luz desde la superficie.
  vec2 lp = uv - vec2(0.15, 1.1);
  float ang = atan(lp.x, -lp.y);
  float shafts = pow(noise(vec2(ang * 34.0, t * 0.25)) * noise(vec2(ang * 11.0 + 3.0, t * 0.12)), 1.8);
  float fall = smoothstep(-0.5, 0.9, uv.y);
  col += mix(uC2, uC3, 0.7) * shafts * fall * (0.06 + 0.22 * uA.y + 0.35 * uA.z + 0.5 * uM.z) * uM.w;

  // Plancton bioluminiscente en dos capas de profundidad.
  for (int layer = 0; layer < 2; layer++) {
    float fl = float(layer);
    float cells = 26.0 - fl * 10.0;
    vec2 g = (uv + vec2(0.0, t * (0.012 + fl * 0.01))) * cells;
    vec2 id = floor(g);
    vec2 fr = fract(g) - 0.5;
    float h = hash12(id + fl * 17.0);
    vec2 o = vec2(hash12(id + 4.1), hash12(id + 9.3)) - 0.5;
    o += 0.15 * vec2(sin(t * 0.7 + h * 30.0), cos(t * 0.5 + h * 20.0));
    float d = length(fr - o * 0.7);
    float glow = smoothstep(0.07 + fl * 0.04, 0.0, d) * step(0.9, h);
    float blink = 0.25 + 0.75 * smoothstep(0.4, 1.0, sin(t * 2.0 + h * 60.0) * 0.5 + 0.5);
    col += uC2 * glow * blink * (0.12 + 1.8 * uM.x + 0.6 * uA.z) * (0.6 + 0.4 * fl);
  }

  col += uC3 * uM.z * 0.12;
  col *= 1.0 - 0.4 * smoothstep(0.45, 1.25, length(uv * vec2(0.85, 0.7)));
  col = clamp((col * (2.51 * col + 0.03)) / (col * (2.43 * col + 0.59) + 0.14), 0.0, 1.0);
  col = pow(col, vec3(0.4545));
  col += (hash12(frag) - 0.5) / 255.0;
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
