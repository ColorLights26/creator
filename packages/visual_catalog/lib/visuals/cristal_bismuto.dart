// Cristal de Bismuto — escaleras de metal con los colores del fuego.
// El bismuto cristaliza en «tolvas»: cuadrados huecos que bajan en escalones
// hacia el centro, como pirámides invertidas, y una capa finísima de óxido
// los tiñe de colores metálicos que cambian con su grosor. Aquí varios
// cristales grandes llenan la pantalla con sus terrazas de oro, naranja y
// rojo; la música corre olas de color por los escalones, los graves los
// hacen crecer y los agudos encienden destellos en las aristas.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // FORMA: cuántos escalones tiene cada cristal.
  CreatorModifier.steps('escalones', 'Escalones', min: 4, max: 14, value: 8),
  // MOVIMIENTO: cristales quietos, girando o flotando.
  CreatorModifier.choice(
    'giro',
    'Movimiento',
    options: ['Quieto', 'Rotación', 'Flotar'],
  ),
  // MÚSICA
  CreatorModifier.choice(
    'pulso',
    'Pulso',
    options: ['Golpes', 'Graves', 'Destellos'],
  ),
  // ATMÓSFERA: reflejos metálicos que recorren las terrazas.
  CreatorModifier.slider('reflejo', 'Reflejo', min: 0, max: 1, value: .5),
  // MODO: terrazas cuadradas o una escalera en espiral.
  CreatorModifier.toggle('espiral', 'Escalera en espiral', value: false),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Escalera', {
    'espiral': true,
    'escalones': 12,
    'giro': 'Rotación',
  }),
  CreatorVariation('Joya', {
    'escalones': 5,
    'reflejo': 1,
    'giro': 'Flotar',
    'pulso': 'Destellos',
  }),
];

