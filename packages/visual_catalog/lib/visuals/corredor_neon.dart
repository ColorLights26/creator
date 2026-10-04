// Corredor de Neón — corredor cuadrado de marcos de neón y cromo líquido.
// La cámara avanza por un corredor de sección cuadrada: marcos de neón pasan
// uno tras otro y las paredes son metal líquido con burbujas y agujeros que
// reflejan la luz. El corredor alterna entre fuego (rojo y amarillo) y hielo
// (blanco y azul) cada ocho golpes. La energía acelera el avance y enciende
// las paredes, cada golpe empuja la cámara y hace destellar los marcos, y
// partículas rojas flotan en el aire.
const nativeSource = r'''
class Visual final : public Scene {
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double travel = 0, clock = 0, sinceSwitch = 0;
  float boost = 0, theme = 0, themeTarget = 0;
  int beats = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    travel = rng.unit() * 20.0;
    clock = 0;
    sinceSwitch = 0;
    boost = 0;
    theme = themeTarget = rng.unit() < 0.5f ? 0.0f : 1.0f;
    beats = 0;
  }

  void update(const Frame& f) override {
    float dt = float(f.delta);
    const Music& m = f.music;
    bass = follow(bass, m.bass, 22.0f, 4.5f, dt);
    body = follow(body, m.body, 12.0f, 3.0f, dt);
    spark = follow(spark, m.spark, 30.0f, 7.0f, dt);
    energy = follow(energy, m.energy, 6.0f, 1.8f, dt);
    drive = follow(drive, m.active ? std::pow(std::clamp(m.energy, 0.0f, 1.0f), 0.8f) : 0.0f, 3.0f, 0.7f, dt);

    float hit = 0, fl = 0;
    for (const auto& e : m.events[0]) hit = std::max(hit, e.strength);
    for (const auto& e : m.events[2]) hit = std::max(hit, e.strength * 0.85f);
    for (const auto& e : m.events[3]) fl = std::max(fl, e.strength);
    float onset = std::clamp((m.bass - slowBass - 0.15f) * 2.5f, 0.0f, 1.0f);
    slowBass = follow(slowBass, m.bass, 3.0f, 3.0f, dt);
    hit = std::min(std::max(hit, onset), 1.0f);
    if (hit > kick + 0.2f) {
      beats++;
      boost = std::max(boost, hit);
      if (beats % 8 == 0) {
        themeTarget = 1.0f - themeTarget;
        sinceSwitch = 0;
      }
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    boost *= std::exp(-dt * 3.0f);
    sinceSwitch += f.delta;
    if (!m.active && sinceSwitch > 10.0) {
      themeTarget = 1.0f - themeTarget;
      sinceSwitch = 0;
    }
    theme += (themeTarget - theme) * (1.0f - std::exp(-dt * 2.5f));
    travel += f.delta * f.speed * (0.7 + 1.4 * drive + 2.0 * boost);
    clock += f.delta * f.speed;
  }

  void render(const Frame& f, Canvas& c) const override {
    float amp = f.intensity;
    std::vector<float> u;
    u.reserve(20);
    u.insert(u.end(), {float(std::fmod(travel, 1000.0)), bass * amp, kick * amp, energy});
    u.insert(u.end(), {theme, f.glow, spark * amp, flash * amp});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("neon_corridor", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'neon_corridor': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // avance, graves, golpe, energía
uniform vec4 uB;   // tema (0 fuego, 1 hielo), glow, agudos, destello
uniform vec3 uC0;
uniform vec3 uC1;
uniform vec3 uC2;
uniform vec3 uC3;
out vec4 fragColor;

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

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  float travel = uA.x;
  float kick = uA.z;
  float theme = uB.x;
  // Colores del tema: fuego (rojo, amarillo) o hielo (blanco, azul).
  vec3 wallCol = mix(uC1, mix(uC3, vec3(1.0), 0.35), theme);
  vec3 frameCol = mix(uC2, vec3(0.92, 0.97, 1.0), theme);
  vec3 endCol = mix(vec3(0.6, 0.75, 1.0), vec3(1.0, 0.2, 0.15), theme);

  // Corredor cuadrado: la distancia a la pared da la profundidad.
  float sq = max(abs(p.x), abs(p.y)) + 1e-4;
  float z = 0.32 / sq;
  float depth = z + travel;
  bool side = abs(p.x) > abs(p.y);
  float v = side ? p.y / abs(p.x) : p.x / abs(p.y);
  float wallId = side ? (p.x > 0.0 ? 0.0 : 1.0) : (p.y > 0.0 ? 2.0 : 3.0);

  // Paredes de metal líquido: burbujas y agujeros con relieve reflejado.
  vec2 w = vec2(v * 4.5 + wallId * 7.3, depth * 3.2);
  float n = noise(w) * 0.65 + noise(w * 2.3 + 4.0) * 0.35;
  float nx = noise(w + vec2(0.05, 0.0)) * 0.65 + noise(w * 2.3 + 4.0 + vec2(0.115, 0.0)) * 0.35;
  float ny = noise(w + vec2(0.0, 0.05)) * 0.65 + noise(w * 2.3 + 4.0 + vec2(0.0, 0.115)) * 0.35;
  vec2 grad = vec2(nx - n, ny - n) * 20.0;
  float holes = smoothstep(0.45, 0.4, n);
  float spec = pow(max(0.0, 1.0 - length(grad - vec2(0.4, 0.6)) * 0.9), 6.0);
  float liquid = (0.15 + 0.85 * smoothstep(0.45, 0.85, n)) * (1.0 - holes);
  float lit = 0.18 + 0.75 * uA.w + 0.35 * uA.y;
  vec3 col = wallCol * liquid * liquid * lit * 0.9 + mix(wallCol, vec3(1.0), 0.5) * spec * (1.0 - holes) * (0.25 + 0.9 * lit);

  // Marcos de neón que pasan, con un marco fino entre cada dos.
  float fz = fract(depth * 0.5);
  float dz = min(fz, 1.0 - fz) / 0.5;
  float frame = exp(-dz * z * 10.0) * 1.4;
  float fz2 = fract(depth * 0.5 + 0.5);
  float frame2 = exp(-min(fz2, 1.0 - fz2) / 0.5 * z * 26.0) * 0.5;
  col += frameCol * (frame + frame2) * (1.0 + 1.6 * kick) * uB.y;

  // Niebla hacia el fondo y puerta luminosa al final.
  float fog = exp(-z * 0.16);
  col *= fog;
  float endSq = abs(sq - 0.045);
  col += endCol * exp(-endSq * 260.0) * (0.8 + 0.6 * kick);
  col *= smoothstep(0.02, 0.05, sq) * 0.85 + 0.15;

  // Partículas rojas que flotan en el aire.
  vec2 pc = floor(frag / scale * 22.0);
  float ph = hash12(pc);
  vec2 off = fract(frag / scale * 22.0) - 0.5 - (vec2(hash12(pc + 3.1), hash12(pc + 7.7)) - 0.5) * 0.6;
  float mote = step(0.9, ph) * exp(-dot(off, off) * 60.0) * (0.5 + 0.5 * sin(travel * 3.0 + ph * 40.0));
  col += vec3(1.0, 0.12, 0.08) * mote * (0.7 + 0.8 * uB.z);
  col += frameCol * uB.w * 0.06;

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
