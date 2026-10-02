// Catedral de Luz — haces volumétricos a través de un rosetón de vidrieras.
// Cada vidriera se ilumina con su banda del espectro y tiñe su haz; cada golpe
// hace estallar la luz y gira el rosetón, y los agudos encienden el polvo que
// flota dentro de los haces.
const nativeSource = r'''
class Visual final : public Scene {
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  std::array<float, 8> bands{};
  float phase = 0, turn = 0, turnVel = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    bands.fill(0);
    phase = rng.unit() * 20.0f;
    turn = rng.unit();
    turnVel = 0;
  }

  void update(const Frame& f) override {
    float dt = float(f.delta);
    const Music& m = f.music;
    bass = follow(bass, m.bass, 20.0f, 4.0f, dt);
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
    if (hit > kick + 0.2f) turnVel += 0.35f * hit;
    kick = std::max(kick * std::exp(-dt * 4.0f), hit);
    flash = std::max(flash * std::exp(-dt * 6.0f), std::min(fl, 1.0f));

    static const int edges[9] = {0, 3, 6, 9, 13, 17, 21, 26, 31};
    for (int b = 0; b < 8; b++) {
      float v = 0;
      for (int i = edges[b]; i < edges[b + 1]; i++) v = std::max(v, m.smoothSpectrum[i]);
      bands[b] = follow(bands[b], v, 18.0f, 3.5f, dt);
    }

    phase += dt * f.speed * (0.2f + 0.8f * drive + 0.6f * kick);
    turnVel *= std::exp(-dt * 2.5f);
    turn += dt * f.speed * (0.006f + 0.02f * drive) + dt * turnVel;
  }

  void render(const Frame& f, Canvas& c) const override {
    float amp = f.intensity;
    float samples = std::round(8.0f + 8.0f * f.detail);
    std::vector<float> u;
    u.reserve(40);
    u.insert(u.end(), {phase, turn, bass * amp, kick * amp});
    u.insert(u.end(), {bands[0], bands[1], bands[2], bands[3]});
    u.insert(u.end(), {bands[4], bands[5], bands[6], bands[7]});
    u.insert(u.end(), {spark * amp, flash, energy, f.glow});
    u.insert(u.end(), {samples, body, 0.0f, 0.0f});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("cathedral", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'cathedral': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // tiempo, giro del rosetón, graves, golpe
uniform vec4 uBands0;
uniform vec4 uBands1;
uniform vec4 uM;   // agudos, destello, energía, glow
uniform vec4 uX;   // muestras, medios
uniform vec3 uC0;
uniform vec3 uC1;
uniform vec3 uC2;
uniform vec3 uC3;
out vec4 fragColor;

const float RW = 0.27;

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

// Luz transmitida por el rosetón en el punto p (relativo a su centro).
// Toda la superficie es vidriera: pétalos de color sobre vidrio de fondo más
// tenue, separados por plomos finos y un marco de piedra.
vec3 rose(vec2 p, float leadWidth) {
  float r = length(p) / RW;
  if (r > 0.97) return vec3(0.0);
  float a = atan(p.y, p.x) / 6.2831853 + uA.y;
  float ring;
  float sectors;
  float center;
  float depth;
  if (r < 0.31) {
    ring = 0.0; sectors = 8.0; center = 0.17; depth = 0.12;
  } else if (r < 0.66) {
    ring = 1.0; sectors = 16.0; center = 0.485; depth = 0.15;
  } else {
    ring = 2.0; sectors = 24.0; center = 0.815; depth = 0.13;
  }
  float s = a * sectors + (ring == 1.0 ? 0.5 : 0.0);
  float id = floor(s);
  float fs = fract(s) - 0.5;
  float width = 6.2831853 * center / sectors;
  float shape = length(vec2(fs * width / depth, (r - center) / depth));
  float petal = smoothstep(1.0, 0.94, shape);
  float h = hash12(vec2(mod(id, sectors), ring * 7.0 + 1.0));
  vec3 glass = h < 0.4 ? uC1 : (h < 0.75 ? uC2 : uC3);
  vec3 ground = mix(uC2, uC1, 0.5 + 0.5 * sin(id * 1.7 + ring)) * 0.35;
  float band = pick(mod(id * 3.0 + ring * 5.0, 8.0));
  vec3 col = mix(ground, glass * (0.45 + 1.6 * band + 0.2 * uA.z), petal);
  // Plomos: contorno de cada pétalo, anillos y parteluces radiales.
  float lead = smoothstep(leadWidth, 0.0, abs(shape - 1.0) * depth);
  lead = max(lead, smoothstep(leadWidth, 0.0, min(abs(r - 0.31), abs(r - 0.66))));
  lead = max(lead, smoothstep(leadWidth, 0.0, abs(fs) * width) * (1.0 - petal));
  float hub = smoothstep(0.075, 0.06, r);
  return col * (1.0 - lead) + uC3 * hub * (0.6 + 1.5 * uA.w);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 uv = (frag - 0.5 * uSize) / scale;
  uv.y = -uv.y;
  float t = uA.x;
  float top = 0.5 * uSize.y / scale;
  vec2 center = vec2(0.0, min(top - 0.36, 0.52));
  vec2 rel = uv - center;
  float kick = uA.w;

  // Muro de piedra oscuro con el rosetón encastrado.
  float stone = 0.5 + 0.5 * noise(uv * 9.0) * noise(uv * 23.0 + 4.0);
  vec3 col = uC0 * (0.7 + 0.6 * stone);
  float frame = smoothstep(0.012, 0.0, abs(length(rel) - RW * 1.04));
  vec3 direct = rose(rel, 0.018);
  col += direct * (0.30 + 0.45 * kick + 0.9 * uM.y) * uM.w;
  col += uC3 * frame * 0.06;

  // Haces: dispersión radial desde el rosetón hacia la cámara. Todas las
  // muestras están sobre la recta píxel-centro y comparten ángulo, así que
  // color y banda de cada anillo se calculan una vez y el bucle es radial.
  float ang = atan(rel.y, rel.x) / 6.2831853 + uA.y;
  vec3 lat = vec3(0.0);
  vec3 glassA = vec3(0.0);
  vec3 glassB = vec3(0.0);
  vec3 glassC = vec3(0.0);
  vec3 groundA = vec3(0.0);
  vec3 groundB = vec3(0.0);
  vec3 groundC = vec3(0.0);
  for (int ring = 0; ring < 3; ring++) {
    float sectors = ring == 0 ? 8.0 : (ring == 1 ? 16.0 : 24.0);
    float center = ring == 0 ? 0.17 : (ring == 1 ? 0.485 : 0.815);
    float depth = ring == 0 ? 0.12 : (ring == 1 ? 0.15 : 0.13);
    float sa = ang * sectors + (ring == 1 ? 0.5 : 0.0);
    float id = floor(sa);
    float l = (fract(sa) - 0.5) * 6.2831853 * center / sectors / depth;
    float h = hash12(vec2(mod(id, sectors), float(ring) * 7.0 + 1.0));
    vec3 glass = h < 0.4 ? uC1 : (h < 0.75 ? uC2 : uC3);
    glass *= 0.45 + 1.6 * pick(mod(id * 3.0 + float(ring) * 5.0, 8.0)) + 0.2 * uA.z;
    vec3 ground = mix(uC2, uC1, 0.5 + 0.5 * sin(id * 1.7 + float(ring))) * 0.35;
    if (ring == 0) { lat.x = l; glassA = glass; groundA = ground; }
    else if (ring == 1) { lat.y = l; glassB = glass; groundB = ground; }
    else { lat.z = l; glassC = glass; groundC = ground; }
  }
  float samples = uX.x;
  float decay = 0.94 + 0.03 * uA.z + 0.015 * kick;
  float weight = 1.0;
  vec3 rays = vec3(0.0);
  float len = 0.92;
  // Ruido de gradiente entrelazado: el grano del muestreo apenas se percibe.
  float jitter = fract(52.9829189 * fract(dot(frag, vec2(0.06711056, 0.00583715))));
  float r0 = length(rel) / RW;
  for (int i = 0; i < 24; i++) {
    if (float(i) >= samples) break;
    float k = (float(i) + jitter) / samples;
    float r = r0 * (1.0 - k * len);
    if (r < 0.97) {
      vec3 glass = r < 0.31 ? glassA : (r < 0.66 ? glassB : glassC);
      vec3 ground = r < 0.31 ? groundA : (r < 0.66 ? groundB : groundC);
      float l = r < 0.31 ? lat.x : (r < 0.66 ? lat.y : lat.z);
      float center = r < 0.31 ? 0.17 : (r < 0.66 ? 0.485 : 0.815);
      float depth = r < 0.31 ? 0.12 : (r < 0.66 ? 0.15 : 0.13);
      float petal = smoothstep(1.0, 0.94, length(vec2(l, (r - center) / depth)));
      rays += mix(ground, glass, petal) * weight;
    }
    weight *= decay;
  }
  rays /= samples;
  // La niebla apaga los haces a medida que se alejan del rosetón.
  rays *= exp(-length(rel) * (1.4 - 0.5 * kick));
  // En la niebla los colores se mezclan: luz cálida apenas teñida, con estrías de polvo.
  float rl = dot(rays, vec3(0.333));
  rays = mix(vec3(rl) * mix(vec3(1.0), uC3, 0.35), rays, 0.45);
  float streak = 0.55 + 0.9 * noise(vec2(atan(rel.x, -rel.y) * 30.0, t * 0.15));
  // Los haces nacen del borde del rosetón: la vidriera se ve nítida.
  rays *= streak * smoothstep(0.85, 1.15, r0);
  float exposure = (1.1 + 1.0 * uA.z + 2.4 * kick + 2.4 * uM.y + 0.4 * uM.z) * uM.w;
  col += rays * exposure;

  // Niebla ambiental teñida por el rosetón y polvo dentro de los haces.
  float haze = exp(-length(rel) * 2.2);
  col += mix(uC2, uC3, 0.5) * haze * (0.04 + 0.12 * kick);
  float beam = dot(rays, vec3(0.333)) * exposure;
  vec2 g = (uv + vec2(t * 0.01, t * 0.02)) * 55.0;
  vec2 id = floor(g);
  float h = hash12(id);
  vec2 o = vec2(hash12(id + 2.3), hash12(id + 5.9)) - 0.5;
  float mote = smoothstep(0.09, 0.0, length(fract(g) - 0.5 - o * 0.6)) * step(0.82, h);
  float twinkle = 0.4 + 0.6 * sin(t * 4.0 + h * 50.0);
  col += uC3 * mote * twinkle * beam * (0.6 + 3.0 * uM.x) * 2.0;

  col *= 1.0 - 0.45 * smoothstep(0.4, 1.3, length((uv - vec2(0.0, 0.15)) * vec2(0.9, 0.6)));
  col = clamp((col * (2.51 * col + 0.03)) / (col * (2.43 * col + 0.59) + 0.14), 0.0, 1.0);
  col = pow(col, vec3(0.4545));
  col += (hash12(frag) - 0.5) / 255.0;
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
