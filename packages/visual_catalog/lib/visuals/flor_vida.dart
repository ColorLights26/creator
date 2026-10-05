// Flor de la Vida — la geometría sagrada se dibuja sola.
// Diecinueve círculos iguales, cada uno con el centro en el borde de los
// vecinos, se trazan uno a uno como con un compás: primero el central, luego
// el anillo de seis y después el de doce. Donde dos círculos se cruzan nacen
// los pétalos, que se tiñen en cuanto sus dos círculos se cierran y se
// encienden en oro sobre violeta cuando dos aros cierran la flor. Con el cubo
// de Metatrón, una regla une cada uno de los trece centros principales con
// los anteriores en cuanto su círculo se cierra; al terminar, sus 78 líneas
// se encienden y todo gira despacio antes de apagarse y volver a empezar.
// Los graves hacen latir los pétalos, cada golpe enciende las líneas y la
// energía acelera el trazado.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.slider('ritmo', 'Velocidad del trazado', min: .4, max: 2.5, value: 1),
  CreatorModifier.slider('tamano', 'Tamaño', min: .6, max: 1.3, value: 1),
  // MODO: la flor sola o atravesada por la red de rectas del cubo.
  CreatorModifier.toggle('metatron', 'Cubo de Metatrón', value: true),
  // MODO: pétalos rellenos o sólo el contorno trazado con el compás.
  CreatorModifier.toggle('petalos', 'Pétalos encendidos', value: true),
];

