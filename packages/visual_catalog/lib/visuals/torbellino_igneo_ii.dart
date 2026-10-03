// Torbellino Ígneo II — el mismo remolino, hecho de fuego líquido.
// En lugar de estelas, corrientes continuas de luz incandescente se enrollan en
// espiral y se hunden en un núcleo ardiente; chispas sueltas siguen el giro.
// Cada golpe expande el torbellino, lanza una onda de choque que deforma el
// fuego y dispara las chispas hacia fuera; los graves avivan el núcleo y el
// cuerpo del fuego, los medios encienden los filamentos y los agudos los
// vuelven blancos.
const nativeSource = r'''
class Visual final : public Scene {
  // Las chispas avanzan en pasos fijos de 1/120 s contados con el tiempo
  // absoluto: son idénticas a 30 y a 60 FPS y se dibujan interpoladas.
  static constexpr double kHz = 120.0;
  static constexpr float kStep = float(1.0 / kHz);
  struct Ember { float x, y, px, py, vx, vy, life, size; };
  std::vector<Ember> embers;
  float w = 0, h = 0;
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0, surge = 0;
  std::array<float, 3> groups{};
  float t = 0, current = 0, breath = 0, breathVel = 0, ringR = 3.0f, ringAmp = 0;
  Random rng{29};
  int64_t steps = -1;
  float frac = 0, pendingHit = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  void spawn(Ember& e) {
    float s = std::min(w, h);
    float margin = s * 0.06f;
    e.x = -margin + rng.unit() * (w + 2.0f * margin);
    e.y = -margin + rng.unit() * (h + 2.0f * margin);
    e.px = e.x;
    e.py = e.y;
    e.vx = e.vy = 0;
    e.life = 2.0f + rng.unit() * 4.0f;
  }

  // Mismo remolino que Torbellino Ígneo: giro que se acelera hacia el núcleo,
  // hundimiento y una ondulación que forma brazos.
  void field(float x, float y, float& fx, float& fy) const {
    float s = std::min(w, h);
    float u = (x - w * 0.5f) / s, v = (y - h * 0.5f) / s;
    float r = std::sqrt(u * u + v * v) + 1e-3f;
    float tx = -v / r, ty = u / r;
    float rx = u / r, ry = v / r;
    float vt = 0.22f + 0.10f / (r + 0.10f);
    float vr = -(0.10f + 0.06f * r + 0.025f / (r + 0.05f));
    float wave = 0.18f * std::sin(r * 9.0f - t * 1.3f + 3.0f * std::atan2(v, u));
    float bx = tx * vt + rx * vr, by = ty * vt + ry * vr;
    float cw = std::cos(wave), sw = std::sin(wave);
    fx = bx * cw - by * sw;
    fy = bx * sw + by * cw;
  }

  void step(float flow, float speed) {
    float s = std::min(w, h);
    float hit = pendingHit;
    pendingHit = 0;
    t += kStep * speed * (0.4f + 0.8f * drive);
    const float decay = std::exp(-kStep * 2.4f);
    float margin = s * 0.1f;
    for (auto& e : embers) {
      e.px = e.x;
      e.py = e.y;
      float dx = e.x - w * 0.5f, dy = e.y - h * 0.5f;
      float d = std::sqrt(dx * dx + dy * dy) + 1.0f;
      if (hit > 0) {
        float push = s * (0.7f + 0.5f * rng.unit()) * hit;
        e.vx += dx / d * push;
        e.vy += dy / d * push;
      }
      float fx, fy;
      field(e.x, e.y, fx, fy);
      e.vx *= decay;
      e.vy *= decay;
      e.x += (fx * s * flow * e.size + e.vx) * kStep;
      e.y += (fy * s * flow * e.size + e.vy) * kStep;
      e.life -= kStep;
      if (e.life <= 0 || d < s * 0.05f || e.x < -margin || e.x > w + margin || e.y < -margin || e.y > h + margin) spawn(e);
    }
  }

 public:
  void reset(uint32_t seed) override {
    rng = Random(seed);
    embers.clear();
    w = h = 0;
    bass = body = spark = energy = slowBass = kick = flash = drive = surge = 0;
    groups.fill(0);
    t = rng.unit() * 20.0f;
    current = rng.unit() * 64.0f;
    breath = breathVel = 0;
    ringR = 3.0f;
    ringAmp = 0;
    steps = -1;
    frac = pendingHit = 0;
  }

  void update(const Frame& f) override {
    float dt = float(f.delta);
    if (f.width != w || f.height != h || embers.empty()) {
      w = f.width;
      h = f.height;
      int count = int(100.0f + 50.0f * std::clamp(f.detail, 0.25f, 2.0f));
      embers.assign(count, Ember{0, 0, 0, 0, 0, 0, 0, 1});
      for (auto& e : embers) {
        e.size = 0.6f + rng.unit() * 0.8f;
        spawn(e);
        e.life *= rng.unit();
      }
    }
    const Music& m = f.music;
    bass = follow(bass, m.bass, 22.0f, 4.5f, dt);
    body = follow(body, m.body, 12.0f, 3.0f, dt);
    spark = follow(spark, m.spark, 30.0f, 7.0f, dt);
    energy = follow(energy, m.energy, 6.0f, 1.8f, dt);
    drive = follow(drive, m.active ? std::pow(std::clamp(m.energy, 0.0f, 1.0f), 0.8f) : 0.0f, 3.0f, 0.7f, dt);
    float lo = 0, mi = 0, hi = 0;
    for (int i = 0; i < 9; i++) lo = std::max(lo, m.smoothSpectrum[i]);
    for (int i = 9; i < 21; i++) mi = std::max(mi, m.smoothSpectrum[i]);
    for (int i = 21; i < 31; i++) hi = std::max(hi, m.smoothSpectrum[i]);
    groups[0] = follow(groups[0], lo, 20.0f, 4.0f, dt);
    groups[1] = follow(groups[1], mi, 20.0f, 4.0f, dt);
    groups[2] = follow(groups[2], hi, 20.0f, 4.0f, dt);

    float hit = 0, fl = 0;
    for (const auto& e : m.events[0]) hit = std::max(hit, e.strength);
    for (const auto& e : m.events[2]) hit = std::max(hit, e.strength * 0.85f);
    for (const auto& e : m.events[3]) fl = std::max(fl, e.strength);
    float onset = std::clamp((m.bass - slowBass - 0.15f) * 2.5f, 0.0f, 1.0f);
    slowBass = follow(slowBass, m.bass, 3.0f, 3.0f, dt);
    hit = std::min(std::max(hit, onset), 1.0f);
    bool strike = hit > kick + 0.2f;
    if (strike) {
      pendingHit = std::max(pendingHit, hit);
      surge = std::max(surge, hit);
      breathVel += 2.4f * hit;
      ringR = 0.0f;
      ringAmp = hit;
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    surge *= std::exp(-dt * 1.8f);
    ringR += dt * (0.9f + 0.5f * drive);
    ringAmp *= std::exp(-dt * 2.4f);
    // El torbellino respira: se expande con el golpe y vuelve con un muelle.
    breathVel += (-breath * 28.0f - breathVel * 6.0f) * dt;
    breath += breathVel * dt;

    float flow = f.speed * (0.65f + 0.7f * drive + 0.45f * bass + 0.6f * surge);
    // La corriente del fuego avanza en espiral; se envuelve en el periodo
    // radial de la textura para no perder precisión.
    current = std::fmod(current + dt * flow * 0.55f, 64.0f);
    int64_t target = int64_t(std::floor(f.time * kHz + 1e-6));
    if (steps < 0 || target < steps || target - steps > 30) steps = target - 1;
    while (steps < target) {
      step(flow, f.speed);
      steps++;
    }
    frac = std::clamp(float(f.time * kHz - double(steps)), 0.0f, 1.0f);
  }

  void render(const Frame& f, Canvas& c) const override {
    float amp = f.intensity;
    std::vector<float> u;
    u.reserve(24);
    u.insert(u.end(), {current, bass * amp, kick * amp, energy});
    u.insert(u.end(), {f.glow, ringR, ringAmp * amp, breath * amp});
    u.insert(u.end(), {groups[0] * amp, groups[1] * amp, groups[2] * amp, flash * amp});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("maelstrom", {0, 0, f.width, f.height}, u);
    if (embers.empty()) return;
    // Chispas: halo tenue y punto caliente, nunca líneas.
    float px = std::min(f.width, f.height) / 400.0f;
    std::vector<Vec2> pts;
    pts.reserve(embers.size());
    for (const auto& e : embers) pts.push_back({e.px + (e.x - e.px) * frac, e.py + (e.y - e.py) * frac});
    const Color& hot = f.colors[3];
    float gain = std::clamp((0.55f + 0.5f * groups[2] + 0.5f * kick) * amp, 0.0f, 1.0f);
    float twinkle = 0.8f + 0.2f * std::sin(t * 11.0f) * spark;
    Paint halo;
    halo.blend = Blend::plus;
    halo.color = {hot.r, hot.g * 0.8f, hot.b * 0.6f, 0.10f * gain * f.glow};
    c.points(pts, (5.0f + 2.0f * kick * amp) * px, halo);
    Paint core;
    core.blend = Blend::plus;
    core.color = {1.0f, 0.86f, 0.62f, gain * twinkle};
    c.points(pts, (1.3f + 0.8f * groups[2] * amp + 0.6f * kick * amp) * px, core);
  }
};
''';

