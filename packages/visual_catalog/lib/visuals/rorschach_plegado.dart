// Rorschach Plegado — la lámina se hace delante de ti.
// Así se fabrican las manchas de verdad: caen gotas de tinta roja, negra y
// dorada en la mitad izquierda de la hoja, la mitad derecha se dobla encima,
// aprieta, y al abrirse aparece la mancha simétrica, que sigue
// extendiéndose por el papel. Con cada golpe (o cada pocos segundos sin
// música) se hace una lámina nueva. Pulso: Golpes hace una lámina nueva y la
// tinta brilla; Graves hace respirar la mancha; Agudos saca gotitas.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.choice('mutacion', 'Metamorfosis', options: ['Cada golpe', 'Cada compás', 'Lenta']),
  CreatorModifier.choice('pulso', 'Pulso', options: ['Golpes', 'Graves', 'Agudos']),
  CreatorModifier.choice('tintas', 'Tintas', options: ['Fuego', 'Sangre', 'Noche']),
  CreatorModifier.slider('sombra', 'Profundidad', min: 0, max: 1.5, value: 1),
  CreatorModifier.slider('gotas', 'Salpicaduras', min: 0, max: 1, value: .4),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Taller', {'tintas': 'Fuego', 'sombra': 1.5, 'mutacion': 'Cada compás'}),
  CreatorVariation('Noche de Tinta', {'tintas': 'Noche', 'gotas': 1, 'pulso': 'Graves'}),
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
    // La hoja nueva empieza con la forma ya elegida.
    for (int i = 0; i < kLobes; i++) from[size_t(i)] = to[size_t(i)];
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
    flow += step * (0.3 + 1.2 * double(drive) + 0.9 * double(kick)) * 0.6;
    // Metamorfosis: la forma cambia con cada golpe, cada cuatro o despacio.
    if (fresh && mu.active && m.mutacion != 2) {
      const uint32_t every = m.mutacion == 0 ? 1u : 4u;
      if (beats % every == 0u && clock - shapeAt > 1.6) newShape(0.0);
    }
    if (!mu.active || m.mutacion == 2) {
      const double idle = m.mutacion == 2 ? 4.5 * 1.8 : 4.5;
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
    u.insert(u.end(), {g.tintas.weight(1), g.tintas.weight(2), g.sombra, g.gotas});
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
    u.insert(u.end(), {float(std::min(clock - shapeAt, 30.0)), 0.5f * f.width / std::min(f.width, f.height), f.detail, 0.0f});
    u.insert(u.end(), {golpe, graves, agudos, morphP});
    u.insert(u.end(), {std::max(-0.2f, spread) * amp * g.pulso.weight(0), float(std::min(sinceBeat, 9.0)),
                       std::min(pulse * amp, 1.2f), float(shapes % 997u)});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[size_t(i)].r, f.colors[size_t(i)].g, f.colors[size_t(i)].b});
    c.material("inkblot_fold", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'inkblot_fold': r"""
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

vec4 sheet(vec2 s, vec2 frag, float a, float spread, out float inkAmt) {
  // Tinta en la hoja (s en coordenadas de la hoja; la mancha es simétrica
  // y algo más pequeña para que quepa en la tarjeta).
  vec2 q = vec2(abs(s.x), s.y) * 1.14;
  vec2 w;
  float n;
  float drop = smoothstep(0.0, 0.3, a);
  float grow = mix(-0.7, 0.0, drop) + spread + growth();
  float F = blot(q, uA.x, grow, w, n);
  inkAmt = smoothstep(-0.008, 0.008, F);
  // Tres tintas: negra, roja y vetas de oro que se mezclan.
  float red = smoothstep(0.1, 0.3, F + (n - 0.5) * 0.4);
  float gold = smoothstep(0.88, 0.97, 1.0 - abs(2.0 * fbm(q * 5.0 + w * 2.0) - 1.0)) * smoothstep(0.0, 0.2, F);
  vec3 cRed = mix(uC2, uC1 * 1.5 + vec3(0.1, 0.0, 0.05), uB.y);
  vec3 cGold = mix(uC3, uC2 * 1.2, uB.x);
  vec3 ink = mix(uC1, cRed, red * 0.85);
  ink = mix(ink, cGold, gold * (0.7 + 0.5 * uY.x));
  ink *= 1.0 + 0.35 * uY.x;
  ink = mix(ink, uC1 * 0.5, smoothstep(0.1, 0.0, F) * 0.6);
  float sp = spatter(q, F, (0.03 + 0.4 * uY.z) * uB.w * drop, floor(uD.w * 4.0));
  inkAmt = max(inkAmt, sp);
  return vec4(mix(ink, uC1, sp), F);
}

// Mesa de madera oscura bajo una lámpara cálida.
vec3 table(vec2 p, vec2 frag) {
  float grain = noise(vec2(p.x * 3.0, p.y * 40.0 + noise(p * 4.0) * 6.0));
  vec3 wood = mix(vec3(0.16, 0.07, 0.035), vec3(0.3, 0.14, 0.06), grain);
  wood *= 0.85 + 0.15 * noise(frag * 0.7);
  float lamp = exp(-dot(p, p) * 1.6);
  return wood * (0.35 + 0.9 * lamp) + uC2 * 0.05 * lamp;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  float a = uX.x;
  // La hoja es una tarjeta con margen; se ve la mesa alrededor.
  float halfW = uX.y * 0.86;
  float halfH = 0.5 * uSize.y / scale * 0.9;
  // Ángulo de la mitad derecha: 0 abierta, PI cerrada sobre la izquierda.
  float closeK = smoothstep(0.3, 0.75, a);
  float openK = smoothstep(0.9, 1.35, a);
  float theta = 3.14159265 * (closeK - openK);
  float cs = cos(theta);
  float sn = sin(theta);
  float pressed = step(0.75, a);
  // Al apretar la tinta se extiende un poco, y luego sigue chupando papel.
  float spread = 0.07 * smoothstep(0.75, 1.0, a) + 0.05 * (1.0 - exp(-max(a - 1.35, 0.0) * 0.3));
  vec3 col = table(p, frag);
  // Sombra de la hoja sobre la mesa (más ancha cuando la solapa se levanta).
  vec2 sd = vec2(max(abs(p.x - 0.015 - 0.03 * sn) - halfW * (p.x > 0.0 ? max(cs, 0.0) : 1.0), 0.0),
                 max(abs(p.y + 0.02) - halfH, 0.0));
  col *= 1.0 - 0.6 * exp(-length(sd) * 28.0) * (0.4 + 0.6 * uB.z);
  bool onLeft = p.x <= 0.0 && p.x > -halfW && abs(p.y) < halfH;
  if (onLeft) {
    float inkL;
    vec4 left = sheet(vec2(p.x, p.y), frag, a, spread, inkL);
    col = mix(paper(frag, p), left.rgb, inkL);
    // Sombra de la solapa al pasar por encima.
    col *= 1.0 - sn * exp(p.x * 6.0 / max(uB.z, 0.05)) * 0.55 * uB.z;
  }
  // La solapa gira sobre el pliegue y se acerca a la cámara (perspectiva).
  float D = 2.6;
  float den = cs + p.x * sn / D;
  float u = abs(den) > 1e-4 ? p.x / den : -1.0;
  float depth = 1.0 - u * sn / D;
  float fy = p.y * depth;
  if (u > 0.0 && u < halfW && depth > 0.05 && abs(fy) < halfH) {
    float shade = 0.62 + 0.38 * abs(cs);
    vec3 flapCol;
    if (cs >= 0.0) {
      // Cara de delante: blanca hasta que se aprieta; luego la mancha en espejo.
      float inkR;
      vec4 right = sheet(vec2(-u, fy), frag, a, spread, inkR);
      flapCol = mix(paper(frag, vec2(u, fy)), right.rgb, inkR * pressed);
    } else {
      // Dorso de la hoja: la tinta se transparenta un poco.
      float inkR;
      vec4 right = sheet(vec2(-u, fy), frag, a, spread, inkR);
      flapCol = mix(paper(frag, vec2(u, fy)) * 0.9, right.rgb * 0.6 + uC0 * 0.4, inkR * pressed * 0.18);
    }
    // La luz de la lámpara resbala por la solapa levantada.
    float sheen = sn * exp(-sq(u / halfW - 0.6) * 6.0) * 0.12;
    col = flapCol * shade * (1.0 - 0.25 * uB.z * (1.0 - abs(cs))) + sheen;
  }
  // El pliegue en el centro de la hoja.
  col *= 1.0 - 0.18 * exp(-abs(p.x) * 120.0) * (0.4 + 0.6 * uB.z) * step(abs(p.y), halfH);
  col += uC3 * uD.y * 0.04;
  col *= 0.97 + 0.03 * uD.x;
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
