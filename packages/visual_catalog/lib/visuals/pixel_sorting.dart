// Pixel Sorting — un atardecer cuyos píxeles se ordenan por brillo.
// Debajo hay una imagen viva: un degradado de atardecer con manchas de luz
// que se mueven. Cada columna de píxeles se parte en tramos de largo propio
// y, en los tramos elegidos (sobre todo donde la imagen es brillante), los
// píxeles se "ordenan": el tramo se convierte en una rampa limpia del color
// más oscuro al más claro, con el borde final cortado en seco, que es el
// sello del pixel sorting. Los tramos se deslizan hacia abajo como si la
// imagen se derritiera. La energía ordena más tramos y más largos, cada golpe
// rasga franjas de la imagen hacia los lados con separación de colores y los
// graves la iluminan.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.choice('direccion', 'Dirección', options: ['Vertical', 'Horizontal']),
  CreatorModifier.slider('cantidad', 'Cantidad ordenada', min: .1, max: 1, value: .55),
  CreatorModifier.slider('ancho', 'Ancho de columna', min: 1, max: 8, value: 3),
  CreatorModifier.toggle('rasgado', 'Rasgado con golpes', value: true),
];

const nativeSource = r'''
class Visual final : public Scene {
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double clock = 0, drip = 0;
  int tears = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    clock = rng.unit() * 50.0;
    drip = rng.unit() * 100.0;
    tears = 0;
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
    if (hit > kick + 0.2f) tears++;
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    clock += f.delta * f.speed * (0.4 + 0.8 * drive);
    drip += f.delta * f.speed * (1.0 + 2.5 * drive + 2.0 * kick);
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    float amp = f.intensity;
    std::vector<float> u;
    u.reserve(28);
    u.insert(u.end(), {float(std::fmod(clock, 1000.0)), float(std::fmod(drip, 4000.0)), bass * amp, kick * amp});
    u.insert(u.end(), {float(m.direccion), std::clamp(m.cantidad + 0.3f * drive + 0.25f * kick, 0.0f, 1.0f), m.ancho, m.rasgado ? 1.0f : 0.0f});
    u.insert(u.end(), {float(tears % 97), energy, f.glow, flash * amp});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("pixel_sort", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'pixel_sort': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // reloj, goteo, graves, golpe
uniform vec4 uB;   // dirección, cantidad, ancho de columna, rasgado
uniform vec4 uD;   // rasgados, energía, glow, destello
uniform vec3 uC0;
uniform vec3 uC1;
uniform vec3 uC2;
uniform vec3 uC3;
out vec4 fragColor;

float hash11(float n) {
  n = fract(n * 0.1031);
  n *= n + 33.33;
  n *= n + n;
  return fract(n);
}

float hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

// Rampa de atardecer: violeta → rosa-rojo → naranja → amarillo.
vec3 ramp(float v) {
  v = clamp(v, 0.0, 1.0);
  vec3 c = mix(uC0 * 1.6, uC1, smoothstep(0.0, 0.4, v));
  c = mix(c, uC2, smoothstep(0.35, 0.7, v));
  return mix(c, uC3, smoothstep(0.68, 1.0, v));
}

// La imagen de debajo: brillo de un atardecer con manchas que se mueven.
float source(vec2 p, float t) {
  // Cielo oscuro arriba, horizonte encendido y un sol que se mueve.
  float horizon = 0.18 + 0.06 * sin(p.x * 2.0 + t * 0.4);
  float v = 0.12 + 0.62 * exp(-(p.y - horizon) * (p.y - horizon) * 4.5);
  v += 0.12 * sin(p.x * 4.1 + t * 0.7) * sin(p.y * 3.3 - t * 0.5);
  vec2 sun = vec2(0.28 * sin(t * 0.21), horizon - 0.12 + 0.05 * cos(t * 0.17));
  v += 0.55 * exp(-dot(p - sun, p - sun) * 26.0);
  vec2 s2 = vec2(-0.3 * cos(t * 0.27), -0.45 + 0.2 * sin(t * 0.19));
  v += 0.3 * exp(-dot(p - s2, p - s2) * 14.0);
  return v;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  // En horizontal se intercambian los ejes: las columnas pasan a ser filas.
  bool horizontal = uB.x > 0.5;
  vec2 g = horizontal ? frag.yx : frag;
  vec2 size = horizontal ? uSize.yx : uSize;
  // Rasgado: franjas que saltan a un lado con cada golpe.
  float band = floor(g.y / (size.y / 26.0));
  float tearH = hash11(band * 7.3 + uD.x * 13.1);
  float tear = uB.w * step(0.72, tearH) * (tearH - 0.72) * 3.5 * uA.w * 90.0;
  g.x += tear;
  float w = max(uB.z, 1.0);
  float col = floor(g.x / w);
  float hc = hash11(col * 0.137 + 3.0);
  // Tramos de cada columna: largo propio y goteo propio.
  float len = mix(60.0, 340.0, hc) * (0.7 + 0.8 * uB.y);
  float slide = uA.y * (12.0 + 30.0 * hash11(col * 1.37 + 9.0));
  float k = floor((g.y + hc * len + slide) / len);
  float t = fract((g.y + hc * len + slide) / len);
  float y0 = k * len - hc * len - slide;
  float y1 = y0 + len;
  float tm = uA.x;
  vec2 toP = vec2(1.0, 1.0) / scale;
  vec2 here = horizontal ? (vec2(g.y, g.x) - 0.5 * uSize) * toP : (g - 0.5 * uSize) * toP;
  float v = source(here, tm);
  vec3 outCol = ramp(v);
  // ¿Se ordena este tramo? Más probable donde la imagen brilla.
  vec2 a = horizontal ? (vec2(y0, g.x) - 0.5 * uSize) * toP : (vec2(g.x, y0) - 0.5 * uSize) * toP;
  vec2 b = horizontal ? (vec2(y1, g.x) - 0.5 * uSize) * toP : (vec2(g.x, y1) - 0.5 * uSize) * toP;
  float va = source(a, tm);
  float vb = source(b, tm);
  float chosen = step(hash12(vec2(col, k)), uB.y) * step(0.5 - 0.25 * uB.y, max(va, vb));
  if (chosen > 0.5) {
    float lo = min(va, vb);
    float hi = max(va, vb) + 0.08;
    float s = lo + (hi - lo) * t * t * (3.0 - 2.0 * t);
    outCol = ramp(s);
    // Borde final cortado en seco con un brillo.
    outCol += uC3 * smoothstep(0.96, 1.0, t) * 0.35;
  }
  // Separación de colores en las franjas rasgadas.
  if (abs(tear) > 1.0) outCol = vec3(outCol.r * 1.15, outCol.g * 0.85, outCol.b * 1.2);
  outCol *= (0.9 + 0.3 * uA.z) * mix(1.0, uD.z, 0.4);
  outCol += uC3 * uD.w * 0.05;
  vec2 p0 = (frag - 0.5 * uSize) / scale;
  outCol *= 1.0 - 0.25 * smoothstep(0.7, 1.5, length(p0 * vec2(0.9, 0.65)));
  float peak = max(outCol.r, max(outCol.g, outCol.b));
  if (peak > 0.85) {
    float e = (peak - 0.85) / 0.15;
    outCol *= (0.85 + 0.15 * e / (1.0 + e)) / peak;
  }
  outCol += (hash12(frag) - 0.5) / 255.0;
  fragColor = vec4(clamp(outCol, 0.0, 1.0), 1.0);
}
""",
};
