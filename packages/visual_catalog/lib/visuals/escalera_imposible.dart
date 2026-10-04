// Escalera Imposible — la escalera de Penrose que sube para siempre.
// Los escalones forman un anillo visto desde arriba que siempre sube: en realidad
// es una espiral cuyo final queda justo delante de su comienzo en la línea
// de vista, así que se dibuja como un bucle cerrado e imposible. Cada bloque
// tiene la cara superior, la izquierda y la derecha en tres colores. Una luz
// sube escalón a escalón sin llegar nunca arriba; cada golpe lanza otra luz
// rápida, los graves encienden los escalones y en Auto el estilo alterna
// entre bloques macizos y bloques de neón cada ocho golpes.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.steps('escalones', 'Escalones por lado', min: 4, max: 10, value: 7),
  CreatorModifier.slider('subida', 'Velocidad de subida', min: .3, max: 2.5, value: 1),
  CreatorModifier.choice('estilo', 'Estilo', options: ['Auto', 'Macizo', 'Neón']),
  CreatorModifier.toggle('caminante', 'Luz que sube', value: true),
];

const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kMaxSteps = 32;
  struct Block { float x, y, z; int index; };
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double walk = 0, runner = 100, sinceStyle = 0;
  float neon = 0, neonTarget = 0, runnerPower = 0;
  int beats = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  static Color shade(const Color& c, float g) {
    return {std::min(1.0f, c.r * g), std::min(1.0f, c.g * g), std::min(1.0f, c.b * g), 1.0f};
  }

  // Bloques del anillo: cuatro tramos (a, b, c, d) con el mismo ascenso por
  // escalón; el desplazamiento total (k, k, k) cae sobre la línea de vista.
  static int buildRing(int n, std::array<Block, kMaxSteps>& out, float& rise) {
    int side = std::max(2, n / 2);
    int a = n, b = n, cc = side, d = side;
    int k = a - cc;
    int total = a + b + cc + d;
    rise = float(k) / float(total);
    int x = 0, y = 0, i = 0;
    auto add = [&](int dx, int dy, int count) {
      for (int s = 0; s < count && i < kMaxSteps; s++) {
        out[size_t(i)] = {float(x), float(y), rise * float(i), i};
        x += dx;
        y += dy;
        i++;
      }
    };
    add(1, 0, a);
    add(0, 1, b);
    add(-1, 0, cc);
    add(0, -1, d);
    return i;
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    walk = rng.unit() * 10.0;
    runner = 100;
    sinceStyle = 0;
    neon = neonTarget = 0;
    runnerPower = 0;
    beats = 0;
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
    runner += f.delta;
    sinceStyle += f.delta;
    if (hit > kick + 0.2f) {
      beats++;
      runner = 0;
      runnerPower = hit;
      if (beats % 8 == 0) {
        neonTarget = 1.0f - neonTarget;
        sinceStyle = 0;
      }
    }
    if (!mu.active && sinceStyle > 10.0) {
      neonTarget = 1.0f - neonTarget;
      sinceStyle = 0;
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    float goal = m.estilo == 1 ? 0.0f : (m.estilo == 2 ? 1.0f : neonTarget);
    neon += (goal - neon) * (1.0f - std::exp(-dt * 2.5f));
    walk += f.delta * f.speed * m.subida * (1.5 + 3.0 * drive);
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    float amp = f.intensity;
    std::vector<float> u;
    u.reserve(20);
    u.insert(u.end(), {bass * amp, kick * amp, energy, f.glow});
    u.insert(u.end(), {spark * amp, flash * amp, neon, 0.0f});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("iso_backdrop", {0, 0, f.width, f.height}, u);

    std::array<Block, kMaxSteps> ring{};
    float rise = 0;
    int count = buildRing(std::clamp(m.escalones, 4, 10), ring, rise);
    // Cada escalón es una columna hasta un suelo común, como el edificio de Escher.
    const float ground = -2.4f;
    // Proyección isométrica y encuadre: el anillo ocupa el ancho disponible.
    // Vista algo cenital; la altura escala al doble que la profundidad para
    // que el ascenso total (k, k, k) caiga exactamente sobre el comienzo.
    auto isoX = [](float x, float y) { return (x - y) * 0.8f; };
    auto isoY = [](float x, float y, float z) { return (x + y) * 0.6f - z * 1.2f; };
    float minX = 1e9f, maxX = -1e9f, minY = 1e9f, maxY = -1e9f;
    for (int i = 0; i < count; i++) {
      const Block& b = ring[size_t(i)];
      for (int cx = 0; cx <= 1; cx++) {
        for (int cy = 0; cy <= 1; cy++) {
          float X = isoX(b.x + cx, b.y + cy);
          minX = std::min(minX, X);
          maxX = std::max(maxX, X);
          minY = std::min(minY, isoY(b.x + cx, b.y + cy, b.z));
          maxY = std::max(maxY, isoY(b.x + cx, b.y + cy, ground));
        }
      }
    }
    float S = std::min(f.width * 0.86f / (maxX - minX), f.height * 0.62f / (maxY - minY));
    float ox = f.width * 0.5f - (minX + maxX) * 0.5f * S;
    float oy = f.height * 0.5f - (minY + maxY) * 0.5f * S;
    auto P = [&](float x, float y, float z) { return Vec2{ox + isoX(x, y) * S, oy + isoY(x, y, z) * S}; };

    // Orden de pintor: primero lo más lejano de la cámara.
    std::array<int, kMaxSteps> order{};
    for (int i = 0; i < count; i++) order[size_t(i)] = i;
    std::sort(order.begin(), order.begin() + count, [&](int l, int r) {
      const Block& a = ring[size_t(l)];
      const Block& b = ring[size_t(r)];
      if (a.x + a.y != b.x + b.y) return a.x + a.y < b.x + b.y;
      return a.z < b.z;
    });

    float walker = float(std::fmod(walk, double(count)));
    float run = float(runner) * 18.0f;
    const Color& coral = f.colors[1];
    const Color& yellow = f.colors[2];
    const Color& blue = f.colors[3];
    float px = std::min(f.width, f.height) / 400.0f;
    for (int oi = 0; oi < count; oi++) {
      const Block& b = ring[size_t(order[size_t(oi)])];
      // Luz que sube: distancia cíclica al caminante y al destello del golpe.
      float d = std::fabs(float(b.index) - walker);
      d = std::min(d, float(count) - d);
      float lit = m.caminante ? std::exp(-d * d * 0.6f) : 0.0f;
      float dr = std::fabs(float(b.index) - std::fmod(run, float(count)));
      dr = std::min(dr, float(count) - dr);
      lit += runner < 1.5 ? std::exp(-dr * dr * 0.5f) * runnerPower * float(1.0 - runner / 1.5) : 0.0f;
      float glow = (0.8f + 0.5f * bass + 0.9f * lit) * amp;
      // La luz que pasa levanta el escalón un poco.
      float zt = b.z + 0.22f * std::min(lit, 1.5f), zb = ground;
      Path top, right, left;
      Vec2 t0 = P(b.x, b.y, zt), t1 = P(b.x + 1, b.y, zt), t2 = P(b.x + 1, b.y + 1, zt), t3 = P(b.x, b.y + 1, zt);
      top.moveTo(t0.x, t0.y).lineTo(t1.x, t1.y).lineTo(t2.x, t2.y).lineTo(t3.x, t3.y).close();
      Vec2 r0 = P(b.x + 1, b.y, zt), r1 = P(b.x + 1, b.y + 1, zt), r2 = P(b.x + 1, b.y + 1, zb), r3 = P(b.x + 1, b.y, zb);
      right.moveTo(r0.x, r0.y).lineTo(r1.x, r1.y).lineTo(r2.x, r2.y).lineTo(r3.x, r3.y).close();
      Vec2 l0 = P(b.x, b.y + 1, zt), l1 = P(b.x + 1, b.y + 1, zt), l2 = P(b.x + 1, b.y + 1, zb), l3 = P(b.x, b.y + 1, zb);
      left.moveTo(l0.x, l0.y).lineTo(l1.x, l1.y).lineTo(l2.x, l2.y).lineTo(l3.x, l3.y).close();
      // Macizo: caras de color; neón: caras oscuras con aristas encendidas.
      float solid = 1.0f - neon;
      Color dark = f.colors[0];
      auto faceColor = [&](const Color& c, float g) {
        Color s = shade(c, g * glow);
        Color n = shade(dark, 1.4f);
        return Color{n.r + (s.r - n.r) * solid, n.g + (s.g - n.g) * solid, n.b + (s.b - n.b) * solid, 1.0f};
      };
      // Las paredes se oscurecen hacia el suelo.
      Paint pt;
      pt.color = faceColor(yellow, 1.0f);
      Vec2 rTop{(r0.x + r1.x) * 0.5f, (r0.y + r1.y) * 0.5f}, rBot{(r2.x + r3.x) * 0.5f, (r2.y + r3.y) * 0.5f};
      Vec2 lTop{(l0.x + l1.x) * 0.5f, (l0.y + l1.y) * 0.5f}, lBot{(l2.x + l3.x) * 0.5f, (l2.y + l3.y) * 0.5f};
      Paint pr = Paint::linear(rTop, rBot, {faceColor(coral, 0.9f), faceColor(coral, 0.3f)});
      Paint pl = Paint::linear(lTop, lBot, {faceColor(blue, 0.85f), faceColor(blue, 0.28f)});
      c.path(top, pt);
      c.path(right, pr);
      c.path(left, pl);
      Paint edge;
      edge.strokeWidth = (1.0f + 1.2f * neon) * px;
      edge.strokeJoin = 1;
      float e = 0.25f + 0.75f * neon;
      edge.color = {std::min(1.0f, yellow.r * e * glow), std::min(1.0f, yellow.g * e * glow), std::min(1.0f, yellow.b * e * glow), 1.0f};
      if (neon < 0.5f) edge.color = {dark.r * 0.5f, dark.g * 0.5f, dark.b * 0.5f, 0.6f};
      c.path(top, edge);
      Paint edge2 = edge;
      if (neon >= 0.5f) edge2.color = {std::min(1.0f, coral.r * glow), std::min(1.0f, coral.g * glow), std::min(1.0f, coral.b * glow), 1.0f};
      c.path(right, edge2);
      Paint edge3 = edge;
      if (neon >= 0.5f) edge3.color = {std::min(1.0f, blue.r * glow), std::min(1.0f, blue.g * glow), std::min(1.0f, blue.b * glow), 1.0f};
      c.path(left, edge3);
      if (lit > 0.05f) {
        Paint halo;
        halo.blend = Blend::plus;
        halo.color = {yellow.r, yellow.g, yellow.b, std::clamp(0.35f * lit * f.glow, 0.0f, 1.0f)};
        c.path(top, halo);
      }
    }
  }
};
''';

const shaderSources = <String, String>{
  'iso_backdrop': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // graves, golpe, energía, glow
uniform vec4 uB;   // agudos, destello, estilo neón
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

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  // Fondo azul noche con una retícula isométrica tenue.
  vec3 col = mix(uC0 * 1.3, uC0 * 0.5, smoothstep(-0.8, 0.9, p.y));
  vec2 g = vec2(p.x / 0.866 + p.y * 2.0, -p.x / 0.866 + p.y * 2.0) * 6.0;
  vec2 gl = abs(fract(g) - 0.5);
  float grid = (1.0 - smoothstep(0.0, 0.04, min(gl.x, gl.y)));
  col += uC3 * grid * (0.05 + 0.05 * uB.z);
  col += mix(uC1, uC2, 0.5) * exp(-dot(p, p) * 2.0) * (0.06 + 0.08 * uA.x + 0.12 * uA.y) * uA.w;
  col += uC2 * uB.y * 0.04;
  col *= 1.0 - 0.4 * smoothstep(0.5, 1.4, length(p * vec2(0.9, 0.65)));
  col += (hash12(frag) - 0.5) / 255.0;
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