const nativeSource = r'''
class Visual final : public Scene {
  static constexpr double kCycle = 24.0;
  // Una recta del cubo: sale del centro más nuevo (from) hacia uno anterior
  // en cuanto el círculo del nuevo se cierra (ready, en círculos trazados).
  struct Line { int from, to; float ready; };
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double cycle = 0, spin = 0;
  std::array<Vec2, 13> nodes{};
  std::array<float, 13> nodeDone{};
  std::array<Line, 78> lines{};

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    cycle = rng.unit() * 2.0;
    spin = rng.unit() * 6.2831853;
    // Trece centros del Fruto de la Vida (en unidades del radio) y cuándo
    // se cierra su círculo, con el mismo orden de trazado que el shader:
    // el central, el anillo de seis y, del de doce, uno de cada dos.
    nodes[0] = {0, 0};
    nodeDone[0] = 1.0f;
    for (int k = 0; k < 6; k++) {
      float a = 6.2831853f * float(k) / 6.0f;
      nodes[size_t(1 + k)] = {std::cos(a), std::sin(a)};
      nodes[size_t(7 + k)] = {2.0f * std::cos(a), 2.0f * std::sin(a)};
      nodeDone[size_t(1 + k)] = float(2 + k);
      nodeDone[size_t(7 + k)] = float(8 + 2 * k);
    }
    int n = 0;
    for (int i = 0; i < 13; i++) {
      for (int j = i + 1; j < 13; j++) {
        // j siempre se cierra después que i: la recta nace en j.
        lines[size_t(n++)] = {j, i, nodeDone[size_t(j)]};
      }
    }
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
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    cycle += f.delta * f.speed * m.ritmo * (1.0 + 0.8 * drive);
    while (cycle >= kCycle) cycle -= kCycle;
    spin += f.delta * f.speed * (0.05 + 0.15 * drive);
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    auto g = glide(f);
    float amp = f.intensity;
    float t = float(cycle);
    // Guion del ciclo: círculos 0–9 s (con sus pétalos y rectas a la par),
    // aros 9–10,5, pétalos encendidos 9–11, cubo encendido 11–15, giro hasta
    // 21 y fundido a negro hasta 24.
    // Llega a 20 (un círculo más que los 19) para que el último también se
    // cierre: cuente en los pétalos y lance sus rectas completas.
    float circles = std::clamp(t / 9.0f * 19.0f, 0.0f, 20.0f);
    float rings = std::clamp((t - 9.0f) / 1.5f, 0.0f, 1.0f);
    float ignite = std::clamp((t - 9.0f) / 2.0f, 0.0f, 1.0f);
    // Pétalos: un relleno suave mientras se forman que se enciende con los aros.
    float petals = g.petalos * (0.55f + 0.45f * ignite);
    float meta = std::clamp((t - 11.0f) / 4.0f, 0.0f, 1.0f);
    float fade = 1.0f - std::clamp((t - 21.0f) / 3.0f, 0.0f, 1.0f);
    float side = std::min(f.width, f.height);
    float r = side * 0.135f * m.tamano * (1.0f + 0.04f * bass * amp);
    float rot = float(std::fmod(spin, 6.2831853));
    std::vector<float> u;
    u.reserve(28);
    u.insert(u.end(), {t, bass * amp, kick * amp, energy});
    u.insert(u.end(), {circles, rings, petals * fade, rot});
    u.insert(u.end(), {r / side, fade, f.glow, flash * amp});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("flower_of_life", {0, 0, f.width, f.height}, u);

    // Cubo de Metatrón: cada centro, al cerrarse su círculo, lanza rectas
    // hacia los centros anteriores; al terminar la flor, la red se enciende.
    float cube = g.metatron * fade;
    if (cube > 0.001f && circles > 1.0f) {
      Vec2 center{f.width * 0.5f, f.height * 0.5f};
      float cs = std::cos(rot), sn = std::sin(rot);
      auto at = [&](int i) {
        Vec2 v = nodes[size_t(i)];
        return Vec2{center.x + (v.x * cs - v.y * sn) * r, center.y + (v.x * sn + v.y * cs) * r};
      };
      Path full, part;
      for (const Line& l : lines) {
        float vis = std::clamp((circles - l.ready) / 1.2f, 0.0f, 1.0f);
        if (vis <= 0.0f) continue;
        Vec2 a = at(l.from), b = at(l.to);
        if (vis >= 1.0f) {
          full.moveTo(a.x, a.y).lineTo(b.x, b.y);
        } else {
          part.moveTo(a.x, a.y).lineTo(a.x + (b.x - a.x) * vis, a.y + (b.y - a.y) * vis);
        }
      }
      float px = side / 400.0f;
      float hitAmp = std::min(kick * amp, 1.5f);
      const Color& gold = f.colors[2];
      Paint glow;
      glow.blend = Blend::plus;
      // Mientras se construye, un halo ancho; con la red completa, más fino
      // para que el centro, donde se cruzan todas, no se lave en oro.
      glow.strokeWidth = (9.0f - 4.0f * meta + 4.0f * hitAmp) * px;
      glow.strokeCap = 1;
      glow.color = gold.opacity(std::clamp((0.14f - 0.03f * meta + 0.18f * hitAmp) * f.glow * cube, 0.0f, 0.6f));
      c.path(full, glow);
      c.path(part, glow);
      Paint line;
      line.blend = Blend::plus;
      line.strokeWidth = 1.8f * px;
      line.strokeCap = 1;
      line.color = gold.opacity(std::clamp((0.5f + 0.12f * meta + 0.3f * hitAmp) * cube, 0.0f, 1.0f));
      c.path(full, line);
      c.path(part, line);
      std::vector<Vec2> pts;
      pts.reserve(13);
      for (int i = 0; i < 13; i++) {
        if (circles >= nodeDone[size_t(i)]) pts.push_back(at(i));
      }
      Paint node;
      node.blend = Blend::plus;
      node.color = Color{0.5f + 0.5f * gold.r, 0.5f + 0.5f * gold.g, 0.5f + 0.5f * gold.b,
                         std::clamp((0.45f + 0.35f * meta + 0.3f * hitAmp) * cube, 0.0f, 1.0f)};
      c.points(pts, (3.2f + 1.0f * meta + 1.5f * hitAmp) * px, node);
    }
  }
};
''';

