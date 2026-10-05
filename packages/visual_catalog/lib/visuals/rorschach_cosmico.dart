// Rorschach Cósmico — la mancha es un agujero al universo.
// La tinta no es tinta: es una ventana al espacio profundo. Dentro se ven
// nebulosas de fuego, una galaxia en espiral o un campo de estrellas que
// viaja hacia ti, y el borde brilla como un horizonte de sucesos que curva
// la luz. Alrededor, el papel de la lámina (o el vacío). Los golpes son
// saltos al hiperespacio que estiran las estrellas, los graves encienden
// la nebulosa y los agudos hacen titilar las estrellas.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.choice('interior', 'Dentro de la tinta', options: ['Nebulosa', 'Galaxia', 'Estrellas']),
  CreatorModifier.choice('viaje', 'Viaje', options: ['Deriva', 'Zoom', 'Giro']),
  CreatorModifier.choice('pulso', 'Pulso', options: ['Golpes', 'Graves', 'Agudos']),
  CreatorModifier.slider('horizonte', 'Horizonte', min: 0, max: 1, value: .5),
  CreatorModifier.toggle('papel', 'Papel alrededor', value: true),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Portal', {'interior': 'Galaxia', 'viaje': 'Giro', 'papel': false}),
  CreatorVariation('Hiperespacio', {'interior': 'Estrellas', 'viaje': 'Zoom', 'pulso': 'Golpes', 'horizonte': 1}),
];

