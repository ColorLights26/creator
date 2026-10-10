// Rorschach Calavera — la calavera que quizá estás imaginando.
// Como en una lámina de verdad, no hay ninguna calavera dibujada: es el hueco
// de papel en el centro de la tinta, con dos islas de tinta donde irían las
// cuencas y una sombra de mandíbula, todo deformado por la tinta que fluye.
// A ratos se lee claramente y a ratos se disuelve en una mancha cualquiera.
// La tinta tiene grano, se acumula más oscura en los bordes y llora regueros
// desde las cuencas. Pulso: Golpes la hace aparecer de golpe y llorar;
// Graves la hace respirar; Agudos hace temblar los bordes.
// Onda expansiva: un aliento de tinta sale de las cuencas, ondula la mancha
// y, al cruzar la cara, hace aparecer la calavera.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.choice('mutacion', 'Metamorfosis', options: ['Cada golpe', 'Cada compás', 'Lenta']),
  CreatorModifier.choice('pulso', 'Pulso', options: ['Golpes', 'Graves', 'Agudos']),
  CreatorModifier.slider('onda', 'Onda expansiva', min: 0, max: 2, value: 1),
  CreatorModifier.slider('presencia', 'Presencia', min: 0, max: 1, value: .7),
  CreatorModifier.slider('lagrimas', 'Lágrimas de tinta', min: 0, max: 1, value: .5),
  CreatorModifier.toggle('negativo', 'Negativo', value: false),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Memento Mori', {'presencia': .9, 'lagrimas': 1, 'pulso': 'Golpes'}),
  CreatorVariation('Duda', {'presencia': .3, 'lagrimas': .2, 'mutacion': 'Lenta'}),
];

