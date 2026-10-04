// Zoom Infinito Transparente — viaje hacia dentro del fractal de Mandelbrot.
// Versión overlay: mismo movimiento y reacción a la música sin fondo opaco.
// La cámara se hunde en el Valle de los Caballitos de Mar, donde no paran de
// aparecer espirales, y al llegar al límite de precisión vuelve a salir sin
// saltos, como una respiración larga. Colores de fuego por el tiempo de
// escape, que circulan despacio; la energía acelera el viaje, los graves y
// cada golpe encienden el fuego y lo hacen girar.
const nativeSource = r'''
class Visual final : public Scene {
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Viaje en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double travel = 0, spin = 0, hue = 0;
  float hueKick = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    travel = rng.unit() * 4.0;
    spin = rng.unit() * 6.2831853;
    hue = rng.unit();
    hueKick = 0;
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
    if (hit > kick + 0.2f) hueKick += 0.08f * hit;
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    travel += f.delta * f.speed * (0.10 + 0.32 * drive);
    spin += f.delta * f.speed * (0.03 + 0.08 * drive);
    hue += f.delta * (0.02 + 0.06 * energy);
  }

  void render(const Frame& f, Canvas& c) const override {
    float amp = f.intensity;
    // Profundidad en ida y vuelta: 0 a 8,5 unidades logarítmicas de zoom.
    const double depthMax = 8.5;
    double r = std::fmod(travel, 2.0 * depthMax);
    double depth = r < depthMax ? r : 2.0 * depthMax - r;
    // Suavizado en los extremos para que el cambio de sentido no se note.
    double k = depth / depthMax;
    depth = depthMax * (k * k * (3.0 - 2.0 * k));
    float zoom = float(2.6 * std::exp(-depth));
    std::vector<float> u;
    u.reserve(20);
    u.insert(u.end(), {zoom, bass * amp, kick * amp, energy});
    u.insert(u.end(), {float(std::fmod(spin, 6.2831853)), float(std::fmod(hue + hueKick, 1000.0)), f.glow, flash * amp});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("mandel_fire", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'mandel_fire': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // ancho visible del plano, graves, golpe, energía
uniform vec4 uB;   // giro, ciclo de color, glow, destello
uniform vec3 uC0;
uniform vec3 uC1;
uniform vec3 uC2;
uniform vec3 uC3;
out vec4 fragColor;

const vec2 CENTER = vec2(-0.743643887, 0.131825904);

float hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

// Rampa de fuego: negro, rojo, naranja, amarillo y blanco.
vec3 fire(float x) {
  x = fract(x);
  float tri = 1.0 - abs(2.0 * x - 1.0);
  vec3 c = mix(uC0, uC1, smoothstep(0.0, 0.3, tri));
  c = mix(c, uC2, smoothstep(0.3, 0.65, tri));
  c = mix(c, uC3, smoothstep(0.65, 0.92, tri));
  return mix(c, vec3(1.0, 0.97, 0.9), smoothstep(0.93, 1.0, tri));
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  float cs = cos(uB.x);
  float sn = sin(uB.x);
  p = vec2(cs * p.x - sn * p.y, sn * p.x + cs * p.y);
  vec2 c = CENTER + p * uA.x;
  // Más iteraciones cuanto más profundo, con un tope para el móvil.
  float depth = log(2.6 / uA.x);
  float maxIter = 60.0 + 12.0 * depth;
  vec2 z = vec2(0.0);
  float n = 0.0;
  float escaped = 0.0;
  // Dentro de la cardioide principal o del círculo de período 2 nunca se
  // escapa: se salta la iteración (gran ahorro cuando se ve el cuerpo del conjunto).
  float qx = c.x - 0.25;
  float q = qx * qx + c.y * c.y;
  bool inside = q * (q + qx) < 0.25 * c.y * c.y || (c.x + 1.0) * (c.x + 1.0) + c.y * c.y < 0.0625;
  for (int i = 0; i < 165; i++) {
    if (inside) break;
    if (float(i) >= maxIter) break;
    z = vec2(z.x * z.x - z.y * z.y, 2.0 * z.x * z.y) + c;
    if (dot(z, z) > 256.0) {
      escaped = 1.0;
      break;
    }
    n += 1.0;
  }
  vec3 col = uC0;
  if (escaped > 0.5) {
    // Conteo suave de iteraciones para bandas sin escalones.
    float mu = n + 1.0 - log2(log2(dot(z, z)) * 0.5);
    float band = log(mu + 1.0) * 1.7 - uB.y;
    col = fire(band) * (0.85 + 0.35 * uA.y + 0.4 * uA.z) * uB.z;
    // Brillo extra cerca del borde del conjunto, donde vive el detalle.
    col += uC3 * smoothstep(0.55, 1.0, mu / maxIter) * (0.3 + 0.5 * uA.z);
    // Overlay: las bandas de fuego se vuelven líneas de contorno con huecos
    // transparentes; junto al conjunto queda todo el detalle y lejos se apaga.
    float stripe = fract(band * 1.2);
    float lines = smoothstep(0.0, 0.06, stripe) * smoothstep(0.42, 0.3, stripe);
    float nearSet = smoothstep(0.5, 0.85, mu / maxIter);
    col *= max(lines, nearSet) * smoothstep(0.04, 0.15, mu / maxIter);
  } else {
    // Interior transparente.
    col = vec3(0.0);
  }
  col *= 1.0 - 0.3 * smoothstep(0.6, 1.4, length((frag - 0.5 * uSize) / scale * vec2(0.9, 0.65)));
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
