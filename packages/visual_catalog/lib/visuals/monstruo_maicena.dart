// Monstruo de Maicena — el fluido que cobra vida sobre un altavoz.
// La maicena con agua es un fluido no newtoniano: sobre un altavoz, cada
// golpe de graves la endurece de golpe y de la masa brotan dedos que se
// retuercen, se sostienen un instante y se derrumban otra vez. Aquí la masa
// brillante descansa sobre el cono del altavoz y le salen dedos, garras o
// bulbos al ritmo de la música, con un brillo húmedo y la luz que se cuela
// por los bordes. Con Golpes, cada golpe hace brotar de una vez varios dedos
// más altos (con dos huecos extra), la masa da un salto de tamaño, se
// enciende y un resplandor la rodea; con Graves, los graves sostenidos sacan
// dedos sin parar, la masa respira con un halo y el cono vibra y brilla; con
// Temblor, los agudos rizan la superficie, retuercen los dedos y hacen
// centellear chispas húmedas por toda la masa. Sin música, el altavoz late
// solo y la masa no para.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // FORMA: qué le sale a la masa.
  CreatorModifier.choice(
    'forma',
    'Forma',
    options: ['Dedos', 'Garras', 'Bulbos'],
  ),
  // MOVIMIENTO: de líquida y temblorosa a firme y lenta.
  CreatorModifier.slider('consistencia', 'Consistencia', min: 0, max: 1, value: .45),
  // MÚSICA
  CreatorModifier.choice(
    'pulso',
    'Pulso',
    options: ['Golpes', 'Graves', 'Temblor'],
  ),
  // ATMÓSFERA: de polvo mate a masa húmeda y brillante.
  CreatorModifier.slider('humedad', 'Humedad', min: 0, max: 1, value: .75),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Pesadilla', {
    'forma': 'Garras',
    'consistencia': .1,
    'humedad': 1,
  }),
  CreatorVariation('Laboratorio', {
    'forma': 'Bulbos',
    'consistencia': .9,
    'humedad': .15,
    'pulso': 'Graves',
  }),
];