const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kLobes = 6;
  static constexpr double kMorph = 0.6;
  struct Lobe { float x, y, r, w; };
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: sin música es idéntico a 30 y 60 FPS.
  double clock = 0, flow = 0, aux = 0, shapeAt = -100, sinceBeat = 100, sinceIdle = 0;
  float beatPower = 0, spread = 0, spreadVel = 0;
  uint32_t shapes = 0, beats = 0;
  std::array<Lobe, kLobes> from{}, to{};
  // Ondas expansivas: nacen con cada golpe. Música fuerte: onda fuerte,
  // rápida y nítida; música tranquila: baja, lenta y suave.
  struct Wave { double born; float power, speed, width, decay; };
  static constexpr int kWaves = 4;
  std::array<Wave, kWaves> waves{};
  uint32_t waveNext = 0;
  double lastWave = -100;
  float lastPhase = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }
  static float hashU(uint32_t x) {
    x ^= x >> 16; x *= 0x7feb352dU; x ^= x >> 15; x *= 0x846ca68bU; x ^= x >> 16;
    return float(x & 0xffffffu) / 16777216.0f;
  }
  // Rebote al llegar a la forma nueva: se pasa un poco y vuelve.
  static float easeBack(float p) {
    p = std::clamp(p, 0.0f, 1.0f);
    const float e = p - 1.0f;
    return 1.0f + 2.4f * e * e * e + 1.4f * e * e;
  }
  // Lóbulo i de la forma número k: el primero es siempre el cuerpo central;
  // algunos son negativos y abren huecos de papel dentro de la tinta.
  static Lobe pick(uint32_t k, int i) {
    const uint32_t s = k * 2654435761u + uint32_t(i) * 2246822519u + 0x9e3779b9u;
    const float a = hashU(s + 1u), b = hashU(s + 2u), c = hashU(s + 3u), d = hashU(s + 4u);
    if (i == 0) return {0.02f + 0.05f * a, -0.15f + 0.3f * b, 0.17f + 0.06f * c, 1.0f};
    Lobe L;
    L.x = 0.04f + 0.38f * a * a;
    L.y = -0.62f + 1.24f * b;
    L.r = 0.07f + 0.13f * c;
    L.w = d < 0.22f ? -0.45f - 0.4f * hashU(s + 5u) : 0.7f + 0.5f * hashU(s + 6u);
    return L;
  }
  Lobe lobeAt(int i, double time) const {
    const float e = easeBack(float((time - shapeAt) / kMorph));
    const Lobe& a = from[size_t(i)];
    const Lobe& b = to[size_t(i)];
    return {a.x + (b.x - a.x) * e, a.y + (b.y - a.y) * e, std::max(0.03f, a.r + (b.r - a.r) * e), a.w + (b.w - a.w) * e};
  }
  // Forma nueva; carry es el tiempo que ya pasó desde el instante del cambio.
  void newShape(double carry) {
    const double at = clock - carry;

    for (int i = 0; i < kLobes; i++) from[size_t(i)] = lobeAt(i, at);
    shapes++;
    for (int i = 0; i < kLobes; i++) to[size_t(i)] = pick(shapes, i);
    shapeAt = at;

  }
  void spawnWave(double at, float power, float speed, float width, float decay) {
    waves[size_t(waveNext % uint32_t(kWaves))] = {at, power, speed, width, decay};
    waveNext++;
    lastWave = at;
  }

 public:
  void reset(uint32_t seed) override {
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    clock = flow = aux = 0;
    shapeAt = -100;
    sinceBeat = 100;
    sinceIdle = 0;
    beatPower = spread = spreadVel = 0;
    shapes = seed % 977u;
    beats = 0;
    for (auto& wv : waves) wv = {-100.0, 0.0f, 0.0f, 0.05f, 1.0f};
    waveNext = 0;
    lastWave = -100;
    lastPhase = 0;
    for (int i = 0; i < kLobes; i++) from[size_t(i)] = to[size_t(i)] = pick(shapes, i);

  }

  void update(const Frame& f) override {
    auto m = modifiers(f);
    const float dt = float(f.delta);
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
    const float onset = std::clamp((mu.bass - slowBass - 0.15f) * 2.5f, 0.0f, 1.0f);
    slowBass = follow(slowBass, mu.bass, 3.0f, 3.0f, dt);
    hit = std::min(std::max(hit, onset), 1.0f);
    const bool fresh = hit > kick + 0.2f;
    sinceBeat += f.delta;
    if (fresh) {
      spreadVel += 2.2f * hit;
      sinceBeat = 0;
      beatPower = hit;
      beats++;
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    spreadVel += (-spread * 18.0f - spreadVel * 5.0f) * dt;
    spread += spreadVel * dt;
    const double step = f.delta * f.speed;
    clock += step;
    // La tinta fluye más deprisa con la energía y con cada golpe.
    flow += step * (0.3 + 1.2 * double(drive) + 0.9 * double(kick)) * 0.8;
    // Onda expansiva con cada golpe: su fuerza y su velocidad salen de la
    // música (lo fuerte que suena y lo fuerte que pega el golpe).
    if (fresh && mu.active && clock - lastWave > 0.16) {
      const float lv = std::clamp(std::max(drive, energy), 0.0f, 1.0f);
      spawnWave(clock, (0.3f + 0.7f * hit) * (0.35f + 0.85f * lv), 0.3f + 1.25f * lv + 0.35f * hit,
                0.085f - 0.045f * lv, 0.8f + 2.4f * lv);
    }
    // Música tranquila, sin golpes marcados: la onda sigue el pulso del tema
    // (o los acentos) y, si no hay pulso, sale cada pocos segundos; baja y lenta.
    if (mu.active) {
      float accent = 0;
      for (const auto& e : mu.events[1]) accent = std::max(accent, e.strength);
      const bool tick = (mu.bpm > 0.0f && mu.phase + 0.5f < lastPhase) || accent > 0.15f;
      const double quiet = clock - lastWave;
      if ((tick && quiet > 0.45) || quiet > 2.4) {
        const float lv = std::clamp(std::max(drive, energy), 0.0f, 1.0f);
        spawnWave(clock, 0.3f + 0.45f * lv, 0.3f + 0.6f * lv, 0.09f - 0.03f * lv, 0.9f + 1.2f * lv);
      }
    }
    lastPhase = mu.phase;
    // Metamorfosis: la forma cambia con cada golpe, cada cuatro o despacio.
    if (fresh && mu.active && m.mutacion != 2) {
      const uint32_t every = m.mutacion == 0 ? 1u : 4u;
      if (beats % every == 0u && clock - shapeAt > 0.4) newShape(0.0);
    }
    if (!mu.active || m.mutacion == 2) {
      const double idle = m.mutacion == 2 ? 2.8 * 1.8 : 2.8;
      sinceIdle += step;
      while (sinceIdle >= idle) {
        sinceIdle -= idle;
        newShape(sinceIdle);
        if (!mu.active) {
          // Sin música, cada forma nueva llega con un sobresalto.
          beatPower = 0.6f;
          sinceBeat = sinceIdle;
          // ...y con una onda baja y lenta.
          spawnWave(clock - sinceIdle, 0.32f, 0.38f, 0.09f, 1.0f);
        }
      }
    }
    aux += step * (0.25 + 0.6 * double(drive));
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    auto g = glide(f);
    (void)m;
    const float amp = f.intensity;
    const float pulse = sinceBeat < 2.0 ? beatPower * float(std::exp(-sinceBeat * 3.0)) : 0.0f;
    // Pulso: cada opción mueve una parte distinta de la mancha.
    const float golpe = std::min(pulse * amp, 1.2f) * g.pulso.weight(0);
    const float graves = std::min(bass * amp, 1.2f) * g.pulso.weight(1);
    const float agudos = std::min(spark * amp, 1.2f) * g.pulso.weight(2);
    const float morphP = float(std::clamp((clock - shapeAt) / kMorph, 0.0, 1.0));
    const float ft = float(std::fmod(flow, 1000.0));

    std::vector<float> u;
    u.reserve(80);
    u.insert(u.end(), {ft, std::min(bass * amp, 1.5f), std::min(kick * amp, 1.0f), std::min(energy * amp, 1.0f)});
    u.insert(u.end(), {g.presencia, g.lagrimas, g.negativo, f.detail});
    u.insert(u.end(), {f.glow, std::min(flash * amp, 1.0f), std::min(spark * amp, 1.0f), float(std::fmod(clock, 1000.0))});
    // Los lóbulos orbitan alrededor de su sitio; los graves los hinchan.
    const float wob = 0.045f * (1.0f + 0.8f * graves);
    for (int i = 0; i < kLobes; i++) {
      Lobe L = lobeAt(i, clock);
      const float fi = float(i);
      L.x = std::max(0.0f, L.x + wob * std::sin(ft * 0.83f + fi * 1.7f));
      L.y += wob * 1.3f * std::cos(ft * 0.61f + fi * 2.3f);
      L.r *= 1.0f + 0.12f * graves + 0.06f * std::sin(ft * 1.1f + fi);
      u.insert(u.end(), {L.x, L.y, L.r, L.w});
    }
    u.insert(u.end(), {float(std::fmod(aux, 1000.0)), float(std::min(clock - shapeAt, 30.0)), 0.0f, 0.0f});
    u.insert(u.end(), {golpe, graves, agudos, morphP});
    u.insert(u.end(), {std::max(-0.2f, spread) * amp * g.pulso.weight(0), float(std::min(sinceBeat, 9.0)),
                       std::min(pulse * amp, 1.2f), float(shapes % 997u)});
    // Ondas: radio, fuerza, ancho y edad. Se frenan al crecer y se apagan.
    const float ondaK = amp * g.onda;
    for (const Wave& wv : waves) {
      const float a = float(std::min(std::max(clock - wv.born, 0.0), 30.0));
      const float radius = wv.speed * a / (1.0f + 0.35f * a);
      float power = std::min(wv.power * std::exp(-a * wv.decay) * ondaK, 1.6f);
      if (power < 0.004f) power = 0.0f;
      u.insert(u.end(), {radius, power, wv.width * (1.0f + 0.6f * radius), a});
    }
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[size_t(i)].r, f.colors[size_t(i)].g, f.colors[size_t(i)].b});
    c.material("inkblot_skull", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'inkblot_skull': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // flujo de la tinta, graves, golpe, energía
uniform vec4 uB;   // ajustes de la variante
uniform vec4 uD;   // glow, destello, agudos, reloj
uniform vec4 uL0;  // lóbulos: x, y, radio, peso (negativo = hueco)
uniform vec4 uL1;
uniform vec4 uL2;
uniform vec4 uL3;
uniform vec4 uL4;
uniform vec4 uL5;
uniform vec4 uX;   // datos de la variante
uniform vec4 uY;   // Pulso: golpe, graves, agudos; avance del cambio de forma
uniform vec4 uP;   // expansión del golpe, edad del golpe, golpe, número de forma
uniform vec4 uW0;  // ondas expansivas: radio, fuerza, ancho, edad
uniform vec4 uW1;
uniform vec4 uW2;
uniform vec4 uW3;
uniform vec3 uC0;
uniform vec3 uC1;
uniform vec3 uC2;
uniform vec3 uC3;
out vec4 fragColor;

const float TAU = 6.2831853;

float sq(float x) {
  return x * x;
}

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
  return L.w * exp(-dot(d, d) / (L.z * L.z));
}

