// Vidrio Líquido — gotas de vidrio que refractan un degradado vivo.
// Seis gotas se mueven, se funden y se separan; cada una actúa como una lente:
// curva y aumenta el degradado naranja y azul que hay detrás, separa un poco
// los colores en los bordes y tiene un brillo especular arriba. Los graves
// hinchan las gotas, cada golpe las separa con un muelle y la energía mueve
// el fondo; los agudos hacen destellar los brillos.
const nativeSource = r'''
class Visual final : public Scene {
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double clock = 0, flow = 0;
  float spread = 0, spreadVel = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    clock = rng.unit() * 100.0;
    flow = rng.unit() * 100.0;
    spread = spreadVel = 0;
  }

  void update(const Frame& f) override {
    float dt = float(f.delta);
    const Music& m = f.music;
    bass = follow(bass, m.bass, 20.0f, 4.0f, dt);
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
    if (hit > kick + 0.2f) spreadVel += 1.8f * hit;
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    // Las gotas se separan con el golpe y vuelven a juntarse con un muelle.
    spreadVel += (-spread * 16.0f - spreadVel * 4.0f) * dt;
    spread += spreadVel * dt;
    clock += f.delta * f.speed * (0.35 + 0.6 * drive);
    flow += f.delta * f.speed * (0.2 + 0.5 * energy);
  }

  void render(const Frame& f, Canvas& c) const override {
    float amp = f.intensity;
    float aspectY = f.height / std::max(1.0f, std::min(f.width, f.height));
    float k = 1.0f + std::max(-0.3f, spread) * 0.9f;
    std::vector<float> u;
    u.reserve(40);
    u.insert(u.end(), {float(std::fmod(flow, 1000.0)), bass * amp, kick * amp, energy});
    u.insert(u.end(), {f.glow, spark * amp, flash * amp, 0.0f});
    float px[6], py[6], pr[6];
    for (int i = 0; i < 6; i++) {
      double t = clock * (0.6 + 0.13 * i) + i * 1.7;
      px[i] = 0.30f * float(std::sin(t * 0.9 + i)) * k;
      py[i] = (0.30f + 0.18f * (aspectY - 1.0f)) * float(std::cos(t * 0.7 + i * 2.3)) * k;
      pr[i] = (0.09f + 0.035f * float((i * 7) % 4)) * (1.0f + 0.25f * bass * amp + 0.1f * kick * amp);
    }
    u.insert(u.end(), {px[0], py[0], px[1], py[1]});
    u.insert(u.end(), {px[2], py[2], px[3], py[3]});
    u.insert(u.end(), {px[4], py[4], px[5], py[5]});
    u.insert(u.end(), {pr[0], pr[1], pr[2], pr[3]});
    u.insert(u.end(), {pr[4], pr[5], 0.0f, 0.0f});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("liquid_glass", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'liquid_glass': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // flujo del fondo, graves, golpe, energía
uniform vec4 uB;   // glow, agudos, destello
uniform vec4 uP0;  // gotas 1 y 2 (lado corto, centradas)
uniform vec4 uP1;  // gotas 3 y 4
uniform vec4 uP2;  // gotas 5 y 6
uniform vec4 uR0;  // radios 1 a 4
uniform vec4 uR1;  // radios 5 y 6
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

// Fondo vivo con franjas y anillos suaves para que la refracción se note.
vec3 backdrop(vec2 q) {
  float t = uA.x;
  float g = smoothstep(-0.9, 0.9, q.y + 0.3 * sin(q.x * 1.7 + t * 0.4));
  vec3 col = mix(uC1, uC2, g);
  float stripes = smoothstep(0.55, 1.0, sin((q.x - q.y) * 7.0 + t * 0.6));
  col = mix(col, mix(col, uC3, 0.6), stripes * 0.35);
  vec2 rc = q - vec2(0.25 * sin(t * 0.13), 0.3 * cos(t * 0.11));
  float rings = smoothstep(0.08, 0.0, abs(fract(length(rc) * 3.5 - t * 0.15) - 0.5) - 0.38);
  col += uC3 * rings * 0.12;
  return col * (0.82 + 0.15 * uA.w);
}

void addBlob(vec2 p, vec2 b, float r, inout float field, inout vec2 grad) {
  vec2 d = p - b;
  float d2 = dot(d, d) + 1e-4;
  float k = r * r / d2;
  field += k;
  grad += -2.0 * k / d2 * d;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  float field = 0.0;
  vec2 grad = vec2(0.0);
  addBlob(p, uP0.xy, uR0.x, field, grad);
  addBlob(p, uP0.zw, uR0.y, field, grad);
  addBlob(p, uP1.xy, uR0.z, field, grad);
  addBlob(p, uP1.zw, uR0.w, field, grad);
  addBlob(p, uP2.xy, uR1.x, field, grad);
  addBlob(p, uP2.zw, uR1.y, field, grad);

  // Sombra suave de las gotas sobre el fondo.
  vec3 outside = backdrop(p) * (1.0 - 0.18 * smoothstep(0.45, 1.0, field));
  float inside = smoothstep(0.96, 1.04, field);
  vec3 col = outside;
  if (field > 0.9) {
    // Pendiente de la gota: grande en el borde y nula en el centro, así la
    // lente es plana en el medio y curva hacia los bordes (sin remolinos).
    vec2 slope = -grad * 0.02;
    float sl = length(slope);
    if (sl > 0.12) slope *= 0.12 / sl;
    // Lente: el fondo se curva hacia el centro y los colores se separan un poco.
    vec2 off = slope;
    vec3 glass = vec3(backdrop(p + off * 1.1).r, backdrop(p + off).g, backdrop(p + off * 0.9).b);
    glass *= 1.08;
    vec3 n3 = normalize(vec3(slope * 6.0, 1.0));
    vec3 L = normalize(vec3(-0.45, 0.6, 0.65));
    float spec = pow(max(dot(n3, L), 0.0), 48.0);
    float rim = 1.0 - smoothstep(1.0, 1.35, field);
    glass += uC3 * spec * (0.55 + 0.6 * uB.y + 0.4 * uA.z);
    glass += uC3 * rim * 0.22;
    col = mix(outside, glass, inside);
  }
  col += uC3 * uB.z * 0.03;
  col *= 1.0 - 0.3 * smoothstep(0.6, 1.4, length(p * vec2(0.9, 0.65)));
  col += (hash12(frag) - 0.5) / 255.0;
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
