// Círculos Infinitos — una espiral de círculos que nunca termina.
// En coordenadas log-polares una red hexagonal de círculos tangentes se
// convierte en una espiral de Doyle: anillos de círculos que se encogen sin
// fin hacia el centro. Desplazar la red a lo largo de uno de sus propios
// vectores produce un zoom con giro perfectamente continuo. Cada círculo
// lleva tres círculos tangentes dentro que giran. Los graves engordan los
// aros, cada golpe manda una onda de luz del centro hacia fuera, las bandas
// del espectro encienden familias de círculos y en Auto la espiral cambia de
// tamaño (grande, media, fina) con un fundido cada ocho golpes.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.slider('velocidad_zoom', 'Velocidad del zoom', min: .2, max: 2.5, value: 1),
  CreatorModifier.choice('espiral', 'Espiral', options: ['Auto', 'Grande', 'Media', 'Fina']),
  CreatorModifier.slider('grosor', 'Grosor de los aros', min: .5, max: 2, value: 1),
  CreatorModifier.toggle('anidados', 'Círculos anidados', value: true),
];

const nativeSource = r'''
class Visual final : public Scene {
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  std::array<float, 3> bands{};
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double travel = 0, spin = 0, sinceWave = 100, sinceSwitch = 0;
  float wavePower = 0, fade = 1;
  int beats = 0, current = 1, previous = 1, autoSize = 1;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  // Pares (i, j) de la red: i·e1 + j·e2 da exactamente una vuelta. Con
  // i - j múltiplo de 3 los tres colores de círculo casan al cerrar la vuelta.
  static void lattice(int size, float& i, float& j) {
    if (size == 0) { i = 5; j = 2; return; }
    if (size == 1) { i = 8; j = 5; return; }
    i = 13; j = 7;
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    bands.fill(0);
    travel = rng.unit();
    spin = rng.unit() * 6.2831853;
    sinceWave = 100;
    sinceSwitch = 0;
    wavePower = 0;
    fade = 1;
    beats = 0;
    current = previous = autoSize = 1;
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
    for (int b = 0; b < 3; b++) {
      float v = 0;
      for (int k = b * 10; k < b * 10 + 10; k++) v = std::max(v, mu.smoothSpectrum[size_t(k)]);
      bands[size_t(b)] = follow(bands[size_t(b)], v, 18.0f, 4.0f, dt);
    }

    float hit = 0, fl = 0;
    for (const auto& e : mu.events[0]) hit = std::max(hit, e.strength);
    for (const auto& e : mu.events[2]) hit = std::max(hit, e.strength * 0.85f);
    for (const auto& e : mu.events[3]) fl = std::max(fl, e.strength);
    float onset = std::clamp((mu.bass - slowBass - 0.15f) * 2.5f, 0.0f, 1.0f);
    slowBass = follow(slowBass, mu.bass, 3.0f, 3.0f, dt);
    hit = std::min(std::max(hit, onset), 1.0f);
    sinceWave += f.delta;
    sinceSwitch += f.delta;
    if (hit > kick + 0.2f) {
      beats++;
      sinceWave = 0;
      wavePower = hit;
      if (beats % 8 == 0) {
        autoSize = (autoSize + 1) % 3;
        sinceSwitch = 0;
      }
    }
    if (!mu.active && sinceSwitch > 12.0) {
      autoSize = (autoSize + 1) % 3;
      sinceSwitch = 0;
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    int wanted = m.espiral == 0 ? autoSize : m.espiral - 1;
    if (wanted != current) {
      previous = current;
      current = wanted;
      fade = 0;
    }
    fade = std::min(1.0f, fade + dt * 1.2f);
    // Avance en vectores de la red: cada 3 pasos los colores vuelven a coincidir.
    travel += f.delta * f.speed * m.velocidad_zoom * (0.18 + 0.4 * drive + 0.25 * kick);
    spin += f.delta * f.speed * (0.6 + 1.2 * drive);
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    float amp = f.intensity;
    float ia, ja, ib, jb;
    lattice(current, ia, ja);
    lattice(previous, ib, jb);
    float wave = sinceWave < 3.0 ? float(sinceWave) * 2.2f - 4.0f : 10.0f;
    std::vector<float> u;
    u.reserve(32);
    u.insert(u.end(), {float(std::fmod(travel, 3.0)), bass * amp, kick * amp, energy});
    u.insert(u.end(), {ia, ja, ib, jb});
    u.insert(u.end(), {fade, m.grosor, m.anidados ? 1.0f : 0.0f, float(std::fmod(spin, 6.2831853))});
    u.insert(u.end(), {wave, wavePower * amp, f.glow, flash * amp});
    u.insert(u.end(), {bands[0] * amp, bands[1] * amp, bands[2] * amp, spark * amp});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("doyle_zoom", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'doyle_zoom': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // avance (0..3), graves, golpe, energía
uniform vec4 uB;   // red actual (i, j), red anterior (i, j)
uniform vec4 uD;   // fundido, grosor, anidados, giro interior
uniform vec4 uE;   // onda (log r), fuerza de la onda, glow, destello
uniform vec4 uS;   // graves, medios, agudos del espectro, chispa
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

float bandFor(float k) {
  return k < 1.0 ? uS.x : (k < 2.0 ? uS.y : uS.z);
}

vec3 familyColor(float k) {
  return k < 1.0 ? uC1 : (k < 2.0 ? uC2 : mix(uC1, uC3, 0.6));
}

// Un aro suavizado; fw es el tamaño del píxel en el plano log-polar.
float ring(float dist, float radius, float width, float fw) {
  float w = max(width, fw);
  float on = 1.0 - smoothstep(w * 0.5, w * 0.5 + fw, abs(dist - radius));
  return on * min(1.0, width / fw);
}

// Espiral de Doyle para la red (i, j): color del píxel en el plano log-polar.
vec3 doyle(vec2 w, float fw, float i, float j) {
  float d = TAU / sqrt(i * i + i * j + j * j);
  // Base hexagonal girada para que i·e1 + j·e2 apunte a una vuelta completa.
  vec2 v = vec2(i + 0.5 * j, 0.8660254 * j) * d;
  float ang = atan(v.y, v.x);
  float rot = 1.5707963 - ang;
  float cs = cos(rot);
  float sn = sin(rot);
  vec2 e1 = vec2(cs, sn) * d;
  vec2 e2 = vec2(cs * 0.5 - sn * 0.8660254, sn * 0.5 + cs * 0.8660254) * d;
  // Zoom continuo: desplazar 3·e1 deja la red y sus colores iguales.
  w -= e1 * uA.x;
  float det = e1.x * e2.y - e1.y * e2.x;
  vec2 ab = vec2(w.x * e2.y - w.y * e2.x, e1.x * w.y - e1.y * w.x) / det;
  vec2 base = floor(ab);
  vec2 best = base;
  float bestD = 1e9;
  for (int k = 0; k < 4; k++) {
    vec2 o = vec2(float(k - (k / 2) * 2), float(k / 2));
    vec2 cand = base + o;
    vec2 cw = cand.x * e1 + cand.y * e2;
    float dd = length(w - cw);
    if (dd < bestD) {
      bestD = dd;
      best = cand;
    }
  }
  vec2 center = best.x * e1 + best.y * e2;
  vec2 rel = w - center;
  float R = d * 0.5;
  float family = mod(best.x - best.y + 300.0, 3.0);
  float level = bandFor(family);
  vec3 tint = familyColor(family);
  float width = R * 0.07 * uD.y * (1.0 + 0.6 * uA.y);
  float main = ring(bestD, R * 0.93, width, fw);
  vec3 col = tint * main * (0.75 + 0.9 * level);
  // Relleno tenue dentro de cada círculo.
  col += tint * 0.06 * (1.0 - smoothstep(R * 0.8, R * 0.93, bestD)) * (0.6 + level);
  if (uD.z > 0.5) {
    // Tres círculos tangentes dentro de cada círculo, girando.
    float r3 = R * 0.93 * 0.4641016;
    float cdist = R * 0.93 - r3;
    float spinDir = mod(family, 2.0) < 1.0 ? 1.0 : -1.0;
    float a0 = uD.w * spinDir + family;
    float inner = 0.0;
    for (int k = 0; k < 3; k++) {
      float a = a0 + float(k) * 2.0943951;
      vec2 cc = vec2(cos(a), sin(a)) * cdist;
      inner = max(inner, ring(length(rel - cc), r3, width * 0.7, fw));
    }
    col += mix(tint, uC3, 0.35) * inner * (0.45 + 0.8 * level);
  }
  return col;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  float r = max(length(p), 1e-4);
  vec2 w = vec2(log(r), atan(p.y, p.x));
  float fw = 1.5 / (scale * r);
  vec3 col = doyle(w, fw, uB.x, uB.y);
  if (uD.x < 1.0) col = mix(doyle(w, fw, uB.z, uB.w), col, smoothstep(0.0, 1.0, uD.x));
  // Onda de luz del centro hacia fuera con cada golpe.
  float wave = exp(-abs(w.x - uE.x) * 3.0) * uE.y;
  col *= 1.0 + 1.8 * wave;
  col += uC3 * wave * 0.05;
  // El centro se vuelve un punto de luz donde los círculos son diminutos.
  float core = exp(-r * 22.0);
  col = mix(col, mix(uC1, uC3, 0.5) * (0.35 + 0.6 * uA.y + 0.5 * uA.z), core);
  col *= (0.85 + 0.25 * uA.z) * mix(1.0, uE.z, 0.6);
  col += uC1 * uE.w * 0.05;
  col += uC0;
  // Compresión que conserva el tono.
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
