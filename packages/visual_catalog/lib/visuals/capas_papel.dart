// Capas de Papel — paisaje abstracto de papel recortado en capas.
// Varias capas de papel apiladas de atrás hacia delante, del magenta al
// amarillo, con bordes ondulados y una sombra suave sobre la capa de detrás;
// se desplazan a distinta velocidad (paralaje) y el papel tiene textura.
// Detrás, un sol de papel late con los graves. Cada capa ondula con su banda
// del espectro (las del fondo con los graves, las del frente con los agudos)
// y cada golpe las separa con un muelle.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.steps('capas', 'Capas', min: 3, max: 8, value: 5),
  CreatorModifier.slider('ondas', 'Ondulación', min: .3, max: 2, value: 1),
  CreatorModifier.choice('forma', 'Forma', options: ['Olas', 'Montañas', 'Dunas']),
  CreatorModifier.toggle('sol', 'Sol de papel', value: true),
];

const nativeSource = r'''
class Visual final : public Scene {
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  std::array<float, 8> bands{};
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double drift = 0;
  float jump = 0, jumpVel = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    bands.fill(0);
    drift = rng.unit() * 50.0;
    jump = jumpVel = 0;
  }

  void update(const Frame& f) override {
    float dt = float(f.delta);
    const Music& mu = f.music;
    bass = follow(bass, mu.bass, 22.0f, 4.5f, dt);
    body = follow(body, mu.body, 12.0f, 3.0f, dt);
    spark = follow(spark, mu.spark, 30.0f, 7.0f, dt);
    energy = follow(energy, mu.energy, 6.0f, 1.8f, dt);
    drive = follow(drive, mu.active ? std::pow(std::clamp(mu.energy, 0.0f, 1.0f), 0.8f) : 0.0f, 3.0f, 0.7f, dt);
    for (int i = 0; i < 8; i++) {
      float v = 0;
      for (int k = i * 4; k < i * 4 + 4 && k < 31; k++) v = std::max(v, mu.smoothSpectrum[k]);
      bands[size_t(i)] = follow(bands[size_t(i)], v, 18.0f, 4.0f, dt);
    }

    float hit = 0, fl = 0;
    for (const auto& e : mu.events[0]) hit = std::max(hit, e.strength);
    for (const auto& e : mu.events[2]) hit = std::max(hit, e.strength * 0.85f);
    for (const auto& e : mu.events[3]) fl = std::max(fl, e.strength);
    float onset = std::clamp((mu.bass - slowBass - 0.15f) * 2.5f, 0.0f, 1.0f);
    slowBass = follow(slowBass, mu.bass, 3.0f, 3.0f, dt);
    hit = std::min(std::max(hit, onset), 1.0f);
    if (hit > kick + 0.2f) jumpVel += 1.8f * hit;
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    jumpVel += (-jump * 30.0f - jumpVel * 6.0f) * dt;
    jump += jumpVel * dt;
    drift += f.delta * f.speed * (0.25 + 0.6 * drive);
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    float amp = f.intensity;
    std::vector<float> u;
    u.reserve(32);
    u.insert(u.end(), {float(std::fmod(drift, 1000.0)), bass * amp, kick * amp, energy});
    u.insert(u.end(), {float(m.capas), m.ondas, float(m.forma), m.sol ? 1.0f : 0.0f});
    // Altura de onda de cada capa: crece hacia delante y con su banda.
    std::array<float, 8> wave{};
    for (int i = 0; i < 8; i++) wave[size_t(i)] = (0.025f + 0.012f * float(i)) * m.ondas * (1.0f + 1.6f * bands[size_t(i)] * amp);
    u.insert(u.end(), {wave[0], wave[1], wave[2], wave[3]});
    u.insert(u.end(), {wave[4], wave[5], wave[6], wave[7]});
    u.insert(u.end(), {std::max(-0.3f, jump) * amp, f.glow, flash * amp, 0.0f});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("paper_layers", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'paper_layers': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // deriva, graves, golpe, energía
uniform vec4 uB;   // capas, ondulación, forma, sol
uniform vec4 uS0;  // altura de onda de las capas 0 a 3
uniform vec4 uS1;  // altura de onda de las capas 4 a 7
uniform vec4 uD;   // separación del golpe, glow, destello
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

float band(float i) {
  vec4 s = i < 4.0 ? uS0 : uS1;
  float k = mod(i, 4.0);
  return k < 1.0 ? s.x : (k < 2.0 ? s.y : (k < 3.0 ? s.z : s.w));
}

// Perfil del borde: olas suaves, montañas en pico o dunas asimétricas.
float profile(float x, float form) {
  if (form < 0.5) return sin(x) * 0.6 + sin(x * 2.3 + 1.0) * 0.4;
  if (form < 1.5) {
    float a = abs(fract(x * 0.16) - 0.5) * 2.0;
    float b = abs(fract(x * 0.37 + 0.3) - 0.5) * 2.0;
    return (a * 0.7 + b * 0.3) * 2.0 - 1.0;
  }
  float s = fract(x * 0.2);
  return (smoothstep(0.0, 0.75, s) - smoothstep(0.75, 1.0, s)) * 2.0 - 1.0;
}

vec3 layerColor(float t) {
  vec3 c = mix(uC1, uC2, smoothstep(0.0, 0.6, t));
  return mix(c, uC3, smoothstep(0.55, 1.0, t));
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  float halfH = 0.5 * uSize.y / scale;
  float count = uB.x;
  // De delante hacia atrás: la primera capa que contiene el píxel lo tapa todo;
  // las capas de delante que no lo contienen sólo le echan su sombra. El bucle
  // sólo busca; el color se calcula una vez después.
  float shade = 1.0;
  float hit = -1.0;
  float hitEdge = 0.0;
  for (int k = 0; k < 8; k++) {
    float fi = count - 1.0 - float(k);
    if (fi < 0.0 || hit >= 0.0) break;
    float t = (fi + 1.0) / (count + 1.0);
    float base = -halfH * 0.55 + t * halfH * 1.7 - uD.x * (0.04 + 0.03 * fi);
    float speed = 0.25 + 0.2 * fi;
    float freq = 3.5 + 1.3 * mod(fi * 7.0, 5.0);
    float edge = base - band(fi) * profile(p.x * freq + uA.x * speed + fi * 3.7, uB.z);
    if (p.y > edge - 0.0015) {
      hit = fi;
      hitEdge = edge;
    } else {
      // Sombra de esta capa sobre lo que hay detrás, justo encima de su borde.
      shade *= 1.0 - 0.45 * smoothstep(0.045, 0.0, edge - p.y);
    }
  }
  vec3 col = vec3(0.0);
  bool found = hit >= 0.0;
  if (found) {
    // Fibra del papel: grano fino más manchas suaves.
    float paper = hash12(floor(frag * 0.5)) * 0.03 + noise(frag * 0.05) * 0.04;
    vec3 lc = layerColor(hit / max(count - 1.0, 1.0)) * (0.9 + 0.2 * paper / 0.07);
    // Más oscuro hacia abajo dentro de cada capa, como papel con relieve.
    lc *= 0.92 + 0.08 * smoothstep(hitEdge + 0.25, hitEdge, p.y);
    // Filo de luz en el borde recortado.
    lc += vec3(1.0) * exp(-abs(p.y - hitEdge) * 900.0) * 0.12;
    float inside = smoothstep(hitEdge - 0.0015, hitEdge + 0.0015, p.y);
    col = lc;
    if (inside < 1.0) {
      // Borde suavizado: mezcla con lo que hay justo detrás (en sombra).
      vec3 behind = hit > 0.0 ? layerColor((hit - 1.0) / max(count - 1.0, 1.0)) * 0.55 : uC0 * 1.6;
      col = mix(behind, lc, inside);
    }
  }
  if (!found) {
    // Cielo de papel con un degradado y el sol detrás de las capas.
    col = mix(uC0 * 1.6, mix(uC0, uC1, 0.25), smoothstep(-halfH, halfH * 0.2, p.y));
    if (uB.w > 0.5) {
      vec2 sc = vec2(0.18, -halfH * 0.45);
      vec2 sv = p - sc;
      float sd = length(sv);
      // Rayos de papel alrededor del sol, girando despacio.
      float ang = atan(sv.y, sv.x) + uA.x * 0.06;
      float ray = fract(ang / 6.2831853 * 16.0);
      float rays = smoothstep(0.48, 0.5, ray) * smoothstep(1.0, 0.98, ray);
      float rayShadow = smoothstep(0.5, 0.56, ray) * (1.0 - smoothstep(0.56, 0.6, ray));
      float reach = smoothstep(1.6, 0.25, sd);
      vec3 rayCol = mix(col, uC1 * 0.55 + uC0, 0.55 + 0.25 * uA.y);
      col = mix(col, rayCol, rays * reach);
      col *= 1.0 - 0.18 * rayShadow * reach;
      // Sol de dos discos de papel con sombra.
      float sr = 0.17 * (1.0 + 0.08 * uA.y + 0.05 * uA.z);
      col *= 1.0 - 0.35 * smoothstep(sr + 0.03, sr, sd) * step(sr, sd);
      col = mix(col, mix(uC2, uC3, 0.55), smoothstep(sr, sr - 0.003, sd));
      float ir = sr * 0.7;
      col *= 1.0 - 0.18 * smoothstep(ir + 0.02, ir, sd) * step(ir, sd);
      col = mix(col, mix(uC3, vec3(1.0, 0.96, 0.8), 0.25), smoothstep(ir, ir - 0.003, sd));
    }
  }
  col *= shade;
  col *= (0.9 + 0.2 * uA.y + 0.15 * uA.z) * mix(1.0, uD.y, 0.5);
  col = mix(col, vec3(1.0), uD.z * 0.05);
  col *= 1.0 - 0.25 * smoothstep(0.7, 1.5, length(p * vec2(0.9, 0.65)));
  col += (hash12(frag) - 0.5) / 255.0;
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
