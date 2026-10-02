// Película Iridiscente — macro de una película de jabón.
// El grosor de la película se calcula por píxel y se convierte en color de
// interferencia, más vivo en los órdenes finos y negro donde casi desaparece.
// Los graves agitan los remolinos, cada golpe expande un anillo de color desde
// el centro y los agudos afinan las vetas.
const nativeSource = r'''
class Visual final : public Scene {
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  float phase = 0, swirl = 0, hue = 0;
  std::array<float, 4> rings{};  // radio, amplitud, radio, amplitud

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    phase = rng.unit() * 20.0f;
    swirl = rng.unit() * 6.0f;
    hue = 0;
    rings = {3.0f, 0.0f, 3.0f, 0.0f};
  }

  void update(const Frame& f) override {
    float dt = float(f.delta);
    const Music& m = f.music;
    bass = follow(bass, m.bass, 20.0f, 4.0f, dt);
    body = follow(body, m.body, 10.0f, 2.5f, dt);
    spark = follow(spark, m.spark, 25.0f, 6.0f, dt);
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
      rings[2] = rings[0];
      rings[3] = rings[1];
      rings[0] = 0.0f;
      rings[1] = hit;
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 7.0f), std::min(fl, 1.0f));
    for (int i = 0; i < 4; i += 2) {
      rings[i] += dt * (0.55f + 0.35f * drive);
      rings[i + 1] *= std::exp(-dt * 1.4f);
    }

    phase += dt * f.speed * (0.18f + 0.9f * drive + 0.7f * kick);
    swirl += dt * f.speed * (0.10f + 1.4f * bass + 0.8f * kick);
    hue += dt * (0.02f + 0.25f * body);
  }

  void render(const Frame& f, Canvas& c) const override {
    float amp = f.intensity;
    std::vector<float> u;
    u.reserve(28);
    u.insert(u.end(), {phase, swirl, bass * amp, kick * amp});
    u.insert(u.end(), {rings[0], rings[1] * amp, rings[2], rings[3] * amp});
    u.insert(u.end(), {hue, spark * amp, energy, f.glow});
    u.insert(u.end(), {flash, 0.6f + 0.4f * f.detail, 0.0f, 0.0f});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("film", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'film': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // tiempo, remolino, graves, golpe
uniform vec4 uR;   // anillos: radio, amplitud, radio, amplitud
uniform vec4 uM;   // tono, agudos, energía, glow
uniform vec4 uX;   // destello, detalle
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

float fbm(vec2 p) {
  float s = 0.0;
  float a = 0.5;
  for (int i = 0; i < 4; i++) {
    s += a * noise(p);
    p = mat2(1.6, 1.2, -1.2, 1.6) * p;
    a *= 0.5;
  }
  return s;
}

float fbmLow(vec2 p) {
  float s = 0.0;
  float a = 0.5;
  for (int i = 0; i < 3; i++) {
    s += a * noise(p);
    p = mat2(1.6, 1.2, -1.2, 1.6) * p;
    a *= 0.5;
  }
  return s / 0.875 * 0.94;
}

vec2 rotate(vec2 p, float a) {
  float c = cos(a);
  float s = sin(a);
  return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  p.y = -p.y;
  float t = uA.x;
  float r = length(p);

  // Remolinos: el dominio gira alrededor de tres vórtices que derivan.
  vec2 q = p;
  for (int i = 0; i < 3; i++) {
    float fi = float(i);
    vec2 c = vec2(sin(t * 0.13 + fi * 2.1), cos(t * 0.11 + fi * 1.7)) * vec2(0.32, 0.45);
    vec2 d = q - c;
    float w = exp(-dot(d, d) * 9.0);
    q = c + rotate(d, w * (1.2 + 0.9 * sin(uA.y * 0.35 + fi)) * (0.6 + uA.z * 1.6));
  }
  vec2 warp = vec2(fbmLow(q * 1.7 + vec2(0.0, t * 0.06)), fbmLow(q * 1.7 + vec2(5.2, -t * 0.05)));
  vec2 s = q + (warp - 0.5) * (0.55 + 0.6 * uA.z);
  float detail = fbm(s * (2.6 + 1.6 * uX.y) + vec2(t * 0.03, -t * 0.09));
  float fine = noise(s * 14.0 + vec2(0.0, -t * 0.5)) - 0.5;

  // Grosor (nm): la película drena hacia abajo; los graves la adelgazan en el centro.
  float thickness = 230.0 + 300.0 * smoothstep(0.55, -0.6, p.y);
  thickness += (detail - 0.5) * (330.0 + 220.0 * uA.z);
  thickness += fine * (18.0 + 80.0 * uM.y);
  thickness -= uA.z * 170.0 * exp(-r * r * 5.0);
  thickness += uR.y * 240.0 * gauss((r - uR.x) * 9.0);
  thickness += uR.w * 190.0 * gauss((r - uR.z) * 9.0);
  thickness += 80.0 * sin(uM.x * 6.2831853);
  // Película negra en la zona más fina, como en una pompa real.
  float black = smoothstep(120.0, 230.0, thickness);
  thickness = max(thickness, 0.0);

  // Color iridiscente: ciclo de tono por grosor, más vivo en los primeros órdenes.
  float order = thickness * 0.0029;
  vec3 iri = 0.5 + 0.5 * cos(6.2831853 * (order + vec3(0.0, 0.33, 0.67)));
  iri = pow(iri, vec3(1.5));
  float fadeOrders = exp(-thickness / 1100.0);
  vec3 film = iri * black * (0.55 + 0.75 * fadeOrders);
  // La luz que refleja la película varía a gran escala: zonas brillantes y oscuras.
  float sheen = 0.12 + 1.25 * smoothstep(0.35, 0.8, fbmLow(p * 0.9 + vec2(t * 0.02, 1.7)));
  float light = (0.24 + 0.15 * uM.z + 0.40 * uA.w) * sheen;
  vec3 col = uC0 + film * light * uM.w;

  // Arco especular suave: reflejo de una luz de anillo sobre la película.
  vec2 hp = p - vec2(-0.05, 0.10);
  float arc = gauss((length(hp * vec2(1.0, 1.25)) - 0.42) / 0.035);
  arc *= smoothstep(-0.2, 0.6, hp.y + hp.x * 0.3);
  col += uC3 * arc * (0.10 + 0.35 * uX.x + 0.25 * uA.w) * (0.6 + 0.4 * sheen);

  // Halo de color que acompaña a los anillos del golpe.
  col += mix(uC1, uC2, 0.5 + 0.5 * sin(t)) * uR.y * 0.25 * gauss((r - uR.x) * 6.0);

  col *= 1.0 - 0.45 * smoothstep(0.45, 1.3, length(p * vec2(0.85, 0.65)));
  col = clamp((col * (2.51 * col + 0.03)) / (col * (2.43 * col + 0.59) + 0.14), 0.0, 1.0);
  col = pow(col, vec3(0.4545));
  col += (hash12(frag) - 0.5) / 255.0;
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