const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kFingers = 8;
  static constexpr float kGrow = 0.14f;
  // La edad sigue contando tras derrumbarse: así se sabe si el hueco estaba libre.
  struct Finger { float x, lean, width, height; double age; };
  float bass = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, bassCredit = 0;
  // Relojes en doble precisión: sin música es idéntico a 30 y 60 FPS.
  double clock = 0, sinceIdle = 0;
  std::array<Finger, kFingers> fingers{};
  uint32_t spawns = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }
  static float hashU(uint32_t x) {
    x ^= x >> 16; x *= 0x7feb352dU; x ^= x >> 15; x *= 0x846ca68bU; x ^= x >> 16;
    return float(x & 0xffffffu) / 16777216.0f;
  }
  static float holdTime(float cons) { return 0.25f + 0.6f * cons; }
  static float collapseTime(float cons) { return 0.3f + 0.9f * cons; }
  static int capacity(float detail) { return std::clamp(int(std::lround(3.0f + 2.5f * detail)), 3, kFingers); }

  static double lifeTime(float cons) { return double(kGrow + holdTime(cons) + collapseTime(cons)); }
  // Hace brotar un dedo en un hueco que estaba libre en el instante del brote;
  // carry es el tiempo que ya pasó desde entonces. tall alarga los dedos de
  // los golpes (1 = altura normal).
  void sprout(float strength, double carry, int limit, double life, float tall = 1.0f) {
    for (int i = 0; i < limit; i++) {
      Finger& fg = fingers[size_t(i)];
      if (fg.age - carry < life) continue;
      const uint32_t k = spawns++;
      fg.x = (hashU(k * 2654435761u + 3u) - 0.5f) * 0.72f;
      fg.lean = (hashU(k * 2246822519u + 7u) - 0.5f) * 0.5f;
      fg.width = 0.03f + 0.025f * hashU(k * 3266489917u + 11u);
      fg.height = (0.3f + 0.36f * hashU(k * 668265263u + 13u)) * std::clamp(strength, 0.35f, 1.2f);
      if (tall > 1.0f) fg.height = std::min(fg.height * tall, 0.85f);
      fg.age = carry;
      return;
    }
  }
  // Los golpes pueden usar dos huecos más que el resto: sin golpes nunca se
  // ocupan, así que sin música el dibujo no cambia.
  static int burstCapacity(float detail) { return std::min(kFingers, capacity(detail) + 2); }

 public:
  void reset(uint32_t seed) override {
    bass = spark = energy = slowBass = kick = flash = bassCredit = 0;
    clock = 0;
    sinceIdle = 0;
    for (auto& fg : fingers) fg = Finger{0, 0, 0.03f, 0, 1000.0};
    spawns = seed * 13u;
  }

  void update(const Frame& f) override {
    auto m = modifiers(f);
    const float dt = float(f.delta);
    const Music& mu = f.music;
    bass = follow(bass, mu.bass, 22.0f, 4.5f, dt);
    spark = follow(spark, mu.spark, 30.0f, 7.0f, dt);
    energy = follow(energy, mu.energy, 6.0f, 1.8f, dt);
    float hit = 0, fl = 0;
    for (const auto& e : mu.events[0]) hit = std::max(hit, e.strength);
    for (const auto& e : mu.events[2]) hit = std::max(hit, e.strength * 0.85f);
    for (const auto& e : mu.events[3]) fl = std::max(fl, e.strength);
    const float onset = std::clamp((mu.bass - slowBass - 0.15f) * 2.5f, 0.0f, 1.0f);
    slowBass = follow(slowBass, mu.bass, 3.0f, 3.0f, dt);
    hit = std::min(std::max(hit, onset), 1.0f);
    const bool fresh = hit > kick + 0.2f;
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    const double step = f.delta * f.speed;
    clock += step;
    const double life = lifeTime(std::clamp(m.consistencia, 0.0f, 1.0f));
    for (auto& fg : fingers) fg.age = std::min(fg.age + step, 1000.0);
    const int limit = capacity(f.detail);
    const float amp = f.intensity;
    // Golpes: cada golpe hace brotar de una vez varios dedos más altos, más
    // cuanto más fuerte, y puede usar dos huecos extra.
    if (m.pulso == 0 && fresh) {
      const int count = 1 + int(hit * amp * 3.5f);
      const float tall = 1.0f + 0.25f * std::min(hit * amp, 1.0f);
      const int burstLimit = burstCapacity(f.detail);
      for (int i = 0; i < count; i++) sprout(0.7f + 0.5f * hit * amp, 0.0, burstLimit, life, tall);
    }
    // Graves: los graves sostenidos hacen brotar dedos sin parar.
    if (m.pulso == 1) {
      bassCredit += bass * amp * float(step) * 7.0f;
      while (bassCredit >= 1.0f) {
        bassCredit -= 1.0f;
        sprout(0.5f + 0.8f * std::min(bass * amp, 1.0f), 0.0, limit, life);
      }
    }
    // A su ritmo la masa sigue viva; con música, más despacio.
    {
      const double period = !mu.active ? 0.5 : (m.pulso == 2 ? 0.7 : 1.0);
      sinceIdle += step;
      while (sinceIdle >= period) {
        sinceIdle -= period;
        sprout(0.85f, sinceIdle, limit, life);
      }
    }
  }

  void render(const Frame& f, Canvas& c) const override {
    auto g = glide(f);
    const float amp = f.intensity;
    const float cons = std::clamp(g.consistencia, 0.0f, 1.0f);
    const float hold = holdTime(cons), fall = collapseTime(cons);
    // Temblor: los agudos retuercen los dedos con más fuerza.
    const float wobble = (1.2f - cons) * (1.0f + 2.6f * g.pulso.weight(2) * std::min((spark + energy) * amp, 1.0f));
    // Los huecos extra sólo los ocupan los golpes; sin golpes siguen vacíos.
    const int limit = burstCapacity(f.detail);
    std::vector<float> u;
    u.reserve(64);
    const float tremble = g.pulso.weight(2) * std::min((spark * 1.2f + energy * 0.5f) * amp, 1.2f);
    // Golpes: la masa se enciende más con cada golpe.
    const float punch = std::min(kick * amp, 1.0f) * (1.0f + 0.5f * g.pulso.weight(0));
    u.insert(u.end(), {float(std::fmod(clock, 1000.0)), std::min(bass * amp, 1.5f), punch, tremble});
    u.insert(u.end(), {g.forma.weight(0), g.forma.weight(1), g.forma.weight(2), std::clamp(g.humedad, 0.0f, 1.0f)});
    u.insert(u.end(), {wobble, f.glow, std::min(flash * amp, 1.0f), std::min(bass * amp, 1.0f) * (0.4f + 0.6f * g.pulso.weight(1))});
    for (int i = 0; i < kFingers; i++) {
      const Finger& fg = fingers[size_t(i)];
      if (i >= limit || fg.age >= double(kGrow + hold + fall)) {
        u.insert(u.end(), {0.0f, 0.0f, 0.0f, 0.03f});
        continue;
      }
      // Crece con un rebote, se sostiene y se derrumba ensanchándose.
      float h, w = fg.width, lean = fg.lean;
      const float age = float(fg.age);
      if (age < kGrow) {
        const float e = age / kGrow - 1.0f;
        h = fg.height * (1.0f + 2.7f * e * e * e + 1.7f * e * e);
      } else if (age < kGrow + hold) {
        h = fg.height;
      } else {
        const float k = std::clamp((age - kGrow - hold) / fall, 0.0f, 1.0f);
        h = fg.height * (1.0f - k) * (1.0f - k);
        w *= 1.0f + 0.8f * k;
        lean += (lean >= 0 ? 0.6f : -0.6f) * k;
      }
      u.insert(u.end(), {fg.x, std::max(h, 0.0f), lean, w});
    }
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[size_t(i)].r, f.colors[size_t(i)].g, f.colors[size_t(i)].b});
    // Pulso para el material: golpe, graves y agudos de su propia opción.
    u.insert(u.end(), {std::min(kick * amp, 1.0f) * g.pulso.weight(0), std::min(bass * amp, 1.0f) * g.pulso.weight(1),
                       std::min(spark * amp, 1.0f) * g.pulso.weight(2), 0.0f});
    c.material("oobleck", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'oobleck': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // tiempo, graves, golpe, temblor
uniform vec4 uB;   // pesos de forma: dedos, garras, bulbos; humedad
uniform vec4 uE;   // bamboleo, glow, destello, vibración del cono
uniform vec4 uF0;  // dedos: x, altura, inclinación, grosor
uniform vec4 uF1;
uniform vec4 uF2;
uniform vec4 uF3;
uniform vec4 uF4;
uniform vec4 uF5;
uniform vec4 uF6;
uniform vec4 uF7;
uniform vec3 uC0;
uniform vec3 uC1;
uniform vec3 uC2;
uniform vec3 uC3;
uniform vec4 uP;   // pulso: golpe, graves, agudos (cero sin música)
out vec4 fragColor;

float sq(float x) {
  return x * x;
}

const float BASE_Y = -0.135;

float hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

float smin(float a, float b, float k) {
  float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
  return mix(b, a, h) - k * h * (1.0 - h);
}

// Un dedo de masa: tronco que se estrecha y una punta según la forma.
float finger(vec2 p, vec4 F, float t) {
  float h = F.y;
  if (h < 0.004) return 1.0;
  // Lejos del dedo: su distancia basta con una cota.
  float bound = abs(F.z) * 2.2 * h + F.w * 2.0 + 0.06;
  if (abs(p.x - F.x) > bound + 0.06) return 1.0;
  float lean = F.z * (1.0 + 1.2 * uB.y);
  float s = clamp((p.y - BASE_Y) / h, 0.0, 1.0);
  float wob = uE.x * 0.02;
  float xc = F.x + lean * h * s * s + wob * s * sin(s * 7.0 + t * 6.0 + F.x * 23.0);
  float w = F.w;
  float r = w * (uB.x * (1.0 - 0.45 * s) + uB.y * (1.0 - 0.85 * s) + uB.z * (0.75 - 0.25 * s));
  float d = length(p - vec2(xc, BASE_Y + h * s)) - r;
  float tipR = w * (uB.x * 0.55 + uB.y * 0.12 + uB.z * 1.35);
  vec2 tip = vec2(F.x + lean * h + wob * sin(7.0 + t * 6.0 + F.x * 23.0), BASE_Y + h);
  return min(d, length(p - tip) - tipR);
}

float scene(vec2 p, float t) {
  // La masa sobre el cono: una elipse con la superficie que tiembla.
  vec2 q = p - vec2(0.0, -0.19);
  q.y += uA.w * 0.02 * sin(q.x * 40.0 + t * 22.0) + 0.006 * uA.y * sin(q.x * 9.0 - t * 5.0);
  float puddle = (length(q / vec2(0.44, 0.075)) - 1.0) * 0.075;
  // Golpes: la masa da un salto de tamaño (16 %). Graves: respira (12 %).
  puddle -= 0.075 * (0.16 * uP.x + 0.12 * uP.y);
  float k = 0.05;
  float d = puddle;
  d = smin(d, finger(p, uF0, t), k);
  d = smin(d, finger(p, uF1, t), k);
  d = smin(d, finger(p, uF2, t), k);
  d = smin(d, finger(p, uF3, t), k);
  d = smin(d, finger(p, uF4, t), k);
  d = smin(d, finger(p, uF5, t), k);
  d = smin(d, finger(p, uF6, t), k);
  d = smin(d, finger(p, uF7, t), k);
  return d;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  p.y = -p.y;
  float t = uA.x;
  // Fondo: oscuridad con un foco desde arriba y el cono del altavoz.
  vec3 col = uC0 + uC1 * 0.1 * exp(-length(p - vec2(0.0, 0.55)) * 1.6);
  vec2 cq = vec2(p.x, (p.y + 0.19) * 2.6);
  // Graves: el cono vibra y sus anillos brillan.
  float r = length(cq) + uE.w * 0.01 * sin(t * 60.0);
  float cone = smoothstep(0.82, 0.78, r);
  vec3 coneCol = uC0 * 1.6 + uC1 * 0.05 * (1.0 - r);
  float rings = exp(-sq((r - 0.52) / 0.01)) + exp(-sq((r - 0.64) / 0.012)) + 0.6 * exp(-sq((r - 0.76) / 0.015));
  coneCol += uC2 * rings * (0.12 + 0.5 * uE.w);
  col = mix(col, coneCol, cone);
  // Golpes: resplandor aditivo alrededor de la masa. Graves: un halo suave
  // que respira con los graves.
  float haloAmt = uP.x * 0.4 + uP.y * 0.24;
  if (haloAmt > 0.0005) {
    vec2 hq = (p - vec2(0.0, -0.08)) / vec2(0.55, 0.36);
    col += mix(uC2, uC3, 0.35) * haloAmt * uE.y * exp(-dot(hq, hq) * 1.6);
  }
  // La masa sólo se calcula donde puede estar.
  float top = BASE_Y + max(max(max(uF0.y, uF1.y), max(uF2.y, uF3.y)), max(max(uF4.y, uF5.y), max(uF6.y, uF7.y))) + 0.1;
  if (p.y < top && abs(p.x) < 0.66 && p.y > -0.32) {
    float F = scene(p, t);
    float e = 1.5 / scale;
    // Sombra de contacto alrededor de la masa.
    col *= 1.0 - 0.5 * exp(-max(F, 0.0) * 30.0) * smoothstep(-0.05, -0.3, p.y);
    float inside = smoothstep(e, -e, F);
    if (inside > 0.0) {
      vec2 grad = vec2(scene(p + vec2(e, 0.0), t) - F, scene(p + vec2(0.0, e), t) - F) / e;
      float depth = clamp(-F / 0.05, 0.0, 1.0);
      vec3 n = normalize(vec3(grad * (1.0 - depth * 0.85), 0.25 + depth));
      vec3 L = normalize(vec3(-0.45, 0.65, 0.6));
      float diff = max(dot(n, L), 0.0);
      vec3 R = reflect(-L, n);
      float wet = uB.w;
      float spec = pow(max(R.z, 0.0), mix(6.0, 48.0, wet)) * mix(0.12, 1.1, wet);
      float rim = sq(1.0 - n.z);
      vec3 goo = mix(uC1, uC2, 0.3 + 0.7 * diff);
      // La luz se cuela por los bordes finos.
      goo += uC2 * rim * 0.35 * uE.y;
      goo += uC3 * spec;
      // Sin humedad parece polvo mate.
      goo *= mix(0.88 + 0.12 * hash12(floor(frag * 0.7)), 1.0, wet);
      goo *= 1.0 + 0.25 * uA.z + 0.1 * uE.z;
      // Música: todo esto vale cero sin música.
      if (uP.x + uP.y + uP.z > 0.0005) {
        // Golpes y graves: la luz de los bordes sube un 80 %.
        goo += uC2 * rim * 0.28 * uE.y * (uP.x + uP.y);
        // Golpes: la masa entera se enciende (+85 % con la subida de antes).
        goo *= 1.0 + 0.35 * uP.x;
        // Agudos: muchas chispas húmedas centellean por toda la masa.
        goo += uC3 * uP.z * 0.75 * step(0.86, hash12(floor(frag * 0.3) + floor(t * 12.0)));
      }
      col = mix(col, goo, inside);
    }
  }
  col *= 1.0 - 0.3 * smoothstep(0.6, 1.4, length(p * vec2(0.9, 0.65)));
  float peak = max(col.r, max(col.g, col.b));
  if (peak > 0.9) col *= (0.9 + 0.1 * (peak - 0.9) / (peak - 0.8)) / peak;
  col += (hash12(frag) - 0.5) / 255.0;
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
