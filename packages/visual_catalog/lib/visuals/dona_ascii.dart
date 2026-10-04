// Dona ASCII — la rosquilla 3D de texto de donut.c, en un monitor antiguo.
// La pantalla es una rejilla de caracteres. En cada celda se lanza un rayo
// contra una figura 3D que gira (una dona, y también esfera, cubo u
// octaedro) y, según cuánta luz recibe ese punto, se escribe uno de los doce
// caracteres de donut.c: . , - ~ : ; = ! * # $ @, del más tenue al más
// brillante. Los caracteres son mapas de bits de 5×7 píxeles dibujados en el
// shader. El ámbar del monitor tiene resplandor y líneas de barrido. La
// energía acelera el giro, los graves la iluminan, cada golpe la hace latir,
// los agudos hacen chispear celdas sueltas y en Auto la figura cambia cada
// ocho golpes.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.steps('columnas', 'Columnas de texto', min: 24, max: 80, value: 38),
  CreatorModifier.choice('figura', 'Figura', options: ['Auto', 'Dona', 'Esfera', 'Cubo', 'Octaedro']),
  CreatorModifier.choice('color', 'Color', options: ['Ámbar', 'Fuego', 'Arcoíris']),
  CreatorModifier.slider('giro', 'Velocidad de giro', min: .2, max: 2.5, value: 1),
];

