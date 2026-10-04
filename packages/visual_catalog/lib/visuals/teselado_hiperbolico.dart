// Teselado Hiperbólico — un mosaico infinito dentro de un círculo.
// Como en los grabados Circle Limit de Escher, el disco de Poincaré se llena
// de polígonos regulares que se encogen sin fin hacia el borde: cada píxel se
// refleja hasta caer en el triángulo base y su número de reflejos da el color
// (rojo o negro), con bordes dorados entre piezas. El mosaico gira y fluye
// por el plano hiperbólico; cada golpe lo empuja, los graves encienden los
// bordes y en Auto el patrón (3·7, 4·5, 5·4, 6·4 u 8·3) cambia cada ocho golpes.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.choice('patron', 'Patrón', options: ['Auto', '3·7', '4·5', '5·4', '6·4', '8·3']),
  CreatorModifier.slider('flujo', 'Flujo', min: 0, max: 2, value: 1),
  CreatorModifier.slider('tamano', 'Tamaño del disco', min: .8, max: 2.2, value: 1.45),
  CreatorModifier.toggle('bordes', 'Bordes dorados', value: true),
];

const nativeSource = r'''
class Visual final : public Scene {
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double spin = 0, wander = 0, sinceSwitch = 0;
  float push = 0, pushVel = 0;
  int beats = 0, autoIndex = 1;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    spin = rng.unit() * 6.2831853;
    wander = rng.unit() * 6.2831853;
    sinceSwitch = 0;
    push = pushVel = 0;
    beats = 0;
    autoIndex = 1;
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
    sinceSwitch += f.delta;
    if (hit > kick + 0.2f) {
      beats++;
      pushVel += 1.4f * hit;
      if (beats % 8 == 0) {
        autoIndex = autoIndex % 5 + 1;
        sinceSwitch = 0;
      }
    }
    if (!mu.active && sinceSwitch > 12.0) {
      autoIndex = autoIndex % 5 + 1;
      sinceSwitch = 0;
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    pushVel += (-push * 12.0f - pushVel * 3.5f) * dt;
    push += pushVel * dt;
    spin += f.delta * f.speed * m.flujo * (0.08 + 0.25 * drive);
    wander += f.delta * f.speed * m.flujo * (0.15 + 0.3 * drive);
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    float amp = f.intensity;
    static const float ps[6] = {4, 3, 4, 5, 6, 8};
    static const float qs[6] = {5, 7, 5, 4, 4, 3};
    int idx = m.patron == 0 ? autoIndex : m.patron;
    // Traslación hiperbólica: deriva lenta más el empujón del golpe.
    float t = 0.28f * float(std::sin(wander)) + 0.25f * std::max(-0.3f, push);
    std::vector<float> u;
    u.reserve(28);
    u.insert(u.end(), {float(std::fmod(spin, 6.2831853)), bass * amp, kick * amp, energy});
    u.insert(u.end(), {ps[idx], qs[idx], std::clamp(t, -0.6f, 0.6f), float(std::sin(wander * 0.7)) * 0.2f});
    u.insert(u.end(), {m.bordes ? 1.0f : 0.0f, f.glow, flash * amp, spark * amp});
    // El disco puede ser más ancho que la pantalla, pero no más alto.
    float radius = std::min(0.49f * std::min(f.width, f.height) * m.tamano, 0.48f * std::max(f.width, f.height));
    u.insert(u.end(), {radius, 0.0f, 0.0f, 0.0f});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("hyperbolic", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'hyperbolic': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // giro, graves, golpe, energía
uniform vec4 uB;   // p, q, traslación en x, traslación en y
uniform vec4 uD;   // bordes, glow, destello, agudos
uniform vec4 uE;   // radio del disco en píxeles
uniform vec3 uC0;
uniform vec3 uC1;
uniform vec3 uC2;
uniform vec3 uC3;
out vec4 fragColor;

const float PI = 3.14159265;

float hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

vec2 cmul(vec2 a, vec2 b) { return vec2(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x); }
vec2 cdiv(vec2 a, vec2 b) { return vec2(a.x * b.x + a.y * b.y, a.y * b.x - a.x * b.y) / dot(b, b); }

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 z = (frag - 0.5 * uSize) / uE.x;
  float r = length(z);
  vec3 col = uC0;
  if (r < 1.0) {
    // Giro y traslación hiperbólica (Möbius): el mosaico fluye por el disco.
    float cs = cos(uA.x);
    float sn = sin(uA.x);
    z = vec2(cs * z.x - sn * z.y, sn * z.x + cs * z.y);
    vec2 a = uB.zw;
    z = cdiv(z + a, vec2(1.0, 0.0) + cmul(vec2(a.x, -a.y), z));
    // Triángulo base: ángulo pi/p en el centro y pi/q en el vértice exterior.
    float A = PI / uB.x;
    float Bq = PI / uB.y;
    float c = 1.0 / sqrt(1.0 - sin(A) * sin(A) / (cos(Bq) * cos(Bq)));
    float rr = c * sin(A) / cos(Bq);
    vec2 C = vec2(c, 0.0);
    float flips = 0.0;
    for (int i = 0; i < 48; i++) {
      float ang = atan(z.y, z.x);
      float len = length(z);
      ang = mod(ang, 2.0 * A);
      if (ang > A) {
        ang = 2.0 * A - ang;
        flips += 1.0;
      }
      z = len * vec2(cos(ang), sin(ang));
      vec2 d = z - C;
      float dd = dot(d, d);
      if (dd < rr * rr) {
        z = C + rr * rr * d / dd;
        flips += 1.0;
      } else {
        break;
      }
    }
    // Distancias a los lados del triángulo base.
    float dCircle = abs(length(z - C) - rr);
    float dAxis = abs(z.y);
    float dRay = abs(dot(z, vec2(-sin(A), cos(A))));
    float parity = mod(flips, 2.0);
    // Pieza: polígono centrado en el origen; color por la paridad de su teja.
    float center = length(z);
    vec3 tile = mix(uC1, uC2, parity);
    tile *= 0.65 + 0.35 * smoothstep(0.9, 0.0, center);
    tile += uC3 * exp(-dAxis * 60.0) * 0.08 + uC3 * exp(-dRay * 60.0) * 0.08;
    // Bordes dorados entre piezas (el lado curvo es el borde del polígono).
    float edge = exp(-dCircle * 90.0);
    tile += uC3 * edge * (0.7 + 0.8 * uA.y + 1.0 * uA.z) * uD.x * uD.y;
    // Destellos en las piezas con los agudos.
    tile += uC3 * step(0.996 - 0.01 * uD.w, hash12(floor(frag * 0.4) + floor(uA.x * 20.0))) * uD.w * 0.5;
    // Hacia el borde las piezas se vuelven diminutas: se funden suavemente.
    float rim = smoothstep(1.0, 0.86, r);
    col = mix(mix(uC1, uC2, 0.5) * 0.4, tile, rim);
  }
  // Aro dorado del disco.
  col += uC3 * exp(-abs(r - 1.0) * 120.0) * (0.6 + 0.8 * uA.z);
  col += uC3 * exp(-max(r - 1.0, 0.0) * 6.0) * step(1.0, r) * (0.08 + 0.1 * uA.y);
  col += uC1 * uD.z * 0.05;
  col += (hash12(frag) - 0.5) / 255.0;
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
