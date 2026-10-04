// Geometría Islámica — lacería de estrellas que se transforman.
// Cada celda (cuadrada para las estrellas de 8 puntas, hexagonal para las de
// 12) lleva un polígono estrellado: las rectas que unen cada vértice de un
// octógono (o dodecágono) con otro saltando algunos. Esas rectas siguen hasta
// el borde y se reflejan en la celda vecina, formando la lacería continua de
// los azulejos. Las zonas entre cintas se rellenan según cuántas rectas las
// rodean: la estrella central en carmín, sus puntas en esmeralda y el fondo
// en azul noche, con cintas de oro. El salto entre vértices cambia poco a
// poco, así la estrella pasa de {8/2} a {8/3} (o de {12/4} a {12/5}). Cada
// golpe lanza una onda de luz dorada desde el centro, los graves ensanchan
// las cintas y en Auto se alterna entre 8 y 12 puntas cada ocho golpes.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.choice('estrella', 'Estrella', options: ['Auto', '8 puntas', '12 puntas']),
  CreatorModifier.slider('tamano', 'Tamaño', min: .5, max: 2, value: 1),
  CreatorModifier.slider('cinta', 'Grosor de la cinta', min: .5, max: 2, value: 1),
  CreatorModifier.toggle('movimiento', 'Transformación', value: true),
];