const nativeSource = r'''
class Visual final : public Scene {
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double angA = 0, angB = 0, clock = 0, sinceShape = 0;
  float morph = 1;
  int beats = 0, autoShape = 0, shapeFrom = 0, shapeTo = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    angA = rng.unit() * 6.28;
    angB = rng.unit() * 6.28;
    clock = 0;
    sinceShape = 0;
    morph = 1;
    beats = 0;
    autoShape = shapeFrom = shapeTo = 0;
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
    sinceShape += f.delta;
    if (hit > kick + 0.2f) {
      beats++;
      if (beats % 8 == 0) {
        autoShape = (autoShape + 1) % 4;
        sinceShape = 0;
      }
    }
    // La transformación avanza antes de mirar cambios: si el cambio es por
    // tiempo, empieza en su instante exacto (igual a 30 y 60 FPS).
    morph = std::min(1.0f, morph + dt / 1.2f);
    double carry = -1.0;
    if (!mu.active && sinceShape > 8.0) {
      autoShape = (autoShape + 1) % 4;
      sinceShape -= 8.0;
      carry = sinceShape;
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    int wanted = m.figura == 0 ? autoShape : m.figura - 1;
    if (wanted != shapeTo) {
      shapeFrom = shapeTo;
      shapeTo = wanted;
      morph = carry >= 0.0 ? std::min(1.0f, float(carry / 1.2)) : 0.0f;
    }
    double spin = f.delta * f.speed * m.giro * (1.0 + 1.5 * drive + 1.5 * kick);
    angA += spin * 0.7;
    angB += spin * 0.35;
    clock += f.delta * f.speed;
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    float amp = f.intensity;
    std::vector<float> u;
    u.reserve(32);
    u.insert(u.end(), {float(std::fmod(angA, 6.2831853)), float(std::fmod(angB, 6.2831853)), float(std::fmod(clock, 1000.0)), morph});
    u.insert(u.end(), {float(shapeFrom), float(shapeTo), float(m.columnas), float(m.color)});
    u.insert(u.end(), {bass * amp, kick * amp, spark * amp, energy});
    u.insert(u.end(), {f.glow, flash * amp, 0.0f, 0.0f});
    // Giro y mezcla de figuras ya calculados: el rayo sólo suma.
    float ca = float(std::cos(angA)), sa = float(std::sin(angA)), cb = float(std::cos(angB)), sb = float(std::sin(angB));
    u.insert(u.end(), {ca, sa, cb, sb});
    std::array<float, 4> w{0, 0, 0, 0};
    float e = morph * morph * (3.0f - 2.0f * morph);
    w[size_t(shapeFrom)] += 1.0f - e;
    w[size_t(shapeTo)] += e;
    u.insert(u.end(), {w[0], w[1], w[2], w[3]});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("ascii_donut", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'ascii_donut': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // ángulo A, ángulo B, reloj, transformación
uniform vec4 uB;   // figura anterior, figura nueva, columnas, color
uniform vec4 uM;   // graves, golpe, agudos, energía
uniform vec4 uD;   // glow, destello
uniform vec4 uR;   // giro: cos A, sen A, cos B, sen B
uniform vec4 uW;   // peso de cada figura: dona, esfera, cubo, octaedro
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

// Los doce caracteres de donut.c en mapas de bits de 5×7: filas 0–3 en x y
// filas 4–6 en y, cinco bits por fila.
vec2 glyph(float i) {
  if (i < 0.5) return vec2(0.0, 396.0);
  if (i < 1.5) return vec2(0.0, 12424.0);
  if (i < 2.5) return vec2(31.0, 0.0);
  if (i < 3.5) return vec2(277.0, 2048.0);
  if (i < 4.5) return vec2(12672.0, 12672.0);
  if (i < 5.5) return vec2(12672.0, 12424.0);
  if (i < 6.5) return vec2(992.0, 31744.0);
  if (i < 7.5) return vec2(135300.0, 4100.0);
  if (i < 8.5) return vec2(21983.0, 15008.0);
  if (i < 9.5) return vec2(338922.0, 32074.0);
  if (i < 10.5) return vec2(147086.0, 6084.0);
  return vec2(476917.0, 24078.0);
}

float glyphBit(float i, vec2 uv) {
  vec2 g = floor(uv * vec2(6.0, 8.0));
  if (g.x > 4.5 || g.y > 6.5) return 0.0;
  vec2 code = glyph(i);
  float val = g.y < 3.5 ? code.x : code.y;
  float shift = g.y < 3.5 ? (3.0 - g.y) * 5.0 + (4.0 - g.x) : (6.0 - g.y) * 5.0 + (4.0 - g.x);
  return mod(floor(val / exp2(shift)), 2.0);
}

vec3 rotate(vec3 p) {
  p = vec3(p.x, uR.x * p.y - uR.y * p.z, uR.y * p.y + uR.x * p.z);
  return vec3(uR.z * p.x - uR.w * p.y, uR.w * p.x + uR.z * p.y, p.z);
}

// Las cuatro figuras mezcladas por peso (sin ramas: siempre el mismo coste).
float scene(vec3 p) {
  float k = 1.0 + 0.12 * uM.y;
  vec3 q = rotate(p) / k;
  float torus = length(vec2(length(q.xz) - 1.0, q.y)) - 0.45;
  float sphere = length(q) - 1.15;
  vec3 d = abs(q) - vec3(0.85);
  float box = length(max(d, 0.0)) + min(max(d.x, max(d.y, d.z)), 0.0) - 0.08;
  vec3 a = abs(q);
  float octa = (a.x + a.y + a.z - 1.35) * 0.577;
  return dot(uW, vec4(torus, sphere, box, octa)) * k;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float cw = uSize.x / uB.z;
  vec2 cellSize = vec2(cw, cw * 8.0 / 6.0);
  vec2 cell = floor(frag / cellSize);
  vec2 cellUv = fract(frag / cellSize);
  vec2 centerPx = (cell + 0.5) * cellSize;
  float scale = min(uSize.x, uSize.y);
  vec2 uv = (centerPx - 0.5 * uSize) / scale * 1.9;
  // Un rayo por celda contra la figura.
  vec3 ro = vec3(0.0, 0.0, -4.2);
  vec3 rd = normalize(vec3(uv, 2.2));
  float t = 0.0;
  float hit = 0.0;
  for (int i = 0; i < 32; i++) {
    float d = scene(ro + rd * t);
    if (d < 0.002) {
      hit = 1.0;
      break;
    }
    t += d;
    if (t > 8.0) break;
  }
  vec3 col = uC0;
  float lum = 0.0;
  if (hit > 0.5) {
    vec3 p = ro + rd * t;
    vec2 e = vec2(0.003, -0.003);
    vec3 n = normalize(e.xyy * scene(p + e.xyy) + e.yyx * scene(p + e.yyx) + e.yxy * scene(p + e.yxy) + e.xxx * scene(p + e.xxx));
    lum = clamp(dot(n, normalize(vec3(0.35, -0.8, -0.6))), 0.0, 1.0);
    lum = clamp(lum * (0.9 + 0.35 * uM.x) + 0.08, 0.0, 1.0);
  }
  // Chispas de los agudos: celdas sueltas que se encienden con @.
  float sparkle = step(0.994 - 0.02 * uM.z, hash12(cell + floor(uA.z * 12.0)));
  float idx = floor(lum * 11.99);
  float on = 0.0;
  if (hit > 0.5) on = glyphBit(idx, cellUv);
  float sp = sparkle * (1.0 - hit) * glyphBit(11.0, cellUv) * uM.z;
  // Color del carácter según el modo.
  vec3 ink = uC1;
  if (uB.w > 0.5 && uB.w < 1.5) ink = mix(uC2, uC3, lum);
  if (uB.w > 1.5) {
    float h = lum * 0.8 + uA.z * 0.05;
    ink = clamp(abs(fract(h + vec3(0.0, 0.667, 0.333)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
  }
  ink *= 0.45 + 0.75 * lum;
  col += ink * on * (1.0 + 0.4 * uM.y);
  col += uC1 * sp * 0.8;
  // Resplandor del monitor detrás de cada carácter.
  col += ink * hit * lum * 0.12 * uD.x;
  // Líneas de barrido y viñeta de tubo.
  col *= 0.86 + 0.14 * sin(frag.y * 1.9);
  vec2 p0 = (frag - 0.5 * uSize) / scale;
  col *= 1.0 - 0.45 * smoothstep(0.5, 1.4, length(p0 * vec2(0.9, 0.6)));
  col += uC1 * uD.y * 0.05;
  col += (hash12(frag) - 0.5) / 255.0;
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
