// Ilusión Óptica — patrones op art que engañan al ojo.
// Cuatro patrones de alto contraste en rojo, negro y blanco: franjas que
// ondulan como las de Bridget Riley, anillos con una burbuja que parece
// salirse de la pantalla, un muaré de dos tramas de anillos que se cruzan y un
// damero que se comprime hacia una costura. Cada ocho golpes (o cada diez
// segundos sin música) se pasa al siguiente con un fundido; cada golpe infla
// la burbuja y los graves aumentan la deformación.
const nativeSource = r'''
class Visual final : public Scene {
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Reloj en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double clock = 0, sinceSwitch = 0;
  int patternA = 0, patternB = 0, beats = 0;
  float blend = 1, bulge = 0, bulgeVel = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  void next() {
    patternA = patternB;
    patternB = (patternB + 1) % 4;
    blend = 0;
    sinceSwitch = 0;
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    clock = rng.unit() * 20.0;
    sinceSwitch = 0;
    patternA = patternB = int(rng.unit() * 4.0f) % 4;
    beats = 0;
    blend = 1;
    bulge = bulgeVel = 0;
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
    if (hit > kick + 0.2f) {
      beats++;
      bulgeVel += 2.4f * hit;
      if (beats % 8 == 0) next();
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    bulgeVel += (-bulge * 30.0f - bulgeVel * 6.0f) * dt;
    bulge += bulgeVel * dt;
    blend = std::min(1.0f, blend + dt * 1.2f);
    sinceSwitch += f.delta;
    if (!m.active && sinceSwitch > 10.0) next();
    clock += f.delta * f.speed * (0.6 + 1.2 * drive);
  }

  void render(const Frame& f, Canvas& c) const override {
    float amp = f.intensity;
    float e = blend * blend * (3.0f - 2.0f * blend);
    std::vector<float> u;
    u.reserve(20);
    u.insert(u.end(), {float(std::fmod(clock, 1000.0)), bass * amp, kick * amp, energy});
    u.insert(u.end(), {float(patternA), float(patternB), e, std::max(-0.3f, bulge) * amp});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("op_art", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'op_art': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // reloj, graves, golpe, energía
uniform vec4 uB;   // patrón actual, patrón siguiente, fundido, burbuja
uniform vec3 uC0;
uniform vec3 uC1;
uniform vec3 uC2;
uniform vec3 uC3;
out vec4 fragColor;

const float PI = 3.14159265;

// Franja suavizada: v cuenta franjas y dv es cuánto cambia v por píxel.
float stripe(float v, float dv) {
  float s = sin(v * PI);
  float aa = max(dv * PI * 1.2, 0.001);
  return smoothstep(-aa, aa, s);
}

// Devuelve blanco (x) y máscara roja (y) del patrón id.
vec2 pattern(float id, vec2 p, float px) {
  float t = uA.x;
  float warp = 0.6 + 0.8 * uA.y;
  if (id < 0.5) {
    // Franjas que ondulan, estilo Bridget Riley; una de cada cinco es roja.
    float k = 16.0;
    float v = (p.y + 0.06 * warp * sin(p.x * 5.0 + t * 1.3) + 0.03 * sin(p.x * 11.0 - t * 0.7)) * k;
    float white = stripe(v, k * px);
    float red = step(4.0, mod(floor(v), 5.0)) * (1.0 - white);
    return vec2(white, red);
  }
  if (id < 1.5) {
    // Anillos con una burbuja que parece salir de la pantalla.
    vec2 bc = vec2(0.22 * sin(t * 0.4), 0.3 * cos(t * 0.33));
    vec2 d = p - bc;
    float rb = 0.32 + 0.12 * uB.w;
    float l = length(d);
    float swell = l < rb ? sqrt(max(rb * rb - l * l, 0.0)) * (0.8 + 0.6 * warp) : 0.0;
    float r = length(p) - swell * 0.35;
    float k = 22.0;
    float v = r * k - t * 2.0;
    float white = stripe(v, k * px * (1.0 + swell * 2.0));
    float red = smoothstep(rb, rb * 0.6, l) * (1.0 - white) * 0.9;
    return vec2(white, red);
  }
  if (id < 2.5) {
    // Muaré: dos tramas de anillos con centros que se separan y se cruzan.
    vec2 o = vec2(0.12 + 0.05 * warp, 0.0) * vec2(cos(t * 0.3), sin(t * 0.3));
    float k = 30.0;
    float a = stripe(length(p - o) * k - t, k * px);
    float b = stripe(length(p + o) * k - t, k * px);
    float white = a * b;
    float red = (1.0 - a) * b;
    return vec2(white, red);
  }
  // Damero comprimido hacia una costura que ondula.
  float seam = 0.25 * sin(t * 0.5) + 0.08 * warp * sin(p.y * 4.0 + t);
  float dx = p.x - seam;
  float sx = sign(dx) * pow(abs(dx) + 0.0001, 0.55) * 1.8;
  float k = 9.0;
  float cx = stripe(sx * k, k * px * 2.5 / (pow(abs(dx) + 0.02, 0.45)));
  float cy = stripe(p.y * k + t * 0.4, k * px);
  float white = abs(cx - cy);
  float red = (1.0 - white) * smoothstep(0.35, 0.0, abs(dx)) * 0.85;
  return vec2(white, red);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  float px = 1.0 / scale;
  vec2 v = pattern(uB.y, p, px);
  if (uB.z < 0.999) v = mix(pattern(uB.x, p, px), v, uB.z);
  vec3 col = mix(uC0, uC2, v.x);
  col = mix(col, uC1, clamp(v.y, 0.0, 1.0));
  // El golpe enciende el rojo y oscurece el blanco un instante.
  col = mix(col, col * vec3(1.0, 0.75, 0.75), 0.4 * uA.z);
  col *= 1.0 - 0.25 * smoothstep(0.6, 1.5, length(p * vec2(0.9, 0.65)));
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