// La silueta sin ruido: los seis lóbulos y el eje del pliegue.
float envelope(vec2 q) {
  float e = lobe(q, uL0) + lobe(q, uL1) + lobe(q, uL2) + lobe(q, uL3) + lobe(q, uL4) + lobe(q, uL5);
  return e + 0.85 * exp(-q.x * q.x / 0.0035) * (1.0 - smoothstep(0.5, 0.92, abs(q.y)));
}

// Campo de tinta (positivo dentro). q ya viene reflejado. Los agudos agitan
// los bordes.
float blot(vec2 q, float t, float grow, out vec2 w, out float n) {
  w = vec2(noise(q * 1.9 + vec2(t * 0.42, 1.3)), noise(q * 1.9 + vec2(5.1, -t * 0.37))) - 0.5;
  vec2 qq = q + w * (0.13 + 0.16 * uY.z);
  n = fbm(qq * 3.3 + vec2(0.0, t * 0.5));
  float fine = noise(qq * 11.0 + vec2(t * 0.3, 2.0)) - 0.5;
  return envelope(qq) * 0.85 + (n - 0.5) * 1.15 + fine * 0.15 - 0.52 + grow;
}

// Los graves hinchan la mancha y el golpe la empuja hacia fuera.
float growth() {
  return 0.08 * uY.y + 0.22 * uP.x + 0.04 * uA.w;
}

