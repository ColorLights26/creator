// Tormenta Eléctrica — cielo de tormenta sobre colinas mojadas.
// Cada golpe dispara un rayo ramificado (con su doble descarga) que ilumina
// las nubes desde dentro y se refleja en el suelo; el destello produce
// relámpago difuso y los graves agitan las nubes. En silencio, relámpagos
// lejanos y tenues mantienen viva la escena.
const nativeSource = r'''
class Visual final : public Scene {
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  float phase = 0, churn = 0;
  std::array<float, 28> bolt{};
  std::array<float, 12> branch{};
  float boltAge = 9.0f, boltPower = 0, sinceStrike = 9.0f;
  float ambientTimer = 2.0f, ambientAge = 9.0f, ambientPower = 0, ambientX = 0;
  float flickX = 0, flickY = 0, flicker = 0;
  Random rng{5};

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  void strike(float power, float top, float ground) {
    float x = (rng.unit() - 0.5f) * 0.55f;
    float start = x;
    for (int i = 0; i < 14; i++) {
      float k = float(i) / 13.0f;
      if (i > 0) x += (rng.unit() - 0.5f) * 0.085f + (start - x) * 0.08f;
      bolt[i * 2] = x;
      bolt[i * 2 + 1] = top + (ground - top) * k + (i > 0 && i < 13 ? (rng.unit() - 0.5f) * 0.02f : 0.0f);
    }
    int from = 3 + int(rng.unit() * 5.0f);
    float bx = bolt[from * 2], by = bolt[from * 2 + 1];
    float dir = rng.unit() < 0.5f ? -1.0f : 1.0f;
    float stepY = (ground - top) / 13.0f;
    for (int i = 0; i < 6; i++) {
      if (i > 0) {
        bx += dir * 0.035f + (rng.unit() - 0.5f) * 0.03f;
        by += stepY * 0.7f;
      }
      branch[i * 2] = bx;
      branch[i * 2 + 1] = by;
    }
    boltAge = 0.0f;
    boltPower = power;
    sinceStrike = 0.0f;
  }

 public:
  void reset(uint32_t seed) override {
    rng = Random(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    phase = rng.unit() * 40.0f;
    churn = 0;
    bolt.fill(0);
    branch.fill(0);
    boltAge = 9.0f;
    boltPower = 0;
    sinceStrike = 9.0f;
    ambientTimer = 1.5f + rng.unit() * 2.0f;
    ambientAge = 9.0f;
    ambientPower = 0;
    ambientX = 0;
    flickX = flickY = flicker = 0;
  }

  void update(const Frame& f) override {
    float dt = float(f.delta);
    const Music& m = f.music;
    bass = follow(bass, m.bass, 20.0f, 4.0f, dt);
    body = follow(body, m.body, 12.0f, 3.0f, dt);
    spark = follow(spark, m.spark, 30.0f, 7.0f, dt);
    energy = follow(energy, m.energy, 6.0f, 1.8f, dt);
    drive = follow(drive, m.active ? std::pow(std::clamp(m.energy, 0.0f, 1.0f), 0.8f) : 0.0f, 3.0f, 0.7f, dt);

    float hit = 0, fl = 0, acc = 0;
    for (const auto& e : m.events[1]) acc = std::max(acc, e.strength);
    for (const auto& e : m.events[0]) hit = std::max(hit, e.strength);
    for (const auto& e : m.events[2]) hit = std::max(hit, e.strength * 0.85f);
    for (const auto& e : m.events[3]) fl = std::max(fl, e.strength);
    float onset = std::clamp((m.bass - slowBass - 0.15f) * 2.5f, 0.0f, 1.0f);
    slowBass = follow(slowBass, m.bass, 3.0f, 3.0f, dt);
    hit = std::min(std::max(hit, onset), 1.0f);

    float half = 0.5f * f.height / std::min(f.width, f.height);
    float ground = -half + 0.30f;
    sinceStrike += dt;
    if (hit > kick + 0.2f && sinceStrike > 0.22f) strike(hit, ground + 0.62f, ground);
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 5.0f), std::min(fl, 1.0f));
    boltAge += dt;

    // Los acentos encienden destellos dentro de las nubes.
    flicker *= std::exp(-dt * 11.0f);
    if (acc > 0.3f && acc * 0.7f > flicker) {
      flickX = (rng.unit() - 0.5f) * 0.9f;
      flickY = ground + 0.75f + rng.unit() * 0.6f;
      flicker = acc * 0.7f;
    }

    // Relámpagos lejanos propios de la escena, también en silencio.
    ambientTimer -= dt;
    if (ambientTimer <= 0.0f) {
      ambientAge = 0.0f;
      ambientPower = 0.25f + rng.unit() * 0.25f;
      ambientX = (rng.unit() - 0.5f) * 0.8f;
      ambientTimer = 3.0f + rng.unit() * 6.0f;
    }
    ambientAge += dt;

    phase += dt * f.speed * (0.20f + 0.9f * drive + 0.6f * kick);
    churn += dt * f.speed * (0.05f + 0.9f * bass);
  }

  void render(const Frame& f, Canvas& c) const override {
    float amp = f.intensity;
    float age = boltAge;
    // Doble descarga: destello, caída, segundo trazo y desvanecimiento.
    float envelope = age < 0.05f ? 1.0f : age < 0.09f ? 0.3f : age < 0.17f ? 0.9f : 0.9f * std::exp(-(age - 0.17f) * 9.0f);
    float boltLight = boltPower * envelope * amp;
    float ambient = ambientPower * std::exp(-ambientAge * 5.0f) * (0.7f + 0.3f * std::cos(ambientAge * 45.0f));
    std::vector<float> u;
    u.reserve(70);
    u.insert(u.end(), {phase, bass * amp, boltLight, energy});
    u.insert(u.end(), bolt.begin(), bolt.end());
    u.insert(u.end(), branch.begin(), branch.end());
    u.insert(u.end(), {spark * amp, flash * amp, f.glow, ambient});
    u.insert(u.end(), {bolt[0], bolt[1], 0.35f + 0.65f * energy, churn});
    u.insert(u.end(), {ambientX, f.detail, kick * amp, 0.0f});
    u.insert(u.end(), {flickX, flickY, flicker * amp, 0.0f});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("storm", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'storm': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // tiempo, graves, luz del rayo, energía
uniform vec4 uB0;
uniform vec4 uB1;
uniform vec4 uB2;
uniform vec4 uB3;
uniform vec4 uB4;
uniform vec4 uB5;
uniform vec4 uB6;
uniform vec4 uR0;
uniform vec4 uR1;
uniform vec4 uR2;
uniform vec4 uM;   // agudos, relámpago difuso, glow, relámpago lejano
uniform vec4 uO;   // origen del rayo x, y; lluvia; agitación
uniform vec4 uX;   // x del relámpago lejano, detalle, golpe
uniform vec4 uF;   // destello en las nubes: x, y, fuerza
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

float fbm(vec2 p) {
  float s = 0.0;
  float a = 0.5;
  for (int i = 0; i < 5; i++) {
    s += a * noise(p);
    p = mat2(1.6, 1.2, -1.2, 1.6) * p;
    a *= 0.5;
  }
  return s;
}

float seg(vec2 p, vec2 a, vec2 b) {
  vec2 pa = p - a;
  vec2 ba = b - a;
  float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-6), 0.0, 1.0);
  return length(pa - ba * h);
}

float boltDistance(vec2 p) {
  float d = seg(p, uB0.xy, uB0.zw);
  d = min(d, seg(p, uB0.zw, uB1.xy));
  d = min(d, seg(p, uB1.xy, uB1.zw));
  d = min(d, seg(p, uB1.zw, uB2.xy));
  d = min(d, seg(p, uB2.xy, uB2.zw));
  d = min(d, seg(p, uB2.zw, uB3.xy));
  d = min(d, seg(p, uB3.xy, uB3.zw));
  d = min(d, seg(p, uB3.zw, uB4.xy));
  d = min(d, seg(p, uB4.xy, uB4.zw));
  d = min(d, seg(p, uB4.zw, uB5.xy));
  d = min(d, seg(p, uB5.xy, uB5.zw));
  d = min(d, seg(p, uB5.zw, uB6.xy));
  d = min(d, seg(p, uB6.xy, uB6.zw));
  return d;
}

float branchDistance(vec2 p) {
  float d = seg(p, uR0.xy, uR0.zw);
  d = min(d, seg(p, uR0.zw, uR1.xy));
  d = min(d, seg(p, uR1.xy, uR1.zw));
  d = min(d, seg(p, uR1.zw, uR2.xy));
  d = min(d, seg(p, uR2.xy, uR2.zw));
  return d;
}

float fbmLow(vec2 p) {
  float s = 0.0;
  float a = 0.5;
  for (int i = 0; i < 3; i++) {
    s += a * noise(p);
    p = mat2(1.6, 1.2, -1.2, 1.6) * p;
    a *= 0.5;
  }
  return s / 0.875;
}

// Nubarrones: masas grandes con deformación de dominio y bordes contrastados.
// Devuelve la densidad y una segunda muestra desplazada hacia la luz, que
// comparten la deformación para no calcularla dos veces.
vec2 clouds(vec2 p, float horizon) {
  vec2 q = vec2(p.x * 1.35 + uA.x * 0.03, (p.y - horizon) * 1.6);
  vec2 w = vec2(fbmLow(q * 0.6 + vec2(uO.w * 0.10, 0.0)), fbmLow(q * 0.6 + vec2(4.3, -uO.w * 0.07)));
  vec2 o = (w - 0.5) * (1.3 + 0.8 * uA.y);
  float d = fbm(q + o);
  float dl = fbm(q + o + vec2(0.04, 0.08));
  float layer = smoothstep(0.08, 0.6, p.y - horizon);
  float layerL = smoothstep(0.08, 0.6, p.y + 0.05 - horizon);
  return vec2(smoothstep(0.36, 0.68, d) * layer, smoothstep(0.36, 0.68, dl) * layerL);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  p.y = -p.y;
  float halfHeight = 0.5 * uSize.y / scale;
  float horizon = -halfHeight + 0.30;
  float bolt = uA.z;
  // Temblor con el trueno.
  p += vec2(sin(uA.x * 37.0), cos(uA.x * 29.0)) * 0.003 * uX.z;

  // Luz total del instante: rayo, relámpago difuso y relámpago lejano.
  vec2 origin = uO.xy;
  float near = bolt / (1.0 + 16.0 * dot(p - origin, p - origin));
  vec2 far = vec2(uX.x, horizon + 0.75);
  float distant = uM.w / (1.0 + 6.0 * dot(p - far, p - far));
  float sheet = uM.y;
  float flick = uF.z / (1.0 + 28.0 * dot(p - uF.xy, p - uF.xy));
  float light = near * 2.6 + distant * 1.3 + sheet * 0.8 + flick * 1.5;

  // Cielo nocturno y nubarrones iluminados desde dentro por el rayo.
  vec3 sky = mix(uC1 * 0.22, uC0 * 0.35, smoothstep(horizon, horizon + 0.8, p.y));
  // Bajo el horizonte no hay nubes: la GPU se salta su ruido.
  vec2 cd = vec2(0.0);
  if (p.y > horizon + 0.07) cd = clouds(p, horizon);
  float d = cd.x;
  float dl = cd.y;
  float rimLit = clamp((d - dl) * 4.0 + 0.2, 0.0, 1.0);
  vec3 cloudCol = mix(uC0 * 0.5, uC1 * 0.6, rimLit * 0.5);
  float inner = light * (0.5 + 0.9 * d) * (0.55 + 0.45 * rimLit);
  cloudCol += mix(uC2, uC3, 0.55) * inner;
  vec3 col = mix(sky + uC2 * light * 0.18, cloudCol, d);

  // Rayo con su resplandor.
  if (bolt > 0.01) {
    float bd = boltDistance(p);
    float br = branchDistance(p);
    float core = exp(-bd * bd / 0.000006) + 0.7 * exp(-br * br / 0.000004);
    float glow = 0.0004 / (bd * bd + 0.0003) + 0.2 * 0.0003 / (br * br + 0.0003);
    col += (vec3(1.0) * core * 1.8 + mix(uC2, uC3, 0.4) * glow * 1.1) * bolt * step(horizon - 0.01, p.y);
  }

  // Colinas y suelo mojado que refleja el cielo y el rayo.
  float hills = horizon + 0.035 * noise(vec2(p.x * 4.0, 1.0)) + 0.02 * noise(vec2(p.x * 11.0, 2.0)) - 0.02;
  if (p.y < hills) {
    vec2 mirror = vec2(p.x, 2.0 * hills - p.y);
    float wet = smoothstep(hills - 0.25, hills, p.y);
    vec3 ground = uC0 * 0.3 + uC1 * 0.02;
    float reflBolt = 0.0;
    if (bolt > 0.01) {
      float bd = boltDistance(mirror + vec2(0.0, 0.01 * sin(p.x * 80.0 + uA.x * 6.0)));
      reflBolt = 0.00015 / (bd * bd + 0.0004) * bolt;
    }
    ground += (mix(uC2, uC3, 0.5) * (light * 0.35 + reflBolt * 0.8)) * wet;
    col = ground;
  }

  // Lluvia sesgada en estelas irregulares, visible sobre todo con el rayo.
  vec2 rp = vec2(p.x + p.y * 0.18, p.y);
  float column = floor(rp.x * 70.0);
  float speed = 2.2 + hash12(vec2(column, 3.0)) * 1.2;
  float y = rp.y * 2.5 + uA.x * speed + hash12(vec2(column, 9.0)) * 10.0;
  float cell = floor(y);
  float fy = fract(y);
  float fx = fract(rp.x * 70.0) - 0.5;
  float h = hash12(vec2(column, cell));
  float drop = smoothstep(0.08, 0.0, abs(fx)) * smoothstep(0.0, 0.5, fy) * smoothstep(1.0, 0.75, fy);
  col += mix(uC2, vec3(1.0), 0.5) * drop * step(0.78 - 0.1 * uO.z, h) * (0.025 + 0.3 * light + 0.04 * uM.x);

  col *= uM.z;
  col *= 1.0 - 0.35 * smoothstep(0.5, 1.3, length(p * vec2(0.9, 0.65)));
  col = clamp((col * (2.51 * col + 0.03)) / (col * (2.43 * col + 0.59) + 0.14), 0.0, 1.0);
  col = pow(col, vec3(0.4545));
  col += (hash12(frag) - 0.5) / 255.0;
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
