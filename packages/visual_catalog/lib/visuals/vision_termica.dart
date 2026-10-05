// Visión Térmica — la fiesta vista con una cámara de calor.
// Una cámara térmica no ve la luz sino el calor: lo frío sale negro y
// morado, lo tibio rojo y naranja, y lo más caliente amarillo y blanco.
// Aquí bailan manchas de calor, siluetas de bailarines o franjas de aire
// caliente que suben, con el visor de la cámara encima: la mira, la escala
// de colores y la temperatura en dígitos. Cada golpe de la música es un
// fogonazo de calor, los graves hinchan las fuentes y los agudos sueltan
// chispas calientes.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // FORMA: qué da calor.
  CreatorModifier.choice(
    'fuentes',
    'Fuentes de calor',
    options: ['Manchas', 'Siluetas', 'Ondas'],
  ),
  // MOVIMIENTO: el aire caliente que sube y hace temblar la imagen.
  CreatorModifier.slider('conveccion', 'Convección', min: 0, max: 1, value: .4),
  // MÚSICA
  CreatorModifier.choice(
    'pulso',
    'Pulso',
    options: ['Golpes', 'Graves', 'Chispas'],
  ),
  // ATMÓSFERA: píxeles gruesos, grano y el visor de la cámara.
  CreatorModifier.slider('sensor', 'Sensor', min: 0, max: 1, value: .45),
  // MODO: curvas de igual temperatura.
  CreatorModifier.toggle('isotermas', 'Isotermas', value: false),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Fiesta Térmica', {
    'fuentes': 'Siluetas',
    'pulso': 'Golpes',
    'sensor': .6,
  }),
  CreatorVariation('Mapa de Calor', {
    'isotermas': true,
    'fuentes': 'Ondas',
    'conveccion': 1,
    'sensor': .1,
  }),
];

