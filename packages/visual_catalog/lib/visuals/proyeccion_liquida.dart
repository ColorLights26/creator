// Proyección Líquida — espectáculo de luz líquida de los conciertos de los 60.
// Tres tintes de aceite y agua se mezclan de forma sustractiva sobre la luz
// del proyector, con meniscos oscuros y burbujas. Cada golpe presiona el
// cristal y expande las manchas; los graves las hacen ondular y los medios
// rotan los colores.
const nativeSource = r'''
class Visual final : public Scene {
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  float phase = 0, press = 0, pressVel = 0, hue = 0, wobble = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    phase = rng.unit() * 50.0f;
    press = pressVel = 0;
    hue = rng.unit();
    wobble = 0;
  }

  void update(const Frame& f) override {
    float dt = float(f.delta);
    const Music& m = f.music;
    bass = follow(bass, m.bass, 20.0f, 4.0f, dt);
    body = follow(body, m.body, 10.0f, 2.5f, dt);
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
    if (hit > kick + 0.2f) pressVel += 2.6f * hit;
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 7.0f), std::min(fl, 1.0f));

    // Muelle amortiguado: el cristal se presiona y rebota como en el proyector.
    pressVel += (-press * 38.0f - pressVel * 7.0f) * dt;
    press += pressVel * dt;

    phase += dt * f.speed * (0.16f + 0.75f * drive + 0.5f * kick);
    hue += dt * (0.01f + 0.12f * body);
    wobble += dt * f.speed * (0.3f + 2.2f * bass);
  }

  void render(const Frame& f, Canvas& c) const override {
    float amp = f.intensity;
    std::vector<float> u;
    u.reserve(28);
    u.insert(u.end(), {phase, press * amp, bass * amp, kick * amp});
    u.insert(u.end(), {hue, wobble, spark * amp, flash});
    u.insert(u.end(), {energy, f.glow, f.detail, 0.0f});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("liquid", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'liquid': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // tiempo, presión, graves, golpe
uniform vec4 uB;   // tono, ondulación, agudos, destello
uniform vec4 uX;   // energía, glow, detalle
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

float fbm(vec2 p, int octaves) {
  float s = 0.0;
  float a = 0.5;
  float norm = 0.0;
  for (int i = 0; i < 4; i++) {
    if (i >= octaves) break;
    s += a * noise(p);
    norm += a;
    p = mat2(1.6, 1.2, -1.2, 1.6) * p;
    a *= 0.5;
  }
  return s / norm;
}

// Gira un color en la rueda de tono preservando su luminancia.
vec3 hueShift(vec3 c, float a) {
  const vec3 k = vec3(0.57735);
  float ca = cos(a);
  return c * ca + cross(k, c) * sin(a) + k * dot(k, c) * (1.0 - ca);
}

// Campo de un tinte: comparte la deformación global y añade la suya propia.
float dyeField(vec2 p, vec2 warp, float t, float seed) {
  vec2 q = p + warp * (1.0 + 0.25 * seed) +
           0.06 * vec2(sin(uB.y + seed), cos(uB.y * 0.8 + seed));
  return fbm(q * 1.7 + vec2(seed * 3.1, -t * 0.04), 3);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 uv = (frag - 0.5 * uSize) / scale;
  uv.y = -uv.y;
  float t = uA.x;
  float r = length(uv);

  // El golpe presiona el cristal: el centro se expande y la luz sube.
  vec2 p = uv / (1.0 + 0.22 * uA.y);
  float lamp = (0.95 - 0.45 * smoothstep(0.0, 1.1, r)) * (1.0 + 0.45 * uA.y + 0.5 * uB.w);

  vec3 light = mix(vec3(1.0, 0.95, 0.86), uC3, 0.2) * lamp;
  vec3 trans = vec3(1.0);
  float lines = 0.0;
  float highlight = 0.0;
  float shift = sin(uB.x * 6.2831853) * 0.35;
  // Deformación compartida por los tres tintes (más barata que una por capa).
  vec2 warp = vec2(fbm(p * 0.8 + vec2(0.0, t * 0.06), 3), fbm(p * 0.8 + vec2(5.2, -t * 0.05), 3));
  warp = (warp - 0.5) * (0.9 + 0.9 * uA.z);
  for (int i = 0; i < 3; i++) {
    float fi = float(i);
    vec2 d = vec2(dyeField(p * (0.62 + fi * 0.16), warp, t * (1.0 + fi * 0.3), fi * 1.7 + 0.4), 0.0);
    float thresh = 0.47 - 0.05 * uA.z - 0.04 * uA.w;
    float edgeSoft = 0.02;
    float dye = smoothstep(thresh - edgeSoft, thresh + edgeSoft, d.x);
    // Tinte translúcido: más denso hacia el interior de cada mancha.
    float depth = smoothstep(thresh, thresh + 0.18, d.x);
    vec3 tint = i == 0 ? uC1 : (i == 1 ? uC2 : uC3);
    tint = clamp(hueShift(tint, shift + fi * 0.1), 0.0, 1.0);
    vec3 absorb = pow(tint, vec3(1.0 + 0.9 * depth));
    trans *= mix(vec3(1.0), absorb, dye * (0.72 + 0.2 * depth));
    float edge = gauss((d.x - thresh) / 0.008);
    lines = max(lines, edge);
    highlight += gauss((d.x - thresh - 0.025) / 0.012) * 0.5;
  }
  vec3 col = light * trans;
  col *= 1.0 - 0.6 * lines;
  col += light * trans * highlight * 0.6;

  // Pocas burbujas grandes atrapadas entre los cristales.
  vec2 g = (p + vec2(sin(t * 0.2) * 0.2, t * 0.03)) * 4.0;
  vec2 id = floor(g);
  vec2 f = fract(g) - 0.5;
  float h = hash12(id);
  if (h > 0.9) {
    vec2 o = (vec2(hash12(id + 1.3), hash12(id + 7.1)) - 0.5) * 0.3;
    float rad = 0.10 + 0.12 * hash12(id + 3.3);
    float d = length(f - o);
    float rim = gauss((d - rad) / 0.012);
    float inner = smoothstep(rad, rad * 0.6, d);
    col = mix(col, col * 1.15 + light * 0.06, inner);
    col *= 1.0 - 0.45 * rim;
    col += light * smoothstep(0.03, 0.0, length(f - o - vec2(-0.35, 0.35) * rad)) * (0.35 + 0.8 * uB.z);
  }

  // Grano de la pantalla y bordes del haz del proyector.
  col *= 0.94 + 0.06 * noise(frag * 0.7);
  float cone = smoothstep(1.35, 0.55, length(uv * vec2(0.9, 0.62)));
  col = mix(uC0, col * uX.y, cone);
  col += vec3(1.0) * uB.w * 0.15;
  col = clamp((col * (2.51 * col + 0.03)) / (col * (2.43 * col + 0.59) + 0.14), 0.0, 1.0);
  col = pow(col, vec3(0.4545));
  col += (hash12(frag) - 0.5) / 255.0;
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
