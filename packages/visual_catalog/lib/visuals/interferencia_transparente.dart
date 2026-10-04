// Interferencia Transparente — ondas de varias fuentes que se cruzan.
// Versión overlay: mismo movimiento y reacción a la música sin fondo opaco.
// Como en una cubeta de ondas: cada fuente lanza anillos y donde dos crestas
// coinciden la luz se suma (naranja y blanco) y donde una cresta se encuentra
// con un valle se apaga, formando franjas de interferencia que cambian al
// moverse las fuentes. Las fuentes derivan despacio. Cada golpe crea una
// fuente nueva en otro sitio: su frente de onda se abre paso entre las demás
// y reordena todo el patrón; sin música cambian solas cada pocos segundos.
// Los graves suben el contraste y la energía acelera las ondas.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.steps('fuentes', 'Fuentes', min: 2, max: 4, value: 3),
  CreatorModifier.slider('longitud', 'Longitud de onda', min: .5, max: 2, value: 1),
  CreatorModifier.slider('movimiento', 'Movimiento de fuentes', min: 0, max: 2, value: 1),
  CreatorModifier.toggle('nitidas', 'Crestas nítidas', value: true),
];

const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kSources = 4;
  struct Source { float x, y, orbit, amp; double age; };
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double phase = 0, wander = 0, sinceIdle = 0;
  int next = 0;
  Random rng{1};
  std::array<Source, kSources> sources{};

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  void place(Source& s, float aspect, double age) {
    s.x = (rng.unit() - 0.5f) * 0.75f;
    s.y = (rng.unit() - 0.5f) * 0.75f * aspect;
    s.orbit = rng.unit() * 6.2831853f;
    s.amp = 0.8f + 0.4f * rng.unit();
    s.age = age;
  }

 public:
  void reset(uint32_t seed) override {
    rng = Random(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    phase = 0;
    wander = rng.unit() * 20.0;
    sinceIdle = 0;
    next = 0;
    for (auto& s : sources) place(s, 1.8f, 100.0);
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
    int count = std::clamp(m.fuentes, 2, kSources);
    sinceIdle += f.delta;
    if (hit > kick + 0.2f) {
      place(sources[size_t(next % count)], aspect, 0.0);
      next = (next + 1) % count;
      sinceIdle = 0;
    }
    if (!mu.active && sinceIdle > 5.0) {
      place(sources[size_t(next % count)], aspect, 0.0);
      next = (next + 1) % count;
      sinceIdle -= 5.0;
    }
    for (auto& s : sources) s.age += f.delta * f.speed;
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    phase += f.delta * f.speed * (2.2 + 3.0 * drive);
    wander += f.delta * f.speed * m.movimiento * 0.25;
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    float amp = f.intensity;
    int count = std::clamp(m.fuentes, 2, kSources);
    std::vector<float> u;
    u.reserve(36);
    u.insert(u.end(), {float(std::fmod(phase, 6283.185307179586)), bass * amp, kick * amp, energy});
    u.insert(u.end(), {38.0f / m.longitud, float(count), m.nitidas ? 1.0f : 0.0f, f.glow});
    for (int i = 0; i < kSources; i++) {
      const Source& s = sources[size_t(i)];
      double w = wander + double(s.orbit);
      float x = s.x + 0.07f * float(std::sin(w * 1.3));
      float y = s.y + 0.07f * float(std::cos(w * 0.9));
      // El frente de una fuente nueva avanza a 0,45 unidades por segundo.
      u.insert(u.end(), {x, y, float(std::min(s.age, 60.0)) * 0.45f, i < count ? s.amp : 0.0f});
    }
    u.insert(u.end(), {flash * amp, spark * amp, 0.0f, 0.0f});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("ripple_tank", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'ripple_tank': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // fase, graves, golpe, energía
uniform vec4 uB;   // número de onda, fuentes, crestas nítidas, glow
uniform vec4 uS0;  // fuente: x, y, radio del frente, amplitud
uniform vec4 uS1;
uniform vec4 uS2;
uniform vec4 uS3;
uniform vec4 uD;   // destello, agudos
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

float wave(vec2 p, vec4 S, float k, float ph, inout float total, inout float dots) {
  if (S.w <= 0.0) return 0.0;
  float d = length(p - S.xy);
  // Sólo hay ondas dentro del frente que avanza desde que nació la fuente.
  float front = smoothstep(0.0, 0.06, S.z - d);
  total += S.w * front / (1.0 + d * 1.2);
  dots += exp(-d * 90.0) * S.w;
  return S.w * sin(k * d - ph) * front / (1.0 + d * 1.2);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  float k = uB.x;
  float ph = uA.x;
  float total = 0.0;
  float dots = 0.0;
  float v = wave(p, uS0, k, ph, total, dots) + wave(p, uS1, k, ph, total, dots) +
            wave(p, uS2, k, ph, total, dots) + wave(p, uS3, k, ph, total, dots);
  float vn = v / max(total, 0.35);
  float t = clamp(0.5 + 0.5 * vn, 0.0, 1.0);
  if (uB.z > 0.5) t = pow(t, 2.2);
  t = clamp(t * (0.85 + 0.35 * uA.y) + 0.12 * uA.z, 0.0, 1.0);
  // Valles oscuros, crestas rojas, naranjas y blancas.
  vec3 col = mix(uC0, uC1, smoothstep(0.05, 0.45, t));
  col = mix(col, uC2, smoothstep(0.45, 0.75, t));
  col = mix(col, uC3, smoothstep(0.8, 1.0, t));
  // Donde todavía no llegan las ondas el agua está en calma y oscura.
  col = mix(uC0, col, smoothstep(0.0, 0.35, total));
  // Fuentes: puntos de luz.
  col += uC3 * dots * (0.8 + 0.6 * uA.z) * uB.w;
  // El destello aviva las ondas en lugar de cubrir la pantalla.
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
