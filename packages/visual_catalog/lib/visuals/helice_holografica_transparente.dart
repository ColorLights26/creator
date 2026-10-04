// Hélice Holográfica Transparente — una doble hélice proyectada como holograma.
// Versión overlay: mismo movimiento y reacción a la música sin fondo opaco.
// Dos hebras de luz azul giran en espiral alrededor de un eje vertical; la
// parte de atrás se ve tenue y fina, la de delante brillante. Entre ellas,
// los peldaños (como las bases del ADN) se encienden en rojo y azul según su
// banda del espectro, con nodos en cada extremo. Abajo un proyector lanza un
// cono de luz y alrededor suben partículas. Cada golpe hace temblar la hélice
// con un fallo digital (copias desplazadas en rojo y cian) y una franja de
// escaneo recorre el holograma sobre líneas de barrido.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.steps('vueltas', 'Vueltas', min: 2, max: 6, value: 3),
  CreatorModifier.slider('giro', 'Velocidad de giro', min: .2, max: 2.5, value: 1),
  CreatorModifier.toggle('escaneo', 'Franja de escaneo', value: true),
  CreatorModifier.toggle('particulas', 'Partículas', value: true),
];

const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kParticles = 90;
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  std::array<float, 12> bands{};
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double turn = 0, clock = 0, rise = 0, sinceGlitch = 100;
  float glitchPower = 0;
  int glitchSeed = 0;
  std::array<float, kParticles> partX{}, partSpeed{}, partPhase{};

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  static float hash(int n) {
    uint32_t x = uint32_t(n) * 747796405u + 2891336453u;
    x = ((x >> ((x >> 28u) + 4u)) ^ x) * 277803737u;
    return float((x >> 22u) ^ x) / 4294967296.0f;
  }

  static Color scaled(const Color& c, float g, float a) {
    return {std::min(1.0f, c.r * g), std::min(1.0f, c.g * g), std::min(1.0f, c.b * g), std::clamp(a, 0.0f, 1.0f)};
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    bands.fill(0);
    turn = rng.unit() * 6.2831853;
    clock = 0;
    rise = 0;
    sinceGlitch = 100;
    glitchPower = 0;
    glitchSeed = 0;
    for (int i = 0; i < kParticles; i++) {
      partX[size_t(i)] = rng.unit() * 2.0f - 1.0f;
      partSpeed[size_t(i)] = 0.04f + 0.08f * rng.unit();
      partPhase[size_t(i)] = rng.unit();
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
    for (int b = 0; b < 12; b++) {
      float v = 0;
      int k0 = b * 31 / 12, k1 = (b + 1) * 31 / 12;
      for (int k = k0; k < std::max(k1, k0 + 1); k++) v = std::max(v, mu.smoothSpectrum[size_t(k)]);
      bands[size_t(b)] = follow(bands[size_t(b)], v, 20.0f, 4.0f, dt);
    }

    float hit = 0, fl = 0;
    for (const auto& e : mu.events[0]) hit = std::max(hit, e.strength);
    for (const auto& e : mu.events[2]) hit = std::max(hit, e.strength * 0.85f);
    for (const auto& e : mu.events[3]) fl = std::max(fl, e.strength);
    float onset = std::clamp((mu.bass - slowBass - 0.15f) * 2.5f, 0.0f, 1.0f);
    slowBass = follow(slowBass, mu.bass, 3.0f, 3.0f, dt);
    hit = std::min(std::max(hit, onset), 1.0f);
    sinceGlitch += f.delta;
    if (hit > kick + 0.2f) {
      sinceGlitch = 0;
      glitchPower = hit;
      glitchSeed++;
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    clock += f.delta * f.speed;
    rise += f.delta * f.speed * (1.0 + 1.5 * drive);
    turn += f.delta * f.speed * m.giro * (0.7 + 1.6 * drive + 1.2 * kick);
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    float amp = f.intensity;
    const Color& blue = f.colors[1];
    const Color& ice = f.colors[2];
    const Color& red = f.colors[3];
    std::vector<float> u;
    u.reserve(20);
    u.insert(u.end(), {float(std::fmod(clock, 1000.0)), bass * amp, kick * amp, energy});
    u.insert(u.end(), {f.glow, flash * amp, 0.0f, 0.0f});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("holo_projector", {0, 0, f.width, f.height}, u);

    float px = std::min(f.width, f.height) / 400.0f;
    float cx = f.width * 0.5f;
    float top = f.height * 0.1f, bottom = f.height * 0.84f;
    float radius = std::min(f.width * 0.36f, f.height * 0.18f) * (1.0f + 0.12f * bass * amp);
    int turns = std::clamp(m.vueltas, 2, 6);
    const int perTurn = 40;
    int samples = turns * perTurn;
    float glitch = sinceGlitch < 0.45 ? glitchPower * float(1.0 - sinceGlitch / 0.45) * amp : 0.0f;
    // Temblor del fallo digital: saltos horizontales por tramos de altura.
    auto jitter = [&](float y) {
      if (glitch <= 0.0f) return 0.0f;
      int slice = int(y / (f.height * 0.06f));
      float h = hash(slice * 31 + glitchSeed * 977);
      return h > 0.55f ? (hash(slice + glitchSeed * 13) - 0.5f) * 60.0f * px * glitch : 0.0f;
    };
    // Una hebra: dos caminos, uno con la parte delantera y otro con la trasera.
    auto strand = [&](float phase, float offset, Path& front, Path& back) {
      bool startedF = false, startedB = false;
      bool prevFront = false;
      for (int s = 0; s <= samples; s++) {
        float t = float(s) / float(samples);
        float y = top + (bottom - top) * t;
        float a = t * 6.2831853f * float(turns) + float(turn) + phase;
        float x = cx + std::cos(a) * radius + jitter(y) + offset;
        bool isFront = std::sin(a) > 0.0f;
        if (isFront) {
          if (!startedF || !prevFront) front.moveTo(x, y); else front.lineTo(x, y);
          startedF = true;
        } else {
          if (!startedB || prevFront) back.moveTo(x, y); else back.lineTo(x, y);
          startedB = true;
        }
        prevFront = isFront;
      }
    };
    auto drawHelix = [&](float offset, const Color* tintOverride, float alpha) {
      Path frontA, backA, frontB, backB;
      strand(0.0f, offset, frontA, backA);
      strand(3.14159265f, offset, frontB, backB);
      // Peldaños agrupados por banda del espectro; mitad azul y mitad roja.
      int rungs = turns * 10;
      for (int b = 0; b < 12; b++) {
        Path ra, rb;
        std::vector<Vec2> nodes;
        nodes.reserve(12);
        bool any = false;
        for (int r = b; r < rungs; r += 12) {
          float t = (float(r) + 0.5f) / float(rungs);
          float y = top + (bottom - top) * t;
          float a = t * 6.2831853f * float(turns) + float(turn);
          float j = jitter(y) + offset;
          float x1 = cx + std::cos(a) * radius + j;
          float x2 = cx - std::cos(a) * radius + j;
          float mid = (x1 + x2) * 0.5f;
          ra.moveTo(x1, y).lineTo(mid, y);
          rb.moveTo(mid, y).lineTo(x2, y);
          nodes.push_back({x1, y});
          nodes.push_back({x2, y});
          any = true;
        }
        if (!any) continue;
        float level = bands[size_t(b)];
        float lit = (0.75f + 1.6f * level + 0.5f * kick) * amp;
        Paint pa, pb;
        pa.strokeWidth = pb.strokeWidth = (2.6f + 2.5f * level) * px;
        pa.strokeCap = pb.strokeCap = 1;
        pa.blend = pb.blend = Blend::plus;
        pa.color = tintOverride ? scaled(*tintOverride, 1.0f, alpha * 0.6f) : scaled(blue, lit, 0.95f);
        pb.color = tintOverride ? scaled(*tintOverride, 1.0f, alpha * 0.6f) : scaled(red, lit, 0.95f);
        c.path(ra, pa);
        c.path(rb, pb);
        if (!tintOverride) {
          Paint node;
          node.blend = Blend::plus;
          node.color = scaled(ice, 0.8f + 0.6f * level, 0.85f);
          c.points(nodes, (2.6f + 3.0f * level) * px, node);
        }
      }
      Paint backPaint;
      backPaint.strokeWidth = 1.6f * px;
      backPaint.strokeCap = 1;
      backPaint.strokeJoin = 1;
      backPaint.blend = Blend::plus;
      backPaint.color = tintOverride ? scaled(*tintOverride, 1.0f, alpha * 0.5f) : scaled(blue, 0.8f * amp, 0.45f);
      c.path(backA, backPaint);
      c.path(backB, backPaint);
      if (!tintOverride) {
        Paint halo;
        halo.strokeWidth = 12.0f * px;
        halo.strokeCap = 1;
        halo.strokeJoin = 1;
        halo.blend = Blend::plus;
        halo.color = scaled(blue, 1.0f, (0.12f + 0.12f * bass) * f.glow * amp);
        c.path(frontA, halo);
        c.path(frontB, halo);
      }
      Paint frontPaint;
      frontPaint.strokeWidth = (3.2f + 1.5f * bass) * px;
      frontPaint.strokeCap = 1;
      frontPaint.strokeJoin = 1;
      frontPaint.blend = Blend::plus;
      frontPaint.color = tintOverride ? scaled(*tintOverride, 1.0f, alpha) : scaled(ice, 1.0f * amp, 1.0f);
      c.path(frontA, frontPaint);
      c.path(frontB, frontPaint);
    };
    if (glitch > 0.02f) {
      Color r{1.0f, 0.1f, 0.2f, 1.0f};
      Color cy{0.0f, 0.9f, 1.0f, 1.0f};
      drawHelix(-9.0f * px * glitch, &r, 0.6f * glitch);
      drawHelix(9.0f * px * glitch, &cy, 0.6f * glitch);
    }
    drawHelix(0.0f, nullptr, 1.0f);

    if (m.particulas) {
      // Partículas que suben del proyector alrededor de la hélice.
      std::vector<Vec2> pts;
      pts.reserve(kParticles);
      for (int i = 0; i < kParticles; i++) {
        float life = float(std::fmod(rise * double(partSpeed[size_t(i)]) + double(partPhase[size_t(i)]), 1.0));
        float y = bottom + (top - bottom) * life;
        float x = cx + partX[size_t(i)] * radius * (1.4f + 0.5f * life);
        pts.push_back({x, y});
      }
      Paint dot;
      dot.blend = Blend::plus;
      dot.color = scaled(ice, 1.0f, std::clamp((0.35f + 0.5f * spark) * amp, 0.0f, 1.0f));
      c.points(pts, (1.2f + 1.2f * spark) * px, dot);
    }

    std::vector<float> s;
    s.reserve(8);
    s.insert(s.end(), {float(std::fmod(clock, 1000.0)), m.escaneo ? 1.0f : 0.0f, glitch, kick * amp});
    s.insert(s.end(), {ice.r, ice.g, ice.b, red.r});
    c.material("holo_scanlines", {0, 0, f.width, f.height}, s);
  }
};
''';

const shaderSources = <String, String>{
  'holo_projector': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // reloj, graves, golpe, energía
uniform vec4 uB;   // glow, destello
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
  vec2 uv = frag / uSize;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  vec3 col = uC0;
  // Cono de luz desde el proyector de abajo.
  float baseY = 0.88;
  float h = clamp((baseY - uv.y) / 0.8, 0.0, 1.0);
  float halfW = 0.04 + 0.42 * h;
  float x = abs(p.x) / max(halfW, 0.001);
  float beam = (1.0 - smoothstep(0.6, 1.0, x)) * step(uv.y, baseY) * (1.0 - h * 0.7);
  float flicker = 0.9 + 0.1 * sin(uA.x * 37.0) * sin(uA.x * 13.0);
  col += uC1 * beam * (0.06 + 0.06 * uA.y + 0.08 * uA.z) * flicker * uB.x;
  // Proyector: disco brillante con anillos.
  vec2 q = vec2(p.x, (uv.y - baseY) * uSize.y / scale * 3.5);
  float d = length(q);
  col += uC2 * exp(-d * 30.0) * (0.5 + 0.5 * uA.z);
  col += uC1 * smoothstep(0.006, 0.0, abs(d - 0.12 - 0.02 * uA.y)) * 0.6;
  col += uC1 * smoothstep(0.004, 0.0, abs(d - 0.2)) * 0.3;
  // Rejilla del suelo en perspectiva.
  if (uv.y > baseY) {
    float depth = (uv.y - baseY) * 10.0 + 0.1;
    float gx = abs(fract(p.x / depth * 3.0) - 0.5);
    float gy = abs(fract(1.0 / depth * 0.6 - uA.x * 0.3) - 0.5);
    float grid = (1.0 - smoothstep(0.0, 0.05, gx)) + (1.0 - smoothstep(0.0, 0.08, gy));
    col += uC1 * grid * 0.12 * smoothstep(0.0, 0.5, depth);
  }
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
  'holo_scanlines': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // reloj, escaneo, fallo, golpe
uniform vec4 uB;   // color hielo, rojo
out vec4 fragColor;

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 uv = frag / uSize;
  // En el overlay no hay líneas de barrido oscuras: oscurecerían lo de detrás.
  vec3 light = vec3(0.0);
  if (uA.y > 0.5) {
    // Franja de escaneo que recorre el holograma de abajo arriba.
    float pos = 1.0 - fract(uA.x * 0.22);
    float band = exp(-abs(uv.y - pos) * 60.0);
    float trail = smoothstep(0.0, 0.12, uv.y - pos) * (1.0 - smoothstep(0.12, 0.3, uv.y - pos));
    // Sólo dentro del haz del holograma, no de lado a lado de la pantalla.
    float inBeam = smoothstep(0.42, 0.3, abs(uv.x - 0.5));
    light = uB.xyz * (band * (0.22 + 0.25 * uA.w) + trail * 0.04) * inBeam;
  }
  float peak = max(light.r, max(light.g, light.b));
  float alpha = clamp(peak * 1.25, 0.0, 1.0);
  fragColor = vec4(light * smoothstep(0.02, 0.06, peak), alpha * smoothstep(0.02, 0.06, peak));
}
""",
};
