// Placa de Circuitos Transparente — energía que recorre las pistas de una placa.
// Versión overlay: mismo movimiento y reacción a la música sin fondo opaco.
// La pantalla es una placa de circuito impreso generada al vuelo: pistas de
// cobre ámbar en horizontal y vertical que giran con chaflanes a 45°, pads
// redondos en los extremos, vías en los cruces y chips con sus patas. Por
// cada pista corren paquetes de datos en su propio sentido. En el centro hay
// un procesador cuyo núcleo late con los graves; cada golpe dispara desde él
// una onda de energía que avanza por la placa como por las pistas y enciende
// todo a su paso.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.steps('celdas', 'Pistas a lo ancho', min: 8, max: 20, value: 12),
  CreatorModifier.toggle('paquetes', 'Paquetes de datos', value: true),
  CreatorModifier.toggle('ondas', 'Ondas de energía', value: true),
  CreatorModifier.toggle('chips', 'Chips', value: true),
];

const nativeSource = r'''
class Visual final : public Scene {
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double clock = 0, sinceIdle = 0;
  std::array<double, 2> waveAge{100, 100};
  std::array<float, 2> wavePower{0, 0};
  int nextWave = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  void fire(float power) {
    waveAge[size_t(nextWave)] = 0;
    wavePower[size_t(nextWave)] = power;
    nextWave = (nextWave + 1) % 2;
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    clock = rng.unit() * 30.0;
    sinceIdle = 0;
    waveAge = {100, 100};
    wavePower = {0, 0};
    nextWave = 0;
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
    sinceIdle += f.delta;
    if (hit > kick + 0.2f) {
      fire(0.6f + 0.5f * hit);
      sinceIdle = 0;
    }
    if (!mu.active && sinceIdle > 3.0) {
      fire(0.6f);
      sinceIdle -= 3.0;
    }
    for (auto& a : waveAge) a += f.delta * f.speed;
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    clock += f.delta * f.speed * (0.5 + 1.3 * drive);
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    float amp = f.intensity;
    std::vector<float> u;
    u.reserve(28);
    u.insert(u.end(), {float(std::fmod(clock, 1000.0)), bass * amp, kick * amp, energy});
    u.insert(u.end(), {float(m.celdas), m.paquetes ? 1.0f : 0.0f, m.ondas ? 1.0f : 0.0f, m.chips ? 1.0f : 0.0f});
    u.insert(u.end(), {float(waveAge[0]) * 0.75f, waveAge[0] < 3.0 ? wavePower[0] * amp : 0.0f,
                       float(waveAge[1]) * 0.75f, waveAge[1] < 3.0 ? wavePower[1] * amp : 0.0f});
    u.insert(u.end(), {f.glow, flash * amp, spark * amp, 0.0f});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("pcb", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'pcb': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // reloj, graves, golpe, energía
uniform vec4 uB;   // celdas, paquetes, ondas, chips
uniform vec4 uW;   // onda 1: radio, fuerza; onda 2: radio, fuerza
uniform vec4 uD;   // glow, destello, agudos
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

float segment(vec2 p, vec2 a, vec2 b) {
  vec2 pa = p - a;
  vec2 ba = b - a;
  float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
  return length(pa - ba * h);
}

// ¿Hay pista entre esta celda y la de la derecha / la de arriba?
float edgeH(vec2 c) { return step(0.42, hash12(c + 0.13)); }
float edgeV(vec2 c) { return step(0.48, hash12(c + 7.31)); }

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  float cells = uB.x;
  vec2 g = p * cells + 0.5;
  vec2 id = floor(g);
  vec2 f = fract(g) - 0.5;
  float pxg = cells / scale;
  float t = uA.x;
  // Vecinos: derecha, izquierda, arriba, abajo.
  float r = edgeH(id);
  float l = edgeH(id - vec2(1.0, 0.0));
  float u = edgeV(id);
  float d = edgeV(id - vec2(0.0, 1.0));
  float degree = r + l + u + d;
  float dist = 9.0;
  float along = 0.0;
  bool lShape = degree == 2.0 && r + l == 1.0;
  if (lShape) {
    // Codo con chaflán a 45°, como en las placas reales.
    vec2 a = vec2(r > 0.5 ? 0.5 : -0.5, 0.0);
    vec2 b = vec2(0.0, u > 0.5 ? 0.5 : -0.5);
    vec2 a2 = a * 0.35;
    vec2 b2 = b * 0.35;
    float d1 = segment(f, a, a2);
    float d2 = segment(f, a2, b2);
    float d3 = segment(f, b2, b);
    dist = min(d1, min(d2, d3));
    along = d2 < min(d1, d3) ? (g.x + g.y) * 0.7 : (d1 < d3 ? g.x : g.y);
  } else {
    if (r > 0.5) { float dd = segment(f, vec2(0.0), vec2(0.5, 0.0)); if (dd < dist) { dist = dd; along = g.x; } }
    if (l > 0.5) { float dd = segment(f, vec2(0.0), vec2(-0.5, 0.0)); if (dd < dist) { dist = dd; along = g.x; } }
    if (u > 0.5) { float dd = segment(f, vec2(0.0), vec2(0.0, 0.5)); if (dd < dist) { dist = dd; along = g.y; } }
    if (d > 0.5) { float dd = segment(f, vec2(0.0), vec2(0.0, -0.5)); if (dd < dist) { dist = dd; along = g.y; } }
  }
  float trackW = 0.07;
  float track = 1.0 - smoothstep(trackW - pxg, trackW + pxg, dist);
  float halo = exp(-dist / 0.12);
  // Pads en los extremos y vías en los cruces.
  float rc = length(f);
  float pad = 0.0;
  float hole = 0.0;
  if (degree == 1.0 || degree >= 3.0) {
    float pr = degree == 1.0 ? 0.17 : 0.13;
    pad = 1.0 - smoothstep(pr - pxg, pr + pxg, rc);
    hole = 1.0 - smoothstep(0.06 - pxg, 0.06 + pxg, rc);
  }

  // Ondas de energía desde el procesador, con distancia "de pista".
  float manhattan = abs(p.x) + abs(p.y);
  float wave = 0.0;
  if (uB.z > 0.5) {
    wave += uW.y * exp(-abs(manhattan - uW.x) * 14.0);
    wave += uW.w * exp(-abs(manhattan - uW.z) * 14.0);
  }
  // Paquetes de datos que corren por cada pista en su sentido.
  float packet = 0.0;
  if (uB.y > 0.5) {
    float h = hash12(id * 1.7 + 3.0);
    float dir = h > 0.5 ? 1.0 : -1.0;
    float run = fract(along * 0.5 - t * (0.6 + 0.8 * h) * dir + h * 7.0);
    packet = smoothstep(0.0, 0.05, run) * smoothstep(0.22, 0.05, run) * step(0.35, hash12(id + 11.0));
  }

  // Placa: fibra de vidrio oscura con trama fina.
  vec3 col = uC0 + vec3(0.025, 0.018, 0.01) * (0.6 + 0.4 * sin(frag.x * 0.9) * sin(frag.y * 0.9));
  float energyLit = wave * 1.6 + packet * 1.4 + 0.25 * uA.y;
  vec3 copper = uC1 * (0.32 + 0.25 * uA.w);
  vec3 hot = mix(uC2, uC3, clamp(wave + packet * 0.6, 0.0, 1.0));
  col += uC1 * halo * (0.04 + 0.25 * wave + 0.1 * packet) * uD.x;
  col = mix(col, copper + hot * energyLit, max(track, pad));
  col = mix(col, uC0 * 0.6, hole);

  // Chips con patas.
  if (uB.w > 0.5) {
    float chipH = hash12(id + 21.7);
    bool isChip = chipH < 0.07 && length(id) > 2.5;
    if (isChip) {
      vec2 q = abs(f);
      float body = step(max(q.x, q.y), 0.3);
      float pins = step(q.x, 0.38) * step(q.y, 0.38) * (1.0 - body) * step(0.5, fract((f.x + f.y) * 10.0));
      col = mix(col, uC1 * (0.5 + 1.2 * wave), pins);
      col = mix(col, vec3(0.03, 0.025, 0.02) + uC2 * 0.08 * (0.5 + 0.5 * sin(t * 3.0 + chipH * 50.0)), body);
      col += uC3 * body * step(max(abs(f.x + 0.18), abs(f.y - 0.18)), 0.03) * (0.3 + wave);
    }
  }
  // Procesador central.
  vec2 cq = abs(p) * cells;
  float cpu = step(max(cq.x, cq.y), 1.1);
  float cpuPins = step(max(cq.x, cq.y), 1.35) * (1.0 - cpu) * step(0.5, fract(max(cq.x, cq.y) > cq.y + 0.001 ? cq.y * 5.0 : cq.x * 5.0));
  col = mix(col, uC1 * (0.6 + 1.5 * uA.z), cpuPins);
  float core = exp(-length(cq) * 1.6) * (0.5 + 0.8 * uA.y + 1.2 * uA.z);
  col = mix(col, vec3(0.04, 0.03, 0.02) + mix(uC2, uC3, 0.4) * core, cpu);
  col += uC2 * exp(-length(cq) * 0.7) * (0.06 + 0.2 * uA.z) * uD.x;

  // El destello aviva la placa en lugar de cubrir la pantalla.
  col *= 1.0 + 0.4 * uD.y;
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