// Ondas expansivas de la música; d es la distancia al origen de la onda.
float ringOf(vec4 W, float d) {
  float x = (d - W.x) / W.z;
  return W.y * exp(-x * x);
}

// Frente: el anillo de todas las ondas.
float waveFront(float d) {
  return ringOf(uW0, d) + ringOf(uW1, d) + ringOf(uW2, d) + ringOf(uW3, d);
}

// Rizo con signo: el frente y dos ecos detrás que se apagan.
float rippleOf(vec4 W, float d) {
  float x = (d - W.x) / W.z;
  return W.y * exp(-x * x * (x > 0.0 ? 1.0 : 0.22)) * cos(x * 2.6);
}

float waveRipple(float d) {
  return rippleOf(uW0, d) + rippleOf(uW1, d) + rippleOf(uW2, d) + rippleOf(uW3, d);
}

// Estela: lo que la onda ya ha barrido, apagándose hacia el centro.
float wakeOf(vec4 W, float d) {
  return W.y * smoothstep(W.x + W.z, W.x - W.z, d) * exp(-max(W.x - d, 0.0) * 5.0);
}

float waveWake(float d) {
  return wakeOf(uW0, d) + wakeOf(uW1, d) + wakeOf(uW2, d) + wakeOf(uW3, d);
}

vec3 paper(vec2 frag, vec2 p) {
  float fiber = hash12(floor(frag * vec2(0.5, 0.08))) * 0.6 + noise(frag * 0.05) * 0.4;
  vec3 col = uC0 * (0.92 + 0.08 * fiber);
  return col * (1.0 - 0.18 * smoothstep(0.55, 1.4, length(p * vec2(0.9, 0.62))));
}

// Tinta de calidad: lavado más claro donde es fina, borde acumulado más
// oscuro y grano de pigmento.
vec3 inkShade(vec3 inkC, vec3 tint, float F, float n, vec2 frag) {
  float grain = noise(frag * 0.9) * 0.5 + noise(frag * 0.23) * 0.5;
  float thin = 1.0 - smoothstep(0.0, 0.35, F);
  vec3 c = mix(inkC, tint, 0.1 + 0.32 * thin * (0.4 + 0.6 * n)) * (0.82 + 0.3 * grain);
  float pool = smoothstep(0.07, 0.0, F) * smoothstep(-0.012, 0.012, F);
  return mix(c, inkC * 0.35, pool * 0.85);
}