const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kCrystals = 4;
  float bass = 0, spark = 0, slowBass = 0;
  float kick = 0, flash = 0, ripplePower = 0;
  // Relojes en doble precisión: sin música es idéntico a 30 y 60 FPS.
  double clock = 0, rippleAge = 100;
  std::array<float, kCrystals> cx{}, cy{}, csize{}, cangle{}, cdir{};

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = spark = slowBass = kick = flash = ripplePower = 0;
    clock = double(rng.unit()) * 30.0;
    rippleAge = 100;
    const float bx[kCrystals] = {-0.16f, 0.2f, -0.18f, 0.18f};
    const float by[kCrystals] = {-0.55f, -0.12f, 0.3f, 0.66f};
    for (int i = 0; i < kCrystals; i++) {
      cx[size_t(i)] = bx[i] + (rng.unit() - 0.5f) * 0.08f;
      cy[size_t(i)] = by[i] + (rng.unit() - 0.5f) * 0.08f;
      csize[size_t(i)] = 0.27f + 0.1f * rng.unit();
      cangle[size_t(i)] = (rng.unit() - 0.5f) * 0.9f;
      cdir[size_t(i)] = rng.unit() < 0.5f ? -1.0f : 1.0f;
    }
  }

  void update(const Frame& f) override {
    const float dt = float(f.delta);
    const Music& mu = f.music;
    bass = follow(bass, mu.bass, 22.0f, 4.5f, dt);
    spark = follow(spark, mu.spark, 30.0f, 7.0f, dt);
    float hit = 0, fl = 0;
    for (const auto& e : mu.events[0]) hit = std::max(hit, e.strength);
    for (const auto& e : mu.events[2]) hit = std::max(hit, e.strength * 0.85f);
    for (const auto& e : mu.events[3]) fl = std::max(fl, e.strength);
    const float onset = std::clamp((mu.bass - slowBass - 0.15f) * 2.5f, 0.0f, 1.0f);
    slowBass = follow(slowBass, mu.bass, 3.0f, 3.0f, dt);
    hit = std::min(std::max(hit, onset), 1.0f);
    rippleAge += f.delta;
    if (hit > kick + 0.2f) {
      rippleAge = 0;
      ripplePower = hit;
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    clock += f.delta * f.speed;
  }

  void render(const Frame& f, Canvas& c) const override {
    auto g = glide(f);
    const float amp = f.intensity;
    const float t = float(std::fmod(clock, 10000.0));
    const float wQuieto = g.giro.weight(0), wRota = g.giro.weight(1), wFlota = g.giro.weight(2);
    // Golpes: una ola de color sale del centro de cada cristal.
    const float wave = g.pulso.weight(0) * ripplePower * amp * float(std::exp(-rippleAge * 1.6));
    const float waveR = float(std::min(rippleAge, 10.0)) * 1.4f;
    const float grow = 1.0f + 0.1f * std::min(bass * amp, 1.0f) * g.pulso.weight(1);
    std::vector<float> u;
    u.reserve(48);
    u.insert(u.end(), {t, std::min(bass * amp, 1.5f), wave, std::min(spark * amp, 1.0f) * g.pulso.weight(2)});
    // Detalle: más finas las terrazas con más detalle.
    u.insert(u.end(), {g.escalones * (0.75f + 0.25f * f.detail), std::clamp(g.espiral, 0.0f, 1.0f), std::clamp(g.reflejo, 0.0f, 1.0f), f.glow});
    u.insert(u.end(), {waveR, std::min(flash * amp, 1.0f), 0.0f, 0.0f});
    for (int i = 0; i < kCrystals; i++) {
      const float fi = float(i);
      const float rot = cangle[size_t(i)] + float(clock) * 0.12f * cdir[size_t(i)];
      const float bob = cangle[size_t(i)] + 0.15f * std::sin(t * 0.2f + fi);
      const float a = wQuieto * cangle[size_t(i)] + wRota * rot + wFlota * bob;
      const float x = cx[size_t(i)] + wFlota * 0.03f * std::sin(t * 0.4f + fi);
      const float y = cy[size_t(i)] + wFlota * 0.04f * std::sin(t * 0.33f + fi * 2.0f);
      u.insert(u.end(), {x, y, csize[size_t(i)] * grow, a});
    }
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[size_t(i)].r, f.colors[size_t(i)].g, f.colors[size_t(i)].b});
    c.material("bismuth", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'bismuth': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // tiempo, graves, ola de golpe, destellos
uniform vec4 uB;   // escalones, espiral, reflejo, glow
uniform vec4 uE;   // radio de la ola, destello
uniform vec4 uK0;  // cristales: x, y, tamaño, ángulo
uniform vec4 uK1;
uniform vec4 uK2;
uniform vec4 uK3;
uniform vec3 uC0;
uniform vec3 uC1;
uniform vec3 uC2;
uniform vec3 uC3;
out vec4 fragColor;

float sq(float x) {
  return x * x;
}

float hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

// Color de la capa de óxido según su grosor: recorre la paleta y un acero.
vec3 film(float tau) {
  vec3 steel = mix(uC1, uC3, 0.5) * 0.35;
  float s = fract(tau) * 4.0;
  if (s < 1.0) return mix(uC1, uC2, smoothstep(0.0, 1.0, s));
  if (s < 2.0) return mix(uC2, uC3, smoothstep(1.0, 2.0, s));
  if (s < 3.0) return mix(uC3, steel, smoothstep(2.0, 3.0, s));
  return mix(steel, uC1, smoothstep(3.0, 4.0, s));
}

// Un cristal en p: nivel de terraza, cara, distancia al centro y si está dentro.
vec4 crystal(vec2 p, vec4 K, out vec2 inward) {
  vec2 d = p - K.xy;
  float cs = cos(K.w);
  float sn = sin(K.w);
  vec2 q = vec2(cs * d.x + sn * d.y, -sn * d.x + cs * d.y) / K.z;
  float dC = max(abs(q.x), abs(q.y));
  vec2 n = abs(q.x) > abs(q.y) ? vec2(-sign(q.x), 0.0) : vec2(0.0, -sign(q.y));
  // La pared de cada escalón mira hacia el centro.
  inward = vec2(cs * n.x - sn * n.y, sn * n.x + cs * n.y);
  if (dC > 1.0) return vec4(-1.0, 0.0, dC, 0.0);
  float ang = atan(q.y, q.x) / 6.2831853 + 0.5;
  float level = dC * uB.x + uB.y * ang;
  return vec4(level, 0.0, dC, 1.0);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  float t = uA.x;
  vec2 n0;
  vec2 n1;
  vec2 n2;
  vec2 n3;
  vec4 a0 = crystal(p, uK0, n0);
  vec4 a1 = crystal(p, uK1, n1);
  vec4 a2 = crystal(p, uK2, n2);
  vec4 a3 = crystal(p, uK3, n3);
  // El escalón más alto tapa a los demás (los bordes de fuera son altos).
  float h0 = a0.w > 0.5 ? floor(a0.x) / uB.x + 0.0 : -9.0;
  float h1 = a1.w > 0.5 ? floor(a1.x) / uB.x + 0.15 : -9.0;
  float h2 = a2.w > 0.5 ? floor(a2.x) / uB.x + 0.3 : -9.0;
  float h3 = a3.w > 0.5 ? floor(a3.x) / uB.x + 0.45 : -9.0;
  vec4 a = a0;
  vec2 inward = n0;
  float idx = 0.0;
  float best = h0;
  if (h1 > best) { best = h1; a = a1; inward = n1; idx = 1.0; }
  if (h2 > best) { best = h2; a = a2; inward = n2; idx = 2.0; }
  if (h3 > best) { best = h3; a = a3; inward = n3; idx = 3.0; }
  // Fondo de terciopelo oscuro con la sombra de los cristales.
  vec3 col = uC0 * (1.0 + 0.4 * (1.0 - length(p * vec2(0.9, 0.6))));
  float nearest = min(min(a0.z, a1.z), min(a2.z, a3.z));
  col *= 1.0 - 0.6 * smoothstep(1.12, 1.0, nearest);
  if (best > -5.0) {
    float k = floor(a.x);
    float u = fract(a.x);
    float dC = a.z;
    float tau = k * 0.13 + dC * 0.25 + idx * 0.31 + t * 0.03 + uA.y * 0.15;
    tau += uA.z * exp(-sq((dC - uE.x) / 0.12)) * 0.35;
    vec2 toLight = normalize(vec2(-0.6, -0.8));
    float lit = max(dot(inward, toLight), 0.0);
    // Reflejos metálicos que recorren las terrazas.
    float sheen = 0.5 + 0.5 * sin(dot(p, vec2(0.8, 0.6)) * 7.0 - t * 0.8 + k * 0.5);
    float wall = 1.0 - smoothstep(0.14, 0.18, u);
    vec3 tread = film(tau) * (0.5 + 0.35 * sheen + 0.6 * uB.z * pow(sheen, 8.0));
    vec3 riser = film(tau + 0.08) * (0.22 + 0.95 * lit);
    vec3 c = mix(tread, riser, wall);
    float edge = exp(-sq((u - 0.17) / 0.02));
    c += mix(uC3, vec3(1.0), 0.3) * edge * (0.25 + 0.5 * lit) * (0.6 + 0.4 * uB.w);
    c *= 1.0 - 0.6 * exp(-sq(u / 0.025));
    // Destellos: las aristas centellean con los agudos.
    float glint = step(0.86, hash12(floor(p * 90.0) + floor(t * 8.0)));
    c += uC3 * edge * glint * uA.w * 1.2;
    // Borde exterior del cristal.
    c *= smoothstep(1.0, 0.985, dC) * 0.6 + 0.4;
    col = c;
  }
  col *= 1.0 + 0.12 * uE.y;
  col *= 1.0 - 0.25 * smoothstep(0.7, 1.5, length(p * vec2(0.9, 0.65)));
  float peak = max(col.r, max(col.g, col.b));
  if (peak > 0.9) col *= (0.9 + 0.1 * (peak - 0.9) / (peak - 0.8)) / peak;
  col += (hash12(frag) - 0.5) / 255.0;
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
