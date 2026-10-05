// Panel de Discos Transparente — el arte cinético de discos que se voltean.
// Versión overlay: mismo movimiento y reacción a la música sin fondo opaco.
// La pantalla es un panel de discos redondos con una cara de color y otra
// negra, como los letreros de discos magnéticos convertidos en arte. Un
// dibujo invisible (ondas, barras del espectro, rayos que giran, un damero en
// movimiento o una espiral) decide qué cara muestra cada disco; cuando el
// dibujo cruza un disco, éste se voltea y se ve girar sobre su eje, así las
// figuras avanzan como olas de discos. Cada golpe lanza un anillo que voltea
// los discos a su paso, los graves avivan el color y en Auto el dibujo
// cambia cada ocho golpes, volteando todo el panel hacia el nuevo.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.steps('discos', 'Discos a lo ancho', min: 14, max: 48, value: 26),
  CreatorModifier.choice('dibujo', 'Dibujo', options: ['Auto', 'Ondas', 'Espectro', 'Rayos', 'Damero', 'Espiral']),
  CreatorModifier.choice('color', 'Cara de los discos', options: ['Amarillo', 'Blanco', 'Rojo', 'Naranja']),
];

const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kRipples = 3;
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  std::array<float, 8> bands{};
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double clock = 0, sinceScene = 0;
  std::array<double, kRipples> rippleAge{};
  std::array<float, kRipples> rippleX{}, rippleY{};
  float fade = 1;
  int beats = 0, autoScene = 0, from = 0, to = 0, nextRipple = 0;
  Random rng{1};

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  void ripple(double age) {
    rippleAge[size_t(nextRipple)] = age;
    rippleX[size_t(nextRipple)] = (rng.unit() - 0.5f) * 0.7f;
    rippleY[size_t(nextRipple)] = (rng.unit() - 0.5f) * 1.1f;
    nextRipple = (nextRipple + 1) % kRipples;
  }

 public:
  void reset(uint32_t seed) override {
    rng = Random(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    bands.fill(0);
    clock = rng.unit() * 30.0;
    sinceScene = 0;
    rippleAge.fill(100.0);
    rippleX.fill(0);
    rippleY.fill(0);
    fade = 1;
    beats = 0;
    autoScene = from = to = 0;
    nextRipple = 0;
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
    for (int b = 0; b < 8; b++) {
      float v = 0;
      for (int k = b * 3; k < b * 3 + 4 && k < 31; k++) v = std::max(v, mu.smoothSpectrum[size_t(k)]);
      bands[size_t(b)] = follow(bands[size_t(b)], v, 20.0f, 4.0f, dt);
    }

    float hit = 0, fl = 0;
    for (const auto& e : mu.events[0]) hit = std::max(hit, e.strength);
    for (const auto& e : mu.events[2]) hit = std::max(hit, e.strength * 0.85f);
    for (const auto& e : mu.events[3]) fl = std::max(fl, e.strength);
    float onset = std::clamp((mu.bass - slowBass - 0.15f) * 2.5f, 0.0f, 1.0f);
    slowBass = follow(slowBass, mu.bass, 3.0f, 3.0f, dt);
    hit = std::min(std::max(hit, onset), 1.0f);
    sinceScene += f.delta;
    for (auto& a : rippleAge) a += f.delta * f.speed;
    fade = std::min(1.0f, fade + dt / 1.6f);
    double carry = -1.0;
    if (hit > kick + 0.2f) {
      ripple(0.0);
      if (++beats % 8 == 0) {
        autoScene = (autoScene + 1) % 5;
        sinceScene = 0;
      }
    }
    if (!mu.active && sinceScene > 9.0) {
      sinceScene -= 9.0;
      carry = sinceScene;
      autoScene = (autoScene + 1) % 5;
      ripple(carry);
    }
    int wanted = m.dibujo == 0 ? autoScene : m.dibujo - 1;
    if (wanted != to) {
      from = to;
      to = wanted;
      fade = carry >= 0.0 ? std::min(1.0f, float(carry / 1.6)) : 0.0f;
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    clock += f.delta * f.speed * (1.0 + 1.0 * drive);
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    float amp = f.intensity;
    std::array<Color, 4> discs = {f.colors[1], Color{0.96f, 0.95f, 0.9f, 1.0f}, f.colors[3], Color{1.0f, 0.55f, 0.05f, 1.0f}};
    const Color& disc = discs[size_t(std::clamp(m.color, 0, 3))];
    std::vector<float> u;
    u.reserve(52);
    u.insert(u.end(), {float(std::fmod(clock, 1000.0)), bass * amp, kick * amp, energy});
    u.insert(u.end(), {float(m.discos), float(from), float(to), fade});
    u.insert(u.end(), {bands[0] * amp, bands[1] * amp, bands[2] * amp, bands[3] * amp});
    u.insert(u.end(), {bands[4] * amp, bands[5] * amp, bands[6] * amp, bands[7] * amp});
    for (int i = 0; i < kRipples; i++) {
      float age = float(std::min(rippleAge[size_t(i)], 9.0));
      u.insert(u.end(), {rippleX[size_t(i)], rippleY[size_t(i)], age * 0.7f, age < 2.5f ? 1.0f - age / 2.5f : 0.0f});
    }
    u.insert(u.end(), {disc.r, disc.g, disc.b, f.glow});
    u.insert(u.end(), {flash * amp, spark * amp, 0.0f, 0.0f});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("flip_discs", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'flip_discs': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // reloj, graves, golpe, energía
uniform vec4 uB;   // discos, dibujo anterior, dibujo nuevo, fundido
uniform vec4 uS0;  // bandas 0–3
uniform vec4 uS1;  // bandas 4–7
uniform vec4 uR0;  // anillos: x, y, radio, fuerza
uniform vec4 uR1;
uniform vec4 uR2;
uniform vec4 uK;   // color de la cara del disco, glow
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

float band(float i) {
  vec4 s = i < 3.5 ? uS0 : uS1;
  float k = mod(i, 4.0);
  return k < 0.5 ? s.x : (k < 1.5 ? s.y : (k < 2.5 ? s.z : s.w));
}

// Dibujo invisible: valor 0–1, el disco muestra el color por encima de 0,5.
float pattern(float k, vec2 p, float t, float halfH) {
  if (k < 0.5) return 0.5 + 0.5 * sin(length(p) * 13.0 - t * 2.4);
  if (k < 1.5) {
    // Barras del espectro desde abajo (sin música, una ecualización de demostración).
    float x = clamp((p.x + 0.5) * 8.0, 0.0, 7.99);
    float level = band(floor(x));
    if (uA.w < 0.02) level = 0.45 + 0.3 * sin(t * 1.7 + floor(x) * 0.9);
    float fromBottom = (p.y + halfH) / (2.0 * halfH);
    return 0.5 + clamp((level - fromBottom) * 6.0, -0.5, 0.5);
  }
  if (k < 2.5) return 0.5 + 0.5 * sin(atan(p.y, p.x) * 6.0 + t * 1.6 + length(p) * 3.0);
  if (k < 3.5) return 0.5 + 0.5 * sin(p.x * 9.0 + t * 1.2) * sin(p.y * 9.0 - t * 1.5);
  return 0.5 + 0.5 * sin(atan(p.y, p.x) * 3.0 - length(p) * 16.0 + t * 3.0);
}

float rippleRing(vec2 p, vec4 R) {
  if (R.w <= 0.0) return 0.0;
  return exp(-abs(length(p - R.xy) - R.z) * 18.0) * R.w;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  float n = uB.x;
  float cs = uSize.x / n;
  vec2 id = floor(frag / cs);
  vec2 local = fract(frag / cs) - 0.5;
  vec2 center = (id + 0.5) * cs;
  vec2 p = (center - 0.5 * uSize) / scale;
  float halfH = 0.5 * uSize.y / scale;
  float t = uA.x;
  float v = pattern(uB.z, p, t, halfH);
  if (uB.w < 0.999) {
    // Fundido entre dibujos: el panel se voltea poco a poco hacia el nuevo.
    float sweep = smoothstep(0.0, 1.0, uB.w * 1.6 - (p.x + 0.5) * 0.4 - hash12(id) * 0.2);
    v = mix(pattern(uB.y, p, t, halfH), v, sweep);
  }
  // Anillos de los golpes: invierten los discos a su paso.
  float ring = rippleRing(p, uR0) + rippleRing(p, uR1) + rippleRing(p, uR2);
  v = mix(v, 1.0 - v, clamp(ring, 0.0, 1.0));
  // Giro del disco: 0 = cara negra, PI = cara de color; cada disco con su
  // pequeño retraso para que el volteo no sea de golpe.
  float angle = 3.14159265 * smoothstep(0.42 - 0.06 * hash12(id + 3.0), 0.58, v);
  float w = abs(cos(angle));
  bool front = angle > 1.5707963;
  float rad = 0.42;
  vec2 e = vec2(local.x / max(rad * w, 0.02), local.y / rad);
  float inside = 1.0 - smoothstep(1.0 - 2.5 / cs, 1.0, length(e));
  // Panel de fondo con su rejilla y los ejes de cada disco.
  vec3 col = uC0 * (0.9 + 0.2 * hash12(id));
  col *= 1.0 - 0.25 * smoothstep(0.44, 0.5, max(abs(local.x), abs(local.y)));
  vec3 face = front ? uK.rgb * (0.85 + 0.25 * uA.y + 0.2 * uA.z) : uC2;
  // Al girar se ve más oscuro: la cara mira menos hacia nosotros.
  face *= 0.35 + 0.65 * w;
  // Brillo de la cara de color.
  if (front) face += vec3(1.0) * pow(max(0.0, 1.0 - length(e - vec2(-0.35, -0.35))), 4.0) * 0.25 * w + uC3 * 0.12 * uA.z;
  else face += uC1 * 0.02;
  float rim = smoothstep(0.8, 1.0, length(e));
  face *= 1.0 - 0.35 * rim;
  col = mix(col, face, inside);
  col *= mix(1.0, uK.w, 0.3);
  // El destello aviva los discos en lugar de cubrir la pantalla.
  col *= 1.0 + 0.4 * uD.x;
  vec2 p0 = (frag - 0.5 * uSize) / scale;
  col *= 1.0 - 0.25 * smoothstep(0.7, 1.5, length(p0 * vec2(0.9, 0.65)));
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
