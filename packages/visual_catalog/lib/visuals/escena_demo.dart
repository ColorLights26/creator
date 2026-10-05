// Escena Demo — los efectos de las demos de Amiga y PC de los noventa.
// Cuatro efectos clásicos que se alternan con una cortina de persiana:
// barras de cobre metálicas que ondulan una delante de otra sobre un campo
// de estrellas; la columna retorcida (twister) de cuatro caras que se
// enrosca; el fuego de píxeles que sube desde abajo; y el rotozoom, un
// suelo de baldosas que gira y se acerca. Todo se dibuja con píxeles gordos
// y líneas de monitor CRT. Los graves engordan las barras y la columna, cada
// golpe las hace destellar y en Auto el efecto cambia cada ocho golpes.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.choice('escena', 'Efecto', options: ['Auto', 'Barras', 'Columna', 'Fuego', 'Rotozoom']),
  CreatorModifier.steps('pixel', 'Píxeles gordos', min: 1, max: 5, value: 3),
  // MOVIMIENTO: cuánto ondula cada efecto, de rectos y calmos (mín.) a cintas
  // y columnas que se retuercen (máx.). Conserva el id: las apariencias
  // guardadas lo usan.
  CreatorModifier.slider('velocidad', 'Ondulación', min: .4, max: 2.5, value: 1),
  CreatorModifier.toggle('crt', 'Líneas de monitor', value: true),
];

