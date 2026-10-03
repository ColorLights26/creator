// Metal Tornasol Transparente — metal líquido a pantalla completa con reflejos tornasolados.
// Versión overlay: mismo movimiento y reacción a la música sin fondo opaco.
// Grandes abultamientos de metal brillante sobre un oleaje fino; las pendientes
// reflejan colores vivos que recorren la paleta. Cada golpe lanza una onda de
// choque, hace saltar el tono y destella; los graves hinchan el metal y los
// agudos encienden los brillos especulares.
const nativeSource = r'''
class Visual final : public Scene {
  struct Blob { float radius, p1, p2, sx, sy; };
  std::vector<Blob> blobs;
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  float phase = 0, hue = 0, swell = 0;
  std::array<float, 12> rings{};  // x, y, radio, amplitud por onda
  int nextRing = 0;
  Random rng{9};

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

 public:
  void reset(uint32_t seed) override {
    rng = Random(seed);
    blobs.clear();
    for (int i = 0; i < 6; i++)
      blobs.push_back({0.16f + rng.unit() * 0.10f, rng.unit() * 6.2831853f, rng.unit() * 6.2831853f,
                       0.21f + float(i) * 0.043f, 0.17f + float(i) * 0.037f});
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    phase = rng.unit() * 20.0f;
    hue = rng.unit();
    swell = 0;
    rings.fill(0);
    for (int i = 0; i < 3; i++) rings[i * 4 + 2] = 3.0f;
    nextRing = 0;
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
      // Nueva onda de choque desde un punto cercano al centro.
      float aspect = f.height / std::min(f.width, f.height);
      rings[nextRing * 4] = (rng.unit() - 0.5f) * 0.6f;
      rings[nextRing * 4 + 1] = (rng.unit() - 0.5f) * 0.6f * aspect;
      rings[nextRing * 4 + 2] = 0.0f;
      rings[nextRing * 4 + 3] = hit;
      nextRing = (nextRing + 1) % 3;
      hue += 0.12f * hit;
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    for (int i = 0; i < 3; i++) {
      rings[i * 4 + 2] += dt * (0.75f + 0.35f * drive);
      rings[i * 4 + 3] *= std::exp(-dt * 1.6f);
    }

    phase += dt * f.speed * (0.22f + 1.1f * drive + 0.9f * kick);
    hue += dt * (0.015f + 0.10f * energy + 0.06f * body);
    swell = follow(swell, bass * 0.7f + kick * 0.5f, 14.0f, 3.0f, dt);
  }

  void render(const Frame& f, Canvas& c) const override {
    float amp = f.intensity;
    float s = std::min(f.width, f.height);
    float hw = 0.5f * f.width / s, hh = 0.5f * f.height / s;
    float grow = 1.0f + 0.45f * swell * amp;
    std::array<float, 18> b{};
    for (int i = 0; i < 6; i++) {
      const Blob& k = blobs[i];
      b[i * 3] = hw * 0.9f * std::sin(phase * k.sx + k.p1);
      b[i * 3 + 1] = hh * 0.85f * std::sin(phase * k.sy + k.p2);
      b[i * 3 + 2] = k.radius * grow;
    }
    std::vector<float> u;
    u.reserve(56);
    u.insert(u.end(), {phase, bass * amp, kick * amp, energy});
    u.insert(u.end(), {hue, spark * amp, flash, f.glow});
    u.insert(u.end(), {b[0], b[1], b[3], b[4]});
    u.insert(u.end(), {b[6], b[7], b[9], b[10]});
    u.insert(u.end(), {b[12], b[13], b[15], b[16]});
    u.insert(u.end(), {b[2], b[5], b[8], b[11]});
    u.insert(u.end(), {b[14], b[17], 0.6f + 0.4f * f.detail, 0.35f + 0.9f * bass * amp});
    for (int i = 0; i < 3; i++)
      u.insert(u.end(), {rings[i * 4], rings[i * 4 + 1], rings[i * 4 + 2], rings[i * 4 + 3] * amp});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("metal", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'metal': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;    // tiempo, graves, golpe, energía
uniform vec4 uB;    // tono, agudos, destello, glow
uniform vec4 uP0;   // centros de las gotas 0 y 1
uniform vec4 uP1;   // centros 2 y 3
uniform vec4 uP2;   // centros 4 y 5
uniform vec4 uR0;   // radios 0..3
uniform vec4 uR1;   // radios 4, 5; detalle; amplitud del oleaje
uniform vec4 uS0;   // ondas de choque: x, y, radio, amplitud
uniform vec4 uS1;
uniform vec4 uS2;
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

float blob(vec2 p, vec2 c, float r) {
  vec2 d = p - c;
  return exp(-dot(d, d) / (r * r));
}

float shock(vec2 p, vec4 s) {
  float d = length(p - s.xy) - s.z;
  return s.w * 0.05 * sin(d * 42.0) * exp(-d * d * 55.0);
}

float height(vec2 p) {
  float t = uA.x;
  float b = blob(p, uP0.xy, uR0.x) + blob(p, uP0.zw, uR0.y) + blob(p, uP1.xy, uR0.z) +
            blob(p, uP1.zw, uR0.w) + blob(p, uP2.xy, uR1.x) + blob(p, uP2.zw, uR1.y);
  // Metal líquido: los abultamientos se funden en una sola superficie.
  float h = b / (1.0 + 0.6 * b) * 0.2;
  vec2 q = p + 0.08 * vec2(sin(p.y * 3.1 + t * 0.7), sin(p.x * 2.7 - t * 0.6));
  h += 0.006 * uR1.w * (sin(q.x * 9.0 * uR1.z + t * 1.6) + sin(q.y * 11.0 * uR1.z - t * 1.3) +
                        sin((q.x + q.y) * 7.0 + t));
  h += shock(p, uS0) + shock(p, uS1) + shock(p, uS2);
  return h;
}

// Ciclo de color vivo a través de la paleta: c1 -> c2 -> c3 -> c1.
vec3 cycle(float x) {
  float f = fract(x) * 3.0;
  vec3 a = f < 1.0 ? uC1 : (f < 2.0 ? uC2 : uC3);
  vec3 b = f < 1.0 ? uC2 : (f < 2.0 ? uC3 : uC1);
  return mix(a, b, smoothstep(0.0, 1.0, fract(f)));
}

// Entorno de estudio que refleja el metal: cielo tornasol según la dirección,
// una franja de luz nítida que dibuja contornos y suelo oscuro para el contraste.
vec3 environment(vec3 r, float hue, float kick, float lift) {
  float tilt = length(r.xy);
  vec3 sky = cycle(hue + r.x * 0.6 + r.y * 0.35);
  vec3 col = uC0 * 0.6;
  col += sky * (0.22 * lift + 0.9 * smoothstep(0.08, 0.8, tilt)) * (1.0 + 0.5 * kick);
  float sy = r.y - 0.42;
  float sx = r.x + 0.55;
  float strip = exp(-sy * sy * 160.0) * smoothstep(0.2, 0.5, tilt);
  float strip2 = exp(-sx * sx * 220.0) * smoothstep(0.3, 0.6, tilt);
  col += mix(vec3(1.0), sky, 0.35) * (strip * 1.1 + strip2 * 0.6) * (1.0 + kick);
  col *= 0.30 + 0.70 * smoothstep(-0.5, -0.1, r.y);
  return col;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  p.y = -p.y;
  float t = uA.x;
  float kick = uA.z;

  float e = 1.5 / scale;
  float h0 = height(p);
  float hx = height(p + vec2(e, 0.0));
  float hy = height(p + vec2(0.0, e));
  vec3 n = normalize(vec3(-(hx - h0) / e, -(hy - h0) / e, 1.0));
  vec3 v = vec3(0.0, 0.0, 1.0);
  vec3 r = reflect(-v, n);

  float slope = clamp(1.0 - n.z, 0.0, 1.0);
  float fres = 0.25 + 0.75 * pow(slope, 0.8);
  float hue = uB.x + h0 * 1.2;
  vec3 iri = cycle(hue);
  // Sólo la cima de las cúpulas refleja algo de color; el fondo plano queda negro.
  float lift = smoothstep(0.03, 0.12, h0);
  vec3 col = environment(r, hue, kick, lift) * fres * (0.9 + 0.3 * uA.w) * uB.w;
  // Brillo especular nítido de la luz principal, más intenso con los agudos.
  vec3 l1 = normalize(vec3(-0.5, 0.6, 0.65));
  float s1 = pow(max(dot(n, normalize(l1 + v)), 0.0), 140.0);
  col += vec3(1.0) * s1 * (0.8 + 2.5 * uB.y);
  // Destello del golpe y del flash.
  col += iri * kick * 0.12 + vec3(1.0) * uB.z * 0.10;

  col *= 1.0 - 0.35 * smoothstep(0.5, 1.3, length(p * vec2(0.9, 0.65)));
  col = clamp((col * (2.51 * col + 0.03)) / (col * (2.43 * col + 0.59) + 0.14), 0.0, 1.0);
  col = pow(col, vec3(0.4545));
  // Fondo transparente: el color va premultiplicado y la opacidad sale del
  // brillo, así la luz se compone sobre lo que haya debajo.
  col = clamp(col, 0.0, 1.0);
  float alpha = clamp(max(col.r, max(col.g, col.b)) * 1.25, 0.0, 1.0);
  // Las cúpulas de metal son sólidas; sólo el fondo plano es transparente.
  alpha = max(alpha, smoothstep(0.06, 0.14, h0));
  fragColor = vec4(col, alpha);
}
""",
};
