// Ojo Psicodélico — un ojo gigante surrealista rodeado de ondas que se derriten.
// En el centro hay un ojo con iris de fibras turquesa y doradas que gira
// despacio, una pupila negra y un brillo húmedo; el ojo mira a su alrededor y
// parpadea de vez en cuando. Alrededor, bandas rojas, naranjas, crema y
// turquesa siguen la forma del ojo, ondulan y gotean como pintura fresca. La
// pupila se dilata con los graves y se contrae de golpe con cada golpe, las
// ondas salen hacia fuera con la música y la energía acelera la mirada.
const nativeSource = r'''
class Visual final : public Scene {
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double clock = 0, flow = 0, look = 0;
  float squeeze = 0, squeezeVel = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    clock = rng.unit() * 3.0;
    flow = rng.unit() * 10.0;
    look = rng.unit() * 20.0;
    squeeze = squeezeVel = 0;
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
    if (hit > kick + 0.2f) squeezeVel += 3.0f * hit;
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    // La pupila se contrae con el golpe y vuelve con un muelle.
    squeezeVel += (-squeeze * 35.0f - squeezeVel * 7.0f) * dt;
    squeeze += squeezeVel * dt;
    clock += f.delta;
    flow += f.delta * f.speed * (0.5 + 1.2 * drive + 0.6 * bass);
    look += f.delta * f.speed * (0.25 + 0.5 * drive);
  }

  void render(const Frame& f, Canvas& c) const override {
    float amp = f.intensity;
    // Mirada: el iris se desplaza despacio dentro del ojo.
    float gx = 0.06f * float(std::sin(look * 0.7) + 0.4 * std::sin(look * 1.9));
    float gy = 0.025f * float(std::sin(look * 0.53 + 1.0));
    // Parpadeo cada siete segundos: cierre y apertura en un tercio de segundo.
    double bt = std::fmod(clock, 7.0);
    float open = bt < 0.32 ? float(std::fabs(bt - 0.16) / 0.16) : 1.0f;
    open = open * open * (3.0f - 2.0f * open);
    float pupil = 0.055f * (1.0f + 0.5f * bass * amp) * (1.0f - 0.35f * std::max(0.0f, squeeze) * amp);
    std::vector<float> u;
    u.reserve(24);
    u.insert(u.end(), {float(std::fmod(flow, 1000.0)), bass * amp, kick * amp, energy});
    u.insert(u.end(), {gx, gy, open, pupil});
    u.insert(u.end(), {f.glow, spark * amp, flash * amp, float(std::fmod(clock, 1000.0))});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("psy_eye", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'psy_eye': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // flujo de las ondas, graves, golpe, energía
uniform vec4 uE;   // mirada x, mirada y, apertura del párpado, radio de la pupila
uniform vec4 uB;   // glow, agudos, destello, reloj
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

// Bandas de pintura: rojo, naranja, crema, turquesa y vuelta.
vec3 bands(float x) {
  float k = fract(x) * 5.0;
  vec3 cream = vec3(1.0, 0.86, 0.62);
  vec3 a = k < 1.0 ? uC1 : (k < 2.0 ? uC2 : (k < 3.0 ? cream : (k < 4.0 ? uC3 : uC2)));
  vec3 b = k < 1.0 ? uC2 : (k < 2.0 ? cream : (k < 3.0 ? uC3 : (k < 4.0 ? uC2 : uC1)));
  return mix(a, b, smoothstep(0.75, 1.0, fract(k)));
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  float t = uA.x;
  float W = 0.44;
  float H = 0.24 * uE.z + 0.004;
  // Forma de almendra: el párpado superior y el inferior.
  float x = clamp(p.x / W, -1.0, 1.0);
  float lid = 1.0 - x * x;
  float upper = H * lid * (1.0 + 0.15 * (1.0 - x * x));
  float lower = -H * 0.85 * lid;
  float eyeDist = max(p.y - upper, lower - p.y);
  float outside = abs(p.x) > W ? 1.0 : 0.0;
  float contour = outside > 0.5 ? length(vec2(abs(p.x) - W, p.y)) : max(eyeDist, 0.0);

  // Ondas que siguen la forma del ojo y gotean hacia abajo.
  float drip = pow(noise(vec2(p.x * 6.0, 3.0)), 3.0) * 0.25 * smoothstep(0.0, -0.6, p.y);
  float warp = noise(p * 3.0 + vec2(0.0, t * 0.2)) * 0.12 + drip;
  float waveX = (contour + warp) * 5.5 - t * 0.6;
  vec3 col = bands(waveX) * (0.75 + 0.35 * uA.y + 0.3 * uA.z);
  // Trazos oscuros entre bandas, como pinceladas.
  float stroke = abs(fract(waveX * 5.0) - 0.5);
  col *= 0.82 + 0.18 * smoothstep(0.0, 0.25, stroke);
  col = mix(col, uC0, smoothstep(0.5, 1.3, length(p * vec2(0.9, 0.65))) * 0.5);

  if (eyeDist < 0.0 && outside < 0.5) {
    // Blanco del ojo con venitas rojas y sombra bajo el párpado.
    float veins = smoothstep(0.92, 1.0, 1.0 - abs(noise(p * 18.0) - 0.5) * 2.0) * 0.5;
    vec3 sclera = mix(vec3(1.0, 0.93, 0.85), vec3(0.95, 0.75, 0.6), smoothstep(0.0, 0.5, length(p) * 1.4));
    sclera = mix(sclera, uC1, veins * smoothstep(0.08, 0.3, length(p)));
    sclera *= 0.75 + 0.25 * smoothstep(0.0, 0.06, -eyeDist);
    vec2 ic = vec2(uE.x, uE.y);
    vec2 d = p - ic;
    float r = length(d);
    float a = atan(d.y, d.x) + uB.w * 0.05;
    float Ri = 0.17;
    vec3 eye = sclera;
    if (r < Ri) {
      // Iris: fibras radiales turquesa con un anillo dorado junto a la pupila.
      float fibers = noise(vec2(a * 18.0 / TAU * 6.0, r * 30.0)) * 0.6 + noise(vec2(a * 40.0 / TAU * 6.0, r * 60.0)) * 0.4;
      vec3 iris = mix(uC3 * 0.45, mix(uC3, vec3(0.6, 1.0, 0.95), 0.4), fibers);
      iris = mix(iris, uC2 * 1.1, smoothstep(uE.w * 2.1, uE.w * 1.1, r) * 0.85);
      iris *= 0.6 + 0.4 * smoothstep(Ri, Ri * 0.8, r);
      iris += uC2 * smoothstep(0.98, 1.0, fibers) * uB.y;
      float ring = smoothstep(Ri - 0.012, Ri, r);
      iris = mix(iris, uC3 * 0.15, ring);
      eye = mix(iris, vec3(0.0), smoothstep(uE.w + 0.004, uE.w - 0.002, r));
    }
    // Brillo húmedo de la córnea.
    vec2 hl = p - (ic + vec2(-0.05, 0.05));
    eye += vec3(1.0) * exp(-dot(hl, hl) * 900.0) * 0.9;
    col = mix(col, eye, smoothstep(0.0, 0.006, -eyeDist));
  }
  // Borde del párpado oscuro y pestañas sugeridas.
  float lidLine = exp(-abs(eyeDist) * 160.0) * (1.0 - outside);
  col = mix(col, vec3(0.08, 0.02, 0.02), lidLine * 0.9);
  float lashes = (1.0 - outside) * smoothstep(0.04, 0.0, p.y - upper) * step(upper, p.y) *
                 smoothstep(0.6, 1.0, abs(sin(p.x * 70.0)));
  col = mix(col, vec3(0.06, 0.02, 0.02), lashes * 0.7);
  col += uC2 * uB.z * 0.06;
  col += (hash12(frag) - 0.5) / 255.0;
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
