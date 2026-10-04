// Sala Infinita — una sala de espejos llena de luces, como las de Kusama.
// Las paredes, el suelo y el techo son espejos, así las luces que cuelgan en
// la sala se repiten hasta el infinito en todas direcciones. Se dibujan como
// capas de luces a distintas distancias que se acercan sin parar: flotas
// despacio entre ellas. Cada luz tiene su altura de cuelgue, su parpadeo y su
// color; olas de color recorren la sala desde el fondo, cada golpe manda una
// ola de luz que pasa a tu lado y enciende todo, y los graves hacen latir
// las luces cercanas.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.slider('densidad', 'Densidad de luces', min: .6, max: 1.6, value: 1),
  CreatorModifier.choice('color', 'Iluminación', options: ['Kusama', 'Paleta', 'Rojo', 'Arcoíris']),
  CreatorModifier.slider('avance', 'Velocidad de avance', min: 0, max: 2, value: 1),
  CreatorModifier.toggle('parpadeo', 'Parpadeo', value: true),
];

const nativeSource = r'''
class Visual final : public Scene {
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double clock = 0, travel = 0, pulseAge = 100, sinceIdle = 0;
  float pulsePower = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    clock = rng.unit() * 40.0;
    travel = rng.unit() * 100.0;
    pulseAge = 100;
    pulsePower = 0;
    sinceIdle = 0;
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
    pulseAge += f.delta;
    sinceIdle += f.delta;
    if (hit > kick + 0.2f) {
      pulseAge = 0;
      pulsePower = hit;
    }
    if (!mu.active && sinceIdle > 3.5) {
      sinceIdle -= 3.5;
      pulseAge = sinceIdle;
      pulsePower = 0.7f;
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    clock += f.delta * f.speed;
    travel += f.delta * f.speed * m.avance * (0.6 + 1.6 * drive);
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    float amp = f.intensity;
    // La ola del golpe viaja desde la cámara hacia el fondo.
    float pulseZ = pulseAge < 4.0 ? float(pulseAge) * 9.0f : 99.0f;
    float pulseP = pulseAge < 4.0 ? pulsePower * float(1.0 - pulseAge / 4.0) * amp : 0.0f;
    std::vector<float> u;
    u.reserve(28);
    u.insert(u.end(), {float(std::fmod(clock, 1000.0)), bass * amp, kick * amp, energy});
    u.insert(u.end(), {float(std::fmod(travel, 1000.0)), m.densidad, float(m.color), m.parpadeo ? 1.0f : 0.0f});
    u.insert(u.end(), {f.glow, flash * amp, pulseZ, pulseP});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("mirror_room", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'mirror_room': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // reloj, graves, golpe, energía
uniform vec4 uB;   // avance, densidad, modo de color, parpadeo
uniform vec4 uD;   // glow, destello, distancia de la ola, fuerza de la ola
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

vec3 hue(float h) {
  return clamp(abs(fract(h + vec3(0.0, 0.667, 0.333)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
}

vec3 lightColor(float h, float wave) {
  float mode = uB.z;
  if (mode < 0.5) {
    // Kusama: rojos, naranjas, rosas, amarillos y algún verde lima.
    float k = fract(h * 5.0 + wave);
    vec3 c = k < 0.3 ? uC1 : (k < 0.55 ? uC2 : (k < 0.75 ? vec3(1.0, 0.2, 0.6) : (k < 0.92 ? uC3 : vec3(0.55, 1.0, 0.15))));
    return c;
  }
  if (mode < 1.5) {
    float k = fract(h * 3.0 + wave);
    return k < 0.33 ? uC1 : (k < 0.66 ? uC2 : uC3);
  }
  if (mode < 2.5) return mix(uC1, vec3(1.0, 0.35, 0.1), fract(h * 2.0 + wave * 0.5));
  return hue(h * 0.3 + wave * 0.5);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  float t = uA.x;
  // La cámara se mece un poco.
  p += 0.025 * vec2(sin(t * 0.31), cos(t * 0.23));
  float spacing = 1.0 / uB.y;
  float trav = uB.x;
  float base = floor(trav);
  float frac = trav - base;
  vec3 col = uC0;
  float glowSum = 0.0;
  for (int k = 0; k < 8; k++) {
    float z = float(k) + 1.0 - frac;
    float layer = base + float(k) + 1.0;
    float zoom = z * 1.5 / spacing;
    vec2 q = p * zoom;
    vec2 cell = floor(q + 0.5);
    vec2 key = cell + vec2(layer * 17.13, layer * 7.31);
    // Sólo algunas celdas tienen luz: la sala queda despejada. Las vacías
    // no cuestan nada más.
    if (hash12(key + 41.7) > 0.3) continue;
    float h = hash12(key);
    // Cada luz cuelga a su altura, sin salirse de su celda.
    vec2 local = q - cell - (vec2(hash12(key + 3.1), h) - 0.5) * 0.5;
    float d = length(local);
    float size = 0.055 + 0.035 * h + 0.025 * uA.y * step(z, 4.0);
    // Borde suave de un píxel aunque la luz esté lejos.
    float aa = 1.2 * zoom / scale;
    // Lejos de la luz no llega ni su halo.
    if (d > max(0.24, size + aa)) continue;
    float core = smoothstep(size + aa, size * 0.3, d);
    // Halo compacto: se apaga antes del borde de la celda, sin cortes.
    float hr = clamp(1.0 - d / 0.24, 0.0, 1.0);
    float halo = hr * hr * hr * 0.3;
    float fog = exp(-z * 0.2) * smoothstep(0.0, 0.9, z) * smoothstep(8.0, 5.5, z);
    float wave = sin(z * 0.45 - t * 1.8 + h * 2.0) * 0.12 + t * 0.05;
    vec3 lc = lightColor(h, wave);
    float twinkle = uB.w > 0.5 ? 0.6 + 0.4 * sin(t * (2.0 + 3.0 * h) + h * 40.0) : 1.0;
    float pulse = uD.w * exp(-abs(z - uD.z) * 0.9);
    float b = (core + halo) * fog * twinkle * (1.0 + 2.5 * pulse + 0.4 * uA.z);
    col += lc * b;
    glowSum += halo * fog;
  }
  // Bruma general de la sala, del color de las luces.
  col += mix(uC1, uC2, 0.5) * glowSum * 0.12 * uD.x;
  col += uC2 * uD.y * 0.05;
  col *= 1.0 - 0.3 * smoothstep(0.7, 1.5, length(p * vec2(0.9, 0.65)));
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
