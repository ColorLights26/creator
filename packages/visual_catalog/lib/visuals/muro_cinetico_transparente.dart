// Muro Cinético Transparente — fachada de plaquitas metálicas que se mecen con el viento.
// Versión overlay: mismo movimiento y reacción a la música sin fondo opaco.
// Miles de plaquitas de plata cuelgan de su borde superior; el viento las
// inclina en olas que recorren la pared y cada una refleja el entorno según
// su ángulo: casi todas grises, algunas encendidas en verde menta y otras con
// el destello blanco del sol. Cada golpe es una ráfaga que cruza la pared de
// lado a lado, los graves agitan las plaquitas y los agudos hacen saltar
// destellos sueltos.
const nativeSource = r'''
class Visual final : public Scene {
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double wind = 0, sun = 0, gustAge = 100, nextGust = 2.0, clock = 0;
  float gustPower = 0, gustDir = 1;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    wind = rng.unit() * 20.0;
    sun = rng.unit() * 6.2831853;
    gustAge = 100;
    nextGust = 2.0;
    clock = 0;
    gustPower = 0;
    gustDir = 1;
  }

  void update(const Frame& f) override {
    float dt = float(f.delta);
    const Music& m = f.music;
    bass = follow(bass, m.bass, 22.0f, 4.5f, dt);
    body = follow(body, m.body, 12.0f, 3.0f, dt);
    spark = follow(spark, m.spark, 30.0f, 7.0f, dt);
    energy = follow(energy, m.energy, 6.0f, 1.8f, dt);
    drive = follow(drive, m.active ? std::pow(std::clamp(m.energy, 0.0f, 1.0f), 0.8f) : 0.0f, 3.0f, 0.7f, dt);

    float hit = 0, fl = 0;
    for (const auto& e : m.events[0]) hit = std::max(hit, e.strength);
    for (const auto& e : m.events[2]) hit = std::max(hit, e.strength * 0.85f);
    for (const auto& e : m.events[3]) fl = std::max(fl, e.strength);
    float onset = std::clamp((m.bass - slowBass - 0.15f) * 2.5f, 0.0f, 1.0f);
    slowBass = follow(slowBass, m.bass, 3.0f, 3.0f, dt);
    hit = std::min(std::max(hit, onset), 1.0f);
    clock += f.delta;
    gustAge += f.delta;
    if (hit > kick + 0.2f) {
      // Ráfaga: cruza la pared alternando el sentido.
      gustAge = 0;
      gustPower = 0.6f + 0.6f * hit;
      gustDir = -gustDir;
    }
    // En silencio: ráfagas suaves en horarios fijos.
    if (!m.active) {
      if (clock >= nextGust) {
        gustAge = clock - nextGust;
        gustPower = 0.55f;
        gustDir = -gustDir;
        nextGust += 4.0;
      }
    } else {
      nextGust = clock + 3.0;
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    wind += f.delta * f.speed * (0.5 + 1.1 * drive + 0.4 * bass);
    sun += f.delta * f.speed * 0.12;
  }

  void render(const Frame& f, Canvas& c) const override {
    float amp = f.intensity;
    float aspect = f.width / std::max(1.0f, std::min(f.width, f.height));
    // Frente de la ráfaga en unidades del lado corto, de un borde al otro.
    float age = float(gustAge);
    float span = aspect + 0.6f;
    float front = gustDir > 0 ? -0.3f + age * 1.4f : aspect + 0.3f - age * 1.4f;
    float power = age < span / 1.4f + 0.5f ? gustPower * std::exp(-age * 0.5f) : 0.0f;
    std::vector<float> u;
    u.reserve(24);
    u.insert(u.end(), {float(std::fmod(wind, 1000.0)), bass * amp, kick * amp, energy});
    u.insert(u.end(), {front, power * amp, 0.5f + 0.18f * float(std::sin(sun)), f.glow});
    u.insert(u.end(), {spark * amp, flash * amp, std::clamp(f.detail, 0.25f, 2.0f), float(std::fmod(clock, 1000.0))});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("kinetic_wall", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'kinetic_wall': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // viento, graves, golpe, energía
uniform vec4 uB;   // frente de la ráfaga, fuerza, altura del sol, glow
uniform vec4 uD;   // agudos, destello, detalle, reloj
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

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  // Retícula de rombos: escamas colgadas de su esquina superior en filas
  // alternas, como las lentejuelas de una fachada cinética.
  float pitch = scale / (12.0 + 5.0 * uD.z);
  vec2 rot = vec2(frag.x + frag.y, frag.y - frag.x) * 0.70710678 / pitch;
  vec2 cellR = floor(rot);
  vec2 centerR = cellR + 0.5;
  vec2 c = vec2(centerR.x - centerR.y, centerR.x + centerR.y) * 0.70710678 * pitch;
  float R = pitch * 0.70710678;
  vec2 d = frag - c;
  vec2 q = c / scale;
  float t = uA.x;

  // Inclinación de cada escama: olas de viento que viajan, ráfaga del golpe
  // y un aleteo propio.
  float w = noise(q * vec2(2.2, 1.4) + vec2(-t * 0.7, t * 0.18)) - 0.5;
  w += 0.5 * (noise(q * 5.0 + vec2(t * 1.3, -t * 0.4)) - 0.5);
  float h = hash12(cellR);
  float flutter = (h - 0.5) * 0.25 * sin(uD.w * (5.0 + 4.0 * h) + h * 40.0);
  float gust = uB.y * exp(-(q.x - uB.x) * (q.x - uB.x) * 14.0) * (0.8 + 0.4 * noise(q * 3.0 + t));
  float tilt = w * (1.1 + 0.9 * uA.y) + gust * 1.2 + flutter * (1.0 + uA.y);

  // La escama cuelga de su esquina superior: al inclinarse se ve más corta.
  float ct = max(abs(cos(tilt)), 0.06);
  float yp = (d.y + R) / ct - R;
  float shape = abs(d.x) + abs(yp);
  float inside = 1.0 - smoothstep(R * 0.84, R * 0.9, shape);
  // Reflejo: la escama es levemente curva y la luz se desliza por ella.
  float ry = sin(2.0 * tilt) + (yp / R) * 0.15;
  float band = exp(-(ry - 0.3) * (ry - 0.3) * 16.0);
  float sunHit = exp(-(ry - uB.z) * (ry - uB.z) * 45.0);
  float env = smoothstep(-1.0, 1.0, -ry);
  vec3 plate = uC2 * (0.06 + 0.16 * env) * (0.85 + 0.3 * h);
  plate += uC1 * band * (0.35 + 0.35 * uA.y + 0.5 * uA.z) * uB.w;
  plate += uC3 * sunHit * (0.85 + 1.0 * uA.z + 0.6 * uD.x);
  // Bisel: el canto de la escama atrapa algo más de luz.
  float rim = smoothstep(R * 0.68, R * 0.86, shape);
  plate += uC2 * rim * (0.08 + 0.25 * sunHit + 0.15 * band);
  // Destellos sueltos con los agudos y fogonazo del destello sobre el metal.
  float tw = step(0.992 - 0.012 * uD.x, hash12(cellR + floor(uD.w * 7.0)));
  plate += uC3 * tw * uD.x * 0.9;
  plate += uC2 * uD.y * 0.25;
  // Pared oscura con la sombra de la escama debajo.
  float shadow = 1.0 - 0.5 * smoothstep(R * 1.1, R * 0.6, abs(d.x) + abs(yp - R * 0.18));
  vec3 col = uC0 * 0.7 * shadow;
  col = mix(col, plate, inside);
  col *= 1.0 - 0.35 * smoothstep(0.6, 1.4, length((frag - 0.5 * uSize) / scale * vec2(0.9, 0.65)));
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
