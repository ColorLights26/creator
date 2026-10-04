// Luz de Bordes 2 Transparente — llamaradas de luz que nacen en los bordes y invaden la pantalla.
// Versión overlay: mismo movimiento y reacción a la música sin fondo opaco.
// Versión con más acción: el brillo sale de todo el contorno como lenguas de
// fuego de colores que se alargan hacia el centro con su banda del espectro y
// con los graves; cada golpe lanza una onda luminosa que viaja desde el borde
// hasta el centro (hasta tres a la vez) y dos pulsos que corren por el borde,
// y el interior se tiñe de color con la energía.
const nativeSource = r'''
class Visual final : public Scene {
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  std::array<float, 16> bands{};
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double hue = 0, clock = 0, pulseAge = 100;
  std::array<double, 3> waveAge{{100.0, 100.0, 100.0}};
  std::array<float, 3> wavePower{};
  int waveNext = 0;
  float pulsePower = 0, pulseStart = 0;
  Random rng{59};

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

 public:
  void reset(uint32_t seed) override {
    rng = Random(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    bands.fill(0);
    hue = rng.unit();
    clock = 0;
    pulseAge = 100;
    waveAge = {{100.0, 100.0, 100.0}};
    wavePower.fill(0);
    waveNext = 0;
    pulsePower = 0;
    pulseStart = 0;
  }

  void update(const Frame& f) override {
    float dt = float(f.delta);
    const Music& m = f.music;
    bass = follow(bass, m.bass, 22.0f, 4.5f, dt);
    body = follow(body, m.body, 12.0f, 3.0f, dt);
    spark = follow(spark, m.spark, 30.0f, 7.0f, dt);
    energy = follow(energy, m.energy, 6.0f, 1.8f, dt);
    drive = follow(drive, m.active ? std::pow(std::clamp(m.energy, 0.0f, 1.0f), 0.8f) : 0.0f, 3.0f, 0.7f, dt);
    for (int i = 0; i < 16; i++) {
      float v = std::max(m.smoothSpectrum[std::min(2 * i, 30)], m.smoothSpectrum[std::min(2 * i + 1, 30)]);
      bands[i] = follow(bands[i], v, 28.0f, 5.0f, dt);
    }

    float hit = 0, fl = 0;
    for (const auto& e : m.events[0]) hit = std::max(hit, e.strength);
    for (const auto& e : m.events[2]) hit = std::max(hit, e.strength * 0.85f);
    for (const auto& e : m.events[3]) fl = std::max(fl, e.strength);
    float onset = std::clamp((m.bass - slowBass - 0.15f) * 2.5f, 0.0f, 1.0f);
    slowBass = follow(slowBass, m.bass, 3.0f, 3.0f, dt);
    hit = std::min(std::max(hit, onset), 1.0f);
    pulseAge += f.delta;
    for (auto& a : waveAge) a += f.delta;
    if (hit > kick + 0.2f) {
      pulseAge = 0;
      pulsePower = hit;
      pulseStart = 0.5f + (rng.unit() - 0.5f) * 0.2f;
      // Onda que entra desde el borde hacia el centro.
      waveAge[waveNext] = 0;
      wavePower[waveNext] = hit;
      waveNext = (waveNext + 1) % 3;
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    hue += f.delta * f.speed * (0.05 + 0.18 * drive);
    clock += f.delta * f.speed * (0.8 + 1.6 * drive);
  }

  void render(const Frame& f, Canvas& c) const override {
    float amp = f.intensity;
    float age = float(pulseAge);
    float power = age < 1.2f ? pulsePower * std::exp(-age * 1.6f) : 0.0f;
    std::vector<float> u;
    u.reserve(48);
    u.insert(u.end(), {float(std::fmod(hue, 1000.0)), bass * amp, kick * amp, energy});
    u.insert(u.end(), {f.glow, spark * amp, flash * amp, float(std::fmod(clock, 1000.0))});
    u.insert(u.end(), {pulseStart, age * 0.55f, power * amp, drive * amp});
    // Ondas: distancia recorrida desde el borde y fuerza que se apaga.
    std::array<float, 3> front{}, strength{};
    for (int k = 0; k < 3; k++) {
      float a = float(waveAge[k]);
      front[k] = a * 0.75f;
      strength[k] = a < 1.6f ? wavePower[k] * std::exp(-a * 1.3f) * amp : 0.0f;
    }
    u.insert(u.end(), {front[0], front[1], front[2], 0.0f});
    u.insert(u.end(), {strength[0], strength[1], strength[2], 0.0f});
    for (int i = 0; i < 16; i++) u.push_back(bands[i] * amp);
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("edge_flames", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'edge_flames': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // tono, graves, golpe, energía
uniform vec4 uB;   // glow, agudos, destello, reloj
uniform vec4 uP;   // inicio del pulso, recorrido, fuerza, intensidad de la música
uniform vec4 uWF;  // frente de las tres ondas (distancia al borde)
uniform vec4 uWS;  // fuerza de las tres ondas
uniform vec4 uS0;  // espectro en 16 bandas
uniform vec4 uS1;
uniform vec4 uS2;
uniform vec4 uS3;
uniform vec3 uC0;
uniform vec3 uC1;
uniform vec3 uC2;
uniform vec3 uC3;
out vec4 fragColor;

const float TAU = 6.2831853;

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

float band(float b) {
  vec4 s = b < 4.0 ? uS0 : (b < 8.0 ? uS1 : (b < 12.0 ? uS2 : uS3));
  float k = mod(b, 4.0);
  return k < 1.0 ? s.x : (k < 2.0 ? s.y : (k < 3.0 ? s.z : s.w));
}

vec3 palette(float x) {
  float f = fract(x) * 3.0;
  vec3 a = f < 1.0 ? uC1 : (f < 2.0 ? uC2 : uC3);
  vec3 b = f < 1.0 ? uC2 : (f < 2.0 ? uC3 : uC1);
  return mix(a, b, smoothstep(0.0, 1.0, fract(f)));
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 q = frag - 0.5 * uSize;
  float rc = scale * 0.11;
  vec2 halfS = 0.5 * uSize - vec2(scale * 0.012);
  vec2 dq = abs(q) - halfS + rc;
  float sd = length(max(dq, 0.0)) + min(max(dq.x, dq.y), 0.0) - rc;
  float dist = max(-sd, 0.0) / scale;
  float s = atan(q.x, q.y) / TAU + 0.5;
  float b = clamp(abs(fract(s) - 0.5) * 2.0 * 15.0, 0.0, 15.0);
  float b0 = floor(b);
  float lvl = mix(band(b0), band(min(b0 + 1.0, 15.0)), fract(b));
  float t = uB.w;

  // Lenguas de fuego: el alcance del brillo varía a lo largo del borde y se
  // retuerce con el tiempo, más largo con su banda, los graves y el golpe.
  // El ruido usa la dirección desde el centro: continuo en todo el contorno.
  vec2 dir = q / max(length(q), 1.0);
  float tongue = noise(dir * 5.0 + vec2(dist * 5.0 - t * 1.6, t * 0.2)) * 0.65 +
                 noise(dir * 12.0 + vec2(7.0 + dist * 9.0 - t * 2.4, -t * 0.3)) * 0.35;
  // Hacia el interior el alcance y el color dejan de depender de la banda,
  // así las llamas se funden sin formar una estrella en el centro.
  float depthMix = smoothstep(0.04, 0.28, dist);
  tongue = mix(tongue, 0.55, smoothstep(0.03, 0.2, dist));
  float lvlEff = mix(lvl, 0.5 * lvl + 0.3 * uP.w, depthMix);
  float reach = (0.03 + 0.20 * lvlEff + 0.06 * uA.y + 0.10 * uA.z + 0.03 * uP.w) * (0.55 + 1.0 * tongue);
  // En el overlay las llamas se quedan más cerca del borde.
  reach = min(reach, 0.14) * (0.6 + 0.4 * uB.x);
  float g = exp(-dist / max(reach, 0.004)) * smoothstep(0.4, 0.2, dist);
  vec3 hueCol = mix(palette(s * 2.0 + uA.x - dist * 1.5), palette(uA.x + dist * 2.5 + 0.2), depthMix);
  vec3 col = uC0;
  col += hueCol * g * (0.85 + 0.6 * uA.y + 0.3 * uB.z);
  // Núcleo blanco en el filo del borde cuando la música aprieta.
  col += vec3(1.0) * exp(-dist / 0.008) * (0.25 + 0.6 * uA.z);

  // Ondas que entran desde el borde hacia el centro con cada golpe.
  float waves = 0.0;
  waves += uWS.x * exp(-(dist - uWF.x) * (dist - uWF.x) * 260.0);
  waves += uWS.y * exp(-(dist - uWF.y) * (dist - uWF.y) * 260.0);
  waves += uWS.z * exp(-(dist - uWF.z) * (dist - uWF.z) * 260.0);
  col += palette(s * 2.0 + uA.x + 0.33) * waves * 1.1;

  // Pulsos que corren por el borde en ambos sentidos.
  float d1 = abs(fract(s - uP.x - uP.y + 0.5) - 0.5);
  float d2 = abs(fract(s - uP.x + uP.y + 0.5) - 0.5);
  float pulse = (exp(-d1 * d1 * 600.0) + exp(-d2 * d2 * 600.0)) * uP.z;
  col += vec3(1.0) * pulse * exp(-dist / 0.035) * 0.9;

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