const nativeSource = r'''
class Visual final : public Scene {
  float bass = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0;
  // Reloj en doble precisión: sin música es idéntico a 30 y 60 FPS.
  double clock = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }
  // Un dígito de siete segmentos (a b c d e f g, de arriba en sentido horario).
  static void digit(Path& p, float x, float y, float w, float h, int mask) {
    const float s = w * 0.2f;
    if (mask & 1) p.rect({x, y, w, s});
    if (mask & 2) p.rect({x + w - s, y, s, h * 0.5f});
    if (mask & 4) p.rect({x + w - s, y + h * 0.5f, s, h * 0.5f});
    if (mask & 8) p.rect({x, y + h - s, w, s});
    if (mask & 16) p.rect({x, y + h * 0.5f, s, h * 0.5f});
    if (mask & 32) p.rect({x, y, s, h * 0.5f});
    if (mask & 64) p.rect({x, y + h * 0.5f - s * 0.5f, w, s});
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = spark = energy = slowBass = kick = flash = 0;
    clock = double(rng.unit()) * 30.0;
  }

  void update(const Frame& f) override {
    const float dt = float(f.delta);
    const Music& mu = f.music;
    bass = follow(bass, mu.bass, 22.0f, 4.5f, dt);
    spark = follow(spark, mu.spark, 30.0f, 7.0f, dt);
    energy = follow(energy, mu.energy, 6.0f, 1.8f, dt);
    float hit = 0, fl = 0;
    for (const auto& e : mu.events[0]) hit = std::max(hit, e.strength);
    for (const auto& e : mu.events[2]) hit = std::max(hit, e.strength * 0.85f);
    for (const auto& e : mu.events[3]) fl = std::max(fl, e.strength);
    const float onset = std::clamp((mu.bass - slowBass - 0.15f) * 2.5f, 0.0f, 1.0f);
    slowBass = follow(slowBass, mu.bass, 3.0f, 3.0f, dt);
    hit = std::min(std::max(hit, onset), 1.0f);
    kick = std::max(kick * std::exp(-dt * 4.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    clock += f.delta * f.speed;
  }

  void render(const Frame& f, Canvas& c) const override {
    auto g = glide(f);
    const auto& pal = f.colors;
    const float amp = f.intensity;
    const float W = f.width, H = f.height;
    const float side = std::min(W, H);
    const float px = side / 400.0f;
    const float sensor = std::clamp(g.sensor, 0.0f, 1.0f);
    std::vector<float> u;
    u.reserve(40);
    u.insert(u.end(), {float(std::fmod(clock, 1000.0)), std::min(bass * amp, 1.5f) * g.pulso.weight(1),
                       std::min(kick * amp, 1.0f) * g.pulso.weight(0), std::min(spark * amp, 1.0f) * g.pulso.weight(2)});
    u.insert(u.end(), {g.fuentes.weight(0), g.fuentes.weight(1), g.fuentes.weight(2), std::clamp(g.conveccion, 0.0f, 1.0f)});
    u.insert(u.end(), {sensor, std::clamp(g.isotermas, 0.0f, 1.0f), f.glow, std::min(flash * amp, 1.0f)});
    // Detalle: cuántas manchas de calor hay.
    u.insert(u.end(), {std::clamp(2.5f + 1.8f * f.detail, 3.0f, 6.0f), 0.5f * H / side, std::min(kick * amp, 1.0f), 0.0f});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {pal[size_t(i)].r, pal[size_t(i)].g, pal[size_t(i)].b});
    c.material("thermal", {0, 0, W, H}, u);

    // El visor de la cámara: mira, esquinas, escala y temperatura.
    const float hud = 0.35f + 0.65f * sensor;
    Paint line;
    line.strokeWidth = 1.4f * px;
    line.color = pal[3].opacity(0.85f * hud);
    const float cx = W * 0.5f, cy = H * 0.5f, arm = 16.0f * px, gap = 5.0f * px;
    Path cross;
    cross.moveTo(cx - arm, cy).lineTo(cx - gap, cy).moveTo(cx + gap, cy).lineTo(cx + arm, cy);
    cross.moveTo(cx, cy - arm).lineTo(cx, cy - gap).moveTo(cx, cy + gap).lineTo(cx, cy + arm);
    const float bx = W * 0.32f, by = H * 0.38f, bl = 14.0f * px;
    for (int k = 0; k < 4; k++) {
      const float sx = k % 2 == 0 ? -1.0f : 1.0f, sy = k < 2 ? -1.0f : 1.0f;
      const float x = cx + sx * bx, y = cy + sy * by;
      cross.moveTo(x - sx * bl, y).lineTo(x, y).lineTo(x, y - sy * bl);
    }
    c.path(cross, line);
    const Color hot{std::min(1.0f, pal[3].r * 0.3f + 0.7f), std::min(1.0f, pal[3].g * 0.3f + 0.7f), std::min(1.0f, pal[3].b * 0.3f + 0.7f), 1.0f};
    const Rect bar{W - 22.0f * px, H * 0.22f, 8.0f * px, H * 0.56f};
    Paint scaleBar = Paint::linear({0, bar.y}, {0, bar.y + bar.height}, {hot, pal[3], pal[2], pal[1], pal[0]});
    c.save();
    c.saveLayer(hud);
    c.rect(bar, scaleBar);
    c.restore();
    c.restore();
    Path ticks;
    for (int k = 0; k <= 8; k++) {
      const float y = bar.y + bar.height * float(k) / 8.0f;
      ticks.moveTo(bar.x - (k % 4 == 0 ? 7.0f : 4.0f) * px, y).lineTo(bar.x - 1.0f * px, y);
    }
    c.path(ticks, line);
    // Temperatura del punto central, en dígitos de siete segmentos.
    const float temp = 24.0f + 10.0f * std::min(energy * amp, 1.2f) + 5.0f * std::min(kick * amp, 1.0f) + 1.5f * std::sin(float(clock) * 0.3f);
    const int tenths = std::clamp(int(std::lround(temp * 10.0f)), 0, 999);
    static const int masks[10] = {63, 6, 91, 79, 102, 109, 125, 7, 127, 111};
    const float dw = 9.0f * px, dh = 16.0f * px, x0 = 14.0f * px, y0 = 14.0f * px;
    Path digits;
    digit(digits, x0, y0, dw, dh, masks[(tenths / 100) % 10]);
    digit(digits, x0 + dw * 1.5f, y0, dw, dh, masks[(tenths / 10) % 10]);
    digits.rect({x0 + dw * 2.75f, y0 + dh - dw * 0.2f, dw * 0.2f, dw * 0.2f});
    digit(digits, x0 + dw * 3.25f, y0, dw, dh, masks[tenths % 10]);
    digits.circle({x0 + dw * 4.75f, y0 + dw * 0.25f}, dw * 0.18f);
    digit(digits, x0 + dw * 5.15f, y0, dw, dh, 1 | 8 | 16 | 32);
    Paint dp;
    dp.color = pal[3].opacity(0.95f * hud);
    c.path(digits, dp);
  }
};
''';

