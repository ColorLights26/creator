// Mapa Topográfico Transparente — curvas de nivel de un terreno que respira.
// Versión overlay: mismo movimiento y reacción a la música sin fondo opaco.
// Un relieve de ruido fractal se desplaza y se transforma despacio; sólo se
// dibujan sus curvas de nivel, con el mismo grosor en toda la pantalla
// gracias a la pendiente exacta del ruido. Cada quinta curva es más gruesa,
// como en los mapas. El color sube del rojo al naranja y las cumbres arden
// en amarillo. Los graves elevan el relieve y aprietan las líneas, cada golpe
// levanta una montaña nueva que crece y se hunde, y una franja de barrido
// recorre el mapa como un radar.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.steps('lineas', 'Densidad de líneas', min: 6, max: 30, value: 14),
  CreatorModifier.slider('relieve', 'Relieve', min: .5, max: 2, value: 1),
  CreatorModifier.slider('deriva', 'Movimiento', min: 0, max: 2, value: 1),
  CreatorModifier.toggle('relleno', 'Relleno por alturas', value: true),
  CreatorModifier.toggle('barrido', 'Barrido de radar', value: true),
];

const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kPeaks = 3;
  struct Peak { float x, y, power; double age; };
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double drift = 0, scan = 0, sinceIdle = 0;
  int nextPeak = 0;
  Random rng{1};
  std::array<Peak, kPeaks> peaks{};

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  void raise(float power, float aspect) {
    Peak& p = peaks[size_t(nextPeak)];
    p.x = (rng.unit() - 0.5f) * 0.8f;
    p.y = (rng.unit() - 0.5f) * 0.8f * aspect;
    p.power = power;
    p.age = 0;
    nextPeak = (nextPeak + 1) % kPeaks;
  }

 public:
  void reset(uint32_t seed) override {
    rng = Random(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    drift = rng.unit() * 40.0;
    scan = 0;
    sinceIdle = 0;
    nextPeak = 0;
    for (auto& p : peaks) p = {0, 0, 0, 100};
  }

  void update(const Frame& f) override {
    auto m = modifiers(f);
    float dt = float(f.delta);
    const Music& mu = f.music;
    bass = follow(bass, mu.bass, 22.0f, 4.5f, dt);
    body = follow(body, mu.body, 12.0f, 3.0f, dt);
    spark = follow(spark, mu.spark, 30.0f, 7.0f, dt);
    energy = follow(energy, mu.energy, 6.0f, 1.8f, dt);
    drive = follow(drive, mu.active ? std::pow(std::clamp(mu.energy, 0.0f, 1.0f), 0.8f) : 0.0f, 3.0f, 0.7f, dt);

    float hit = 0, fl = 0;
    for (const auto& e : mu.events[0]) hit = std::max(hit, e.strength);
    for (const auto& e : mu.events[2]) hit = std::max(hit, e.strength * 0.85f);
    for (const auto& e : mu.events[3]) fl = std::max(fl, e.strength);
    float onset = std::clamp((mu.bass - slowBass - 0.15f) * 2.5f, 0.0f, 1.0f);
    slowBass = follow(slowBass, mu.bass, 3.0f, 3.0f, dt);
    hit = std::min(std::max(hit, onset), 1.0f);
    float aspect = f.height / std::max(std::min(f.width, f.height), 1.0f);
    sinceIdle += f.delta;
    if (hit > kick + 0.2f) {
      raise(0.6f + 0.6f * hit, aspect);
      sinceIdle = 0;
    }
    // Sin música también nacen montañas de vez en cuando.
    if (!mu.active && sinceIdle > 4.0) {
      raise(0.7f, aspect);
      sinceIdle -= 4.0;
    }
    for (auto& p : peaks) p.age += f.delta;
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    drift += f.delta * f.speed * m.deriva * (0.05 + 0.12 * drive);
    scan += f.delta * f.speed * (0.18 + 0.2 * drive);
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    float amp = f.intensity;
    std::vector<float> u;
    u.reserve(36);
    u.insert(u.end(), {float(std::fmod(drift, 1000.0)), bass * amp, kick * amp, energy});
    u.insert(u.end(), {float(m.lineas), m.relieve, m.relleno ? 1.0f : 0.0f, f.glow});
    for (const auto& p : peaks) {
      // La montaña sube y baja en 2,4 s.
      float t = float(std::min(p.age / 2.4, 1.0));
      float height = p.power * std::sin(t * 3.14159265f) * amp;
      u.insert(u.end(), {p.x, p.y, height, 0.08f + 0.16f * t});
    }
    u.insert(u.end(), {flash * amp, float(std::fmod(scan, 1.0)), m.barrido ? 1.0f : 0.0f, spark * amp});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("contours", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'contours': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // deriva, graves, golpe, energía
uniform vec4 uB;   // líneas, relieve, relleno, glow
uniform vec4 uP0;  // montaña: x, y, altura, anchura
uniform vec4 uP1;
uniform vec4 uP2;
uniform vec4 uD;   // destello, barrido, barrido activo, agudos
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

// Ruido de valor con su derivada exacta.
vec3 noised(vec2 x) {
  vec2 i = floor(x);
  vec2 f = fract(x);
  vec2 u = f * f * (3.0 - 2.0 * f);
  vec2 du = 6.0 * f * (1.0 - f);
  float a = hash12(i);
  float b = hash12(i + vec2(1.0, 0.0));
  float c = hash12(i + vec2(0.0, 1.0));
  float d = hash12(i + vec2(1.0, 1.0));
  float k1 = b - a;
  float k2 = c - a;
  float k4 = a - b - c + d;
  return vec3(a + k1 * u.x + k2 * u.y + k4 * u.x * u.y, du * (vec2(k1, k2) + k4 * u.yx));
}

// Relieve fractal: altura en x, pendiente en yz.
vec3 terrain(vec2 p, float t) {
  vec3 h = vec3(0.0);
  float a = 0.55;
  float fr = 1.6;
  vec2 o = vec2(t * 0.7, -t * 0.4);
  for (int i = 0; i < 4; i++) {
    vec3 n = noised(p * fr + o);
    h += vec3(n.x * a, n.yz * a * fr);
    a *= 0.5;
    fr *= 2.03;
    o = -o * 1.3 + vec2(3.1, 1.7);
  }
  return h;
}

vec3 bump(vec2 p, vec4 P) {
  vec2 d = p - P.xy;
  float g = P.z * exp(-dot(d, d) / (P.w * P.w));
  return vec3(g, -2.0 * d / (P.w * P.w) * g);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  float relief = uB.y * (0.75 + 0.55 * uA.y);
  vec3 h = terrain(p, uA.x) * relief;
  h += bump(p, uP0) + bump(p, uP1) + bump(p, uP2);
  float levels = uB.x;
  float v = h.x * levels;
  float slope = length(h.yz) * levels / scale;
  // Distancia en píxeles a la curva de nivel más cercana.
  float near = abs(fract(v + 0.5) - 0.5);
  float distPx = near / max(slope, 1e-4);
  float index = mod(floor(v + 0.5), 5.0) < 0.5 ? 1.0 : 0.0;
  float width = mix(1.1, 2.4, index) * (1.0 + 0.4 * uA.z);
  float line = 1.0 - smoothstep(width * 0.5, width * 0.5 + 1.0, distPx);
  float height01 = clamp(h.x / max(relief, 0.01) * 1.2 - 0.1, 0.0, 1.0);
  vec3 lineCol = mix(uC1, uC2, smoothstep(0.2, 0.7, height01));
  lineCol = mix(lineCol, uC3, smoothstep(0.75, 1.0, height01));
  // Barrido de radar que enciende las líneas a su paso.
  float halfH = 0.5 * uSize.y / scale;
  float scanY = -halfH + uD.y * (2.0 * halfH + 0.4) - 0.2;
  float sweep = uD.z * exp(-abs(p.y - scanY) * 14.0);
  vec3 col = uC0;
  if (uB.z > 0.5) {
    // Relleno tenue por franjas de altura.
    float band = floor(v) / max(levels, 1.0);
    col += mix(uC1, uC2, clamp(band, 0.0, 1.0)) * (0.035 + 0.04 * mod(floor(v), 2.0)) * (0.6 + 0.6 * uA.y);
  }
  float bright = (0.75 + 0.5 * index + 0.4 * uA.y + 0.5 * sweep) * mix(1.0, uB.w, 0.5);
  col += lineCol * line * bright;
  // Halo suave alrededor de las líneas maestras.
  col += lineCol * index * (1.0 - smoothstep(0.0, 6.0, distPx)) * 0.12 * uB.w;
  // Cumbres que brillan.
  col += uC3 * smoothstep(0.8, 1.1, height01) * 0.12 * (1.0 + uA.z);
  // El destello aviva las líneas en lugar de cubrir la pantalla.
  col *= 1.0 + 0.4 * uD.x;
  col *= 1.0 - 0.3 * smoothstep(0.7, 1.5, length(p * vec2(0.9, 0.65)));
  float peak = max(col.r, max(col.g, col.b));
  if (peak > 0.85) {
    float e = (peak - 0.85) / 0.15;
    col *= (0.85 + 0.15 * e / (1.0 + e)) / peak;
  }
  // Fondo transparente: color premultiplicado y opacidad según el brillo; la
  // luz muy tenue se vuelve transparente del todo para no dejar velo.
  col = clamp(col, 0.0, 1.0);
  float veilPeak = max(col.r, max(col.g, col.b));
  float clearCut = smoothstep(0.04, 0.12, veilPeak);
  col *= clearCut;
  float alpha = clamp(veilPeak * 1.25, 0.0, 1.0) * clearCut;
  fragColor = vec4(col, alpha);
}
""",
};
