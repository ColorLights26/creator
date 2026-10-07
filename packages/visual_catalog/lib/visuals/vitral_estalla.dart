// Vitral que Estalla — vitral de colores intensos iluminado desde atrás.
// La pantalla es un mosaico de vidrios de rubí, esmeralda y zafiro con plomo
// negro; una luz que se mueve detrás los enciende y late con los graves, y
// cada golpe recorre el vitral como una onda de luz. En el drop el vitral se
// rompe: los fragmentos giran y vuelan hacia la cámara, una luz cegadora entra
// por el hueco y un vitral nuevo se recompone desde el centro.
const nativeSource = r'''
class Visual final : public Scene {
  struct Cell {
    std::vector<Vec2> poly;
    Vec2 c;
    float radius = 0, tone = 1, clear = 0, delay = 0;
    float vx = 0, vy = 0, spin = 0, zoom = 0;
    int color = 1;
  };
  std::vector<Cell> window, shards;
  float w = 0, h = 0;
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  float ringR = 3.0f, ringAmp = 0, blast = 0;
  double clock = 0, sinceShatter = 100;
  bool rebuilt = false;
  Random rng{37};

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  // Recorta el polígono al semiplano dot(p, n) <= d.
  static std::vector<Vec2> clip(const std::vector<Vec2>& poly, Vec2 n, float d) {
    std::vector<Vec2> out;
    out.reserve(poly.size() + 2);
    for (size_t i = 0; i < poly.size(); i++) {
      Vec2 p = poly[i], q = poly[(i + 1) % poly.size()];
      float dp = p.x * n.x + p.y * n.y - d, dq = q.x * n.x + q.y * n.y - d;
      if (dp <= 0) out.push_back(p);
      if ((dp <= 0) != (dq <= 0)) {
        float t = dp / (dp - dq);
        out.push_back({p.x + (q.x - p.x) * t, p.y + (q.y - p.y) * t});
      }
    }
    return out;
  }

  // Mosaico de Voronoi exacto: cada celda es el rectángulo recortado por las
  // mediatrices de sus vecinas.
  void build(float detail) {
    float s = std::min(w, h);
    float size = s / (4.6f + 1.2f * std::clamp(detail, 0.25f, 2.0f));
    int cols = int(std::ceil(w / size)) + 1, rows = int(std::ceil(h / size)) + 1;
    float cw = w / float(cols - 1), ch = h / float(rows - 1);
    std::vector<Vec2> seeds;
    for (int j = 0; j < rows; j++)
      for (int i = 0; i < cols; i++)
        seeds.push_back({(float(i) + (rng.unit() - 0.5f) * 0.8f) * cw, (float(j) + (rng.unit() - 0.5f) * 0.8f) * ch});
    window.clear();
    float pad = s * 0.05f;
    Vec2 mid{w * 0.5f, h * 0.5f};
    for (size_t i = 0; i < seeds.size(); i++) {
      std::vector<Vec2> poly = {{-pad, -pad}, {w + pad, -pad}, {w + pad, h + pad}, {-pad, h + pad}};
      for (size_t j = 0; j < seeds.size() && !poly.empty(); j++) {
        if (i == j) continue;
        float dx = seeds[j].x - seeds[i].x, dy = seeds[j].y - seeds[i].y;
        if (dx * dx + dy * dy > size * size * 9.0f) continue;
        Vec2 n{dx, dy};
        float d = ((seeds[i].x + seeds[j].x) * dx + (seeds[i].y + seeds[j].y) * dy) * 0.5f;
        poly = clip(poly, n, d);
      }
      if (poly.size() < 3) continue;
      Cell cell;
      cell.poly = poly;
      float sx = 0, sy = 0;
      for (const auto& p : poly) { sx += p.x; sy += p.y; }
      cell.c = {sx / poly.size(), sy / poly.size()};
      float r = 0;
      for (const auto& p : poly) r = std::max(r, std::hypot(p.x - cell.c.x, p.y - cell.c.y));
      cell.radius = r;
      float pick = rng.unit();
      cell.color = pick < 0.36f ? 1 : (pick < 0.68f ? 2 : 3);
      cell.clear = rng.unit() < 0.14f ? 0.55f : 0.0f;
      cell.tone = 0.8f + 0.35f * rng.unit();
      float dist = std::hypot(cell.c.x - mid.x, cell.c.y - mid.y) / s;
      cell.delay = 0.45f + dist * 0.55f;
      window.push_back(cell);
    }
  }

  void shatter() {
    float s = std::min(w, h);
    shards = window;
    Vec2 mid{w * 0.5f, h * 0.5f};
    for (auto& sh : shards) {
      float dx = sh.c.x - mid.x, dy = sh.c.y - mid.y;
      float d = std::sqrt(dx * dx + dy * dy) + 1.0f;
      float speed = s * (0.8f + 1.4f * rng.unit());
      sh.vx = dx / d * speed + (rng.unit() - 0.5f) * s * 0.3f;
      sh.vy = dy / d * speed + (rng.unit() - 0.5f) * s * 0.3f - s * 0.2f;
      sh.spin = (rng.unit() - 0.5f) * 7.0f;
      sh.zoom = 0.5f + 1.6f * rng.unit();
    }
    build(1.0f);
    sinceShatter = 0;
    rebuilt = true;
  }

  Color glassColor(const Frame& f, const Cell& cell, float light) const {
    const Color& g = f.colors[cell.color];
    float r = g.r + (1.0f - g.r) * cell.clear, gg = g.g + (1.0f - g.g) * cell.clear, b = g.b + (1.0f - g.b) * cell.clear;
    return {std::min(1.0f, r * light), std::min(1.0f, gg * light), std::min(1.0f, b * light), 1.0f};
  }

  // Giro, escala y desplazamiento de un vidrio alrededor de su centro,
  // aplicados a los puntos aquí en vez de con save/transform/restore: así
  // todo el vitral (y cada fragmento) cabe en una sola pasada.
  struct Move {
    Vec2 to;
    float cs = 1, sn = 0, scale = 1;
    bool still = true;
  };
  static Vec2 moved(const Move& m, const Cell& cell, Vec2 p) {
    if (m.still) return p;
    const float x = (p.x - cell.c.x) * m.scale, y = (p.y - cell.c.y) * m.scale;
    return {m.to.x + x * m.cs - y * m.sn, m.to.y + x * m.sn + y * m.cs};
  }

  void drawCell(const Frame& f, Canvas& c, const Cell& cell, float light, float alpha, Vec2 lamp, bool edge, const Move& m) const {
    float s = std::min(f.width, f.height);
    Path path;
    const Vec2 p0 = moved(m, cell, cell.poly[0]);
    path.moveTo(p0.x, p0.y);
    for (size_t i = 1; i < cell.poly.size(); i++) {
      const Vec2 p = moved(m, cell, cell.poly[i]);
      path.lineTo(p.x, p.y);
    }
    path.close();
    // Gradiente radial desplazado hacia la luz: el vidrio brilla por el lado
    // que mira a la lámpara y se oscurece hacia el plomo.
    Vec2 hot = moved(m, cell, {cell.c.x + (lamp.x - cell.c.x) * 0.18f, cell.c.y + (lamp.y - cell.c.y) * 0.18f});
    Color bright = glassColor(f, cell, light * 1.35f);
    Color dark = glassColor(f, cell, light * 0.42f);
    bright.r = std::min(1.0f, bright.r + 0.08f * light);
    bright.g = std::min(1.0f, bright.g + 0.08f * light);
    bright.b = std::min(1.0f, bright.b + 0.08f * light);
    bright.a = dark.a = alpha;
    Paint fill = Paint::radial(hot, cell.radius * 1.25f * m.scale, {bright, dark});
    c.path(path, fill);
    Paint lead;
    lead.strokeWidth = s * 0.011f * m.scale;
    lead.strokeJoin = 1;
    const Color& ld = f.colors[0];
    lead.color = {ld.r, ld.g, ld.b, alpha};
    c.path(path, lead);
    if (edge) {
      // Filo de luz sobre el plomo: era una suma (plus) de 0,55 de luz
      // cálida sobre el plomo recién pintado. Pintado normal con el color
      // plomo + luz da el mismo píxel (exacto con el fragmento opaco) y no
      // corta la pasada del vitral.
      const float k = 0.55f * alpha;
      const float warm[3] = {1.0f, 0.95f, 0.85f}, base[3] = {ld.r, ld.g, ld.b};
      float a = 0.0f;
      for (int ch = 0; ch < 3; ch++) a = std::max(a, k * warm[ch] / std::max(1e-4f, 1.0f - alpha * base[ch]));
      a = std::min(a, 1.0f);
      if (a > 1e-4f) {
        float rgb[3];
        for (int ch = 0; ch < 3; ch++) rgb[ch] = std::clamp(k * warm[ch] / a + alpha * base[ch], 0.0f, 1.0f);
        Paint rim;
        rim.strokeWidth = s * 0.003f * m.scale;
        rim.strokeJoin = 1;
        rim.color = {rgb[0], rgb[1], rgb[2], a};
        c.path(path, rim);
      }
    }
  }

  float lightAt(const Frame& f, Vec2 p, Vec2 lamp) const {
    float s = std::min(f.width, f.height);
    float dx = (p.x - lamp.x) / s, dy = (p.y - lamp.y) / s;
    float d2 = dx * dx + dy * dy;
    float d = std::sqrt(d2);
    float wave = ringAmp * std::exp(-(d - ringR) * (d - ringR) * 30.0f);
    return (0.45f + 0.85f * std::exp(-d2 * 2.2f)) * (0.8f + 0.55f * bass + 0.25f * energy) + 0.9f * wave + 0.35f * flash;
  }

  Vec2 lampAt(const Frame& f) const {
    return {f.width * (0.5f + 0.16f * float(std::sin(clock * 0.21))),
            f.height * (0.45f + 0.12f * float(std::cos(clock * 0.17)))};
  }

 public:
  void reset(uint32_t seed) override {
    rng = Random(seed);
    window.clear();
    shards.clear();
    w = h = 0;
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    ringR = 3.0f;
    ringAmp = blast = 0;
    clock = rng.unit() * 20.0;
    sinceShatter = 100;
    rebuilt = false;
  }

  void update(const Frame& f) override {
    float dt = float(f.delta);
    if (f.width != w || f.height != h || window.empty()) {
      w = f.width;
      h = f.height;
      build(f.detail);
      shards.clear();
      sinceShatter = 100;
      rebuilt = false;
    }
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
    sinceShatter += f.delta;
    if (hit > kick + 0.2f) {
      ringR = 0.0f;
      ringAmp = hit;
      // Drop: golpe fuerte con la música lanzada y el vitral entero.
      if (hit > 0.55f && drive > 0.3f && sinceShatter > 8.0) {
        shatter();
        blast = 1.0f;
      }
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    blast *= std::exp(-dt * 1.6f);
    ringR += dt * (0.9f + 0.5f * drive);
    ringAmp *= std::exp(-dt * 2.0f);
    clock += f.delta * f.speed * (0.5 + 0.8 * drive);
    if (sinceShatter > 2.5) shards.clear();
  }

  void render(const Frame& f, Canvas& c) const override {
    float amp = f.intensity;
    Vec2 lamp = lampAt(f);
    std::vector<float> u;
    u.reserve(20);
    u.insert(u.end(), {float(std::fmod(clock, 1000.0)), bass * amp, kick * amp, energy});
    u.insert(u.end(), {lamp.x / f.width, lamp.y / f.height, blast * amp, f.glow});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    // Luz de fondo: sólo se ve por el hueco cuando el vitral se rompe.
    c.material("backlight", {0, 0, f.width, f.height}, u);

    float tNew = float(sinceShatter);
    for (const Cell& cell : window) {
      float alpha = 1.0f, grow = 1.0f;
      if (rebuilt) {
        float a = std::clamp((tNew - cell.delay) / 0.4f, 0.0f, 1.0f);
        if (a <= 0) continue;
        alpha = a;
        grow = 0.75f + 0.25f * a * a * (3.0f - 2.0f * a);
      }
      float light = lightAt(f, cell.c, lamp) * amp;
      Move m;
      if (grow < 0.999f) {
        m.still = false;
        m.to = cell.c;
        m.scale = grow;
      }
      drawCell(f, c, cell, light, alpha, lamp, false, m);
    }

    // Fragmentos que vuelan hacia la cámara girando.
    float tau = float(sinceShatter);
    float s = std::min(f.width, f.height);
    for (const Cell& sh : shards) {
      float alpha = 1.0f - std::clamp((tau - 0.55f) / 0.6f, 0.0f, 1.0f);
      if (alpha <= 0) continue;
      float ox = sh.vx * tau, oy = sh.vy * tau + 0.5f * s * 1.4f * tau * tau;
      Move m;
      m.still = false;
      m.to = {sh.c.x + ox, sh.c.y + oy};
      m.cs = std::cos(sh.spin * tau);
      m.sn = std::sin(sh.spin * tau);
      m.scale = 1.0f + sh.zoom * tau;
      drawCell(f, c, sh, (1.1f + 0.8f * blast) * amp, alpha, lamp, true, m);
    }

    // Brillo del vidrio: ondulaciones y destellos con los agudos.
    std::vector<float> g;
    g.reserve(16);
    g.insert(g.end(), {float(std::fmod(clock, 1000.0)), spark * amp, kick * amp, f.glow});
    for (int i = 0; i < 4; i++) g.insert(g.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("glass_sheen", {0, 0, f.width, f.height}, g, {}, Blend::plus);
  }
};
''';

