// Globo Tesla Transparente — lámpara de plasma con filamentos eléctricos.
// Versión overlay: mismo movimiento y reacción a la música sin fondo opaco.
// Ocho filamentos nacen del electrodo y tocan el cristal; cada uno sigue una
// banda del espectro, cada golpe los hace saltar a nuevas posiciones con un
// estallido de luz y los agudos añaden chisporroteo al arco.
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
      float target = (i < 3 ? 0.55f : 0.0f) + bands[i] * 1.1f + kick * (i < 6 ? 0.7f : 0.3f);
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
    c.material("plasma_globe", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'plasma_globe': r"""
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

// Campana gaussiana segura: pow() con base negativa no está definido en GLSL.
float gauss(float x) {
  return exp(-x * x);
}

const float R = 0.34;

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

// Devuelve (núcleo, halo) de un filamento que va del centro al cristal.
vec2 filament(vec2 p, float ang, float power, float seed) {
  if (power < 0.02) return vec2(0.0);
  float t = uA.x;
  vec2 dir = vec2(cos(ang), sin(ang));
  vec2 nrm = vec2(-dir.y, dir.x);
  float along = dot(p, dir);
  float s = clamp(along / R, 0.0, 1.0);
  float env = sin(3.14159 * s) * (0.6 + 0.4 * s);
  float disp = (sin(s * 6.0 + t * 1.3 + seed * 5.0) * 0.07 +
                sin(s * 15.0 - t * 2.7 + seed * 11.0) * 0.03) * env * R;
  disp += (noise(vec2(s * 38.0 + seed, t * 9.0)) - 0.5) * (0.02 + 0.07 * uM.x) * env * R;
  float lateral = dot(p, nrm) - disp;
  float inside = smoothstep(-0.01, 0.02, along) * smoothstep(R * 1.01, R * 0.96, along);
  float width = (0.0030 + 0.0040 * min(power, 1.5)) * (1.0 - 0.45 * s);
  float core = exp(-lateral * lateral / (width * width));
  float halo = (0.00006 + 0.00012 * power) / (lateral * lateral + 0.00025);
  // Punto de contacto con el cristal.
  vec2 tip = dir * R + nrm * disp;
  float contact = exp(-dot(p - tip, p - tip) / (0.00025 + 0.0004 * power));
  return vec2((core * 1.4 + contact * 1.6) * inside * power + contact * power * 0.6,
              halo * inside * power);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  p.y = -p.y;
  p.y -= 0.04;
  float r = length(p);
  float kick = uA.z;

  // Sala oscura con resplandor de color detrás del globo.
  vec3 col = uC0 + mix(uC2, uC1, 0.4) * exp(-r * r * 8.0) * (0.10 + 0.30 * kick + 0.12 * uA.w);

  // Peana bajo el globo.
  float baseTop = -R * 0.93;
  float baseW = 0.11 + (baseTop - p.y) * 0.35;
  float pedestal = step(p.y, baseTop) * step(abs(p.x), baseW) * step(baseTop - 0.22, p.y);
  float sheen = smoothstep(baseW, baseW * 0.2, abs(p.x - baseW * 0.35));
  vec3 pedestalCol = uC0 * 0.5 + vec3(0.05) * sheen +
                     mix(uC1, uC2, 0.5) * 0.18 * exp(-(baseTop - p.y) * 40.0) * (0.4 + kick);
  col = mix(col, pedestalCol, pedestal);

  if (r < R * 1.02) {
    // Gas interior y electrodo central.
    float inside = smoothstep(R, R * 0.97, r);
    vec3 gas = mix(uC2, uC1, 0.5 + 0.5 * sin(atan(p.y, p.x) * 2.0 + uA.x * 0.3)) *
               (0.015 + 0.04 * uA.w + 0.10 * kick) * (0.6 + 0.4 * noise(p * 6.0 + uA.x * 0.2));
    col = mix(col, uC0 * 0.35 + gas, inside);

    vec2 acc = vec2(0.0);
    acc += filament(p, uAng0.x, uPow0.x, 0.0);
    acc += filament(p, uAng0.y, uPow0.y, 1.7);
    acc += filament(p, uAng0.z, uPow0.z, 3.1);
    acc += filament(p, uAng0.w, uPow0.w, 4.6);
    acc += filament(p, uAng1.x, uPow1.x, 6.2);
    acc += filament(p, uAng1.y, uPow1.y, 7.9);
    acc += filament(p, uAng1.z, uPow1.z, 9.3);
    acc += filament(p, uAng1.w, uPow1.w, 10.8);
    vec3 arc = mix(uC1, uC3, clamp(acc.x * 0.6, 0.0, 1.0)) * acc.x;
    arc += uC1 * acc.y;
    col += arc * inside * (0.9 + 0.8 * uA.y) * uM.z;

    float coreR = 0.05 + 0.006 * uA.y + 0.01 * kick;
    float electrode = smoothstep(coreR, coreR * 0.85, r);
    vec3 electrodeCol = mix(uC1, uC3, 0.6) * (1.2 + 1.5 * kick) * (0.75 + 0.25 * smoothstep(coreR, 0.0, length(p - vec2(-0.015, 0.015))));
    col = mix(col, electrodeCol, electrode);
    col += uC1 * (0.0005 + 0.0025 * kick) / (r * r + 0.0025) * inside;

    // Cristal: borde con Fresnel y reflejo de ventana.
    float rim = gauss((r - R) / 0.006);
    col += mix(uC2, vec3(1.0), 0.5) * rim * (0.35 + 0.4 * kick);
    col += uC2 * smoothstep(R * 0.8, R, r) * inside * 0.06;
    vec2 hl = p - vec2(-0.13, 0.17);
    float highlight = exp(-dot(hl * vec2(1.0, 1.8), hl * vec2(1.0, 1.8)) * 140.0);
    col += vec3(1.0) * highlight * 0.12;
    float arcHl = gauss((r - R * 0.9) / 0.01) * smoothstep(0.2, 0.9, dot(normalize(p + vec2(1e-5, 0.0)), normalize(vec2(-0.6, 0.8))));
    col += vec3(1.0) * arcHl * 0.15;
  }

  col *= 1.0 - 0.4 * smoothstep(0.45, 1.2, length(p * vec2(0.9, 0.65)));
  col = clamp((col * (2.51 * col + 0.03)) / (col * (2.43 * col + 0.59) + 0.14), 0.0, 1.0);
  col = pow(col, vec3(0.4545));
  // Fondo transparente: color premultiplicado y opacidad según el brillo; la
  // luz muy tenue se vuelve transparente del todo para no dejar velo.
  col = clamp(col, 0.0, 1.0);
  float veilPeak = max(col.r, max(col.g, col.b));
  float clearCut = smoothstep(0.04, 0.12, veilPeak);
  col *= clearCut;
  float alpha = clamp(veilPeak * 1.25, 0.0, 1.0) * clearCut;
  // La peana es un objeto sólido.
  alpha = max(alpha, pedestal);
  fragColor = vec4(col, alpha);
}
""",
};