const nativeSource = r'''
class Visual final : public Scene {
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double clock = 0, sinceScene = 0;
  float wipe = 1;
  int beats = 0, autoScene = 0, from = 0, to = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    clock = rng.unit() * 30.0;
    sinceScene = 0;
    wipe = 1;
    beats = 0;
    autoScene = from = to = 0;
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
    sinceScene += f.delta;
    // La cortina avanza antes de mirar cambios: si el cambio es por tiempo,
    // empieza en su instante exacto (igual a 30 y 60 FPS).
    wipe = std::min(1.0f, wipe + dt / 0.9f);
    double carry = -1.0;
    if (hit > kick + 0.2f && ++beats % 8 == 0) {
      autoScene = (autoScene + 1) % 4;
      sinceScene = 0;
    }
    if (!mu.active && sinceScene > 10.0) {
      autoScene = (autoScene + 1) % 4;
      sinceScene -= 10.0;
      carry = sinceScene;
    }
    int wanted = m.escena == 0 ? autoScene : m.escena - 1;
    if (wanted != to) {
      from = to;
      to = wanted;
      wipe = carry >= 0.0 ? std::min(1.0f, float(carry / 0.9)) : 0.0f;
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    clock += f.delta * f.speed * (1.0 + 0.9 * drive);
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    float amp = f.intensity;
    std::vector<float> u;
    u.reserve(29);
    u.insert(u.end(), {float(std::fmod(clock, 1000.0)), bass * amp, kick * amp, energy});
    u.insert(u.end(), {float(from), float(to), wipe, float(std::clamp(m.pixel, 1, 5))});
    u.insert(u.end(), {m.crt ? 1.0f : 0.0f, f.glow, flash * amp, spark * amp});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    // Ondulación se desliza al cambiarla y se ve también en pausa.
    u.push_back(std::clamp(glide(f).velocidad, 0.4f, 2.5f));
    c.material("demo_effects", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'demo_effects': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // reloj, graves, golpe, energía
uniform vec4 uB;   // efecto anterior, efecto nuevo, cortina, tamaño de píxel
uniform vec4 uD;   // líneas CRT, glow, destello, agudos
uniform vec3 uC0;
uniform vec3 uC1;
uniform vec3 uC2;
uniform vec3 uC3;
uniform float uWave;  // Ondulación: 1 = el efecto original
out vec4 fragColor;

const float PI = 3.14159265;

// Ondulación por debajo de 1 calma las ondas propias de cada efecto; por
// encima añade ondas nuevas (cintas, llamas que se doblan, suelo de agua).
float calmWave() { return min(uWave, 1.0); }
float wildWave() { return max(uWave - 1.0, 0.0); }

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

// Rampa de fuego: negro → rojo → naranja → amarillo → blanco.
vec3 fireRamp(float v) {
  v = clamp(v, 0.0, 1.0);
  vec3 c = mix(vec3(0.0), uC1, smoothstep(0.05, 0.35, v));
  c = mix(c, uC2, smoothstep(0.3, 0.6, v));
  c = mix(c, uC3, smoothstep(0.55, 0.85, v));
  return mix(c, vec3(1.0, 0.97, 0.85), smoothstep(0.95, 1.1, v));
}

vec3 barColor(float i) {
  float k = mod(i, 3.0);
  return k < 1.0 ? uC1 : (k < 2.0 ? uC2 : uC3);
}

vec3 stars(vec2 p, float t) {
  vec3 col = vec3(0.0);
  for (int l = 0; l < 3; l++) {
    float fl = float(l);
    vec2 g = (p + vec2(t * (0.05 + 0.08 * fl), 0.0)) * (16.0 + 10.0 * fl);
    vec2 id = floor(g);
    float h = hash12(id + fl * 13.0);
    vec2 off = vec2(hash12(id + 3.1), hash12(id + 7.7)) - 0.5;
    float d = length(fract(g) - 0.5 - off * 0.6);
    col += vec3(0.9, 0.9, 1.0) * step(0.93, h) * smoothstep(0.12, 0.0, d) * (0.4 + 0.3 * fl);
  }
  return col;
}

// Barras de cobre metálicas, la de delante tapa a las demás.
vec3 copper(vec2 p, float t, float halfH) {
  vec3 col = uC0 * (1.2 - 0.6 * (p.y / halfH * 0.5 + 0.5)) + stars(p, t);
  float best = -9.0;
  vec3 bar = vec3(0.0);
  float hit = 0.0;
  for (int i = 0; i < 9; i++) {
    float fi = float(i);
    // Calmas, las barras viajan juntas; onduladas, cada una es una cinta.
    float ph = t * 1.4 + fi * 0.62 * calmWave();
    float y = sin(ph) * halfH * 0.7 + 0.12 * sin(t * 0.7 + fi)
            + wildWave() * 0.07 * sin(p.x * 9.0 + t * 2.0 + fi * 0.9);
    float depth = cos(ph);
    float h = (0.045 + 0.012 * depth) * (1.0 + 0.35 * uA.y);
    float d = abs(p.y - y) / h;
    if (d < 1.0 && depth > best) {
      best = depth;
      float m = 1.0 - d * d;
      vec3 base = barColor(fi);
      bar = base * (0.2 + 1.0 * m) + vec3(1.0) * pow(m, 10.0) * (0.55 + 0.6 * uA.z);
      bar *= 0.55 + 0.45 * (depth * 0.5 + 0.5);
      hit = 1.0;
    }
  }
  return mix(col, bar, hit);
}

// La columna retorcida de cuatro caras.
vec3 twister(vec2 p, float t, float halfH) {
  vec3 col = uC0 * 0.8 + stars(p * 0.7, t * 0.5) * 0.6;
  float y = p.y;
  float a = t * 1.3 + sin(y * 2.4 + t * 0.9) * (1.7 + 0.6 * uA.y) * uWave;
  float R = 0.2 * (1.0 + 0.15 * uA.z + 0.1 * uA.y);
  float cx = 0.1 * sin(y * 1.6 + t * 0.7) * uWave;
  for (int k = 0; k < 4; k++) {
    float fk = float(k);
    float x0 = cx + R * sin(a + fk * PI * 0.5);
    float x1 = cx + R * sin(a + (fk + 1.0) * PI * 0.5);
    if (x0 < x1 && p.x >= x0 && p.x < x1) {
      float w = (x1 - x0) / (R * 1.4142);
      float u = (p.x - x0) / (x1 - x0);
      vec3 face = barColor(fk);
      // Rayas que suben por la cara y brillo en el centro.
      float stripe = step(0.5, fract(y * 6.0 - t * 0.8 + fk * 0.25));
      face = mix(face, face * 0.55, stripe * 0.6);
      col = face * (0.25 + 0.95 * w) + vec3(1.0) * pow(1.0 - abs(u - 0.5) * 2.0, 6.0) * 0.3 * w;
      col *= 1.0 - 0.6 * smoothstep(0.42, 0.5, abs(u - 0.5));
    }
  }
  return col;
}

// Fuego de píxeles que sube desde abajo.
vec3 fire(vec2 p, float t, float halfH) {
  // Altura desde abajo (en pantalla la y crece hacia abajo).
  float h = (halfH - p.y) / (2.0 * halfH);
  vec2 q = vec2(p.x * 4.0 + wildWave() * 0.8 * sin(h * 6.0 - t * 1.7), h * 5.0);
  // El ruido sube con el tiempo: las llamas trepan.
  float n = noise(q - vec2(0.0, t * 2.6)) * 0.55 + noise(q * 2.1 + vec2(1.7, -t * 4.0)) * 0.3 + noise(q * 4.3 + vec2(5.0, -t * 6.0)) * 0.15;
  float tongue = 0.5 + 0.5 * sin(p.x * 9.0 + t * 1.5 + n * 3.0 * uWave);
  float v = (n * 1.2 + tongue * 0.25) * (1.0 - h) * 1.4 - h * 0.45 + 0.25 * uA.y + 0.2 * uA.z - 0.2;
  return fireRamp(v) + uC0 * 0.6;
}

// Rotozoom: suelo de baldosas que gira y se acerca.
vec3 rotozoom(vec2 p, float t) {
  float ang = t * 0.35;
  float zoom = 2.6 + 1.6 * sin(t * 0.27) * calmWave() - 0.6 * uA.z;
  float cs = cos(ang);
  float sn = sin(ang);
  vec2 q = vec2(cs * p.x - sn * p.y, sn * p.x + cs * p.y) * zoom + vec2(t * 0.6, t * 0.35);
  q += wildWave() * 0.25 * sin(q.yx * 1.6 + t * 1.2);
  vec2 cell = floor(q);
  vec2 f = fract(q) - 0.5;
  float check = mod(cell.x + cell.y, 2.0);
  float ring = max(abs(f.x), abs(f.y));
  float bands = step(0.5, fract(ring * 4.0 - t * 0.6));
  vec3 a = mix(uC1, uC2, check);
  vec3 b = mix(uC3, uC0 * 2.0, check);
  vec3 col = mix(a, b, bands);
  col *= 0.75 + 0.35 * uA.y;
  return col;
}

vec3 effect(float k, vec2 p, float t, float halfH) {
  if (k < 0.5) return copper(p, t, halfH);
  if (k < 1.5) return twister(p, t, halfH);
  if (k < 2.5) return fire(p, t, halfH);
  return rotozoom(p, t);
}

void main() {
  vec2 frag0 = FlutterFragCoord().xy;
  // Píxeles gordos: todo se calcula en el centro de cada bloque.
  float px = uB.w;
  vec2 frag = (floor(frag0 / px) + 0.5) * px;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  float halfH = 0.5 * uSize.y / scale;
  float t = uA.x;
  vec3 col = effect(uB.y, p, t, halfH);
  if (uB.z < 0.999) {
    // Cortina de persiana: franjas que se abren de izquierda a derecha.
    float slat = fract(frag.y / 36.0);
    float show = step((frag.x / uSize.x) * 0.7 + slat * 0.3, uB.z * 1.05);
    if (show < 0.5) col = effect(uB.x, p, t, halfH);
  }
  col *= mix(1.0, uD.y, 0.4);
  col += uC3 * uD.z * 0.05;
  if (uD.x > 0.5) {
    col *= 0.82 + 0.18 * step(0.5, fract(frag0.y / 3.0));
    col *= 1.0 - 0.35 * smoothstep(0.55, 1.4, length(p * vec2(0.9, 0.6)));
  }
  float peak = max(col.r, max(col.g, col.b));
  if (peak > 0.9) {
    float e = (peak - 0.9) / 0.1;
    col *= (0.9 + 0.1 * e / (1.0 + e)) / peak;
  }
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