const shaderSources = <String, String>{
  'backlight': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // reloj, graves, golpe, energía
uniform vec4 uB;   // posición de la lámpara, fogonazo, glow
uniform vec3 uC0;
uniform vec3 uC1;
uniform vec3 uC2;
uniform vec3 uC3;
out vec4 fragColor;

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - uB.xy * uSize) / scale;
  float r = length(p);
  float a = atan(p.y, p.x);
  // Luz blanca cálida con rayos que salen de la lámpara.
  float rays = 0.6 + 0.4 * sin(a * 9.0 + uA.x * 0.7) * sin(a * 5.0 - uA.x * 0.4);
  float core = 0.05 / (r * r + 0.05);
  float I = (0.12 + core * rays * 1.6) * (0.6 + 2.2 * uB.z + 0.4 * uA.y) * uB.w;
  vec3 col = uC0 + vec3(1.0, 0.86, 0.6) * I + vec3(1.0) * smoothstep(0.6, 3.0, I) * 0.5;
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
  'glass_sheen': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // reloj, agudos, golpe, glow
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
  vec2 p = frag / scale;
  // Vidrio soplado: ondulaciones suaves que reflejan un brillo blanco.
  float n = noise(p * vec2(6.0, 14.0) + vec2(0.0, uA.x * 0.05));
  float sheen = smoothstep(0.62, 0.95, n) * 0.05 * uA.w;
  // Destellos de luz que saltan con los agudos.
  float glint = step(0.998 - 0.004 * uA.y, hash12(floor(frag * 0.34) + floor(uA.x * 5.0)));
  vec3 col = vec3(1.0, 0.96, 0.9) * (sheen + glint * 0.7 * uA.y + 0.02 * uA.z);
  col = clamp(col, 0.0, 1.0);
  fragColor = vec4(col, max(col.r, max(col.g, col.b)));
}
""",
};