// Gotas que saltan alrededor del borde.
float spatter(vec2 q, float F, float amount, float seed) {
  if (F > 0.0 || F < -0.4) return 0.0;
  vec2 g = q * 30.0;
  vec2 cell = floor(g);
  if (hash12(cell + seed) > amount) return 0.0;
  vec2 off = vec2(hash12(cell + 3.1 + seed), hash12(cell + 7.7 + seed)) - 0.5;
  float rad = 0.08 + 0.25 * hash12(cell + 11.3);
  return 1.0 - smoothstep(rad - 0.05, rad, length(fract(g) - 0.5 - off * 0.45));
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  float t = uA.x;
  float br = uX.x;
  float age = uX.y;
  vec2 q = vec2(abs(p.x), p.y);
  vec2 w;
  float n;
  float F = blot(q, t, growth() + 0.05, w, n);
  // Onda expansiva: un aliento de tinta sale de las cuencas y ondula la
  // mancha; cuando cruza la cara, la calavera aparece.
  float cd = length(p - vec2(0.0, -0.1));
  float cf = waveFront(cd);
  F += 0.16 * waveRipple(cd);
  float reveal = clamp(waveFront(0.14) + 0.6 * waveWake(0.14), 0.0, 1.0);
  // La calavera sólo se insinúa: aparece y desaparece despacio.
  float pres = clamp(uB.x * (0.6 + 0.4 * sin(br * 0.55)) + 0.45 * uY.x + 0.7 * reveal * (0.25 + 0.75 * uB.x), 0.0, 1.0);
  vec2 qw = q + w * 0.1;
  // Tinta alrededor: la calavera es el hueco de papel que queda dentro.
  float halo = exp(-sq(length((qw - vec2(0.0, -0.02)) / vec2(0.36, 0.5))));
  float cr = length((qw - vec2(0.0, -0.1)) / vec2(0.19, 0.21));
  float jaw = length((qw - vec2(0.0, 0.1)) / vec2(0.12, 0.1));
  float skullM = max(smoothstep(1.15, 0.75, cr), smoothstep(1.2, 0.7, jaw));
  // Cuencas, nariz y dientes: islas de tinta dentro del hueco.
  vec2 eyeC = vec2(0.082 + 0.012 * sin(br), -0.1);
  float socket = smoothstep(1.1, 0.65, length((qw - eyeC) / vec2(0.055, 0.05 * (1.0 + 0.25 * uY.y))));
  float nose = smoothstep(1.1, 0.6, length((qw - vec2(0.0, 0.012)) / vec2(0.02, 0.035)));
  float teeth = smoothstep(0.55, 0.9, sin(qw.x * 70.0)) * exp(-sq((qw.y - 0.115) / 0.018)) * step(qw.x, 0.09);
  F += pres * (1.2 * halo - 2.6 * skullM + 2.8 * socket + 2.2 * nose + 1.2 * teeth);
  // Lágrimas de tinta que bajan desde las cuencas.
  float tears = 0.0;
  for (int k = 0; k < 3; k++) {
    float fk = float(k);
    float dx = eyeC.x - 0.025 + 0.025 * fk + 0.01 * (hash12(vec2(fk, uP.w)) - 0.5);
    float y0 = eyeC.y + 0.04;
    float len = uB.y * pres * (0.1 + 0.25 * hash12(vec2(fk, uP.w + 1.0))) * (1.0 - exp(-age * (0.4 + 1.2 * uY.x))) * (1.0 + 0.6 * reveal);
    float along = qw.y - y0;
    float wd = 0.006 * (1.0 - 0.5 * clamp(along / max(len, 0.01), 0.0, 1.0));
    float stem = step(0.0, along) * step(along, len) * smoothstep(wd, wd * 0.4, abs(qw.x - dx));
    float bulb = smoothstep(wd * 2.0, wd * 1.3, length(qw - vec2(dx, y0 + len)));
    tears = max(tears, max(stem, bulb) * step(0.01, len));
  }
  float ink = max(smoothstep(-0.007, 0.007, F), tears);
  float grain = noise(frag * 0.9) * 0.5 + noise(frag * 0.23) * 0.5;
  vec3 inkCol = inkShade(uC1, uC2, F, n, frag);
  vec3 pap = paper(frag, p);
  pap = mix(pap, uC3, 0.2 * smoothstep(-0.12, 0.0, F) * (1.0 - ink));
  // Al paso de la onda el papel se lava con un cerco de tinta.
  pap = mix(pap, uC1 * 0.5 + uC0 * 0.5, 0.34 * clamp(cf, 0.0, 1.0));
  vec3 col = mix(pap, inkCol, ink);
  // Negativo: papel oscuro y tinta de hueso.
  vec3 neg = mix(uC1 * 0.6 + uC2 * 0.1, mix(uC3, uC0, 0.4) * (0.85 + 0.25 * grain), ink);
  col = mix(col, neg, uB.z);
  col += uC2 * 0.12 * pres * uY.x * (1.0 - ink) * exp(-sq(length(qw - vec2(0.0, -0.05)) / 0.25));
  float sp = spatter(q, F, 0.02 + 0.25 * uY.z + 0.15 * uY.x, floor(uD.w * 5.0));
  col = mix(col, mix(uC1, uC3, uB.z), sp);
  col = mix(col, uC2, uD.y * 0.04);
  col *= 0.97 + 0.03 * uD.x;
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
