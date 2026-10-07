// Goteo Pollock — un cuadro de pintura de acción que se pinta solo.
// Como Jackson Pollock sobre el lienzo en el suelo: la pintura cae en
// latigazos largos y curvos de grosor irregular, en chorros gruesos que
// serpentean y en salpicones con gotas alrededor. Cada trazo se dibuja
// mientras vuela, en el orden en que cae, así las capas se tapan unas a
// otras como en el cuadro real. La pintura cae a ritmo constante; cada golpe
// lanza un trazo extra (y un salpicón en los golpes fuertes) y la energía
// acelera el ritmo. Cuando el lienzo está lleno se cubre y empieza otro.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.slider('ritmo', 'Ritmo de pintura', min: .3, max: 2.5, value: 1),
  CreatorModifier.slider('grosor', 'Grosor', min: .5, max: 2, value: 1),
  // MOVIMIENTO: el gesto del pintor: latigazos largos, chorros gruesos que
  // serpentean o salpicones. Conserva el id: las apariencias guardadas lo usan.
  CreatorModifier.choice('colores', 'Gesto', options: ['Latigazos', 'Chorros', 'Salpicones']),
  CreatorModifier.choice('fondo', 'Lienzo', options: ['Lino', 'Negro']),
];

const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kMax = 150;
  static constexpr int kPoints = 64;   // puntos del contorno de un latigazo o chorro
  static constexpr int kDrops = 40;    // gotas de un salpicón
  // Pool fijo: los kMax trazos se reservan en reset y se reutilizan, así la
  // memoria no crece mientras el cuadro se pinta.
  struct Stroke {
    double start = 0;
    std::array<Vec2, kPoints> left{}, right{};   // contorno del trazo, en unidades del lado corto
    std::array<Vec2, kDrops> drops{};
    std::array<uint8_t, kDrops> dropBin{};       // tamaño de cada gota: 0, 1 o 2
    int leftCount = 0, rightCount = 0, dropCount = 0;
    uint8_t color = 0;
    float duration = 0;
  };
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double clock = 0, spawnAcc = 0, clearStart = -1;
  float halfH = 1;
  Random rng{1};
  std::vector<Stroke> strokes;
  int count = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  float range(float a, float b) { return a + (b - a) * rng.unit(); }

  // Gota redonda con dos semicírculos cúbicos: la mitad de comandos que
  // Path::circle y la misma forma a este tamaño (desvío menor al 2 % del radio).
  static void addDrop(Path& path, Vec2 c, float r) {
    float k = r * 4.0f / 3.0f;
    path.moveTo(c.x + r, c.y)
        .cubicTo(c.x + r, c.y + k, c.x - r, c.y + k, c.x - r, c.y)
        .cubicTo(c.x - r, c.y - k, c.x + r, c.y - k, c.x + r, c.y)
        .close();
  }

  void spawn(double when, int kind, float thick) {
    if (count >= kMax || clearStart >= 0.0) return;
    Stroke& s = strokes[size_t(count)];
    s.leftCount = s.rightCount = s.dropCount = 0;
    s.start = when;
    s.color = uint8_t(std::min(int(rng.unit() * 5.0f), 4));
    // Latigazo largo, chorro grueso que serpentea o salpicón.
    int points = kind == 2 ? 10 : 64;
    float x = range(-0.55f, 0.55f), y = range(-halfH * 1.05f, halfH * 1.05f);
    float heading = range(0.0f, 6.2831853f);
    float length = kind == 0 ? range(0.6f, 1.5f) : (kind == 1 ? range(0.2f, 0.5f) : range(0.04f, 0.08f));
    float base = (kind == 0 ? range(0.004f, 0.014f) : (kind == 1 ? range(0.018f, 0.04f) : range(0.045f, 0.09f))) * thick;
    float bend = range(-3.0f, 3.0f), wiggle = range(1.0f, 4.0f), ph = range(0.0f, 6.28f);
    float step = length / float(points - 1);
    std::array<Vec2, kPoints> center{};
    std::array<float, kPoints> width{};
    float wp1 = range(0.0f, 6.28f), wp2 = range(0.0f, 6.28f);
    for (int i = 0; i < points; i++) {
      float u = float(i) / float(points - 1);
      center[size_t(i)] = {x, y};
      float taper = std::min(1.0f, std::min(u, 1.0f - u) * 6.0f + 0.15f);
      float w = base * (0.45f + 0.35f * std::sin(u * 17.0f + wp1) + 0.3f * std::sin(u * 41.0f + wp2));
      if (kind == 2) w = base * (0.75f + 0.25f * std::sin(u * 6.28f * 2.0f + wp1));
      width[size_t(i)] = std::max(base * 0.12f, w) * taper;
      heading += (bend + wiggle * std::sin(u * 9.0f + ph)) * step * 2.0f;
      x += std::cos(heading) * step;
      y += std::sin(heading) * step;
    }
    // Contorno: a cada lado del centro según el grosor (un salpicón es redondo).
    for (int i = 0; i < points; i++) {
      Vec2 a = center[size_t(std::max(0, i - 1))], b = center[size_t(std::min(points - 1, i + 1))];
      float dx = b.x - a.x, dy = b.y - a.y, len = std::sqrt(dx * dx + dy * dy) + 1e-6f;
      float nx = -dy / len, ny = dx / len;
      if (kind == 2) {
        float ang = 6.2831853f * float(i) / float(points);
        float r = width[size_t(i)] * range(0.8f, 1.25f);
        s.left[size_t(s.leftCount++)] = {center[0].x + std::cos(ang) * r, center[0].y + std::sin(ang) * r};
        continue;
      }
      s.left[size_t(s.leftCount++)] = {center[size_t(i)].x + nx * width[size_t(i)] * 0.5f, center[size_t(i)].y + ny * width[size_t(i)] * 0.5f};
      s.right[size_t(s.rightCount++)] = {center[size_t(i)].x - nx * width[size_t(i)] * 0.5f, center[size_t(i)].y - ny * width[size_t(i)] * 0.5f};
    }
    // Gotas alrededor: muchas en un salpicón, unas pocas en un latigazo.
    int drops = kind == 2 ? 40 : int(range(4.0f, 18.0f));
    for (int k = 0; k < drops; k++) {
      Vec2 c0 = center[size_t(std::min(int(rng.unit() * float(points)), points - 1))];
      float ang = range(0.0f, 6.2831853f);
      float dist = kind == 2 ? base * range(1.0f, 4.5f) : range(0.005f, 0.06f);
      float size = range(0.0015f, kind == 2 ? 0.012f : 0.006f) * thick;
      s.drops[size_t(s.dropCount)] = {c0.x + std::cos(ang) * dist, c0.y + std::sin(ang) * dist};
      s.dropBin[size_t(s.dropCount)] = uint8_t(size < 0.003f ? 0 : (size < 0.006f ? 1 : 2));
      s.dropCount++;
    }
    s.duration = kind == 0 ? 0.45f : (kind == 1 ? 0.35f : 0.12f);
    count++;
  }

  // Qué trazo cae según el gesto: 0 latigazo, 1 chorro, 2 salpicón.
  int pickKind(int gesture) {
    static const float mix[3][2] = {{0.68f, 0.9f}, {0.18f, 0.88f}, {0.15f, 0.3f}};
    const float* m = mix[std::clamp(gesture, 0, 2)];
    float r = rng.unit();
    return r < m[0] ? 0 : (r < m[1] ? 1 : 2);
  }

 public:
  void reset(uint32_t seed) override {
    rng = Random(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    clock = 0;
    spawnAcc = 0.6;
    clearStart = -1;
    halfH = 1;
    strokes.assign(size_t(kMax), Stroke{});
    count = 0;
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
    bool beat = hit > kick + 0.2f;
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    halfH = 0.5f * f.height / std::max(std::min(f.width, f.height), 1.0f);

    double step = f.delta * f.speed;
    double before = clock;
    clock += step;
    // Ritmo constante de pintura, cada trazo en su instante exacto.
    double rate = 2.2 * double(m.ritmo) * (1.0 + 1.5 * double(drive));
    spawnAcc += step * rate;
    while (spawnAcc >= 1.0) {
      spawnAcc -= 1.0;
      spawn(clock - spawnAcc / rate, pickKind(m.colores), m.grosor);
    }
    if (beat) {
      // El trazo extra de cada golpe es el del gesto elegido.
      spawn(clock, std::clamp(m.colores, 0, 2), m.grosor * (1.0f + 0.5f * hit));
      if (hit > 0.7f) spawn(clock, 2, m.grosor);
    }
    (void)before;
    // Lienzo lleno: se cubre durante 1,4 s y se empieza otro.
    if (clearStart < 0.0 && count >= kMax) clearStart = clock;
    if (clearStart >= 0.0 && clock - clearStart > 1.4) {
      count = 0;
      clearStart = -1;
    }
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    float amp = f.intensity;
    bool dark = m.fondo == 1;
    Color paper = dark ? Color{0.035f, 0.03f, 0.03f, 1.0f} : f.colors[0];
    std::vector<float> u = {paper.r, paper.g, paper.b, dark ? 1.0f : 0.0f};
    c.material("linen", {0, 0, f.width, f.height}, u);
    std::array<Color, 5> pal = {f.colors[3], f.colors[3], f.colors[1], f.colors[2], Color{0.88f, 0.48f, 0.08f, 1.0f}};
    // En lienzo negro, la pintura negra pasa a ser blanca.
    if (dark) {
      pal[0] = Color{0.95f, 0.93f, 0.88f, 1.0f};
      pal[1] = Color{0.95f, 0.93f, 0.88f, 1.0f};
    }
    float side = std::min(f.width, f.height);
    float cx = f.width * 0.5f, cy = f.height * 0.5f;
    auto toPx = [&](Vec2 p) { return Vec2{cx + p.x * side, cy + p.y * side}; };
    float cover = clearStart >= 0.0 ? float(std::clamp((clock - clearStart) / 1.4, 0.0, 1.0)) : 0.0f;
    float lit = (0.92f + 0.15f * kick) * amp;
    static const float radii[3] = {0.0016f, 0.0038f, 0.0075f};
    // Dos trazados reutilizados por todos los trazos: copiar uno vacío los
    // vacía sin soltar su memoria.
    const Path empty;
    Path path, drops;
    for (int si = 0; si < count; si++) {
      const Stroke& s = strokes[size_t(si)];
      float prog = float(std::clamp((clock - s.start) / double(s.duration), 0.0, 1.0));
      if (prog <= 0.0f) continue;
      const Color& base = pal[size_t(s.color)];
      Paint p;
      p.color = Color{std::min(1.0f, base.r * lit), std::min(1.0f, base.g * lit), std::min(1.0f, base.b * lit), 1.0f};
      path = empty;
      if (s.rightCount == 0) {
        // Salpicón: crece desde el centro.
        Vec2 c0{0, 0};
        for (int i = 0; i < s.leftCount; i++) { c0.x += s.left[size_t(i)].x; c0.y += s.left[size_t(i)].y; }
        c0.x /= float(s.leftCount);
        c0.y /= float(s.leftCount);
        for (size_t i = 0; i < size_t(s.leftCount); i++) {
          Vec2 q{c0.x + (s.left[i].x - c0.x) * prog, c0.y + (s.left[i].y - c0.y) * prog};
          Vec2 px = toPx(q);
          if (i == 0) path.moveTo(px.x, px.y); else path.lineTo(px.x, px.y);
        }
      } else {
        size_t drawn = std::max<size_t>(2, size_t(prog * float(s.leftCount)));
        for (size_t i = 0; i < drawn; i++) {
          Vec2 px = toPx(s.left[i]);
          if (i == 0) path.moveTo(px.x, px.y); else path.lineTo(px.x, px.y);
        }
        for (size_t i = drawn; i-- > 0;) {
          Vec2 px = toPx(s.right[i]);
          path.lineTo(px.x, px.y);
        }
      }
      path.close();
      c.path(path, p);
      if (prog >= 0.6f && s.dropCount > 0) {
        // Gotas en tres tamaños, como círculos en el mismo lote que los
        // trazos: trazos y gotas se pintan en un solo pase y cada trazo
        // posterior sigue tapando las gotas anteriores.
        drops = empty;
        for (int k = 0; k < s.dropCount; k++)
          addDrop(drops, toPx(s.drops[size_t(k)]), radii[s.dropBin[size_t(k)]] * side * m.grosor);
        c.path(drops, p);
      }
    }
    if (cover > 0.0f) {
      // Lienzo nuevo: una capa de imprimación cubre el cuadro.
      Paint veil;
      veil.color = Color{paper.r, paper.g, paper.b, cover};
      c.rect({0, 0, f.width, f.height}, veil);
    }
    if (flash > 0.01f) {
      Paint fl;
      fl.color = pal[2].opacity(std::clamp(flash * 0.06f * amp, 0.0f, 1.0f));
      c.rect({0, 0, f.width, f.height}, fl);
    }
  }
};
''';

const shaderSources = <String, String>{
  'linen': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uP;   // color del lienzo, lienzo negro
out vec4 fragColor;

float hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  // Trama del lino: hilos horizontales y verticales con irregularidades.
  float warp = 0.5 + 0.5 * sin(frag.x * 1.9 + hash12(vec2(floor(frag.x * 0.5), 0.0)) * 3.0);
  float weft = 0.5 + 0.5 * sin(frag.y * 1.9 + hash12(vec2(0.0, floor(frag.y * 0.5))) * 3.0);
  float fiber = hash12(floor(frag * 0.7));
  float shade = 0.93 + 0.035 * warp + 0.035 * weft - 0.03 * fiber;
  vec2 p = (frag - 0.5 * uSize) / min(uSize.x, uSize.y);
  shade *= 1.0 - 0.12 * smoothstep(0.6, 1.4, length(p * vec2(0.9, 0.65)));
  fragColor = vec4(clamp(uP.rgb * shade, 0.0, 1.0), 1.0);
}
""",
};
