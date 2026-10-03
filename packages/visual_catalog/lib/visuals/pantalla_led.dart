// Pantalla LED — pared de LEDs de concierto a pantalla completa.
// Una matriz de LEDs redondos con brillo que muestra patrones de escenario:
// anillos que salen del centro, barridos diagonales, barras del espectro en
// espejo, un radar giratorio, damero estroboscópico y plasma. Cada dos compases
// el patrón cambia con un fundido; cada golpe lanza un anillo y aviva la pared,
// los graves encienden el brillo y los destellos blanquean la pantalla.
const nativeSource = r'''
class Visual final : public Scene {
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0, mids = 0;
  double clock = 0, spin = 0, sinceSwitch = 0;
  int patternA = 5, patternB = 5, beats = 0, step = 0, toggle = 0;
  float blend = 1, ringR = 3.0f, ringAmp = 0;
  std::array<float, 16> bands{};

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  void next(bool music) {
    // Con música recorre los seis patrones; en silencio sólo los ambientales.
    static const int withMusic[6] = {0, 2, 1, 4, 3, 5};
    static const int ambient[4] = {5, 1, 3, 0};
    step++;
    patternA = patternB;
    patternB = music ? withMusic[step % 6] : ambient[step % 4];
    if (patternB == patternA) patternB = music ? withMusic[(step + 1) % 6] : ambient[(step + 1) % 4];
    blend = 0;
    sinceSwitch = 0;
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = mids = 0;
    clock = rng.unit() * 10.0;
    spin = rng.unit() * 6.2831853;
    sinceSwitch = 0;
    patternA = patternB = 5;
    beats = step = toggle = 0;
    blend = 1;
    ringR = 3.0f;
    ringAmp = 0;
    bands.fill(0);
  }

  void update(const Frame& f) override {
    float dt = float(f.delta);
    const Music& m = f.music;
    bass = follow(bass, m.bass, 22.0f, 4.5f, dt);
    body = follow(body, m.body, 12.0f, 3.0f, dt);
    spark = follow(spark, m.spark, 30.0f, 7.0f, dt);
    energy = follow(energy, m.energy, 6.0f, 1.8f, dt);
    drive = follow(drive, m.active ? std::pow(std::clamp(m.energy, 0.0f, 1.0f), 0.8f) : 0.0f, 3.0f, 0.7f, dt);
    float mi = 0;
    for (int i = 9; i < 21; i++) mi = std::max(mi, m.smoothSpectrum[i]);
    mids = follow(mids, mi, 12.0f, 3.0f, dt);
    for (int i = 0; i < 16; i++) {
      float v = std::max(m.smoothSpectrum[std::min(2 * i, 30)], m.smoothSpectrum[std::min(2 * i + 1, 30)]);
      bands[i] = follow(bands[i], v, 30.0f, 5.0f, dt);
    }

    float hit = 0, fl = 0;
    for (const auto& e : m.events[0]) hit = std::max(hit, e.strength);
    for (const auto& e : m.events[2]) hit = std::max(hit, e.strength * 0.85f);
    for (const auto& e : m.events[3]) fl = std::max(fl, e.strength);
    float onset = std::clamp((m.bass - slowBass - 0.15f) * 2.5f, 0.0f, 1.0f);
    slowBass = follow(slowBass, m.bass, 3.0f, 3.0f, dt);
    hit = std::min(std::max(hit, onset), 1.0f);
    if (hit > kick + 0.2f) {
      beats++;
      toggle ^= 1;
      ringR = 0.0f;
      ringAmp = hit;
      if (beats % 8 == 0) next(true);
    }
    kick = std::max(kick * std::exp(-dt * 6.0f), hit);
    flash = std::max(flash * std::exp(-dt * 9.0f), std::min(fl, 1.0f) * 0.8f);

    clock += f.delta * f.speed * (0.6 + 1.2 * drive);
    spin += f.delta * f.speed * (0.4 + 1.4 * mids + 0.6 * drive);
    sinceSwitch += f.delta;
    // En silencio el patrón cambia cada siete segundos.
    if (!m.active && sinceSwitch > 7.0) next(false);
    blend = std::min(1.0f, blend + dt * 2.5f);
    ringR += dt * (0.9f + 0.6f * drive);
    ringAmp *= std::exp(-dt * 2.0f);
  }

  void render(const Frame& f, Canvas& c) const override {
    float amp = f.intensity;
    float eased = blend * blend * (3.0f - 2.0f * blend);
    std::vector<float> u;
    u.reserve(44);
    u.insert(u.end(), {float(std::fmod(clock, 1000.0)), bass * amp, kick * amp, energy});
    u.insert(u.end(), {float(patternA), float(patternB), eased, flash * amp});
    u.insert(u.end(), {ringR, ringAmp * amp, float(std::fmod(spin, 6.2831853)), float(toggle)});
    u.insert(u.end(), {f.glow, spark * amp, mids * amp, f.detail});
    for (int i = 0; i < 16; i++) u.push_back(bands[i] * amp);
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("led_wall", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'led_wall': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // reloj, graves, golpe, energía
uniform vec4 uB;   // patrón actual, patrón siguiente, fundido, destello
uniform vec4 uR;   // radio y fuerza del anillo del golpe, giro, alternancia
uniform vec4 uD;   // glow, agudos, medios, detalle
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

// Patrones de escenario evaluados en el centro de cada LED (q en unidades del
// lado corto, centrado). Devuelven la intensidad del LED.
float pattern(float id, vec2 q, vec2 cell) {
  float t = uA.x;
  float kick = uA.z;
  float r = length(q);
  if (id < 0.5) {
    // Anillos que salen del centro.
    float rings = smoothstep(0.55, 0.95, sin(r * 22.0 - t * 5.0));
    return rings * (0.4 + 0.6 * uA.y + 0.5 * kick);
  }
  if (id < 1.5) {
    // Barridos diagonales cruzados.
    float a = smoothstep(0.6, 1.0, sin((q.x + q.y) * 9.0 - t * 4.0));
    float b = smoothstep(0.75, 1.0, sin((q.x - q.y) * 6.0 + t * 2.7));
    return a * 0.8 + b * 0.6 * (0.4 + uA.y);
  }
  if (id < 2.5) {
    // Barras del espectro en espejo desde el centro de la pantalla.
    float b = clamp(floor(abs(q.x) * 30.0), 0.0, 15.0);
    float level = 0.06 + 0.9 * band(b);
    float y = abs(q.y) / (0.5 * uSize.y / min(uSize.x, uSize.y));
    float bar = step(y, level);
    float cap = exp(-(y - level) * (y - level) * 4000.0);
    return bar * (0.45 + 0.55 * y / max(level, 0.05)) + cap * 1.4;
  }
  if (id < 3.5) {
    // Radar: haz giratorio con estela, anillos de referencia y núcleo.
    float behind = mod(atan(q.y, q.x) - uR.z, TAU);
    float beam = exp(-behind * 1.6) * (0.9 + 0.5 * kick);
    float grid = step(0.86, fract(r * 6.0)) * 0.3;
    return beam * smoothstep(0.02, 0.12, r) + grid + smoothstep(0.1, 0.0, r);
  }
  if (id < 4.5) {
    // Damero estroboscópico que alterna con cada golpe.
    vec2 block = floor(cell / 3.0);
    float parity = mod(block.x + block.y + uR.w, 2.0);
    return parity * (0.15 + 0.95 * kick) + (1.0 - parity) * 0.04;
  }
  // Plasma suave de escenario.
  float pl = sin(q.x * 7.0 + t * 1.3) + sin(q.y * 5.0 - t * 1.1) + sin((q.x + q.y) * 4.0 + t * 0.7);
  return smoothstep(1.4, 2.9, pl + 1.5) * (0.6 + 0.5 * uA.y + 0.4 * kick);
}

float wall(vec2 q, vec2 cell) {
  float next = pattern(uB.y, q, cell);
  if (uB.z >= 0.999) return next;
  return mix(pattern(uB.x, q, cell), next, uB.z);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  float pitch = scale / (22.0 + 6.0 * clamp(uD.w, 0.25, 2.0));
  vec2 cell = floor(frag / pitch);
  vec2 local = fract(frag / pitch) - 0.5;
  vec2 q = ((cell + 0.5) * pitch - 0.5 * uSize) / scale;
  vec2 qp = (frag - 0.5 * uSize) / scale;

  float I = wall(q, cell) * (0.85 + 0.6 * uA.z + 0.3 * uA.w);
  // Anillo blanco del golpe sobre cualquier patrón.
  float rq = length(q);
  I += uR.y * exp(-(rq - uR.x) * (rq - uR.x) * 140.0) * 1.5;
  // Brillo que se derrama entre LEDs: el patrón evaluado en el píxel.
  float spill = wall(qp, floor(frag / pitch));

  float d = length(local);
  float body = smoothstep(0.42, 0.30, d);
  float halo = exp(-d * d * 7.0);
  vec3 hot = mix(uC1, uC2, smoothstep(0.75, 1.4, I));
  vec3 col = uC0;
  col += uC3 * body * 0.10;                                  // LED apagado
  col += hot * I * (body * 1.1 + halo * 0.5 * uD.x);
  col += uC1 * spill * 0.10 * uD.x;
  // Destello blanco de la pared.
  col += uC2 * uB.w * (0.25 + 0.5 * body);
  // Titileo de LEDs sueltos con los agudos.
  float tw = step(0.993 - 0.01 * uD.y, hash12(cell + floor(uA.x * 8.0)));
  col += mix(uC1, uC2, 0.6) * tw * body * uD.y;

  col *= 1.0 - 0.3 * smoothstep(0.6, 1.4, length(qp * vec2(0.9, 0.65)));
  float peak = max(col.r, max(col.g, col.b));
  if (peak > 0.8) {
    float e = (peak - 0.8) / 0.2;
    col *= (0.8 + 0.2 * e / (1.0 + e)) / peak;
  }
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
