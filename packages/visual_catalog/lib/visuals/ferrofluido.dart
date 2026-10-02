// Ferrofluido — escultura de líquido magnético negro bajo luz de estudio.
// Una cúpula brillante con una corona de púas: los graves alargan todas las
// púas, cada dirección sigue su banda del espectro y cada golpe las dispara
// hacia fuera mientras el halo de color late detrás.
const nativeSource = r'''
class Visual final : public Scene {
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  std::array<float, 8> bands{};
  float phase = 0, spin = 0, wobble = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    bands.fill(0);
    phase = rng.unit() * 10.0f;
    spin = rng.unit();
    wobble = 0;
  }

  void update(const Frame& f) override {
    float dt = float(f.delta);
    const Music& m = f.music;
    bass = follow(bass, m.bass, 22.0f, 4.5f, dt);
    body = follow(body, m.body, 14.0f, 3.5f, dt);
    spark = follow(spark, m.spark, 30.0f, 7.0f, dt);
    energy = follow(energy, m.energy, 8.0f, 2.0f, dt);
    drive = follow(drive, m.active ? std::pow(std::clamp(m.energy, 0.0f, 1.0f), 0.8f) : 0.0f, 3.0f, 0.7f, dt);

    float hit = 0, fl = 0;
    for (const auto& e : m.events[0]) hit = std::max(hit, e.strength);
    for (const auto& e : m.events[2]) hit = std::max(hit, e.strength * 0.85f);
    for (const auto& e : m.events[3]) fl = std::max(fl, e.strength);
    float onset = std::clamp((m.bass - slowBass - 0.15f) * 2.5f, 0.0f, 1.0f);
    slowBass = follow(slowBass, m.bass, 3.0f, 3.0f, dt);
    hit = std::min(std::max(hit, onset), 1.0f);
    kick = std::max(kick * std::exp(-dt * 6.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));

    static const int edges[9] = {0, 3, 6, 9, 13, 17, 21, 26, 31};
    for (int b = 0; b < 8; b++) {
      float v = 0;
      for (int i = edges[b]; i < edges[b + 1]; i++) v = std::max(v, m.smoothSpectrum[i]);
      bands[b] = follow(bands[b], v, 18.0f, 4.0f, dt);
    }

    phase += dt * f.speed * (0.3f + 1.2f * drive + 1.0f * kick);
    spin += dt * f.speed * (0.008f + 0.035f * drive + 0.06f * kick);
    wobble += dt * f.speed * (0.6f + 2.0f * body);
  }

  void render(const Frame& f, Canvas& c) const override {
    float amp = f.intensity;
    float spikes = std::round(18.0f + 8.0f * f.detail);
    std::vector<float> u;
    u.reserve(40);
    u.insert(u.end(), {phase, spin, 0.19f + 0.015f * bass * amp, spikes});
    u.insert(u.end(), {0.05f, 0.14f * bass * amp, 0.14f * amp, kick * amp});
    u.insert(u.end(), {wobble, body, drive, 0.0f});
    u.insert(u.end(), {bands[0], bands[1], bands[2], bands[3]});
    u.insert(u.end(), {bands[4], bands[5], bands[6], bands[7]});
    u.insert(u.end(), {spark, flash, f.glow, energy});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("ferro", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'ferro': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;      // tiempo, giro, radio de la cúpula, número de púas
uniform vec4 uB;      // púa base, púa por graves, púa por banda, golpe
uniform vec4 uW;      // ondulación, medios, impulso, libre
uniform vec4 uBands0;
uniform vec4 uBands1;
uniform vec4 uL;      // agudos, destello, glow, energía
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

float pick(float i) {
  if (i < 0.5) return uBands0.x;
  if (i < 1.5) return uBands0.y;
  if (i < 2.5) return uBands0.z;
  if (i < 3.5) return uBands0.w;
  if (i < 4.5) return uBands1.x;
  if (i < 5.5) return uBands1.y;
  if (i < 6.5) return uBands1.z;
  return uBands1.w;
}

// Banda por dirección: graves arriba, agudos abajo, simétrico.
float bandAt(float turns) {
  float m = abs(fract(turns + 0.25) * 2.0 - 1.0) * 7.0;
  float i = floor(m);
  return mix(pick(i), pick(min(i + 1.0, 7.0)), smoothstep(0.0, 1.0, m - i));
}

float spikeLength(float turns) {
  float wave = 0.5 + 0.5 * sin(turns * 6.2831853 * 3.0 - uA.x * 1.7);
  float wave2 = 0.5 + 0.5 * sin(turns * 6.2831853 * 5.0 + uA.x * 1.1);
  return uB.x * (0.6 + 0.8 * wave * wave2) + uB.y * (0.7 + 0.3 * wave) +
         bandAt(turns) * uB.z + uB.w * (0.07 + 0.05 * wave2);
}

// Cono de sección redonda que nace del borde de la cúpula y se afila.
float spike(float r, float a, float offset, float scale) {
  float n = uA.w;
  float aa = a + offset;
  float k = floor(aa);
  float f = aa - k - 0.5;
  float len = spikeLength((k + 0.5 - offset) / n - uA.y) * scale;
  float base = uA.z * 0.80;
  float t = (r - base) / (len + uA.z * 0.22);
  float halfW = 0.5 * (1.0 - t);
  float d = abs(f) / max(halfW, 0.0001);
  float inside = step(0.0, t) * step(t, 1.0) * step(d, 1.0);
  return inside * uA.z * 0.66 * pow(max(1.0 - t, 0.0), 1.15) *
         sqrt(max(1.0 - d * d, 0.0));
}

float height(vec2 p) {
  float r = length(p);
  float a = (atan(p.y, p.x) / 6.2831853 + uA.y) * uA.w;
  float breathe = 1.0 + 0.02 * sin(uW.x + r * 30.0) + 0.05 * uB.w;
  float dr = r / (uA.z * breathe);
  float dome = uA.z * sqrt(max(1.0 - dr * dr, 0.0));
  float s = max(spike(r, a, 0.0, 1.0), spike(r, a, 0.5, 0.55));
  // Unión suave entre cúpula y púas.
  if (dome <= 0.0 || s <= 0.0) return max(dome, s);
  float k = uA.z * 0.08;
  float hk = clamp(0.5 + 0.5 * (s - dome) / k, 0.0, 1.0);
  return mix(dome, s, hk) + k * hk * (1.0 - hk);
}

vec3 environment(vec3 r) {
  float kick = uB.w;
  vec3 col = uC0 * 0.25;
  float up = step(0.0, r.z);
  // Softbox redondeado y difuso arriba a la izquierda, más brillante arriba.
  vec2 q = r.xy - vec2(-0.30, 0.36);
  vec2 bq = abs(q) - vec2(0.17, 0.10);
  float box = length(max(bq, 0.0)) + min(max(bq.x, bq.y), 0.0) - 0.06;
  float soft = (1.0 - smoothstep(-0.06, 0.10, box)) * (0.65 + 0.35 * smoothstep(-0.2, 0.2, q.y));
  col += vec3(1.0, 0.97, 0.94) * soft * (1.3 + 3.0 * uL.y + 1.0 * kick) * up;
  // Luz de relleno cálida, pequeña y muy suave abajo a la derecha.
  float fill = exp(-dot(r.xy - vec2(0.45, -0.35), r.xy - vec2(0.45, -0.35)) * 18.0);
  col += uC3 * fill * 0.35 * up;
  // Luces de color en el horizonte: sólo las ven los flancos rasantes.
  float az = atan(r.y, r.x);
  float horizon = pow(1.0 - abs(r.z), 5.0);
  vec3 rim = mix(uC1, uC2, smoothstep(-0.6, 0.6, sin(az + uA.x * 0.25)));
  col += rim * horizon * (1.4 + 3.5 * kick + 1.2 * uL.w) * uL.z;
  return col;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  p.y = -p.y;
  float r0 = length(p);
  float kick = uB.w;

  // Fondo: estudio oscuro con halo de color que late con el golpe.
  float halo = exp(-r0 * r0 * 7.0);
  vec3 bg = uC0 + mix(uC1, uC2, 0.5 + 0.5 * sin(atan(p.y, p.x) + uA.x * 0.3)) *
            halo * (0.10 + 0.45 * kick + 0.15 * uL.w) * uL.z;
  float rings = 0.5 + 0.5 * sin(r0 * 60.0 - uA.x * 4.0);
  bg += mix(uC2, uC1, 0.5) * halo * rings * (0.015 + 0.08 * kick);
  vec3 col = bg;

  float h0 = height(p);
  if (h0 > 0.0) {
    float e = 1.25 / scale;
    float hx = height(p + vec2(e, 0.0));
    float hy = height(p + vec2(0.0, e));
    vec3 n = normalize(vec3(-(hx - h0) / e, -(hy - h0) / e, 1.0));
    vec3 v = vec3(0.0, 0.0, 1.0);
    vec3 r = reflect(-v, n);
    float fres = 0.05 + 0.95 * pow(1.0 - max(n.z, 0.0), 5.0);
    vec3 surf = environment(r) * (0.25 + 0.75 * fres);
    // Brillos con los agudos en las puntas de las púas.
    float tip = smoothstep(0.03, 0.0, h0) * step(uA.z * 1.05, r0);
    float tw = hash12(floor(vec2(atan(p.y, p.x) * uA.w * 0.5, uA.x * 8.0)));
    surf += uC3 * tip * smoothstep(0.4, 1.0, tw) * uL.x * 3.0;
    // Contorno suave para evitar dientes de sierra en el borde.
    float edge = smoothstep(0.0, 0.004, h0);
    col = mix(bg * 0.4, surf, edge);
  }

  col *= 1.0 - 0.4 * smoothstep(0.35, 1.2, length(p * vec2(0.9, 0.65)));
  col = clamp((col * (2.51 * col + 0.03)) / (col * (2.43 * col + 0.59) + 0.14), 0.0, 1.0);
  col = pow(col, vec3(0.4545));
  col += (hash12(frag) - 0.5) / 255.0;
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
