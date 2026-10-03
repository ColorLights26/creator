// Luz de Bordes — resplandor de colores alrededor de la pantalla.
// Un brillo continuo recorre el contorno redondeado de la pantalla con los
// colores de la paleta en movimiento; su grosor en cada punto sigue una banda
// del espectro (graves abajo, agudos arriba, en espejo), así que el borde
// respira con la música. Cada golpe lanza dos pulsos que corren por el borde
// en sentidos opuestos y el destello lo enciende entero.
const nativeSource = r'''
class Visual final : public Scene {
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  std::array<float, 16> bands{};
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double hue = 0, pulseAge = 100;
  float pulsePower = 0, pulseStart = 0;
  Random rng{53};

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

 public:
  void reset(uint32_t seed) override {
    rng = Random(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    bands.fill(0);
    hue = rng.unit();
    pulseAge = 100;
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
    if (hit > kick + 0.2f) {
      // Pulsos desde la parte de abajo de la pantalla.
      pulseAge = 0;
      pulsePower = hit;
      pulseStart = 0.5f + (rng.unit() - 0.5f) * 0.2f;
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    hue += f.delta * f.speed * (0.04 + 0.12 * drive);
  }

  void render(const Frame& f, Canvas& c) const override {
    float amp = f.intensity;
    float age = float(pulseAge);
    float travel = age * 0.55f;
    float power = age < 1.2f ? pulsePower * std::exp(-age * 1.6f) : 0.0f;
    std::vector<float> u;
    u.reserve(36);
    u.insert(u.end(), {float(std::fmod(hue, 1000.0)), bass * amp, kick * amp, energy});
    u.insert(u.end(), {f.glow, spark * amp, flash * amp, 0.0f});
    u.insert(u.end(), {pulseStart, travel, power * amp, 0.0f});
    for (int i = 0; i < 16; i++) u.push_back(bands[i] * amp);
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("edge_glow", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'edge_glow': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // tono, graves, golpe, energía
uniform vec4 uB;   // glow, agudos, destello
uniform vec4 uP;   // inicio del pulso (0..1 del contorno), recorrido, fuerza
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
  // Contorno redondeado como las esquinas del teléfono.
  float rc = scale * 0.11;
  vec2 halfS = 0.5 * uSize - vec2(scale * 0.012);
  vec2 dq = abs(q) - halfS + rc;
  float sd = length(max(dq, 0.0)) + min(max(dq.x, dq.y), 0.0) - rc;
  float dist = max(-sd, 0.0) / scale;
  // Posición a lo largo del contorno (0 a 1) y banda en espejo: graves abajo.
  float s = atan(q.x, q.y) / TAU + 0.5;
  float b = clamp(abs(fract(s) - 0.5) * 2.0 * 15.0, 0.0, 15.0);
  // Nivel suavizado entre bandas vecinas: el borde ondula sin escalones.
  float b0 = floor(b);
  float lvl = mix(band(b0), band(min(b0 + 1.0, 15.0)), fract(b));
  float thick = min(0.010 + 0.035 * lvl + 0.010 * uA.y + 0.014 * uA.z, 0.05) * (0.6 + 0.4 * uB.x);
  float g = exp(-dist / thick) + 0.3 * exp(-dist / (thick * 2.5));
  // Pulsos que corren por el borde en ambos sentidos.
  float d1 = abs(fract(s - uP.x - uP.y + 0.5) - 0.5);
  float d2 = abs(fract(s - uP.x + uP.y + 0.5) - 0.5);
  float pulse = (exp(-d1 * d1 * 600.0) + exp(-d2 * d2 * 600.0)) * uP.z;
  vec3 hueCol = palette(s * 2.0 + uA.x);
  vec3 col = uC0;
  col += hueCol * g * (0.75 + 0.5 * uA.y + 0.3 * uB.z);
  col += vec3(1.0) * pulse * exp(-dist / (thick * 1.5)) * 0.9;
  // Reflejo tenue del brillo hacia el interior.
  col += hueCol * exp(-dist * 9.0) * 0.04 * (1.0 + uA.z);
  col += hueCol * uB.z * 0.06 * exp(-dist * 2.0);
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