const shaderSources = <String, String>{
  'thermal': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // tiempo, graves, fogonazo, chispas
uniform vec4 uB;   // pesos de fuentes: manchas, siluetas, ondas; convección
uniform vec4 uE;   // sensor, isotermas, glow, destello
uniform vec4 uF;   // manchas, media altura, golpe para los bailarines
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

float seg(vec2 p, vec2 a, vec2 b) {
  vec2 pa = p - a;
  vec2 ba = b - a;
  float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
  return length(pa - ba * h);
}

float heat(float d, float r) {
  return exp(-d * d / (r * r));
}

// Un bailarín: tronco y cabeza calientes, brazos y piernas tibios.
float dancer(vec2 p, float x, float i, float t) {
  float sway = 0.06 * sin(t * 1.8 + i * 1.3);
  float hop = -0.04 * uF.z * (0.5 + 0.5 * sin(i * 2.1));
  vec2 hip = vec2(x + sway * 0.3, 0.15 + hop);
  vec2 neck = vec2(x + sway, -0.2 + hop);
  vec2 head = vec2(x + sway * 1.2, -0.3 + hop);
  float wave = sin(t * 2.0 + i);
  vec2 handL = neck + vec2(-0.17, 0.05 - 0.2 * wave);
  vec2 handR = neck + vec2(0.17, 0.05 + 0.2 * wave);
  vec2 footL = vec2(x - 0.08, 0.6);
  vec2 footR = vec2(x + 0.08 + 0.03 * sin(t * 1.8 + i), 0.6);
  float h = heat(seg(p, hip, neck), 0.055) * 1.0;
  h = max(h, heat(length(p - head), 0.06) * 1.1);
  h = max(h, heat(min(seg(p, neck, handL), seg(p, neck, handR)), 0.028) * 0.75);
  h = max(h, heat(min(seg(p, hip, footL), seg(p, hip, footR)), 0.032) * 0.7);
  return h;
}

vec3 thermal(float T) {
  T = clamp(T, 0.0, 1.0);
  vec3 white = mix(uC3, vec3(1.0), 0.7);
  if (T < 0.3) return mix(uC0, uC1, T / 0.3);
  if (T < 0.55) return mix(uC1, uC2, (T - 0.3) / 0.25);
  if (T < 0.8) return mix(uC2, uC3, (T - 0.55) / 0.25);
  return mix(uC3, white, (T - 0.8) / 0.2);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  float t = uA.x;
  // Sensor: píxeles gruesos como una cámara térmica de verdad.
  float cell = mix(0.0, 0.012, uE.x);
  if (cell > 0.0005) p = (floor(p / cell) + 0.5) * cell;
  // Convección: el aire caliente hace temblar la imagen.
  p.x += uB.w * 0.012 * sin(p.y * 30.0 + t * 4.0);
  float T = 0.0;
  if (uB.x > 0.001) {
    float m = 0.0;
    for (int i = 0; i < 6; i++) {
      float fi = float(i);
      if (fi >= uF.x) break;
      float h = fract(sin(fi * 12.9898) * 43758.5453);
      vec2 c = vec2(0.32 * sin(t * (0.21 + 0.13 * h) + fi * 2.1), 0.7 * sin(t * (0.17 + 0.11 * h) + fi * 1.3) * uF.y / 0.89);
      float r = (0.12 + 0.05 * h) * (1.0 + 0.25 * uA.y);
      m += heat(length(p - c), r) * (0.7 + 0.3 * h);
    }
    T += uB.x * min(m, 1.2);
  }
  if (uB.y > 0.001) {
    float d = dancer(p, -0.33, 0.0, t);
    d = max(d, dancer(p, -0.11, 1.0, t));
    d = max(d, dancer(p, 0.11, 2.0, t));
    d = max(d, dancer(p, 0.33, 3.0, t));
    T += uB.y * (0.12 + d * (0.85 + 0.2 * uA.y));
  }
  if (uB.z > 0.001) {
    float w = 0.5 + 0.4 * sin(p.y * 9.0 + t * 2.0 + 1.5 * sin(p.x * 4.0 + t));
    T += uB.z * w * (0.35 + 0.65 * smoothstep(-0.9, 0.9, p.y)) * (1.0 + 0.2 * uA.y);
  }
  // Aire caliente que sube desde lo que quema.
  T += uB.w * 0.2 * (noise(p * vec2(4.0, 2.0) + vec2(0.0, t * 0.8)) - 0.5) * smoothstep(0.05, 0.5, T);
  // Fogonazo de calor con cada golpe.
  T += uA.z * 0.22;
  // Chispas calientes.
  T += step(0.985 - uA.w * 0.04, hash12(floor(p * 40.0) + floor(t * 6.0))) * uA.w * 0.8;
  T += (noise(p * 3.0 + t * 0.1) - 0.5) * 0.05;
  vec3 col = thermal(T);
  // Isotermas: bandas de igual temperatura con su línea.
  if (uE.y > 0.001) {
    float bands = floor(T * 8.0) / 8.0;
    float lineIso = 1.0 - smoothstep(0.0, 0.08, abs(fract(T * 8.0) - 0.5) * 2.0 - 0.9);
    vec3 iso = mix(thermal(bands + 0.06), uC3, lineIso * 0.7);
    col = mix(col, iso, uE.y);
  }
  col *= 1.0 + 0.1 * uE.w + 0.05 * uE.z;
  col += (hash12(frag + t) - 0.5) * 0.05 * uE.x;
  col *= 1.0 - 0.3 * smoothstep(0.7, 1.5, length(p * vec2(0.9, 0.65)));
  col += (hash12(frag) - 0.5) / 255.0;
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
