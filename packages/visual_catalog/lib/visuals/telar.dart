// Telar — una tela de colores que se teje mientras la miras.
// Los hilos de urdimbre bajan en franjas de colores simétricas y, abajo,
// la lanzadera cruza de lado a lado dejando cada pasada de trama. Según el
// ligamento, en cada cruce queda encima uno u otro hilo: tafetán (damero),
// sarga (diagonales), rombos y espiga (zigzag). La tela tejida sube como si
// se enrollara, y en Auto cada tramo de tela tiene otro ligamento y otras
// franjas de trama, como un muestrario. Cada hilo tiene volumen y sombra en
// los cruces. La energía acelera el tejido, cada golpe hace brillar la
// lanzadera y la tela, y los graves avivan los colores.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.steps('hilos', 'Hilos a lo ancho', min: 16, max: 64, value: 34),
  CreatorModifier.choice('tejido', 'Ligamento', options: ['Auto', 'Tafetán', 'Sarga', 'Rombos', 'Espiga']),
  CreatorModifier.toggle('relieve', 'Relieve', value: true),
];

const nativeSource = r'''
class Visual final : public Scene {
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double clock = 0, rows = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    clock = rng.unit() * 30.0;
    rows = rng.unit() * 400.0;
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
    clock += f.delta * f.speed;
    // Pasadas de trama por segundo.
    rows += f.delta * f.speed * (2.5 + 5.0 * drive + 3.0 * kick);
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    float amp = f.intensity;
    std::vector<float> u;
    u.reserve(24);
    u.insert(u.end(), {float(std::fmod(clock, 1000.0)), bass * amp, kick * amp, energy});
    u.insert(u.end(), {float(m.hilos), float(m.tejido), float(std::fmod(rows, 96000.0)), m.relieve ? 1.0f : 0.0f});
    u.insert(u.end(), {f.glow, flash * amp, spark * amp, 0.0f});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("loom", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'loom': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // reloj, graves, golpe, energía
uniform vec4 uB;   // hilos, ligamento, pasadas tejidas, relieve
uniform vec4 uD;   // glow, destello, agudos
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

// Paleta andina: rojo, naranja, amarillo, fucsia, turquesa y negro.
vec3 yarn(float k) {
  k = mod(k, 6.0);
  if (k < 1.0) return uC1;
  if (k < 2.0) return uC2;
  if (k < 3.0) return uC3;
  if (k < 4.0) return vec3(1.0, 0.16, 0.55);
  if (k < 5.0) return vec3(0.0, 0.72, 0.66);
  return vec3(0.07, 0.05, 0.05);
}

// ¿Queda encima la urdimbre en el cruce (i, j)?
bool warpOver(float i, float j, float mode) {
  if (mode < 0.5) return mod(i + j, 2.0) < 1.0;
  if (mode < 1.5) return mod(i + j, 4.0) < 2.0;
  if (mode < 2.5) return mod(abs(mod(i, 12.0) - 6.0) + abs(mod(j, 12.0) - 6.0), 4.0) < 2.0;
  float dir = mod(floor(i / 4.0), 2.0) < 1.0 ? 1.0 : -1.0;
  return mod(i * dir + j + 400.0, 4.0) < 2.0;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float n = uB.x;
  float tp = uSize.x / n;
  float fell = uSize.y * 0.84;
  float t = uA.x;
  vec2 cell = vec2(frag.x / tp, frag.y / tp + uB.z);
  float i = floor(cell.x);
  float j = floor(cell.y);
  vec2 fr = fract(cell);
  // Franjas de urdimbre simétricas, de tres hilos cada una.
  float wi = abs(mod(i, 30.0) - 15.0);
  vec3 warpCol = yarn(floor(wi / 3.0) + floor(i / 30.0) * 2.0);
  // Tramos de tela: cada uno con su ligamento y su secuencia de franjas.
  float section = floor(j / 48.0);
  float mode = uB.y < 0.5 ? floor(hash11(section * 3.7 + 1.0) * 4.0) : uB.y - 1.0;
  float stripe = floor(mod(j, 48.0) / 4.0);
  float sym = abs(stripe - 5.5);
  vec3 weftCol = yarn(floor(hash11(section * 7.1 + floor(sym)) * 6.0));
  vec3 col;
  float gapX = smoothstep(0.0, 0.12, fr.x) * smoothstep(1.0, 0.88, fr.x);
  float gapY = smoothstep(0.0, 0.12, fr.y) * smoothstep(1.0, 0.88, fr.y);
  float lit = 0.9 + 0.25 * uA.y;
  if (frag.y > fell) {
    // Debajo del peine sólo hay urdimbre: hilos tensos sobre el fondo.
    float prof = cos((fr.x - 0.5) * 3.14159);
    col = mix(uC0, warpCol * (0.35 + 0.75 * prof) * lit, gapX * 0.95);
    // Lanzadera que cruza de lado a lado con cada pasada.
    float pass = fract(uB.z);
    float dir = mod(floor(uB.z), 2.0) < 1.0 ? pass : 1.0 - pass;
    vec2 sh = vec2(frag.x / uSize.x - dir, (frag.y - fell - 0.05 * uSize.y) / uSize.y);
    float shuttle = exp(-dot(sh * vec2(9.0, 40.0), sh * vec2(9.0, 40.0)));
    col = mix(col, mix(vec3(0.55, 0.32, 0.12), vec3(1.0, 0.85, 0.5), 0.3 + 0.7 * uA.z), clamp(shuttle * 2.0, 0.0, 1.0));
    col += uC3 * shuttle * (0.3 + 0.8 * uA.z) * uD.x;
  } else {
    bool over = warpOver(i, j, mode);
    float relief = uB.w;
    if (over) {
      float prof = cos((fr.x - 0.5) * 3.14159);
      float along = mix(1.0, 0.75 + 0.25 * sin(fr.y * 3.14159), relief);
      col = warpCol * (0.3 + 0.8 * prof) * along * gapX;
    } else {
      float prof = cos((fr.y - 0.5) * 3.14159);
      float along = mix(1.0, 0.75 + 0.25 * sin(fr.x * 3.14159), relief);
      col = weftCol * (0.3 + 0.8 * prof) * along * gapY;
    }
    col *= lit;
    // Fibras del hilo.
    col *= 0.92 + 0.08 * hash12(floor(frag * 0.8));
    // Brillo que recorre la tela en diagonal con los golpes.
    float sheen = exp(-abs(fract((frag.x + frag.y) / uSize.y * 0.6 - t * 0.15) - 0.5) * 18.0);
    col += vec3(1.0, 0.9, 0.7) * sheen * (0.04 + 0.2 * uA.z) * uD.x;
    // Barra del peine sobre la última pasada.
    col = mix(col, vec3(0.75, 0.7, 0.62), smoothstep(5.0, 0.0, abs(frag.y - fell + 2.0)) * 0.9);
  }
  col += uC2 * uD.y * 0.05;
  vec2 p = (frag - 0.5 * uSize) / min(uSize.x, uSize.y);
  col *= 1.0 - 0.25 * smoothstep(0.7, 1.5, length(p * vec2(0.9, 0.65)));
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
