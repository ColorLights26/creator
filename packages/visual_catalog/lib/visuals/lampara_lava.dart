// Lámpara de Lava — cera caliente que sube y se funde en líquido violeta.
// Siete gotas de cera suben y bajan a ritmos distintos; se estiran cuando
// van rápido y, cuando se acercan, se funden en una sola (metabolas). Abajo
// hay un charco de cera sobre la bombilla y arriba se acumula un poco. La
// cera tiene relieve: brillo especular, borde más oscuro y un núcleo que se
// ve más caliente donde es más gruesa. El líquido violeta se ilumina desde
// abajo. Con Calor de la cera, fría se queda abajo en gotas redondas que
// apenas suben y caliente sube en columnas altas y se acumula arriba. Los
// graves inflan y calientan las gotas, la energía acelera el ciclo y cada
// golpe las hace temblar.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.steps('gotas', 'Gotas', min: 3, max: 7, value: 6),
  CreatorModifier.slider('calor', 'Calor de la cera', min: 0, max: 1, value: .5),
  CreatorModifier.slider('tamano', 'Tamaño de gotas', min: .6, max: 1.5, value: 1),
  CreatorModifier.toggle('reflejos', 'Reflejos', value: true),
];

const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kBlobs = 7;
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double clock = 0, wobble = 0;
  std::array<float, kBlobs> period{}, phase{}, lane{}, size{};

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    clock = rng.unit() * 100.0;
    wobble = 0;
    for (int i = 0; i < kBlobs; i++) {
      period[size_t(i)] = 14.0f + 12.0f * rng.unit();
      phase[size_t(i)] = rng.unit() * 6.2831853f;
      lane[size_t(i)] = (float(i) / float(kBlobs - 1) - 0.5f) * 0.55f + (rng.unit() - 0.5f) * 0.1f;
      size[size_t(i)] = 0.09f + 0.07f * rng.unit();
    }
  }

  void update(const Frame& f) override {
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
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    clock += f.delta * f.speed * (1.0 + 1.5 * drive);
    wobble += f.delta * (6.0 + 6.0 * energy);
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    auto g = glide(f);
    float amp = f.intensity;
    float side = std::min(f.width, f.height);
    float halfH = 0.5f * f.height / side;
    int count = std::clamp(m.gotas, 3, kBlobs);
    // Calor de la cera (0,5 es la lámpara de siempre): fría, las gotas son
    // redondas y sólo suben un poco desde el charco; caliente, suben en
    // columnas altas que se estiran, se mecen y se juntan arriba.
    const float heat = std::clamp(g.calor, 0.0f, 1.0f);
    const float cold = std::clamp(1.0f - heat * 2.0f, 0.0f, 1.0f);
    const float hot = std::clamp(heat * 2.0f - 1.0f, 0.0f, 1.0f);
    std::vector<float> u;
    u.reserve(52);
    u.insert(u.end(), {float(std::fmod(wobble, 1000.0)), bass * amp, kick * amp, energy});
    u.insert(u.end(), {float(count), m.reflejos ? 1.0f : 0.0f, f.glow, flash * amp});
    // Charco de abajo y de arriba: crece abajo con el frío y arriba con el calor.
    u.insert(u.end(), {0.16f + 0.1f * cold - 0.03f * hot, 0.08f * (1.0f - cold) + 0.06f * hot});
    for (int i = 0; i < kBlobs; i++) {
      // Sube y baja: cerca de los extremos va más despacio, como la cera real.
      double w = 6.283185307179586 / double(period[size_t(i)]);
      double s = std::sin(clock * w + double(phase[size_t(i)]));
      double v = std::cos(clock * w + double(phase[size_t(i)]));
      float y = (float(s) * (0.78f - 0.42f * cold) - 0.44f * cold) * halfH;
      float sway = 0.05f - 0.035f * cold + 0.05f * hot;
      float x = lane[size_t(i)] + sway * float(std::sin(clock * 0.21 + double(i)));
      float r = size[size_t(i)] * m.tamano * (1.0f + 0.22f * bass * amp) * (1.0f - 0.22f * hot);
      float stretch = 1.0f + (0.55f - 0.45f * cold + 0.5f * hot) * float(std::fabs(v)) + 0.7f * hot;
      u.insert(u.end(), {x, y, i < count ? r : 0.0f, stretch});
    }
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("lava_lamp", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'lava_lamp': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // temblor, graves, golpe, energía
uniform vec4 uB;   // gotas, reflejos, glow, destello
uniform vec2 uH;   // alto del charco de abajo y del de arriba (calor de la cera)
uniform vec4 uG0;  // gota: x, y, radio, estiramiento vertical
uniform vec4 uG1;
uniform vec4 uG2;
uniform vec4 uG3;
uniform vec4 uG4;
uniform vec4 uG5;
uniform vec4 uG6;
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

// Suma el campo de una gota y su gradiente. El campo tiene alcance limitado
// (1 − q/R²)³: las gotas sólo se funden cuando se acercan y no hay puntos
// singulares en su centro.
void blob(vec2 p, vec4 g, inout float F, inout vec2 grad) {
  if (g.z <= 0.0) return;
  vec2 d = p - g.xy;
  d.y /= g.w;
  float R2 = g.z * g.z * 3.6;
  float q = dot(d, d);
  if (q >= R2) return;
  float k = 1.0 - q / R2;
  F += k * k * k;
  grad += -6.0 * k * k / R2 * vec2(d.x, d.y / g.w);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  p.y = -p.y;
  float halfH = 0.5 * uSize.y / scale;
  // Temblor del golpe: la superficie de la cera vibra un instante.
  vec2 pw = p + uA.z * 0.012 * vec2(sin(p.y * 40.0 + uA.x * 3.0), sin(p.x * 36.0 - uA.x * 2.0));
  float F = 0.0;
  vec2 grad = vec2(0.0);
  blob(pw, uG0, F, grad);
  blob(pw, uG1, F, grad);
  blob(pw, uG2, F, grad);
  blob(pw, uG3, F, grad);
  blob(pw, uG4, F, grad);
  blob(pw, uG5, F, grad);
  blob(pw, uG6, F, grad);
  // Charco de cera abajo y un poco arriba, con el mismo tipo de campo.
  float bottom = pw.y + halfH;
  if (bottom < uH.x) {
    float k = 1.0 - bottom / uH.x;
    F += 0.9 * k * k * k;
    grad += vec2(0.0, -0.9 * 3.0 * k * k / uH.x);
  }
  float top = halfH - pw.y;
  if (uH.y > 0.001 && top < uH.y) {
    float k = 1.0 - top / uH.y;
    F += 0.7 * k * k * k;
    grad += vec2(0.0, 0.7 * 3.0 * k * k / uH.y);
  }

  // Líquido violeta iluminado desde abajo.
  float fromBottom = clamp((p.y + halfH) / (2.0 * halfH), 0.0, 1.0);
  vec3 col = uC0 * (1.6 - 0.9 * fromBottom);
  col += uC2 * exp(-(p.y + halfH) * 3.0) * (0.22 + 0.25 * uA.y);
  col += uC1 * smoothstep(0.05, 0.3, F) * 0.1 * uB.z;

  float T = 0.3;
  float inside = smoothstep(T - 0.025, T + 0.025, F);
  if (inside > 0.0) {
    // Relieve de la cera desde el gradiente del campo.
    vec3 n = normalize(vec3(-grad * 0.05, 1.0));
    vec3 L = normalize(vec3(-0.5, 0.6, 0.8));
    float diff = clamp(dot(n, L), 0.0, 1.0);
    float thick = smoothstep(T, 1.1, F);
    vec3 wax = mix(uC1, uC2, thick);
    wax = mix(wax, uC3, smoothstep(0.9, 1.6, F) * (0.5 + 0.5 * uA.y));
    wax *= 0.55 + 0.6 * diff;
    // Borde oscuro y luz de abajo que atraviesa la cera.
    float rim = 1.0 - clamp(n.z, 0.0, 1.0);
    wax *= 1.0 - 0.45 * rim;
    wax += uC2 * exp(-(p.y + halfH) * 2.5) * 0.35;
    if (uB.y > 0.5) {
      vec3 hv = normalize(L + vec3(0.0, 0.0, 1.0));
      float spec = pow(clamp(dot(n, hv), 0.0, 1.0), 40.0);
      wax += vec3(1.0, 0.92, 0.8) * spec * 0.7;
    }
    wax *= 1.0 + 0.25 * uA.y + 0.2 * uA.z;
    col = mix(col, wax, inside);
  }
  col += uC2 * uB.w * 0.05;
  col *= 1.0 - 0.3 * smoothstep(0.6, 1.4, abs(p.x) * 1.4 + 0.2);
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