const shaderSources = <String, String>{
  'flower_of_life': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // ciclo, graves, golpe, energía
uniform vec4 uB;   // círculos trazados, aros, pétalos, giro
uniform vec4 uD;   // radio, fundido, glow, destello
uniform vec3 uC0;
uniform vec3 uC1;
uniform vec3 uC2;
uniform vec3 uC3;
out vec4 fragColor;

const float TAU = 6.2831853;

float hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p0 = (frag - 0.5 * uSize) / scale;
  float cs = cos(uB.w);
  float sn = sin(uB.w);
  // Coordenadas en unidades del radio de los círculos, giradas.
  vec2 p = vec2(cs * p0.x + sn * p0.y, -sn * p0.x + cs * p0.y) / uD.x;
  float px = 1.0 / (scale * uD.x);
  float lineW = 0.022 + 0.012 * uA.y;
  float line = 0.0;
  float glow = 0.0;
  float inside = 0.0;
  float r = length(p);
  // Sólo los centros a menos de un radio pueden tocar este píxel: se buscan
  // en la rejilla triangular alrededor del punto (como mucho 16 candidatos),
  // y fuera de la flor no hay ninguno.
  if (r < 3.3) {
    float lb = p.y / 0.8660254;
    float fb0 = floor(lb);
    float fa0 = floor(p.x - 0.5 * lb);
    for (int j = -1; j <= 2; j++) {
      for (int i = -1; i <= 2; i++) {
        float fb = fb0 + float(j);
        float fa = fa0 + float(i);
        float ring = max(abs(fa), max(abs(fb), abs(fa + fb)));
        if (ring > 2.5) continue;
        vec2 c = fa * vec2(1.0, 0.0) + fb * vec2(0.5, 0.8660254);
        vec2 d = p - c;
        float dist = length(d);
        float e = abs(dist - 1.0);
        if (e > 0.6 && dist > 1.0) continue;
        // Orden de trazado: centro, anillo de 6, anillo de 12, por ángulo.
        float order = 0.0;
        if (ring > 0.5 && ring < 1.5) order = 1.0 + mod(floor(mod(atan(c.y, c.x), TAU) / TAU * 6.0 + 0.5), 6.0);
        if (ring > 1.5) order = 7.0 + mod(floor(mod(atan(c.y, c.x), TAU) / TAU * 12.0 + 0.5), 12.0);
        float fr = clamp(uB.x - order, 0.0, 1.0);
        if (fr <= 0.0) continue;
        // Un círculo cerrado cuenta para los rellenos; entra en un tercio de
        // círculo, así los pétalos se forman sin saltos.
        inside += clamp((uB.x - order - 1.0) * 3.0, 0.0, 1.0) * step(dist, 1.0);
        // Arco trazado hasta ahora, empezando por el lado del centro.
        float drawn = 1.0;
        if (fr < 1.0) {
          float start = atan(-c.y, -c.x);
          drawn = step(mod(atan(d.y, d.x) - start, TAU) / TAU, fr);
        }
        line = max(line, (1.0 - smoothstep(lineW, lineW + px * 1.5, e)) * drawn);
        glow += exp(-e * 22.0) * drawn;
      }
    }
  }
  // Dos aros que cierran la flor.
  float ringA = abs(r - 3.0);
  float ringB = abs(r - 3.12);
  float ringAng = mod(atan(p.y, p.x) + 1.5707963, TAU) / TAU;
  float ringDrawn = step(ringAng, uB.y);
  line = max(line, (1.0 - smoothstep(lineW, lineW + px * 1.5, min(ringA, ringB))) * ringDrawn);
  glow += exp(-min(ringA, ringB) * 22.0) * ringDrawn;

  vec3 col = uC0 + uC1 * 0.08 * exp(-r * 0.6) * (1.0 + uA.y);
  // Pétalos: donde se cruzan exactamente dos círculos (suave mientras entra
  // un círculo nuevo; con cuentas enteras es exacto).
  float single = clamp(1.0 - abs(inside - 1.0), 0.0, 1.0);
  float petal = clamp(1.0 - abs(inside - 2.0), 0.0, 1.0);
  float knot = clamp(inside - 2.0, 0.0, 1.0);
  float inner = clamp(1.0 - r / 3.0, 0.0, 1.0);
  vec3 petalCol = mix(uC2, uC3, 0.35 + 0.35 * sin(r * 3.0 - uA.x * 1.5)) * (0.55 + 0.45 * inner);
  col += petalCol * petal * uB.z * (0.95 + 0.6 * uA.y + 0.4 * uA.z);
  col += uC1 * knot * uB.z * 0.45;
  col += uC1 * single * 0.12 * uB.z;
  // Trazos de luz de los círculos.
  vec3 lineCol = mix(uC1, vec3(1.0, 0.92, 1.0), 0.35);
  col += uC1 * glow * 0.06 * uD.z * (1.0 + uA.z);
  col = mix(col, lineCol * (1.0 + 0.4 * uA.z), line);
  col *= uD.y;
  col += uC1 * uD.w * 0.05;
  col *= 1.0 - 0.3 * smoothstep(0.7, 1.5, length(p0 * vec2(0.9, 0.65)));
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