const shaderSources = <String, String>{
  'maelstrom': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // corriente en espiral, graves, golpe, energía
uniform vec4 uB;   // glow, radio y fuerza de la onda de choque, respiración
uniform vec4 uD;   // graves, medios y agudos del espectro, destello
uniform vec3 uC0;
uniform vec3 uC1;
uniform vec3 uC2;
uniform vec3 uC3;
out vec4 fragColor;

const float TAU = 6.2831853;
const float ARMS = 12.0;     // celdas de ruido por vuelta
const float RADIAL = 64.0;   // periodo radial de la textura, en celdas
const float WIND = 2.6;      // enrollamiento de la espiral

float hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

// Ruido periódico: sin costura en el corte del ángulo y sin perder precisión
// aunque la corriente avance durante horas.
float pnoise(vec2 p, vec2 period) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  vec2 i0 = mod(i, period);
  vec2 i1 = mod(i + 1.0, period);
  float a = hash12(i0);
  float b = hash12(vec2(i1.x, i0.y));
  float c = hash12(vec2(i0.x, i1.y));
  float d = hash12(i1);
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float pfbm(vec2 p, vec2 period) {
  float s = 0.0;
  float a = 0.5;
  for (int i = 0; i < 4; i++) {
    s += a * pnoise(p, period);
    p = p * 2.0 + vec2(0.0, 17.0);
    period *= 2.0;
    a *= 0.5;
  }
  return s / 0.9375;
}

// Rampa de fuego: brasa roja, naranja, ámbar y blanco sólo en lo más intenso.
// La paleta se pasa a luz lineal para que, tras la corrección gamma final, el
// naranja conserve su tono y no se vuelva dorado.
vec3 fireRamp(float I) {
  vec3 c1 = pow(uC1, vec3(2.2));
  vec3 c2 = pow(uC2, vec3(2.2));
  vec3 c3 = pow(uC3, vec3(2.2));
  vec3 c = mix(c1, c2, smoothstep(0.1, 0.8, I));
  c = mix(c, c3, smoothstep(1.3, 2.5, I));
  c = mix(c, vec3(1.0, 0.94, 0.82), smoothstep(2.8, 4.2, I));
  return c * min(I, 2.2) * 0.6;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  float r = length(p) + 0.0005;
  float a = atan(p.y, p.x);
  float bass = uA.y;
  float kick = uA.z;

  // La onda de choque empuja el fuego al pasar y el golpe expande el remolino.
  float dr = r - uB.y;
  float shock = uB.z * exp(-dr * dr * 160.0);
  float rr = max(r / (1.0 + 0.5 * uB.w) - 0.04 * shock, 0.0005);
  float lr = log(rr);

  // Coordenadas de espiral: X etiqueta cada brazo y Y avanza hacia el centro
  // con la corriente; las celdas quedan alargadas a lo largo del giro.
  float X = (a + WIND * lr) * (ARMS / TAU);
  float Y = lr * 1.5 + uA.x;
  float warp = pnoise(vec2(X * 0.5, lr * 0.75 + uA.x * 0.5), vec2(ARMS * 0.5, RADIAL * 0.5));
  float n = pfbm(vec2(X + 2.4 * (warp - 0.5), Y), vec2(ARMS, RADIAL));

  // Filamentos de luz donde el ruido cruza su valor medio y cuerpo de fuego.
  float ridge = 1.0 - abs(2.0 * n - 1.0);
  float r4 = ridge * ridge;
  r4 *= r4;
  float fil = r4 * r4 * r4;
  float hot = fil * fil;
  float bodyFire = smoothstep(0.55, 1.0, n);

  float env = smoothstep(0.03, 0.16, r) * (0.35 + 1.0 * exp(-r * 2.0));
  float I = bodyFire * (0.12 + 0.35 * uD.x + 0.15 * bass)
          + fil * (0.7 + 1.2 * uD.y + 0.7 * kick)
          + hot * (0.5 + 2.0 * uD.z);
  I *= env * (0.75 + 0.5 * uA.w) * uB.x;
  // Umbral de negro: el fuego tenue desaparece y el fondo queda negro.
  I = max(I - 0.05, 0.0) * 1.1;

  // Núcleo ardiente que late con los graves, anillo de choque y destello.
  I += (0.0015 + 0.004 * bass + 0.008 * kick) / (r * r + 0.002);
  I += shock * exp(-dr * dr * 900.0) * 3.0;
  I += uD.w * 0.3 * env;

  vec3 col = pow(uC0, vec3(2.2)) + fireRamp(I);
  col *= 1.0 - 0.35 * smoothstep(0.6, 1.4, length(p * vec2(0.9, 0.65)));
  // Mapeo de tonos que conserva el tono: el naranja no vira a amarillo.
  float peak = max(col.r, max(col.g, col.b));
  float mapped = clamp((peak * (2.51 * peak + 0.03)) / (peak * (2.43 * peak + 0.59) + 0.14), 0.0, 1.0);
  col *= mapped / max(peak, 0.0001);
  col = pow(max(col, 0.0), vec3(0.4545));
  col += (hash12(frag) - 0.5) / 255.0;
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
