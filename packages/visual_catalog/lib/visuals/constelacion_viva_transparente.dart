// Constelación Táctil Transparente — constelación tridimensional viva sobre una nebulosa.
// Versión overlay: mismo movimiento y reacción a la música sin fondo opaco.
// Estrellas luminosas unidas por líneas de luz gruesas por las que viajan
// pulsos de energía. Cada golpe expande la constelación como una explosión
// que rebota, enciende estrellas y líneas y lanza un anillo de choque; cada
// estrella late con su banda del espectro y los agudos aceleran los pulsos.
const nativeSource = r'''
class Visual final : public Scene {
  struct Star { float x, y, z, size, phase; int band; };
  struct Edge { int a, b; };
  std::vector<Star> stars;
  std::vector<Edge> edges;
  std::vector<float> pulseRate, pulseOffset;
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  std::array<float, 8> bands{};
  float time = 0, yaw = 0, spinVel = 0, pulsePhase = 0, push = 0, pushVel = 0;
  std::array<float, 4> rings{};  // radio, amplitud, radio, amplitud

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  struct Projected { float x, y, depth, persp; };

  // Campo de estrellas a pantalla completa: una capa con profundidad que gira
  // suavemente; las cercanas se mueven más que las lejanas (paralaje).
  Projected project(const Star& s, float cx, float cy, float sx, float sy, float tilt) const {
    float a = std::sin(yaw) * 0.45f;
    float ca = std::cos(a), sa = std::sin(a);
    float x1 = s.x * ca + s.z * sa;
    float z1 = -s.x * sa + s.z * ca;
    float ct = std::cos(tilt), st = std::sin(tilt);
    float y2 = s.y * ct - z1 * st;
    float z2 = s.y * st + z1 * ct;
    float persp = 2.4f / (2.4f + z2);
    return {cx + x1 * sx * persp, cy - y2 * sy * persp, 0.5f - 0.5f * z2, persp};
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    stars.clear();
    edges.clear();
    // Rejilla con desplazamiento aleatorio: estrellas repartidas por toda la
    // pantalla sin huecos grandes ni montones.
    const int cols = 6, rows = 12;
    const int count = cols * rows;
    for (int i = 0; i < count; i++) {
      float gx = (float(i % cols) + 0.15f + 0.7f * rng.unit()) / float(cols);
      float gy = (float(i / cols) + 0.15f + 0.7f * rng.unit()) / float(rows);
      stars.push_back({(gx * 2.0f - 1.0f) * 1.25f, (gy * 2.0f - 1.0f) * 1.12f, rng.unit() * 2.0f - 1.0f,
                       0.6f + rng.unit() * 0.8f, rng.unit() * 6.2831853f, i % 8});
    }
    // Cada estrella se une a sus dos vecinas más cercanas.
    for (int i = 0; i < count; i++) {
      int best[2] = {-1, -1};
      float dist[2] = {1e9f, 1e9f};
      for (int j = 0; j < count; j++) {
        if (j == i) continue;
        float dx = stars[i].x - stars[j].x, dy = (stars[i].y - stars[j].y) * 1.8f;
        float dz = (stars[i].z - stars[j].z) * 0.35f;
        float d = dx * dx + dy * dy + dz * dz;
        if (d < dist[0]) { dist[1] = dist[0]; best[1] = best[0]; dist[0] = d; best[0] = j; }
        else if (d < dist[1]) { dist[1] = d; best[1] = j; }
      }
      for (int k = 0; k < 2; k++) {
        int a = std::min(i, best[k]), b = std::max(i, best[k]);
        bool exists = false;
        for (const auto& e : edges) if (e.a == a && e.b == b) exists = true;
        if (!exists) edges.push_back({a, b});
      }
    }
    pulseRate.clear();
    pulseOffset.clear();
    for (int i = 0; i < 40; i++) {
      pulseRate.push_back(0.5f + rng.unit() * 0.7f);
      pulseOffset.push_back(rng.unit());
    }
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    bands.fill(0);
    time = 0;
    yaw = rng.unit() * 6.2831853f;
    spinVel = pulsePhase = push = pushVel = 0;
    rings = {2.0f, 0.0f, 2.0f, 0.0f};
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
      pushVel += 2.4f * hit;
      spinVel += 0.7f * hit;
      rings[2] = rings[0];
      rings[3] = rings[1];
      rings[0] = 0.0f;
      rings[1] = hit;
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));

    static const int edgesSpec[9] = {0, 3, 6, 9, 13, 17, 21, 26, 31};
    for (int b = 0; b < 8; b++) {
      float v = 0;
      for (int i = edgesSpec[b]; i < edgesSpec[b + 1]; i++) v = std::max(v, m.smoothSpectrum[i]);
      bands[b] = follow(bands[b], v, 22.0f, 4.5f, dt);
    }

    // Explosión con rebote: muelle amortiguado que vuelve a la forma original.
    pushVel += (-push * 32.0f - pushVel * 6.5f) * dt;
    push += pushVel * dt;
    spinVel *= std::exp(-dt * 1.8f);
    time += dt * f.speed;
    yaw += dt * f.speed * (0.06f + 0.22f * drive) + dt * spinVel;
    pulsePhase += dt * f.speed * (0.18f + 0.6f * drive + 0.9f * kick + 0.6f * spark);
    for (int i = 0; i < 4; i += 2) {
      rings[i] += dt * (0.7f + 0.3f * drive);
      rings[i + 1] *= std::exp(-dt * 2.2f);
    }
  }

  void render(const Frame& f, Canvas& c) const override {
    float w = f.width, h = f.height;
    float s = std::min(w, h);
    float k = s / 400.0f;
    float cx = w * 0.5f, cy = h * 0.5f;
    float amp = f.intensity;
    float glow = std::clamp(f.glow, 0.0f, 2.0f);
    const Color& c1 = f.colors[1];
    const Color& c2 = f.colors[2];
    const Color& c3 = f.colors[3];

    // Fondo: nebulosa suave que respira con los graves.
    c.material("cosmos", {0, 0, w, h},
               {time, bass * amp, kick * amp, energy, flash, glow,
                f.colors[0].r, f.colors[0].g, f.colors[0].b, c1.r, c1.g, c1.b, c2.r, c2.g, c2.b});

    float tilt = 0.12f * std::sin(time * 0.13f);
    float zoom = 1.0f + 0.22f * push * amp + 0.05f * bass * amp;
    float sx = w * 0.5f * zoom, sy = h * 0.5f * zoom;
    std::vector<Projected> pts;
    pts.reserve(stars.size());
    for (const auto& st : stars) pts.push_back(project(st, cx, cy, sx, sy, tilt));

    auto alpha = [](float v) { return std::clamp(v, 0.0f, 1.0f); };
    float lineBoost = 0.7f + 0.6f * energy + 1.1f * kick * amp + 0.5f * flash;

    // Líneas de luz: lejanas y cercanas, cada grupo en tres capas de brillo.
    Path farPath, nearPath;
    for (const auto& e : edges) {
      const Projected& a = pts[e.a];
      const Projected& b = pts[e.b];
      Path& target = (a.depth + b.depth) * 0.5f > 0.5f ? nearPath : farPath;
      target.moveTo(a.x, a.y);
      target.lineTo(b.x, b.y);
    }
    for (int layer = 0; layer < 2; layer++) {
      const Path& path = layer == 0 ? farPath : nearPath;
      float depthGain = layer == 0 ? 0.55f : 1.0f;
      Paint halo;
      halo.blend = Blend::plus;
      halo.strokeCap = 1;
      halo.strokeWidth = (layer == 0 ? 10.0f : 16.0f) * k;
      halo.color = {c1.r, c1.g, c1.b, alpha(0.09f * lineBoost * depthGain * glow)};
      c.path(path, halo);
      Paint mid = halo;
      mid.strokeWidth = (layer == 0 ? 4.0f : 6.0f) * k;
      mid.color = {c2.r, c2.g, c2.b, alpha(0.2f * lineBoost * depthGain)};
      c.path(path, mid);
      Paint core = halo;
      core.strokeWidth = (layer == 0 ? 1.6f : 2.6f) * k;
      core.color = {(c1.r + c3.r) * 0.5f, (c1.g + c3.g) * 0.5f, (c1.b + c3.b) * 0.5f,
                    alpha(0.7f * lineBoost * depthGain)};
      c.path(path, core);
    }

    // Pulsos de energía que recorren las líneas.
    std::vector<Vec2> pulses;
    pulses.reserve(pulseRate.size());
    for (size_t i = 0; i < pulseRate.size() && !edges.empty(); i++) {
      const Edge& e = edges[(i * 7 + 3) % edges.size()];
      float t = pulsePhase * pulseRate[i] + pulseOffset[i];
      t -= std::floor(t);
      if (int(std::floor(pulsePhase * pulseRate[i] + pulseOffset[i])) % 2 == 1) t = 1.0f - t;
      const Projected& a = pts[e.a];
      const Projected& b = pts[e.b];
      pulses.push_back({a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t});
    }
    Paint pulseGlow;
    pulseGlow.blend = Blend::plus;
    pulseGlow.color = {c1.r, c1.g, c1.b, alpha(0.14f + 0.18f * energy + 0.3f * kick * amp)};
    c.points(pulses, 6.5f * k, pulseGlow);
    Paint pulseCore = pulseGlow;
    pulseCore.color = {1, 1, 1, alpha(0.55f + 0.3f * spark + 0.3f * kick)};
    c.points(pulses, 2.8f * k, pulseCore);

    // Estrellas: halo radial que late con su banda del espectro.
    std::vector<Vec2> cores;
    cores.reserve(stars.size());
    for (size_t i = 0; i < stars.size(); i++) {
      const Star& st = stars[i];
      const Projected& p = pts[i];
      float band = bands[st.band];
      float twinkle = 0.85f + 0.15f * std::sin(time * 2.3f + st.phase);
      float radius = (14.0f + 16.0f * st.size) * k * p.persp *
                     (1.0f + 1.1f * band * amp + 0.9f * kick * amp) * twinkle;
      float mixT = float(st.band) / 7.0f;
      Color col{c1.r + (c2.r - c1.r) * mixT, c1.g + (c2.g - c1.g) * mixT, c1.b + (c2.b - c1.b) * mixT, 1};
      float a = alpha((0.55f + 0.5f * band + 0.45f * kick * amp) * (0.55f + 0.45f * p.depth) * glow);
      Paint halo = Paint::radial({p.x, p.y}, radius,
                                 {col.opacity(a), col.opacity(a * 0.45f), col.opacity(a * 0.12f), col.opacity(0.0f)},
                                 {0.0f, 0.2f, 0.5f, 1.0f});
      halo.blend = Blend::plus;
      c.circle({p.x, p.y}, radius, halo);
      cores.push_back({p.x, p.y});
    }
    Paint coreP;
    coreP.blend = Blend::plus;
    coreP.color = {1, 1, 1, alpha(0.75f + 0.25f * kick)};
    c.points(cores, 2.8f * k, coreP);

    // Destellos en cruz en las estrellas más cercanas.
    for (size_t i = 0; i < stars.size(); i++) {
      const Projected& p = pts[i];
      if (p.depth < 0.72f) continue;
      float band = bands[stars[i].band];
      float len = (22.0f + 40.0f * band * amp + 45.0f * kick * amp) * k * p.persp;
      float a = alpha((0.35f + 0.4f * band + 0.4f * kick * amp) * (p.depth - 0.6f) * 2.5f);
      Color tint{1, 1, 1, 1};
      for (int axis = 0; axis < 2; axis++) {
        Vec2 from = axis == 0 ? Vec2{p.x - len, p.y} : Vec2{p.x, p.y - len};
        Vec2 to = axis == 0 ? Vec2{p.x + len, p.y} : Vec2{p.x, p.y + len};
        Paint spike = Paint::linear(from, to, {tint.opacity(0.0f), tint.opacity(a), tint.opacity(0.0f)},
                                    {0.0f, 0.5f, 1.0f});
        spike.blend = Blend::plus;
        spike.strokeWidth = 1.6f * k;
        Path line;
        line.moveTo(from.x, from.y);
        line.lineTo(to.x, to.y);
        c.path(line, spike);
      }
    }

    // Anillos de choque con cada golpe.
    for (int i = 0; i < 4; i += 2) {
      if (rings[i + 1] < 0.02f) continue;
      Paint ring;
      ring.blend = Blend::plus;
      ring.strokeWidth = 4.0f * k;
      float fade = rings[i + 1] * amp * std::max(0.0f, 1.0f - rings[i] / 1.2f);
      ring.color = {c3.r, c3.g, c3.b, alpha(0.75f * fade)};
      c.circle({cx, cy}, rings[i] * s * 0.6f, ring);
      Paint wide = ring;
      wide.strokeWidth = 22.0f * k;
      wide.color = {c1.r, c1.g, c1.b, alpha(0.18f * fade)};
      c.circle({cx, cy}, rings[i] * s * 0.6f, wide);
    }
  }
};
''';

