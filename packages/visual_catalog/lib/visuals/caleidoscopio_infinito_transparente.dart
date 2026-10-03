// Caleidoscopio Infinito Transparente — viaje sin fin hacia un mandala de geometría de neón.
// Versión overlay: mismo movimiento y reacción a la música sin fondo opaco.
// En coordenadas logarítmicas cada capa crece hacia fuera y te atraviesa
// mientras la siguiente nace en el centro. Simetría de espejo de 6 a 12 lados,
// capas que giran en sentidos opuestos y dispersión de color tipo prisma.
// Cada golpe empuja el viaje, enciende un anillo y destella; cada dos golpes
// la simetría se transforma. Pide 60 FPS para un avance perfectamente fluido.
const nativeSource = r'''
class Visual final : public Scene {
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0, mids = 0;
  float travel = 0, travelVel = 0, rot = 0, hue = 0, hueGoal = 0;
  float symA = 6, symB = 6, morph = 1;
  float ringR = 3.0f, ringAmp = 0;
  int beats = 0, symIndex = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = mids = 0;
    travel = rng.unit() * 10.0f;
    travelVel = 0;
    rot = 0;
    hue = hueGoal = rng.unit();
    symA = symB = 6;
    morph = 1;
    ringR = 3.0f;
    ringAmp = 0;
    beats = 0;
    symIndex = 0;
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

    float hit = 0, fl = 0;
    for (const auto& e : m.events[0]) hit = std::max(hit, e.strength);
    for (const auto& e : m.events[2]) hit = std::max(hit, e.strength * 0.85f);
    for (const auto& e : m.events[3]) fl = std::max(fl, e.strength);
    float onset = std::clamp((m.bass - slowBass - 0.15f) * 2.5f, 0.0f, 1.0f);
    slowBass = follow(slowBass, m.bass, 3.0f, 3.0f, dt);
    hit = std::min(std::max(hit, onset), 1.0f);
    if (hit > kick + 0.2f) {
      beats++;
      travelVel += 1.6f * hit;
      ringR = 0.0f;
      ringAmp = hit;
      hueGoal += 0.12f * hit;
      if (beats % 2 == 0) {
        // La simetría se transforma: 6 -> 8 -> 12 -> 10 -> 6 ...
        static const float steps[4] = {6.0f, 8.0f, 12.0f, 10.0f};
        symIndex = (symIndex + 1) % 4;
        symA = symB;
        symB = steps[symIndex];
        morph = 0.0f;
      }
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));

    // Avance continuo: velocidad base según la energía y empujones amortiguados.
    travelVel *= std::exp(-dt * 3.0f);
    travel += dt * f.speed * (0.12f + 0.9f * drive) + dt * travelVel;
    rot += dt * f.speed * (0.04f + 0.35f * mids + 0.1f * drive);
    hueGoal += dt * (0.01f + 0.05f * energy);
    hue += (hueGoal - hue) * (1.0f - std::exp(-dt * 4.0f));
    morph = std::min(1.0f, morph + dt * 1.6f);
    ringR += dt * (0.9f + 0.6f * drive);
    ringAmp *= std::exp(-dt * 2.2f);
  }

  void render(const Frame& f, Canvas& c) const override {
    float amp = f.intensity;
    float eased = morph * morph * (3.0f - 2.0f * morph);
    std::vector<float> u;
    u.reserve(28);
    u.insert(u.end(), {travel, bass * amp, kick * amp, energy});
    u.insert(u.end(), {rot, hue, spark * amp, f.glow});
    u.insert(u.end(), {symA, symB, eased, flash});
    u.insert(u.end(), {ringR, ringAmp * amp, 0.004f + 0.012f * spark * amp, 0.0f});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("kaleido", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'kaleido': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // viaje, graves, golpe, energía
uniform vec4 uB;   // giro, tono, agudos, glow
uniform vec4 uS;   // simetría actual, simetría siguiente, transición, destello
uniform vec4 uR;   // radio del anillo, intensidad del anillo, dispersión
uniform vec3 uC0;
uniform vec3 uC1;
uniform vec3 uC2;
uniform vec3 uC3;
out vec4 fragColor;

const float K = 1.6;            // capas por unidad logarítmica
const float TAU = 6.2831853;

// Hash sin seno: el seno con números grandes pierde precisión en móviles.
float hash11(float x) {
  x = fract(x * 0.1031);
  x *= x + 33.33;
  x *= x + x;
  return fract(x);
}

float hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

vec3 cycle(float x) {
  float f = fract(x) * 3.0;
  vec3 a = f < 1.0 ? uC1 : (f < 2.0 ? uC2 : uC3);
  vec3 b = f < 1.0 ? uC2 : (f < 2.0 ? uC3 : uC1);
  return mix(a, b, smoothstep(0.0, 1.0, fract(f)));
}

// Geometría de una capa en coordenadas isótropas: X a lo ancho del sector
// plegado (0 = eje de espejo), Y en profundidad (0..1). Devuelve la distancia
// a las líneas y un relleno suave de vidrio dentro de los pétalos.
vec2 shapes(float X, float Y, float id, float xmax) {
  float h = hash11(id);
  float h2 = hash11(id + 7.3);
  vec2 q = vec2(X, Y - 0.5);
  float d = min(Y, 1.0 - Y);                                      // anillos
  // Pétalos entrelazados, tipo flor de la vida.
  float rr = 0.2 + 0.12 * h;
  float c1 = length(q);
  float c2 = length(q - vec2(xmax * 0.55, 0.0));
  d = min(d, abs(c1 - rr));
  d = min(d, abs(c2 - rr * 0.8));
  // Retícula de rombos plegada en espejo.
  vec2 k = abs(q - vec2(xmax * 0.3, 0.0));
  k = vec2(k.x + k.y, abs(k.x - k.y)) * 0.7071;
  d = min(d, abs(max(k.x, k.y) - (0.07 + 0.08 * h2)));
  // Radios: borde del sector y segmento sobre el eje de espejo.
  d = min(d, abs(X - xmax));
  d = min(d, abs(X) + max(0.0, abs(Y - 0.5) - 0.3 - 0.15 * h2));
  // Gemas en los extremos.
  d = min(d, abs(length(vec2(X - xmax * 0.78, Y - 0.18)) - 0.035 - 0.03 * h));
  float fill = smoothstep(rr, rr * 0.3, c1) * 0.18 + smoothstep(rr * 0.8, 0.0, c2) * 0.1;
  return vec2(d, fill);
}

// Luz de la geometría para una simetría n y un desplazamiento del viaje.
float layerLight(float lr, float a, float n, float shift) {
  float z = lr * K - uA.x + shift;
  float id = floor(z);
  float v = z - id;
  float dir = mod(id, 2.0) < 1.0 ? 1.0 : -1.0;
  float s = fract((a + uB.x * dir) * n / TAU);
  float uf = abs(s - 0.5);                       // sector plegado en espejo
  float xmax = 0.5 * (TAU / n) * K;
  float X = (0.5 - uf) * (TAU / n) * K;          // 0 en el eje, xmax en el borde
  vec2 g = shapes(X, v, id, xmax);
  float core = smoothstep(0.014, 0.0, g.x);
  float glow = 0.016 / (g.x + 0.016);
  return (core * 1.2 + glow * glow * 0.55 + g.y) * (0.55 + 0.45 * v);
}

float light(float lr, float a, float shift) {
  float next = layerLight(lr, a, uS.y, shift);
  if (uS.z >= 0.999) return next;
  return mix(layerLight(lr, a, uS.x, shift), next, uS.z);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  float r = max(length(p), 0.0005);
  float lr = log(r);
  float a = atan(p.y, p.x);
  float kick = uA.z;

  // Dispersión tipo prisma: cada canal recorre el viaje ligeramente desfasado.
  float disp = uR.z;
  float lrR = light(lr, a, disp);
  float lrG = light(lr, a, 0.0);
  float lrB = light(lr, a, -disp);

  float z = lr * K - uA.x;
  vec3 tint = cycle(uB.y + floor(z) * 0.17 + 0.08 * cos(a * 2.0));
  vec3 tint2 = cycle(uB.y + floor(z) * 0.17 + 0.33);
  vec3 col = uC0;
  vec3 glowCol = mix(tint, tint2, 0.5 + 0.5 * sin(a * 3.0 + uB.x * 2.0));
  col += vec3(lrR * glowCol.r, lrG * glowCol.g, lrB * glowCol.b) * (0.55 + 0.55 * uA.y + 0.4 * kick) * uB.w;
  // Núcleos blancos donde la geometría es más intensa.
  col += vec3(1.0) * smoothstep(0.6, 1.1, lrG) * (0.08 + 0.2 * kick);

  // Profundidad: el centro está lejos y oscuro; lo cercano brilla más.
  col *= smoothstep(0.015, 0.35, r) * 0.85 + 0.15;
  // Núcleo de luz en el centro y anillo del golpe.
  col += mix(tint, vec3(1.0), 0.5) * (0.0025 + 0.004 * uA.y + 0.012 * kick) / (r * r + 0.003) * exp(-r * r * 6.0);
  float ring = uR.y * exp(-(r - uR.x) * (r - uR.x) * 8000.0);
  col += mix(tint2, vec3(1.0), 0.15) * ring * 1.6;
  // Centelleo de los bordes con los agudos.
  float tw = step(0.992 - 0.01 * uB.z, hash12(floor(frag * 0.5) + floor(uA.x * 6.0)));
  col += vec3(1.0) * tw * smoothstep(0.4, 0.9, lrG) * uB.z;

  col *= 1.0 - 0.3 * smoothstep(0.6, 1.4, length(p * vec2(0.9, 0.65)));
  // Realce de croma: colores vivos aunque haya mucha luz.
  float luma = dot(col, vec3(0.299, 0.587, 0.114));
  col = max(mix(vec3(luma), col, 1.35), 0.0);
  col = clamp((col * (2.51 * col + 0.03)) / (col * (2.43 * col + 0.59) + 0.14), 0.0, 1.0);
  col = pow(col, vec3(0.4545));
  // Fondo transparente: el color va premultiplicado y la opacidad sale del
  // brillo, así la luz se compone sobre lo que haya debajo.
  col = clamp(col, 0.0, 1.0);
  // La luz muy tenue se vuelve transparente del todo: sin velo sobre la app.
  float veilPeak = max(col.r, max(col.g, col.b));
  float clearCut = smoothstep(0.08, 0.2, veilPeak);
  col *= clearCut;
  float alpha = clamp(veilPeak * 1.25, 0.0, 1.0) * clearCut;
  fragColor = vec4(col, alpha);
}
""",
};