const nativeSource = r'''
class Visual final : public Scene {
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double clock = 0, morph = 0, sinceSwitch = 0, pulseAge = 100;
  float fadeMix = 1, pulsePower = 0;
  int beats = 0, autoMode = 0, modeFrom = 0, modeTo = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    clock = rng.unit() * 40.0;
    morph = rng.unit() * 6.28;
    sinceSwitch = 0;
    pulseAge = 100;
    pulsePower = 0;
    fadeMix = 1;
    beats = 0;
    autoMode = modeFrom = modeTo = 0;
  }

  void update(const Frame& f) override {
    auto m = modifiers(f);
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
    sinceSwitch += f.delta;
    pulseAge += f.delta;
    if (hit > kick + 0.2f) {
      beats++;
      pulseAge = 0;
      pulsePower = hit;
      if (beats % 8 == 0) {
        autoMode = 1 - autoMode;
        sinceSwitch = 0;
      }
    }
    // El fundido avanza antes de mirar cambios: si el cambio es por tiempo,
    // empieza en su instante exacto (igual a 30 y 60 FPS).
    fadeMix = std::min(1.0f, fadeMix + dt / 1.2f);
    double carry = -1.0;
    if (!mu.active && sinceSwitch > 12.0) {
      autoMode = 1 - autoMode;
      sinceSwitch -= 12.0;
      carry = sinceSwitch;
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    int wanted = m.estrella == 0 ? autoMode : m.estrella - 1;
    if (wanted != modeTo) {
      modeFrom = modeTo;
      modeTo = wanted;
      fadeMix = carry >= 0.0 ? std::min(1.0f, float(carry / 1.2)) : 0.0f;
    }
    clock += f.delta * f.speed * (1.0 + 0.8 * drive);
    if (m.movimiento) morph += f.delta * f.speed * (0.25 + 0.5 * drive);
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    float amp = f.intensity;
    float shape = 0.5f + 0.5f * float(std::sin(morph));
    float pulse = pulseAge < 3.0 ? float(pulseAge) * 0.9f : 9.0f;
    std::vector<float> u;
    u.reserve(32);
    u.insert(u.end(), {float(std::fmod(clock, 1000.0)), bass * amp, kick * amp, energy});
    u.insert(u.end(), {float(modeFrom), float(modeTo), fadeMix, shape});
    u.insert(u.end(), {m.tamano, m.cinta, f.glow, flash * amp});
    u.insert(u.end(), {pulse, pulseAge < 3.0 ? pulsePower * amp : 0.0f, spark * amp, 0.0f});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("girih", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'girih': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // reloj, graves, golpe, energía
uniform vec4 uB;   // modo anterior, modo nuevo (0 = 8 puntas, 1 = 12), fundido, forma
uniform vec4 uD;   // tamaño, grosor de cinta, glow, destello
uniform vec4 uE;   // radio de la onda, fuerza de la onda, agudos
uniform vec3 uC0;
uniform vec3 uC1;
uniform vec3 uC2;
uniform vec3 uC3;
out vec4 fragColor;

const float PI = 3.14159265;

float hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

// Celda local: cuadrada (8 puntas) o hexagonal (12 puntas).
vec2 cellLocal(vec2 p, float hexMode) {
  if (hexMode < 0.5) return fract(p) - 0.5;
  vec2 r = vec2(1.0, 1.7320508);
  vec2 h = r * 0.5;
  vec2 a = mod(p, r) - h;
  vec2 b = mod(p - h, r) - h;
  return dot(a, a) < dot(b, b) ? a : b;
}

// Estrella {n/k}: distancia a sus rectas y número de rectas que la rodean.
vec2 star(vec2 q, float hexMode, float shape) {
  float n = hexMode < 0.5 ? 8.0 : 12.0;
  float k = hexMode < 0.5 ? mix(2.0, 3.0, shape) : mix(4.0, 5.0, shape);
  float R = hexMode < 0.5 ? 0.56 : 0.6;
  float c = R * cos(k * PI / n);
  float d = 9.0;
  float cnt = 0.0;
  for (int j = 0; j < 12; j++) {
    float fj = float(j);
    if (fj >= n) break;
    float a = (fj + 0.5 * k) * 2.0 * PI / n;
    float s = dot(q, vec2(cos(a), sin(a))) - c;
    d = min(d, abs(s));
    cnt += step(0.0, s);
  }
  return vec2(d, cnt);
}

vec3 tile(vec2 p, float hexMode, float shape, float px, float pulseLight) {
  vec2 q = cellLocal(p, hexMode);
  vec2 s = star(q, hexMode, shape);
  float cnt = s.y;
  // Relleno de las piezas según su sitio en el patrón.
  vec3 fill = cnt < 0.5 ? uC2 : (cnt < 1.5 ? uC3 : (cnt < 2.5 ? uC0 * 2.4 : uC0 * 1.2));
  fill *= 0.85 + 0.25 * uA.y;
  // Cinta de oro con borde oscuro y brillo en el centro.
  float w = 0.03 * uD.y * (1.0 + 0.35 * uA.y);
  float band = 1.0 - smoothstep(w, w + px, s.x);
  float edge = 1.0 - smoothstep(w + px * 1.5, w + px * 3.0, s.x);
  vec3 gold = uC1 * (0.85 + 0.35 * (1.0 - s.x / max(w, 1e-4)) + 0.9 * pulseLight);
  vec3 col = mix(fill, uC0 * 0.35, edge);
  col = mix(col, gold, band);
  return col;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  float t = uA.x;
  // Lento giro y deriva de todo el patrón.
  float ang = t * 0.03;
  float cs = cos(ang);
  float sn = sin(ang);
  vec2 q = vec2(cs * p.x - sn * p.y, sn * p.x + cs * p.y);
  float cells = 3.2 / uD.x;
  q = q * cells + vec2(t * 0.05, t * 0.03);
  float px = cells / scale * 1.2;
  // Onda de luz dorada que sale del centro con cada golpe.
  float pulseLight = uE.y * exp(-abs(length(p) - uE.x) * 10.0);
  vec3 col = tile(q, uB.y, uB.w, px, pulseLight);
  if (uB.z < 0.999) {
    // Cambio de estrella: barrido circular desde el centro con un aro de oro.
    float front = uB.z * 1.9;
    float r = length(p);
    if (r > front) col = tile(q, uB.x, uB.w, px, pulseLight);
    col += uC1 * exp(-abs(r - front) * 40.0) * 1.2;
  }
  // Brillos sueltos sobre el oro con los agudos.
  col += uC1 * step(0.997 - 0.004 * uE.z, hash12(floor(frag * 0.5) + floor(t * 6.0))) * 0.6 * uE.z;
  col *= mix(1.0, uD.z, 0.4) * (0.95 + 0.15 * uA.z);
  col += uC1 * uD.w * 0.05;
  col *= 1.0 - 0.3 * smoothstep(0.7, 1.5, length(p * vec2(0.9, 0.65)));
  float peak = max(col.r, max(col.g, col.b));
  if (peak > 0.85) {
    float e = (peak - 0.85) / 0.15;
    col *= (0.85 + 0.15 * e / (1.0 + e)) / peak;
  }
  col += (hash12(frag) - 0.5) / 255.0;
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