const shaderSources = <String, String>{
  'cosmos': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // tiempo, graves, golpe, energía
uniform vec2 uB;   // destello, glow
uniform vec3 uC0;
uniform vec3 uC1;
uniform vec3 uC2;
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
  for (int i = 0; i < 3; i++) {
    s += a * noise(p);
    p = mat2(1.6, 1.2, -1.2, 1.6) * p;
    a *= 0.5;
  }
  return s / 0.875;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  float t = uA.x;
  float r = length(p);

  float n1 = fbm(p * 1.5 + vec2(t * 0.02, -t * 0.015));
  float n2 = fbm(p * 2.6 - vec2(t * 0.03, t * 0.01) + 4.0);
  vec3 neb = mix(uC1, uC2, smoothstep(0.3, 0.7, n2)) * smoothstep(0.45, 0.85, n1);
  vec3 col = uC0 + neb * (0.22 + 0.30 * uA.y + 0.35 * uA.z) * uB.y;
  col += mix(uC1, uC2, 0.5) * exp(-r * r * 3.0) * (0.05 + 0.12 * uA.w + 0.22 * uA.z) * uB.y;

  // Polvo de estrellas lejano.
  vec2 g = p * 70.0;
  float h = hash12(floor(g));
  float star = smoothstep(0.08, 0.0, length(fract(g) - 0.5)) * step(0.975, h);
  col += vec3(0.85, 0.9, 1.0) * star * (0.35 + 0.35 * sin(t * 2.0 + h * 60.0));

  col *= 1.0 - 0.45 * smoothstep(0.45, 1.25, length(p * vec2(0.9, 0.65)));
  // Fondo transparente: color premultiplicado y opacidad según el brillo; la
  // luz muy tenue se vuelve transparente del todo para no dejar velo.
  col = clamp(col, 0.0, 1.0);
  float veilPeak = max(col.r, max(col.g, col.b));
  float clearCut = smoothstep(0.04, 0.12, veilPeak);
  col *= clearCut;
  float alpha = clamp(veilPeak * 1.25, 0.0, 1.0) * clearCut;
  fragColor = vec4(col, alpha);
}
""",
};
