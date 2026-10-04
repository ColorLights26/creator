// Arena de Colores Transparente — arena que cae y se apila en capas de colores.
// Versión overlay: mismo movimiento y reacción a la música sin fondo opaco.
// Una simulación de arena grano a grano, como en los juegos de partículas:
// cada grano cae si tiene hueco debajo y, si no, resbala en diagonal, así se
// forman montañas con su ángulo natural. Desde arriba caen varios chorros que
// se mueven de lado a lado y cambian de color, y la arena se acumula en
// estratos como en las botellas de arena. Cuando la pantalla se llena se abre
// un agujero en el centro del suelo y todo se vacía como un reloj de arena.
// La energía hace caer más arena y cada golpe cambia el color de los chorros
// y suelta un puñado extra.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.steps('granos', 'Granos a lo ancho', min: 60, max: 140, value: 90),
  CreatorModifier.steps('chorros', 'Chorros', min: 1, max: 3, value: 2),
  CreatorModifier.slider('caudal', 'Caudal', min: .4, max: 2.5, value: 1),
  CreatorModifier.toggle('textura', 'Textura de grano', value: true),
];

const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kMaxCols = 140;
  static constexpr int kMaxRows = 320;
  static constexpr int kColors = 5;
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double clock = 0;
  int64_t steps = 0, colorStep = 0;
  int cols = 0, rows = 0, grains = 0, burst = 0;
  bool draining = false;
  std::array<int, 3> streamColor{};
  Random rng{1};
  std::vector<uint8_t> grid;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  uint8_t& cell(int x, int y) { return grid[size_t(y * cols + x)]; }

  // Dunas iniciales por capas para no empezar con la pantalla vacía.
  void seedLayers() {
    float p1 = rng.unit() * 6.28f, p2 = rng.unit() * 6.28f, p3 = rng.unit() * 6.28f;
    int first = int(rng.unit() * float(kColors));
    for (int x = 0; x < cols; x++) {
      float fx = float(x);
      float total = float(rows) * (0.2f + 0.05f * std::sin(fx * 0.06f + p1) + 0.035f * std::sin(fx * 0.17f + p2));
      int y0 = rows - 1;
      for (int layer = 0; layer < 4; layer++) {
        float part = 0.25f + 0.08f * std::sin(fx * (0.09f + 0.03f * float(layer)) + p3 + float(layer) * 1.7f);
        int h = std::max(1, int(total * part));
        uint8_t color = uint8_t(1 + (first + layer * 2) % kColors);
        for (int k = 0; k < h && y0 >= 0; k++, y0--) {
          cell(x, y0) = color;
          grains++;
        }
      }
    }
  }

  void nextColors() {
    for (auto& c : streamColor) c = (c + 1 + int(rng.unit() * 2.0f)) % kColors;
  }

  void step(const Frame& f, int streams, float rate) {
    // Fuentes: chorros que van y vienen por arriba.
    if (!draining) {
      for (int s = 0; s < streams; s++) {
        // Tiempo del paso, no del frame: igual a 30 y a 60 FPS.
        double ph = double(steps) / 60.0 * (0.13 + 0.05 * double(s)) + double(s) * 2.1;
        int x = int((0.5 + 0.38 * std::sin(ph)) * double(cols));
        float amount = rate + (burst > 0 ? 2.0f : 0.0f);
        int n = int(amount) + (rng.unit() < amount - std::floor(amount) ? 1 : 0);
        for (int k = 0; k < n; k++) {
          int xx = std::clamp(x + int((rng.unit() - 0.5f) * 5.0f), 0, cols - 1);
          if (cell(xx, 0) == 0) {
            cell(xx, 0) = uint8_t(1 + streamColor[size_t(s)]);
            grains++;
          }
        }
      }
      if (burst > 0) burst--;
      // Sin música el color de los chorros cambia cada 3,5 s de simulación.
      if (steps - colorStep >= 210) {
        nextColors();
        colorStep = steps;
      }
    } else {
      // Agujero en el centro del suelo: la arena se escapa.
      int hole = std::max(2, cols / 7);
      for (int x = cols / 2 - hole / 2; x < cols / 2 + hole / 2; x++) {
        if (cell(x, rows - 1)) {
          cell(x, rows - 1) = 0;
          grains--;
        }
      }
    }
    // Caída: de abajo arriba, alternando el sentido de cada fila.
    bool flip = (steps & 1) != 0;
    for (int y = rows - 2; y >= 0; y--) {
      for (int i = 0; i < cols; i++) {
        int x = flip ? cols - 1 - i : i;
        uint8_t v = cell(x, y);
        if (!v) continue;
        if (!cell(x, y + 1)) {
          cell(x, y + 1) = v;
          cell(x, y) = 0;
          continue;
        }
        bool leftFirst = rng.unit() < 0.5f;
        int a = leftFirst ? x - 1 : x + 1, b = leftFirst ? x + 1 : x - 1;
        if (a >= 0 && a < cols && !cell(a, y + 1) && !cell(a, y)) {
          cell(a, y + 1) = v;
          cell(x, y) = 0;
        } else if (b >= 0 && b < cols && !cell(b, y + 1) && !cell(b, y)) {
          cell(b, y + 1) = v;
          cell(x, y) = 0;
        }
      }
    }
    int capacity = cols * rows;
    if (!draining && grains * 100 > capacity * 58) draining = true;
    if (draining && grains * 100 < capacity * 2) draining = false;
    (void)f;
  }

 public:
  void reset(uint32_t seed) override {
    rng = Random(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    clock = 0;
    steps = 0;
    colorStep = 0;
    cols = rows = 0;
    grains = 0;
    burst = 0;
    draining = false;
    streamColor = {0, 2, 3};
    grid.assign(size_t(kMaxCols * kMaxRows), 0);
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
    if (hit > kick + 0.2f) {
      nextColors();
      colorStep = steps;
      burst = 8;
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));

    int c = std::clamp(m.granos, 60, kMaxCols);
    float size = f.width / float(c);
    int r = std::clamp(int(std::ceil(f.height / std::max(size, 0.5f))), 1, kMaxRows);
    if (c != cols || r != rows) {
      cols = c;
      rows = r;
      std::fill(grid.begin(), grid.end(), 0);
      grains = 0;
      draining = false;
      seedLayers();
    }
    // Pasos fijos a 60 por segundo.
    clock += f.delta * f.speed;
    int64_t target = int64_t(std::floor(clock * 60.0 + 1e-6));
    if (target - steps > 6) steps = target - 6;
    float rate = m.caudal * (1.6f + 3.0f * energy) * float(cols) / 90.0f;
    int streams = std::clamp(m.chorros, 1, 3);
    while (steps < target) {
      step(f, streams, rate);
      steps++;
    }
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    float amp = f.intensity;
    if (cols <= 0) return;
    float size = f.width / float(cols);
    std::array<Color, kColors> sand = {f.colors[1], f.colors[2], f.colors[3], Color{1.0f, 0.88f, 0.12f, 1.0f},
                                       Color{1.0f, 0.18f, 0.72f, 1.0f}};
    // Tramos seguidos del mismo color en cada fila: un rectángulo por tramo.
    std::array<Path, kColors> paths;
    // Toda la arena junta: el grano sólo se pinta sobre ella.
    Path all;
    for (int y = 0; y < rows; y++) {
      int x = 0;
      while (x < cols) {
        uint8_t v = grid[size_t(y * cols + x)];
        if (!v) {
          x++;
          continue;
        }
        int start = x;
        while (x < cols && grid[size_t(y * cols + x)] == v) x++;
        Rect cellRun{float(start) * size, float(y) * size, float(x - start) * size + 0.5f, size + 0.5f};
        paths[size_t(v - 1)].rect(cellRun);
        all.rect(cellRun);
      }
    }
    float lit = (0.9f + 0.2f * bass + 0.15f * kick) * amp;
    for (int k = 0; k < kColors; k++) {
      Paint p;
      const Color& col = sand[size_t(k)];
      p.color = {std::min(1.0f, col.r * lit), std::min(1.0f, col.g * lit), std::min(1.0f, col.b * lit), 1.0f};
      c.path(paths[size_t(k)], p);
    }
    if (m.textura) {
      std::vector<float> u = {size, f.glow, 0.0f, 0.0f};
      c.save();
      c.clip(all);
      c.material("sand_grain", {0, 0, f.width, f.height}, u);
      c.restore();
    }
  }
};
''';

const shaderSources = <String, String>{
  'sand_grain': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // tamaño del grano
out vec4 fragColor;

float hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  // Cada grano tiene su tono: se oscurece un poco al azar.
  vec2 cell = floor(frag / max(uA.x, 1.0));
  float h = hash12(cell);
  fragColor = vec4(0.0, 0.0, 0.0, h * 0.28);
}
""",
};
