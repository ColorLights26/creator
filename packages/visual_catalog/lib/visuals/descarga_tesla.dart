// Descarga Tesla — plasma eléctrico a pantalla completa.
// Desde un núcleo de energía, ocho rayos ramificados recorren la pantalla hasta
// sus bordes como si toda ella fuera el cristal del globo. Cada rayo sigue una
// banda del espectro, cada golpe los hace saltar a nuevas posiciones con un
// estallido de luz y los agudos añaden chisporroteo.
const nativeSource = r'''
class Visual final : public Scene {
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  std::array<float, 8> bands{}, base{}, seeds{}, power{};
  float phase = 0;
  Random rng{3};

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

 public:
  void reset(uint32_t seed) override {
    rng = Random(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    bands.fill(0);
    power.fill(0);
    for (int i = 0; i < 8; i++) {
      base[i] = rng.unit() * 6.2831853f;
      seeds[i] = rng.unit() * 10.0f;
    }
    phase = rng.unit() * 10.0f;
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
    bool strike = hit > kick + 0.2f;
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));

    static const int edges[9] = {0, 3, 6, 9, 13, 17, 21, 26, 31};
    for (int b = 0; b < 8; b++) {
      float v = 0;
      for (int i = edges[b]; i < edges[b + 1]; i++) v = std::max(v, m.smoothSpectrum[i]);
      bands[b] = follow(bands[b], v, 22.0f, 4.0f, dt);
    }

    for (int i = 0; i < 8; i++) {
      // Tres filamentos siempre vivos; el resto aparece con su banda.
      float target = (i < 4 ? 0.5f : 0.0f) + bands[i] * 1.1f + kick * (i < 6 ? 0.7f : 0.4f);
      power[i] = follow(power[i], target, 25.0f, 5.0f, dt);
      if (strike) base[i] += (rng.unit() - 0.5f) * 2.2f;
      base[i] += dt * f.speed * (i % 2 ? 1.0f : -1.0f) * (0.08f + 0.25f * drive);
    }
    phase += dt * f.speed * (0.6f + 1.6f * drive + 1.2f * kick);
  }

  void render(const Frame& f, Canvas& c) const override {
    float amp = f.intensity;
    std::array<float, 8> angle{};
    for (int i = 0; i < 8; i++) angle[i] = base[i] + std::sin(phase * 0.35f + seeds[i]) * 0.45f;
    std::vector<float> u;
    u.reserve(44);
    u.insert(u.end(), {phase, bass * amp, kick * amp, energy});
    u.insert(u.end(), {angle[0], angle[1], angle[2], angle[3]});
    u.insert(u.end(), {angle[4], angle[5], angle[6], angle[7]});
    for (int i = 0; i < 8; i++) u.push_back(std::min(power[i] * amp, 2.0f));
    u.insert(u.end(), {spark * amp, flash, f.glow, f.detail});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("plasma", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'plasma': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;     // tiempo, graves, golpe, energía
uniform vec4 uAng0;
uniform vec4 uAng1;
uniform vec4 uPow0;
uniform vec4 uPow1;
uniform vec4 uM;     // agudos, destello, glow, detalle
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

// Desvío lateral suave del rayo a lo largo de su recorrido (s = 0..1).
float wander(float s, float len, float seed) {
  float t = uA.x;
  float env = sin(3.14159 * s) * (0.55 + 0.45 * s);
  float amp = min(len, 0.7);
  return (sin(s * 6.0 + t * 1.3 + seed * 5.0) * 0.09 + sin(s * 15.0 - t * 2.7 + seed * 11.0) * 0.035) * amp * env;
}

// Rayo de plasma desde `origin` en la dirección `dir`; devuelve (núcleo, halo).
// El halo usa el trazado suave y la distancia a una cápsula, así no hay cortes
// ni estrías; el chisporroteo de alta frecuencia sólo afecta al núcleo.
vec2 bolt(vec2 p, vec2 origin, vec2 dir, float len, float power, float seed, float width0) {
  vec2 nrm = vec2(-dir.y, dir.x);
  vec2 q = p - origin;
  float along = dot(q, dir);
  float s = clamp(along / len, 0.0, 1.0);
  float env = sin(3.14159 * s);
  float smoothLat = dot(q, nrm) - wander(s, len, seed);
  float crackle = (noise(vec2(s * 40.0 + seed * 3.0, uA.x * 9.0)) - 0.5) * (0.035 + 0.09 * uM.x) * min(len, 0.7) * env;
  float lateral = smoothLat - crackle;
  float beyond = along < 0.0 ? -along : max(along - len, 0.0);
  float dist2 = smoothLat * smoothLat + beyond * beyond;
  float inside = step(0.0, along) * step(along, len);
  float width = (width0 + 0.005 * min(power, 1.5)) * (1.0 - 0.5 * s);
  float core = exp(-lateral * lateral / (width * width)) * inside;
  float halo = (0.00005 + 0.0001 * power) / (dist2 + 0.0004);
  return vec2(core * 1.5 * power, halo * power);
}

// Rayo principal hasta el borde de la pantalla, con una rama.
vec2 tendril(vec2 p, float ang, float power, float seed, vec2 halfSize) {
  if (power < 0.02) return vec2(0.0);
  vec2 dir = vec2(cos(ang), sin(ang));
  float len = min(halfSize.x / max(abs(dir.x), 0.001), halfSize.y / max(abs(dir.y), 0.001)) * 1.02;
  vec2 acc = bolt(p, vec2(0.0), dir, len, power, seed, 0.004);
  // Punto de contacto con el borde: la descarga ilumina donde toca.
  vec2 tip = dir * len;
  acc.x += exp(-dot(p - tip, p - tip) / (0.0012 + 0.002 * power)) * power;
  if (power > 0.25) {
    float fork = 0.42 + 0.2 * fract(seed * 0.37);
    vec2 nrm = vec2(-dir.y, dir.x);
    vec2 origin = dir * len * fork + nrm * wander(fork, len, seed);
    float side = fract(seed * 0.61) < 0.5 ? -1.0 : 1.0;
    float ba = ang + side * (0.45 + 0.25 * sin(uA.x * 0.7 + seed));
    vec2 bdir = vec2(cos(ba), sin(ba));
    acc += bolt(p, origin, bdir, len * 0.45, power * 0.7, seed + 7.0, 0.0025) * 0.8;
  }
  return acc;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  p.y = -p.y;
  vec2 halfSize = 0.5 * uSize / scale;
  float r = length(p);
  float kick = uA.z;
  float t = uA.x;

  // Gas eléctrico en toda la pantalla, más vivo con la música y el golpe.
  float gas = noise(p * 2.2 + vec2(t * 0.12, -t * 0.08)) * 0.6 + noise(p * 5.0 - t * 0.2) * 0.4;
  vec3 col = uC0 + mix(uC2, uC1, gas) * gas * (0.006 + 0.03 * uA.w + 0.12 * kick) * uM.z;
  col += mix(uC1, uC2, 0.5) * exp(-r * r * 2.5) * (0.015 + 0.04 * uA.w + 0.2 * kick);

  vec2 acc = vec2(0.0);
  acc += tendril(p, uAng0.x, uPow0.x, 0.0, halfSize);
  acc += tendril(p, uAng0.y, uPow0.y, 1.7, halfSize);
  acc += tendril(p, uAng0.z, uPow0.z, 3.1, halfSize);
  acc += tendril(p, uAng0.w, uPow0.w, 4.6, halfSize);
  acc += tendril(p, uAng1.x, uPow1.x, 6.2, halfSize);
  acc += tendril(p, uAng1.y, uPow1.y, 7.9, halfSize);
  acc += tendril(p, uAng1.z, uPow1.z, 9.3, halfSize);
  acc += tendril(p, uAng1.w, uPow1.w, 10.8, halfSize);
  vec3 arc = mix(uC1, uC3, clamp(acc.x * 0.55, 0.0, 1.0)) * acc.x + mix(uC2, uC1, 0.4) * acc.y * (0.9 + 0.7 * kick);
  col += arc * (0.9 + 0.7 * uA.y) * uM.z;

  // Núcleo de energía con corona que pulsa con cada golpe.
  float coreR = 0.06 + 0.012 * uA.y + 0.03 * kick;
  float corona = 0.5 + 0.5 * noise(vec2(atan(p.y, p.x) * 3.0, t * 2.0));
  col += mix(uC1, uC3, 0.6) * smoothstep(coreR, coreR * 0.6, r) * (1.4 + 1.6 * kick);
  col += uC1 * (0.002 + 0.006 * kick) / (r * r + 0.003) * (0.7 + 0.3 * corona);

  col += mix(uC1, uC3, 0.5) * uM.y * 0.15;
  col *= 1.0 - 0.3 * smoothstep(0.6, 1.4, length(p * vec2(0.9, 0.6)));
  col = clamp((col * (2.51 * col + 0.03)) / (col * (2.43 * col + 0.59) + 0.14), 0.0, 1.0);
  col = pow(col, vec3(0.4545));
  col += (hash12(frag) - 0.5) / 255.0;
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
