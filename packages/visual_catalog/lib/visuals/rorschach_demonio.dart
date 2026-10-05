// Rorschach Demonio — algo arde dentro de la mancha.
// La tinta es una costra negra con grietas de lava que se mueven por dentro.
// No hay una cara dibujada: a veces, entre las grietas, se abren dos
// rendijas de brasa simétricas que parecen mirarte, y se apagan antes de que
// estés seguro. El aire tiembla de calor y suben brasas. La forma cambia con
// cada golpe. Pulso: Golpes hace estallar la lava, abre los ojos y lanza
// brasas; Graves hace respirar el fuego; Agudos agita las grietas.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.choice('mutacion', 'Metamorfosis', options: ['Cada golpe', 'Cada compás', 'Lenta']),
  CreatorModifier.choice('pulso', 'Pulso', options: ['Golpes', 'Graves', 'Agudos']),
  CreatorModifier.slider('grietas', 'Grietas', min: 0, max: 1, value: .5),
  CreatorModifier.slider('mirada', 'Mirada', min: 0, max: 1, value: .5),
  CreatorModifier.slider('brasas', 'Brasas', min: 0, max: 1, value: .5),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Infierno', {'grietas': 1, 'brasas': 1, 'mutacion': 'Cada golpe'}),
  CreatorVariation('Acecho', {'grietas': .2, 'mirada': 1, 'pulso': 'Graves', 'mutacion': 'Lenta'}),
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
    // Metamorfosis: la forma cambia con cada golpe, cada cuatro o despacio.
    if (fresh && mu.active && m.mutacion != 2) {
      const uint32_t every = m.mutacion == 0 ? 1u : 4u;
      if (beats % every == 0u && clock - shapeAt > 0.35) newShape(0.0);
    }
    if (!mu.active || m.mutacion == 2) {
      const double idle = m.mutacion == 2 ? 2.6 * 1.8 : 2.6;
      sinceIdle += step;
      while (sinceIdle >= idle) {
        sinceIdle -= idle;
        newShape(sinceIdle);
        if (!mu.active) {
          // Sin música, cada forma nueva llega con un sobresalto.
          beatPower = 0.6f;
          sinceBeat = sinceIdle;
        }
      }
    }
    aux += step * (0.3 + 1.4 * double(bass) + 0.8 * double(kick));
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
    u.reserve(64);
    u.insert(u.end(), {ft, std::min(bass * amp, 1.5f), std::min(kick * amp, 1.0f), std::min(energy * amp, 1.0f)});
    u.insert(u.end(), {g.grietas, g.mirada, g.brasas, f.detail});
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
    u.insert(u.end(), {float(std::fmod(aux, 1000.0)), float(std::fmod(clock, 1000.0)), 0.0f, 0.0f});
    u.insert(u.end(), {golpe, graves, agudos, morphP});
    u.insert(u.end(), {std::max(-0.2f, spread) * amp * g.pulso.weight(0), float(std::min(sinceBeat, 9.0)),
                       std::min(pulse * amp, 1.2f), float(shapes % 997u)});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[size_t(i)].r, f.colors[size_t(i)].g, f.colors[size_t(i)].b});
    c.material("inkblot_demon", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'inkblot_demon': r"""
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
  vec2 p0 = (frag - 0.5 * uSize) / scale;
  float t = uA.x;
  float heatT = uX.x;
  float clk = uX.y;
  // El aire tiembla de calor por encima de la mancha.
  vec2 p = p0 + vec2(0.006 * sin(p0.y * 30.0 + clk * 5.0) * smoothstep(0.3, -0.6, p0.y), 0.0);
  vec2 q = vec2(abs(p.x), p.y);
  vec2 w;
  float n;
  float F = blot(q, t, growth() + 0.06, w, n);
  float ink = smoothstep(-0.008, 0.008, F);
  // Grietas de lava: crestas del ruido que se mueven dentro de la costra.
  vec2 cq = q * 6.0 + w * 2.0 + vec2(0.0, -heatT * 0.3);
  float c1 = 1.0 - abs(2.0 * noise(cq) - 1.0);
  float c2 = 1.0 - abs(2.0 * noise(cq * 2.1 + 4.0) - 1.0);
  float crack = max(c1, c2 * 0.85);
  float thr = 0.87 - 0.14 * uB.x - 0.07 * uY.y - 0.12 * uY.x - 0.04 * uY.z;
  float lava = smoothstep(thr, thr + 0.05, crack) * smoothstep(0.02, 0.12, F);
  float heat = lava * (0.65 + 0.35 * sin(heatT * 3.0 + n * 6.0)) * (1.0 + 1.6 * uY.x + 0.9 * uY.y);
  // Ojos: dos rendijas de brasa que a veces se abren y se apagan.
  float sid = uP.w;
  float pres = uB.y * smoothstep(0.45, 0.85, 0.5 + 0.5 * sin(clk * 0.37 + sid) + 0.7 * uY.x);
  vec2 ep = vec2(0.09 + 0.06 * hash12(vec2(sid, 1.0)), -0.14 + 0.12 * hash12(vec2(sid, 2.0)));
  vec2 ed = q - ep;
  float tilt = 0.25 + 0.3 * hash12(vec2(sid, 3.0));
  ed = vec2(cos(tilt) * ed.x + sin(tilt) * ed.y, -sin(tilt) * ed.x + cos(tilt) * ed.y);
  float slit = length(ed / vec2(0.065, 0.01 + 0.022 * uY.x + 0.006 * uY.y));
  float eye = smoothstep(1.0, 0.55, slit) * pres * smoothstep(0.03, 0.12, F);
  // Fondo de humo rojizo que sube, más claro que la costra.
  float smoke = fbm(p0 * 2.5 + vec2(0.0, clk * 0.15));
  vec3 col = uC0 * 2.2 + uC2 * (0.05 + 0.1 * smoke) * (0.6 + 0.6 * smoothstep(0.9, -0.3, p0.y));
  vec3 crust = uC1 * (0.3 + 0.35 * n) + uC2 * 0.06 * smoothstep(0.55, 0.8, noise(q * 25.0 + w * 4.0));
  vec3 lavaCol = mix(uC2, uC3, clamp(heat - 0.6, 0.0, 1.0));
  vec3 inkCol = mix(crust, lavaCol, clamp(heat, 0.0, 1.0));
  inkCol += uC2 * smoothstep(0.08, 0.0, F) * (0.15 + 0.7 * uY.x);
  inkCol = mix(inkCol, mix(uC3, vec3(1.0), 0.3), eye);
  col = mix(col, inkCol, ink);
  // Resplandor: el fuego se escapa por el borde y alrededor de los ojos.
  col += uC2 * exp(-abs(F) * 9.0) * (0.12 + 0.55 * uY.x + 0.25 * uY.y) * (1.0 - ink * 0.5) * uD.x;
  col += uC2 * exp(-slit * 1.2) * pres * 0.35;
  // Brasas que suben.
  vec2 bgc = p0 * vec2(14.0, 8.0) + vec2(0.0, clk * (0.6 + 1.2 * uY.x));
  vec2 bc = floor(bgc);
  float bh = hash12(bc);
  float ember = step(1.0 - 0.12 * uB.z - 0.08 * uY.x, bh) * smoothstep(0.25, 0.0, length(fract(bgc) - 0.5 - (vec2(hash12(bc + 3.1), hash12(bc + 5.7)) - 0.5) * 0.5));
  col += mix(uC2, uC3, bh) * ember * (0.6 + 0.4 * sin(clk * 9.0 + bh * 30.0)) * (1.0 + uY.z);
  col = mix(col, uC2, uD.y * 0.05);
  col *= 1.0 - 0.35 * smoothstep(0.6, 1.4, length(p0 * vec2(0.9, 0.6)));
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
