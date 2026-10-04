// Prisma — un haz de luz blanca que el prisma convierte en arcoíris.
// Un haz blanco baja en diagonal hasta un gran prisma de cristal, lo cruza
// tenue por dentro y sale por la otra cara abierto en un abanico enorme con
// los seis colores del arcoíris, como en la portada de un disco icónico,
// llenando la mitad de abajo de la pantalla. Por el abanico corren pulsos de
// luz; el haz late con los graves, el abanico se abre con la energía, cada
// color se enciende y se alarga con su banda del espectro (de graves a
// agudos) y cada golpe manda una onda de luz por el arcoíris y hace
// destellar las aristas del cristal.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.slider('apertura', 'Apertura del arcoíris', min: .5, max: 1.8, value: 1),
  CreatorModifier.slider('grosor', 'Grosor del haz', min: .5, max: 2, value: 1),
  CreatorModifier.toggle('espectro', 'Colores con la música', value: true),
  CreatorModifier.toggle('giro', 'Giro lento', value: false),
];

const nativeSource = r'''
class Visual final : public Scene {
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  std::array<float, 6> bands{};
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double clock = 0, spin = 0, sinceKick = 100;
  float kickPower = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    bands.fill(0);
    clock = rng.unit() * 50.0;
    spin = 0;
    sinceKick = 100;
    kickPower = 0;
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
    // Seis bandas del espectro, una por color (rojo = graves, violeta = agudos).
    for (int i = 0; i < 6; i++) {
      float v = 0;
      for (int k = i * 5; k < i * 5 + 6 && k < 31; k++) v = std::max(v, mu.smoothSpectrum[k]);
      bands[size_t(i)] = follow(bands[size_t(i)], v, 25.0f, 5.0f, dt);
    }

    float hit = 0, fl = 0;
    for (const auto& e : mu.events[0]) hit = std::max(hit, e.strength);
    for (const auto& e : mu.events[2]) hit = std::max(hit, e.strength * 0.85f);
    for (const auto& e : mu.events[3]) fl = std::max(fl, e.strength);
    float onset = std::clamp((mu.bass - slowBass - 0.15f) * 2.5f, 0.0f, 1.0f);
    slowBass = follow(slowBass, mu.bass, 3.0f, 3.0f, dt);
    hit = std::min(std::max(hit, onset), 1.0f);
    sinceKick += f.delta;
    if (hit > kick + 0.2f) {
      sinceKick = 0;
      kickPower = hit;
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    clock += f.delta * f.speed;
    if (m.giro) spin += f.delta * f.speed * (0.05 + 0.1 * drive);
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    float amp = f.intensity;
    float on = m.espectro ? 1.0f : 0.0f;
    std::vector<float> u;
    u.reserve(32);
    u.insert(u.end(), {float(std::fmod(clock, 1000.0)), bass * amp, kick * amp, energy});
    u.insert(u.end(), {m.apertura, m.grosor, on, float(std::fmod(spin, 6.2831853))});
    u.insert(u.end(), {bands[0] * amp, bands[1] * amp, bands[2] * amp, bands[3] * amp});
    u.insert(u.end(), {bands[4] * amp, bands[5] * amp, f.glow, flash * amp});
    float wave = sinceKick < 2.5 ? float(sinceKick) * 1.4f : 10.0f;
    u.insert(u.end(), {drive, wave, kickPower * amp, spark * amp});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("prism_light", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'prism_light': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // reloj, graves, golpe, energía
uniform vec4 uB;   // apertura, grosor del haz, colores con la música, giro
uniform vec4 uS0;  // bandas rojo, naranja, amarillo, verde
uniform vec4 uS1;  // bandas azul, violeta, glow, destello
uniform vec4 uE;   // música activa, onda del golpe, fuerza, agudos
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

// Distancia con signo a un triángulo (negativa dentro).
float sdTriangle(vec2 p, vec2 a, vec2 b, vec2 c) {
  vec2 e0 = b - a;
  vec2 e1 = c - b;
  vec2 e2 = a - c;
  vec2 v0 = p - a;
  vec2 v1 = p - b;
  vec2 v2 = p - c;
  vec2 pq0 = v0 - e0 * clamp(dot(v0, e0) / dot(e0, e0), 0.0, 1.0);
  vec2 pq1 = v1 - e1 * clamp(dot(v1, e1) / dot(e1, e1), 0.0, 1.0);
  vec2 pq2 = v2 - e2 * clamp(dot(v2, e2) / dot(e2, e2), 0.0, 1.0);
  float s = sign(e0.x * e2.y - e0.y * e2.x);
  vec2 d = min(min(vec2(dot(pq0, pq0), s * (v0.x * e0.y - v0.y * e0.x)),
                   vec2(dot(pq1, pq1), s * (v1.x * e1.y - v1.y * e1.x))),
               vec2(dot(pq2, pq2), s * (v2.x * e2.y - v2.y * e2.x)));
  return -sqrt(d.x) * sign(d.y);
}

vec3 rainbow(int i) {
  return i == 0 ? vec3(1.0, 0.1, 0.1) : (i == 1 ? vec3(1.0, 0.5, 0.0) : (i == 2 ? vec3(1.0, 0.92, 0.1)
       : (i == 3 ? vec3(0.15, 0.9, 0.25) : (i == 4 ? vec3(0.15, 0.4, 1.0) : vec3(0.6, 0.2, 1.0)))));
}

float bandLevel(int i) {
  return i == 0 ? uS0.x : (i == 1 ? uS0.y : (i == 2 ? uS0.z : (i == 3 ? uS0.w : (i == 4 ? uS1.x : uS1.y))));
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  float halfH = 0.5 * uSize.y / scale;
  // Prisma grande en la parte de arriba; el arcoíris baja y llena el resto.
  vec2 O = vec2(-0.08, -min(halfH * 0.42, 0.42));
  vec2 q = p - O;
  float cs = cos(uB.w);
  float sn = sin(uB.w);
  q = vec2(cs * q.x - sn * q.y, sn * q.x + cs * q.y);
  float R = 0.3;
  vec2 A = vec2(0.0, -R);
  vec2 B = vec2(-R * 0.866, R * 0.5);
  vec2 C = vec2(R * 0.866, R * 0.5);
  float tri = sdTriangle(q, A, B, C);
  // Entrada en la cara izquierda y salida en la derecha.
  vec2 E = mix(A, B, 0.5);
  vec2 X = mix(A, C, 0.58);
  vec2 S = E + vec2(-2.0, -0.95);
  float bassPulse = 1.0 + 0.6 * uA.y + 0.5 * uA.z;
  vec3 col = uC0;

  // Haz blanco que entra.
  float beamW = 0.005 * uB.y * bassPulse;
  float dBeam = segment(q, S, E);
  col += uC1 * (exp(-dBeam / beamW) + 0.3 * exp(-dBeam / (beamW * 6.0))) * uS1.z;

  // Abanico del arcoíris que sale por la cara derecha, hacia abajo.
  vec2 v = q - X;
  float dist = length(v);
  float a = atan(v.y, v.x);
  float a0 = 0.58;
  float spread = 0.72 * uB.x * (1.0 + 0.2 * uA.w + 0.12 * uA.z);
  // Ángulo relativo al centro del abanico, sin el salto de atan detrás.
  float off = a - (a0 + 0.5 * spread);
  off = mod(off + 3.14159265, 6.2831853) - 3.14159265;
  float tf = off / spread + 0.5;
  float music = uB.z * uE.x;
  if (tri > 0.0 && dist > 0.0) {
    float tt = clamp(tf, 0.0, 0.9999);
    int band = int(tt * 6.0);
    float bl = bandLevel(band);
    float inside = smoothstep(-0.015, 0.0, tf) * smoothstep(1.015, 1.0, tf);
    float level = mix(1.0, 0.15 + 1.8 * bl, music);
    // Cada color llega más lejos cuanto más suena su banda.
    float reach = mix(9.0, 0.2 + 1.7 * bl, music);
    float fade = 1.0 - smoothstep(reach * 0.7, reach, dist);
    float within = fract(tt * 6.0);
    float soft = smoothstep(0.0, 0.06, within) * smoothstep(1.0, 0.94, within) * 0.2 + 0.8;
    // Pulsos de luz que corren hacia fuera y la onda de cada golpe.
    float pulses = 0.85 + 0.15 * sin(dist * 22.0 - uA.x * 5.0 + float(band) * 0.7);
    float wave = exp(-abs(dist - uE.y) * 7.0) * uE.z;
    float lit = inside * level * soft * pulses * fade * (1.0 + 2.5 * wave) * uS1.z;
    col += rainbow(band) * lit * smoothstep(0.0, 0.04, dist);
    // Halo suave alrededor del abanico.
    float out_ = max(-tf, tf - 1.0);
    float halo = exp(-out_ * 6.0) * (1.0 - inside) * fade;
    col += rainbow(tf < 0.5 ? 0 : 5) * halo * 0.18;
    // Luz difusa del arcoíris sobre todo el fondo.
    float aside = max(abs(off) - 0.5 * spread, 0.0);
    col += mix(rainbow(2), rainbow(4), clamp(tf, 0.0, 1.0)) * 0.05 * exp(-dist * 0.8) * exp(-aside * 2.5) * (1.0 + uA.y);
  }

  // Cristal del prisma: relleno tenue, haz interior y aristas que destellan.
  if (tri < 0.0) {
    col += uC2 * 0.06 + uC3 * 0.06 * smoothstep(-0.15, 0.0, tri);
    float dInner = segment(q, E, X);
    vec3 inner = mix(uC1, vec3(0.9, 0.85, 1.0), 0.5);
    col += inner * exp(-dInner / (beamW * 2.5)) * 0.55;
    // Reflejos de colores dentro del cristal.
    col += rainbow(int(mod(floor((q.x + q.y) * 18.0 + uA.x * 0.5), 6.0))) * 0.035 * smoothstep(-0.1, 0.0, tri);
  }
  float edge = abs(tri);
  col += uC2 * (exp(-edge / 0.003) * 0.85 + exp(-edge / 0.015) * 0.22) * (0.7 + 1.2 * uA.z + 0.5 * uS1.w);
  // Brillos en los vértices.
  col += uC1 * exp(-dot(q - A, q - A) * 1500.0) * (0.5 + 0.9 * uA.z);
  col += uC1 * exp(-dot(q - X, q - X) * 900.0) * (0.3 + 0.6 * uA.y);
  // Motas de polvo en el haz y destellos en el arcoíris con los agudos.
  if (dBeam < beamW * 30.0) {
    float dust = step(0.993, hash12(floor(frag * 0.5) + floor(uA.x * 3.0))) * exp(-dBeam / (beamW * 6.0));
    col += uC1 * dust * 0.6;
  }
  if (uE.w > 0.02 && tri > 0.0 && tf > 0.0 && tf < 1.0) {
    col += uC1 * step(0.997, hash12(floor(frag * 0.4) + floor(uA.x * 7.0))) * uE.w * 0.6;
  }
  col *= 1.0 - 0.3 * smoothstep(0.8, 1.6, length(p * vec2(0.9, 0.6)));
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
