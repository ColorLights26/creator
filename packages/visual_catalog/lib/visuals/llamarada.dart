// Llamarada — fuego vivo con brasas y lecho incandescente.
// Las llamas se modelan con ruido deformado y una rampa de cuerpo negro. Los
// graves hacen rugir el fuego hacia arriba, cada golpe lanza una llamarada con
// una lluvia de chispas y los agudos multiplican las brasas.
const nativeSource = r'''
class Visual final : public Scene {
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  float phase = 0, roar = 0, burst = 0, burstAge = 9.0f, burstX = 0;
  Random rng{11};

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

 public:
  void reset(uint32_t seed) override {
    rng = Random(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    phase = rng.unit() * 30.0f;
    roar = 0;
    burst = 0;
    burstAge = 9.0f;
    burstX = 0;
  }

  void update(const Frame& f) override {
    float dt = float(f.delta);
    const Music& m = f.music;
    bass = follow(bass, m.bass, 20.0f, 3.5f, dt);
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
      burst = hit;
      burstAge = 0.0f;
      burstX = (rng.unit() - 0.5f) * 0.3f;
    }
    kick = std::max(kick * std::exp(-dt * 4.0f), hit);
    flash = std::max(flash * std::exp(-dt * 7.0f), std::min(fl, 1.0f));
    burstAge += dt;

    // La altura del fuego sube rápido y baja despacio, como un rugido.
    roar = follow(roar, 0.30f + 0.75f * bass + 0.35f * drive + 0.55f * kick, 9.0f, 1.6f, dt);
    phase += dt * f.speed * (0.55f + 1.2f * drive + 0.9f * kick);
  }

  void render(const Frame& f, Canvas& c) const override {
    float amp = f.intensity;
    std::vector<float> u;
    u.reserve(28);
    u.insert(u.end(), {phase, roar * (0.6f + 0.4f * amp), kick * amp, energy});
    u.insert(u.end(), {burst * amp, burstAge, burstX, spark * amp});
    u.insert(u.end(), {body, flash, f.glow, f.detail});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("fire", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'fire': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // tiempo, altura del fuego, golpe, energía
uniform vec4 uB;   // chispas del golpe: fuerza, edad, x; agudos
uniform vec4 uX;   // medios, destello, glow, detalle
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

float fbm(vec2 p) {
  float s = 0.0;
  float a = 0.5;
  for (int i = 0; i < 5; i++) {
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
  return s / 0.875 * 0.97;
}

// Rampa de cuerpo negro teñida con la paleta: rojo profundo, naranja, oro, blanco.
vec3 fireColor(float x) {
  vec3 c = mix(uC0, uC1, smoothstep(0.0, 0.25, x));
  c = mix(c, uC2, smoothstep(0.2, 0.55, x));
  c = mix(c, uC3, smoothstep(0.5, 0.85, x));
  c = mix(c, vec3(1.0, 0.98, 0.92), smoothstep(0.9, 1.15, x));
  return c * (0.3 + 1.2 * x);
}

float embers(vec2 p, float t, float cells, float speed, float seed, float density) {
  vec2 g = vec2(p.x * cells, (p.y - t * speed) * cells);
  vec2 id = floor(g);
  vec2 f = fract(g) - 0.5;
  float h = hash12(id + seed);
  vec2 o = vec2(hash12(id + seed + 1.7), hash12(id + seed + 4.2)) - 0.5;
  o.x += 0.3 * sin(t * 2.0 + h * 30.0);
  float d = length((f - o * 0.6) * vec2(1.0, 0.3));
  return smoothstep(0.07, 0.0, d) * step(1.0 - density, h) * (0.6 + 0.4 * sin(t * 30.0 + h * 80.0));
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 uv = (frag - 0.5 * uSize) / scale;
  uv.y = -uv.y;
  float t = uA.x;
  float bottom = -0.5 * uSize.y / scale;
  float h = uv.y - bottom;                 // altura sobre el borde inferior
  float height = 0.25 + 1.05 * uA.y;       // altura de las llamas

  // Calima: el aire caliente ondula por encima del fuego.
  vec2 p = uv;
  if (h < height * 2.0 + 0.2) {
    p.x += (noise(vec2(uv.x * 6.0, h * 4.0 - t * 2.0)) - 0.5) * 0.03 * smoothstep(0.1, 0.8, h);
  }

  vec3 col = uC0;
  // Resplandor cálido sólo alrededor del fuego.
  float glowR = length(vec2(p.x * 0.8, h - height * 0.35));
  col += uC1 * 0.06 * exp(-glowR * glowR * 3.0 / max(height, 0.15)) * (0.6 + 0.8 * uA.y);

  // Las llamas sólo existen en la parte baja: por encima la GPU se salta el ruido.
  if (h < height * 1.2 + 0.05) {
    // Ruido estirado en vertical: lenguas de fuego que suben y se rompen.
    vec2 q = vec2(p.x * 3.4, h * 1.5 - t * 1.9);
    vec2 warp = vec2(fbmLow(q * 0.6 + vec2(0.0, -t * 0.5)), fbmLow(q * 0.6 + vec2(3.7, -t * 0.6)));
    float n = fbm(q + (warp - 0.5) * 1.8);
    float licks = noise(vec2(p.x * 9.0, h * 3.0 - t * 4.0));
    float tongues = 0.7 + 0.3 * sin(p.x * 6.5 + noise(vec2(p.x * 2.5, t * 0.5)) * 5.0);
    float shape = 1.0 - h / (height * tongues);
    float widthMask = smoothstep(1.05, 0.2, abs(p.x) * (1.3 - 0.35 * uA.y));
    float flame = shape * widthMask * 1.55 - n * 1.05 - licks * 0.18 + 0.2;
    float body = smoothstep(0.0, 0.06, flame);
    float heat = clamp(flame * 0.85, 0.0, 1.0) * (0.66 + 0.22 * uA.z + 0.08 * uX.x);
    col += fireColor(heat) * body;
  }
  // Lecho de brasas en la base.
  if (h < 0.3) {
    float bed = exp(-h * 22.0) * (0.55 + 0.45 * noise(vec2(p.x * 14.0, t * 0.6)));
    col += fireColor(0.5 + 0.25 * noise(vec2(p.x * 9.0, t))) * bed * (0.7 + 0.5 * uA.y);
  }

  // Humo tenue en una franja por encima de las llamas.
  float smokeBand = smoothstep(height * 0.8, height * 1.5, h) * smoothstep(height * 2.6 + 0.5, height * 1.6, h);
  if (smokeBand > 0.0) {
    float smoke = fbmLow(vec2(p.x * 2.0, h * 1.5 - t * 0.35) + 9.0);
    col = mix(col, uC0 * 1.8, smoothstep(0.55, 0.85, smoke) * smokeBand * 0.4);
  }

  // Brasas: pocas, cerca del fuego y como estelas; más con los agudos.
  float density = 0.02 + 0.06 * uB.w + 0.03 * uA.w;
  float e = embers(p, t * 0.3, 14.0, 1.1, 0.0, density) +
            embers(p, t * 0.3, 24.0, 1.6, 13.0, density * 0.7) * 0.7;
  float fade = smoothstep(height * 1.6, height * 0.2, h) * smoothstep(1.0, 0.3, abs(p.x));
  col += mix(uC2, uC3, 0.5) * e * fade * 1.6;
  float age = uB.y;
  if (age < 2.5 && uB.x > 0.01) {
    vec2 bp = p - vec2(uB.z, bottom + height * 0.4 + age * 1.1);
    float spray = embers(bp * vec2(1.0, 0.7), 0.0, 22.0, 0.0, 31.0, 0.4);
    float cloud = exp(-dot(bp, bp) * 5.0 / (0.15 + age));
    col += mix(uC2, uC3, 0.7) * spray * cloud * uB.x * exp(-age * 1.6) * 3.0;
  }

  col += uC3 * uX.y * 0.15;
  col *= uX.z;
  col *= 1.0 - 0.35 * smoothstep(0.5, 1.3, length(uv * vec2(0.9, 0.65)));
  col = clamp((col * (2.51 * col + 0.03)) / (col * (2.43 * col + 0.59) + 0.14), 0.0, 1.0);
  col = pow(col, vec3(0.4545));
  col += (hash12(frag) - 0.5) / 255.0;
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