const nativeSource = r'''
class Visual final : public Scene {
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double morph = 0, clock = 0, aux = 0, sinceBeat = 100, sinceIdle = 0;
  float spread = 0, spreadVel = 0, beatPower = 0;
  int beats = 0;


  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  static float hashf(int n) {
    uint32_t x = uint32_t(n) * 2654435761u;
    x ^= x >> 15;
    x *= 2246822519u;
    x ^= x >> 13;
    return float(x & 0xffffff) / 16777216.0f;
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    morph = rng.unit() * 40.0;
    clock = 0;
    aux = 0;
    sinceBeat = 100;
    sinceIdle = 0;
    spread = spreadVel = beatPower = 0;
    beats = 0;

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
    sinceBeat += f.delta;
    sinceIdle += f.delta;
    if (hit > kick + 0.2f) {
      spreadVel += 2.2f * hit;
      sinceBeat = 0;
      beatPower = hit;
      beats++;
      sinceIdle = 0;
    }
    // Sin música también hay un sobresalto cada pocos segundos.
    if (!mu.active && sinceIdle > 2.6) {
      sinceIdle -= 2.6;
      sinceBeat = sinceIdle;
      beatPower = 0.7f;
      beats++;
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    spreadVel += (-spread * 18.0f - spreadVel * 5.0f) * dt;
    spread += spreadVel * dt;
    clock += f.delta * f.speed;
    morph += f.delta * f.speed * (0.14 + 0.35 * drive) * 0.6;
    aux += f.delta * f.speed * (0.3 + 1.2 * double(drive));
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    auto g = glide(f);
    float amp = f.intensity;
    float t = float(std::fmod(morph, 1000.0));
    float pulse = sinceBeat < 2.0 ? beatPower * float(std::exp(-sinceBeat * 3.0)) : 0.0f;
    std::vector<float> u;
    u.reserve(56);
    u.insert(u.end(), {t, bass * amp, kick * amp, energy});
    u.insert(u.end(), {g.interior.weight(0), g.interior.weight(1), g.interior.weight(2), std::clamp(g.horizonte, 0.0f, 1.0f)});
    u.insert(u.end(), {f.glow, flash * amp, spark * amp, float(std::fmod(clock, 1000.0))});
    // Lóbulos de la mancha: cinco manchas grandes que derivan despacio.
    static const float lx[5] = {0.12f, 0.24f, 0.2f, 0.32f, 0.08f};
    static const float ly[5] = {-0.32f, -0.12f, 0.1f, 0.3f, 0.5f};
    static const float lr[5] = {0.15f, 0.16f, 0.15f, 0.13f, 0.11f};
    for (int k = 0; k < 5; k++) {
      float fk = float(k);
      u.insert(u.end(), {lx[k] + 0.07f * std::sin(t * 0.7f + fk * 1.9f), ly[k] + 0.07f * std::cos(t * 0.5f + fk * 2.7f), lr[k], 0.0f});
    }
    u.insert(u.end(), {g.viaje.weight(0), g.viaje.weight(1), g.viaje.weight(2), float(std::fmod(aux, 1000.0))});
    u.insert(u.end(), {g.pulso.weight(0), g.pulso.weight(1), g.pulso.weight(2), std::clamp(g.papel, 0.0f, 1.0f)});
    u.insert(u.end(), {pulse, std::max(-0.2f, spread) * amp, f.detail, 0.0f});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("inkblot_cosmos", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'inkblot_cosmos': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // cambio, graves, golpe, energía
uniform vec4 uB;   // ajustes de la variante
uniform vec4 uD;   // glow, destello, agudos, reloj real
uniform vec4 uL0;  // lóbulos: x, y, radio
uniform vec4 uL1;
uniform vec4 uL2;
uniform vec4 uL3;
uniform vec4 uL4;
uniform vec4 uX;   // datos propios de la variante
uniform vec4 uY;   // más datos de la variante
uniform vec4 uP;   // sobresalto, expansión
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

float fbm(vec2 p) {
  float v = 0.0;
  float a = 0.5;
  for (int i = 0; i < 3; i++) {
    v += noise(p) * a;
    p = p * 2.03 + vec2(1.7, 9.2);
    a *= 0.5;
  }
  return v / 0.875;
}

float lobe(vec2 q, vec4 L) {
  vec2 d = q - L.xy;
  return exp(-dot(d, d) / (L.z * L.z));
}

// Campo de tinta: positivo dentro de la mancha. q ya viene reflejado.
float blot(vec2 q, float t, float grow, out vec2 w, out float n) {
  w = vec2(noise(q * 2.2 + vec2(t * 0.6, 0.0)), noise(q * 2.2 + vec2(4.3, -t * 0.5))) - 0.5;
  n = fbm(q * 3.6 + w * 1.4 + vec2(0.0, t * 0.25));
  vec2 qw = q + w * 0.08;
  float env = lobe(qw, uL0) + lobe(qw, uL1) + lobe(qw, uL2) + lobe(qw, uL3) + lobe(qw, uL4);
  env += 0.9 * exp(-q.x * q.x / 0.004) * (1.0 - smoothstep(0.55, 0.95, abs(q.y)));
  return env * 0.8 + (n - 0.5) * 1.1 - 0.5 + grow;
}

vec3 paper(vec2 frag, vec2 p) {
  float fiber = hash12(floor(frag * vec2(0.5, 0.08))) * 0.6 + noise(frag * 0.05) * 0.4;
  vec3 col = uC0 * (0.93 + 0.07 * fiber);
  return col * (1.0 - 0.16 * smoothstep(0.6, 1.4, length(p * vec2(0.9, 0.65))));
}

float sq(float x) {
  return x * x;
}

float stars(vec2 s, float density, float twinkle, float clk, float streak, vec2 radial) {
  vec2 g = s * 40.0;
  vec2 cell = floor(g);
  float h = hash12(cell);
  if (h > density) return 0.0;
  vec2 c = cell + 0.5 + (vec2(hash12(cell + 3.1), hash12(cell + 7.7)) - 0.5) * 0.7;
  vec2 d = g - c;
  // Salto al hiperespacio: la estrella se estira hacia fuera.
  float along = dot(d, radial);
  vec2 perp = d - radial * along;
  float len = length(perp) + max(abs(along) - streak * 1.5, 0.0) * (1.0 - step(streak, 0.02)) + abs(along) * step(streak, 0.02);
  float tw = 1.0 + twinkle * (0.5 + 0.5 * sin(clk * 12.0 + h * 50.0));
  return smoothstep(0.16, 0.0, len) * tw * (0.5 + 0.5 * hash12(cell + 9.1));
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  float t = uA.x;
  float clk = uD.w;
  vec2 q = vec2(abs(p.x), p.y);
  vec2 w;
  float n;
  float F = blot(q, t, 0.1 + 0.12 * uA.y * uY.y + 0.15 * uP.y, w, n);
  float ink = smoothstep(-0.006, 0.006, F);
  // Coordenadas del espacio: deriva, zoom hacia el fondo o giro.
  float tr = uX.w;
  float r = length(p) + 1e-3;
  vec2 radial = p / r;
  vec2 lens = p - radial * 0.05 * exp(-max(F, 0.0) * 12.0) * ink;
  vec2 sDrift = lens + vec2(tr * 0.05, tr * 0.02);
  vec2 sZoom = lens * (1.6 + 0.6 * sin(tr * 0.2));
  float spin = tr * 0.15 / (0.3 + r);
  vec2 sSpin = vec2(cos(spin) * lens.x - sin(spin) * lens.y, sin(spin) * lens.x + cos(spin) * lens.y);
  vec2 s = sDrift * uX.x + sZoom * uX.y + sSpin * uX.z;
  vec3 space = vec3(0.0);
  // El espacio sólo se calcula dentro de la tinta, y sólo lo que se ve.
  if (ink > 0.0) {
    float streak = uP.x * uY.x;
    float st = stars(s, 0.06 * (0.6 + 0.4 * uP.z), uD.z * uY.z, clk, streak, radial);
    if (uB.x > 0.001) {
      float neb = fbm(s * 2.2 + w * 0.5);
      vec3 nebula = mix(uC1 * 0.3, uC2, smoothstep(0.38, 0.75, neb)) + uC3 * smoothstep(0.7, 0.92, neb) * 0.7;
      nebula *= 0.55 + 0.45 * smoothstep(0.2, 0.6, noise(s * 1.3 - 5.0));
      nebula *= 0.65 + 0.35 * noise(s * 5.0 + 3.0);
      nebula *= 1.0 + 0.8 * uA.y * uY.y;
      space += nebula * uB.x;
    }
    if (uB.y > 0.001) {
      float gr = length(s) + 1e-3;
      float ga = atan(s.y, s.x);
      float armsG = pow(max(0.5 + 0.5 * cos(2.0 * ga - log(gr) * 4.0 + tr * 0.3), 0.0), 3.0);
      space += (mix(uC2, uC3, 0.5) * (armsG * exp(-gr * 2.2) * 1.4 + exp(-gr * 7.0) * 1.5) + uC1 * 0.4) * uB.y;
    }
    if (uB.z > 0.001) {
      st += stars(s * 0.5 + 7.3, 0.08, uD.z * uY.z, clk, streak, radial) * 0.7;
      space += (uC1 * 0.25 + uC3 * st * 1.4) * uB.z;
    }
    space += uC3 * st * (1.0 - uB.z) * 0.9;
  }
  // Horizonte: el borde brilla y por dentro hay un resplandor.
  float rim = exp(-abs(F) * 30.0) * (0.5 + 0.5 * uB.w) + exp(-max(F, 0.0) * 8.0) * uB.w * 0.35 * ink;
  space += uC3 * rim * uD.x;
  vec3 outside = paper(frag, p);
  if (uY.w < 0.999) {
    vec3 voidCol = uC1 * 0.15 + uC3 * stars(p + 3.7, 0.03, 0.0, clk, 0.0, radial) * 0.6;
    outside = mix(voidCol, outside, uY.w);
  }
  vec3 col = mix(outside, space, ink);
  col += uC3 * exp(-abs(F) * 60.0) * 0.4 * (1.0 - ink);
  col = mix(col, uC2, uD.y * 0.04);
  float cover = ink;
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
