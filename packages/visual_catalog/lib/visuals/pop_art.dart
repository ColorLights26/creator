// Pop Art — un cómic de Lichtenstein que late con la música.
// Una trama de puntos de imprenta (rojo sobre amarillo, girada 45°) dibuja
// ondas que salen del centro; donde la trama roja se aclara aparece una
// segunda tinta cian algo desplazada, como un registro de imprenta mal
// alineado. Cada golpe lanza un estallido de cómic dentado (negro, rojo,
// amarillo y blanco) que nace de golpe y se desinfla, rodeado de líneas
// cinéticas. En modo Warhol la pantalla se divide en paneles, cada uno con
// su combinación de tintas; en Auto se alterna entre cómic y paneles con una
// cortina diagonal cada ocho golpes.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.choice('paleta', 'Estilo', options: ['Auto', 'Cómic', 'Warhol']),
  CreatorModifier.slider('puntos', 'Tamaño de puntos', min: .5, max: 2, value: 1),
  CreatorModifier.toggle('estallido', 'Estallidos', value: true),
  CreatorModifier.toggle('lineas', 'Líneas cinéticas', value: true),
];

const nativeSource = r'''
class Visual final : public Scene {
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double clock = 0, sinceBurst = 100, sinceSwitch = 0;
  float burstX = 0, burstY = 0, burstPower = 0, burstSpin = 0;
  float panels = 0, panelsTarget = 0;
  int beats = 0;
  Random rng{1};

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

 public:
  void reset(uint32_t seed) override {
    rng = Random(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    clock = rng.unit() * 20.0;
    sinceBurst = 100;
    sinceSwitch = 0;
    burstX = burstY = burstPower = 0;
    burstSpin = rng.unit() * 6.28f;
    panels = panelsTarget = 0;
    beats = 0;
  }

  void update(const Frame& f) override {
    float dt = float(f.delta);
    const Music& mu = f.music;
    bass = follow(bass, mu.bass, 22.0f, 4.5f, dt);
    body = follow(body, mu.body, 12.0f, 3.0f, dt);
    spark = follow(spark, mu.spark, 30.0f, 7.0f, dt);
    energy = follow(energy, mu.energy, 6.0f, 1.8f, dt);
    drive = follow(drive, mu.active ? std::pow(std::clamp(mu.energy, 0.0f, 1.0f), 0.8f) : 0.0f, 3.0f, 0.7f, dt);

    float hit = 0, fl = 0;
    for (const auto& e : mu.events[0]) hit = std::max(hit, e.strength);
    for (const auto& e : mu.events[2]) hit = std::max(hit, e.strength * 0.85f);
    for (const auto& e : mu.events[3]) fl = std::max(fl, e.strength);
    float onset = std::clamp((mu.bass - slowBass - 0.15f) * 2.5f, 0.0f, 1.0f);
    slowBass = follow(slowBass, mu.bass, 3.0f, 3.0f, dt);
    hit = std::min(std::max(hit, onset), 1.0f);
    sinceBurst += f.delta;
    sinceSwitch += f.delta;
    if (hit > kick + 0.2f) {
      beats++;
      // Estallido nuevo en un punto distinto cada vez, lejos de los bordes.
      if (sinceBurst > 0.18) {
        sinceBurst = 0;
        burstX = (rng.unit() - 0.5f) * 0.5f;
        burstY = (rng.unit() - 0.5f) * 0.7f;
        burstSpin = rng.unit() * 6.28f;
        burstPower = 0.6f + 0.4f * hit;
      }
      if (beats % 8 == 0) {
        panelsTarget = 1.0f - panelsTarget;
        sinceSwitch = 0;
      }
    }
    if (!mu.active && sinceSwitch > 9.0) {
      panelsTarget = 1.0f - panelsTarget;
      sinceSwitch = 0;
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    // La cortina diagonal cruza la pantalla en algo menos de un segundo.
    float step = dt * 1.6f;
    panels = panelsTarget > panels ? std::min(panelsTarget, panels + step) : std::max(panelsTarget, panels - step);
    clock += f.delta * f.speed * (0.6 + 1.4 * drive);
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    float amp = f.intensity;
    float mode = m.paleta == 1 ? 0.0f : (m.paleta == 2 ? 1.0f : panels);
    // Edad del estallido: nace en 0,12 s y se desinfla durante 0,9 s.
    float age = float(sinceBurst);
    float burst = m.estallido && age < 1.1f ? burstPower * amp : 0.0f;
    std::vector<float> u;
    u.reserve(28);
    u.insert(u.end(), {float(std::fmod(clock, 1000.0)), bass * amp, kick * amp, energy});
    u.insert(u.end(), {m.puntos, m.lineas ? 1.0f : 0.0f, mode, f.glow});
    u.insert(u.end(), {burstX, burstY, age, burst});
    u.insert(u.end(), {burstSpin, flash * amp, spark * amp, drive});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("pop_halftone", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'pop_halftone': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // reloj, graves, golpe, energía
uniform vec4 uB;   // tamaño de puntos, líneas, paneles, glow
uniform vec4 uE;   // estallido: x, y, edad, fuerza
uniform vec4 uF;   // giro del estallido, destello, agudos, empuje
uniform vec3 uC0;
uniform vec3 uC1;
uniform vec3 uC2;
uniform vec3 uC3;
out vec4 fragColor;

const float TAU = 6.2831853;

float hash11(float n) {
  n = fract(n * 0.1031);
  n *= n + 33.33;
  n *= n + n;
  return fract(n);
}

float hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

// Combinaciones de tinta de los paneles Warhol: fondo y puntos.
vec3 panelBg(float k) {
  if (k < 1.0) return uC0;
  if (k < 2.0) return uC1;
  if (k < 3.0) return uC2;
  if (k < 4.0) return uC1;
  if (k < 5.0) return uC0;
  return uC2;
}
vec3 panelInk(float k) {
  if (k < 1.0) return uC1;
  if (k < 2.0) return uC0;
  if (k < 3.0) return uC1;
  if (k < 4.0) return uC2;
  if (k < 5.0) return uC2;
  return uC0;
}

// Campo de tono: ondas que salen del centro, más un pulso con cada golpe.
float tone(vec2 q, float t, float phase) {
  float r = length(q);
  float a = atan(q.y, q.x);
  float v = 0.5 + 0.32 * sin(r * 13.0 - t * 3.0 + phase);
  v += 0.18 * sin(a * 3.0 + t * 0.7 + r * 4.0 + phase);
  v += uA.z * 0.35 * exp(-abs(r - 0.15 - (1.0 - uA.z) * 0.6) * 8.0);
  return clamp(v + 0.25 * uA.y - 0.1, 0.0, 1.0);
}

// Trama de puntos girada; devuelve la cobertura del punto en este píxel.
float halftone(vec2 q, float cell, float angle, float t, float phase, float boost, float px) {
  float cs = cos(angle);
  float sn = sin(angle);
  vec2 g = vec2(cs * q.x + sn * q.y, -sn * q.x + cs * q.y) / cell;
  vec2 id = floor(g) + 0.5;
  vec2 c = vec2(cs * id.x - sn * id.y, sn * id.x + cs * id.y) * cell;
  float v = clamp(tone(c, t, phase) + boost, 0.0, 1.0);
  float radius = sqrt(v) * 0.68 * cell;
  float d = length(g - id) * cell;
  return smoothstep(radius + px, radius - px, d);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  float px = 1.0 / scale;
  float t = uA.x;
  // Cortina diagonal entre el cómic de pantalla completa y los paneles.
  vec2 uv = frag / uSize;
  float wipe = uB.z * 1.6 - 0.3;
  bool usePanels = uv.x * 0.6 + uv.y * 0.4 < wipe;
  vec2 q = p;
  vec3 bg = uC0;
  vec3 ink = uC1;
  vec3 ink2 = uC2;
  float phase = 0.0;
  float border = 1.0;
  if (usePanels) {
    vec2 grid = uSize.x < uSize.y ? vec2(2.0, 3.0) : vec2(3.0, 2.0);
    vec2 cell = floor(uv * grid);
    vec2 local = fract(uv * grid);
    float k = mod(cell.x + cell.y * grid.x, 6.0);
    bg = panelBg(k);
    ink = panelInk(k);
    ink2 = uC3;
    phase = k * 1.7;
    q = (local - 0.5) * uSize / grid / scale * 1.6;
    // Marco negro entre paneles.
    vec2 e = min(local, 1.0 - local) * uSize / grid;
    border = smoothstep(3.0, 4.5, min(e.x, e.y));
  }
  float cell = 0.032 * uB.x;
  float dots = halftone(q, cell, 0.785, t, phase, 0.0, px);
  // Segunda tinta desplazada: aparece donde la primera se aclara.
  float dots2 = halftone(q + vec2(0.006, -0.004), cell * 0.8, 0.26, t, phase + 3.1, -0.45, px);
  vec3 col = bg;
  col = mix(col, ink2, dots2 * 0.9 * (1.0 - dots));
  col = mix(col, ink, dots);
  // Líneas cinéticas desde el centro del estallido.
  vec2 bc = uE.xy;
  vec2 d = p - bc;
  float r = length(d);
  float a = atan(d.y, d.x);
  if (uB.y > 0.5) {
    float rays = 70.0;
    float ray = floor((a / TAU + 0.5) * rays);
    float fr = fract((a / TAU + 0.5) * rays);
    float h = hash11(ray + floor(t * 6.0) * 13.0);
    float width = 0.12 + 0.25 * h;
    float on = step(0.45, h) * smoothstep(width, width * 0.5, abs(fr - 0.5));
    float reach = 0.32 + 0.25 * h - 0.2 * uF.w;
    on *= smoothstep(reach, reach + 0.08, r);
    col = mix(col, uC3, on * clamp(0.25 + 0.75 * max(uF.w, uA.z), 0.0, 1.0));
  }
  // Estallido de cómic: estrella dentada con capas negra, roja, amarilla y blanca.
  if (uE.w > 0.0) {
    float age = uE.z;
    float grow = smoothstep(0.0, 0.12, age);
    float shrink = 1.0 - smoothstep(0.35, 1.1, age);
    float R = (0.16 + 0.14 * uE.w) * grow * shrink * (1.0 + 0.06 * sin(age * 40.0) * shrink);
    float spikes = 13.0;
    float s = fract((a + uF.x) / TAU * spikes);
    float jag = abs(s - 0.5) * 2.0;
    float jit = hash11(floor((a + uF.x) / TAU * spikes) + floor(uF.x * 10.0));
    float star = R * (0.72 + (0.28 + 0.25 * jit) * jag);
    float outline = smoothstep(star + 0.012 + px, star + 0.012, r);
    float red = smoothstep(star + px, star, r);
    float yellow = smoothstep(star * 0.72 + px, star * 0.72, r);
    float white = smoothstep(star * 0.42 + px, star * 0.42, r);
    col = mix(col, uC3, outline);
    col = mix(col, uC1, red);
    col = mix(col, uC0, yellow);
    col = mix(col, vec3(1.0), white);
  }
  col = mix(uC3, col, border);
  col = mix(col, vec3(1.0), uF.y * 0.08);
  // Grano de papel de imprenta.
  col *= 0.97 + 0.03 * hash12(floor(frag));
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
