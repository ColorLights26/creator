// Osciloscopio Transparente — figuras vectoriales dibujadas por un haz de luz.
// Versión overlay: mismo movimiento y reacción a la música sin fondo opaco.
// Como en la música de osciloscopio, un haz verde dibuja una figura cerrada:
// Lissajous, rosas, espirógrafos y un nudo toroidal que gira en 3D. Cada
// cuatro golpes la figura se transforma en la siguiente (o cada seis segundos
// sin música); las bandas del espectro la deforman, cada golpe la hace saltar
// y una copia tenue detrás imita la persistencia del fósforo.
// Copias repite la figura girada alrededor del centro como un caleidoscopio,
// Rotación la hace girar sobre sí misma y Persistencia alarga la estela del
// fósforo. Pulso elige qué más hace la música: en Golpes cada golpe hace
// que la figura salte hacia arriba y crezca, el haz engorda y brilla y un
// resplandor verde la envuelve; en Graves la figura respira con una
// ondulación lenta, crece, su halo se ensancha y el resplandor late; en
// Agudos el haz tiembla con un rizo fino, brilla más y suelta chispas.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // FORMA: copias de la figura giradas alrededor del centro.
  CreatorModifier.steps('copias', 'Copias', min: 1, max: 6, value: 1),
  // MOVIMIENTO: la figura gira sobre sí misma, como una órbita.
  CreatorModifier.slider('giro', 'Rotación', min: 0, max: 1, value: 0),
  // ATMÓSFERA: cuántas copias tenues deja el fósforo detrás del haz.
  CreatorModifier.slider('fosforo', 'Persistencia', min: 0, max: 6, value: 1),
  // MÚSICA: qué parte del haz reacciona.
  CreatorModifier.choice('pulso', 'Pulso', options: ['Golpes', 'Graves', 'Agudos']),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Mandala', {
    'copias': 5,
    'giro': .5,
    'fosforo': 3,
    'pulso': 'Graves',
  }),
  CreatorVariation('Fósforo Vivo', {
    'fosforo': 5,
    'pulso': 'Agudos',
    'speed': 1.3,
  }),
];

const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kSamples = 520;
  static constexpr int kShapes = 6;
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  std::array<float, 6> bands{};
  // Fase en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double phase = 0, sinceShape = 0;
  // Giro acumulado de Rotación (cero si no gira).
  double spin = 0;
  // Reloj de las chispas de los agudos.
  double shimmer = 0;
  int shapeA = 0, shapeB = 0, beats = 0;
  float morph = 1, punch = 0, punchVel = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }
  static float hashU(uint32_t x) {
    x ^= x >> 16; x *= 0x7feb352dU; x ^= x >> 15; x *= 0x846ca68bU; x ^= x >> 16;
    return float(x & 0xffffffu) / 16777216.0f;
  }

  // Figura s evaluada en tau (0..2π) y fase t; devuelve x, y en -1..1.
  static void shape(int s, float tau, float t, float& x, float& y) {
    switch (s) {
      case 0: x = std::sin(3.0f * tau + t * 0.6f); y = std::sin(2.0f * tau); break;
      case 1: {
        float r = std::cos(5.0f * tau + t * 0.2f);
        x = r * std::cos(tau);
        y = r * std::sin(tau);
        break;
      }
      case 2: {
        // Espirógrafo (epitrocoide) cerrado en tres vueltas.
        float a = tau * 3.0f;
        x = (std::cos(a) * 0.6f + 0.4f * std::cos(a * 5.0f / 3.0f + t * 0.4f));
        y = (std::sin(a) * 0.6f - 0.4f * std::sin(a * 5.0f / 3.0f + t * 0.4f));
        break;
      }
      case 3: {
        // Nudo toroidal (2, 3) que gira en 3D.
        float r = 0.55f + 0.3f * std::cos(3.0f * tau);
        float px = r * std::cos(2.0f * tau), py = r * std::sin(2.0f * tau), pz = 0.3f * std::sin(3.0f * tau);
        float ca = std::cos(t * 0.5f), sa = std::sin(t * 0.5f);
        float ry = py * std::cos(0.6f) - pz * std::sin(0.6f);
        x = px * ca + pz * sa;
        y = ry;
        break;
      }
      case 4: x = std::sin(5.0f * tau + t * 0.45f); y = std::sin(4.0f * tau); break;
      default: {
        float r = 0.5f + 0.45f * std::sin(7.0f * tau + t * 0.3f);
        x = r * std::cos(tau);
        y = r * std::sin(tau);
        break;
      }
    }
  }

  void next() {
    shapeA = shapeB;
    shapeB = (shapeB + 1) % kShapes;
    morph = 0;
    sinceShape = 0;
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    bands.fill(0);
    phase = rng.unit() * 20.0;
    sinceShape = 0;
    shapeA = shapeB = int(rng.unit() * float(kShapes)) % kShapes;
    beats = 0;
    morph = 1;
    punch = punchVel = 0;
    spin = 0;
    shimmer = 0;
  }

  void update(const Frame& f) override {
    auto mods = modifiers(f);
    float dt = float(f.delta);
    const Music& m = f.music;
    bass = follow(bass, m.bass, 22.0f, 4.5f, dt);
    body = follow(body, m.body, 12.0f, 3.0f, dt);
    spark = follow(spark, m.spark, 30.0f, 7.0f, dt);
    energy = follow(energy, m.energy, 6.0f, 1.8f, dt);
    drive = follow(drive, m.active ? std::pow(std::clamp(m.energy, 0.0f, 1.0f), 0.8f) : 0.0f, 3.0f, 0.7f, dt);
    for (int i = 0; i < 6; i++) {
      float v = 0;
      for (int k = i * 5; k < i * 5 + 5 && k < 31; k++) v = std::max(v, m.smoothSpectrum[k]);
      bands[size_t(i)] = follow(bands[size_t(i)], v, 25.0f, 5.0f, dt);
    }

    float hit = 0, fl = 0;
    for (const auto& e : m.events[0]) hit = std::max(hit, e.strength);
    for (const auto& e : m.events[2]) hit = std::max(hit, e.strength * 0.85f);
    for (const auto& e : m.events[3]) fl = std::max(fl, e.strength);
    float onset = std::clamp((m.bass - slowBass - 0.15f) * 2.5f, 0.0f, 1.0f);
    slowBass = follow(slowBass, m.bass, 3.0f, 3.0f, dt);
    hit = std::min(std::max(hit, onset), 1.0f);
    if (hit > kick + 0.2f) {
      beats++;
      punchVel += 2.2f * hit;
      if (beats % 4 == 0) next();
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    punchVel += (-punch * 50.0f - punchVel * 8.0f) * dt;
    punch += punchVel * dt;
    morph = std::min(1.0f, morph + dt * 1.3f);
    sinceShape += f.delta;
    if (!m.active && sinceShape > 6.0) next();
    phase += f.delta * f.speed * (0.8 + 1.6 * drive);
    spin += f.delta * f.speed * double(mods.giro) * 0.6;
    shimmer += f.delta;
  }

  void render(const Frame& f, Canvas& c) const override {
    auto gl = glide(f);
    float amp = f.intensity;
    // Pulso: cada opción mueve algo distinto; sin música todo vale cero.
    const float kickP = std::min(kick * amp, 1.0f) * gl.pulso.weight(0);
    const float bassP = std::min(bass * amp, 1.0f) * gl.pulso.weight(1);
    const float sparkP = std::min(spark * amp, 1.0f) * gl.pulso.weight(2);
    float w = f.width, h = f.height, s = std::min(w, h);
    std::vector<float> u;
    u.reserve(20);
    u.insert(u.end(), {bass * amp, kick * amp, energy, f.glow});
    u.insert(u.end(), {spark * amp, flash * amp, float(std::fmod(phase, 1000.0)), 0.0f});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("crt_screen", {0, 0, w, h}, u);

    float e = morph * morph * (3.0f - 2.0f * morph);
    float R = s * 0.45f * (1.0f + 0.12f * std::max(-0.3f, punch) * amp);
    // Golpes: la figura salta hacia arriba y crece; Graves: respira.
    const float jump = std::max(-0.3f, punch) * std::min(amp, 1.0f) * gl.pulso.weight(0);
    R *= 1.0f + 1.3f * jump + 0.12f * bassP;
    float cx = w * 0.5f, cy = h * 0.5f;
    cy -= s * 0.45f * jump;
    const bool shake = bassP > 0.002f || sparkP > 0.002f;
    // Agudos: chispas sueltas a lo largo del haz, 14 veces por segundo.
    std::vector<Vec2> glints;
    const uint32_t tick = uint32_t(std::fmod(shimmer, 100000.0) * 14.0);
    const float chance = 0.12f * sparkP;
    auto trace = [&](float t, float angle, Path& path, std::vector<Vec2>* sparks, uint32_t salt) {
      const float ca = std::cos(angle), sa = std::sin(angle);
      for (int i = 0; i <= kSamples; i++) {
        float tau = 6.2831853f * float(i) / float(kSamples);
        float ax, ay, bx, by;
        shape(shapeA, tau, t, ax, ay);
        shape(shapeB, tau, t, bx, by);
        float x = ax + (bx - ax) * e, y = ay + (by - ay) * e;
        // El espectro deforma la figura con ondulaciones de distinta frecuencia.
        float wob = 1.0f + amp * (0.10f * bands[0] * std::sin(tau * 2.0f + t) + 0.07f * bands[2] * std::sin(tau * 9.0f - t * 1.7f) +
                                  0.05f * bands[4] * std::sin(tau * 23.0f + t * 2.3f));
        // Graves: ondulación lenta que respira; Agudos: rizo fino que tiembla.
        if (shake) wob += 0.1f * bassP * std::sin(tau * 3.0f + t * 0.7f) + 0.05f * sparkP * std::sin(tau * 47.0f + t * 9.0f);
        // Copias y Rotación: la figura girada alrededor del centro.
        if (angle != 0.0f) {
          const float rx = x * ca - y * sa;
          y = x * sa + y * ca;
          x = rx;
        }
        float X = cx + x * R * wob, Y = cy + y * R * wob;
        if (i == 0) path.moveTo(X, Y); else path.lineTo(X, Y);
        if (sparks && hashU(uint32_t(i) * 2654435761u + tick * 40503u + salt) < chance) sparks->push_back({X, Y});
      }
    };
    float t = float(std::fmod(phase, 6283.0));
    float px = s / 400.0f;
    float gain = std::clamp((0.85f + 0.5f * bass + 0.6f * kick) * amp, 0.0f, 1.6f);
    const Color& green = f.colors[1];
    const Color& light = f.colors[2];
    const Color& white = f.colors[3];
    Paint ghostPaint;
    ghostPaint.blend = Blend::plus;
    ghostPaint.strokeWidth = 2.0f * px;
    ghostPaint.strokeJoin = 1;
    // Copias: la figura repetida alrededor del centro; la última aparece poco a poco.
    const float copies = std::clamp(gl.copias, 1.0f, 6.0f);
    const int nCopies = int(std::ceil(copies - 1e-4f));
    // Persistencia: copias tenues que el fósforo deja detrás del haz.
    const float persist = std::clamp(gl.fosforo, 0.0f, 6.0f);
    const int nGhosts = int(std::ceil(persist - 1e-4f));
    const float rot = float(std::fmod(spin, 6.283185307179586));
    const float lagTurn = 0.75f * std::clamp(gl.giro, 0.0f, 1.0f);
    // Resplandor local alrededor de la figura: Golpes lo enciende y Graves lo
    // hace latir.
    const float aura = std::clamp((0.3f * kickP + 0.2f * bassP) * f.glow, 0.0f, 0.6f);
    if (aura > 0.002f) {
      Paint ap = Paint::radial({cx, cy}, R * 1.15f, {green.opacity(aura), green.opacity(aura * 0.35f), green.opacity(0.0f)}, {0.0f, 0.6f, 1.0f});
      ap.blend = Blend::plus;
      c.circle({cx, cy}, R * 1.15f, ap);
    }
    if (sparkP > 0.002f) glints.reserve(size_t(nCopies) * 160);
    for (int k = 0; k < nCopies; k++) {
      const float share = std::min(1.0f, copies - float(k));
      const float angle = rot + 6.2831853f * float(k) / copies;
      float fall = 1.0f;
      for (int j = 1; j <= nGhosts; j++) {
        const float lag = 0.12f + 0.16f * float(j - 1);
        Path ghost;
        trace(t - lag, angle - lag * lagTurn, ghost, nullptr, 0u);
        const float wj = std::min(1.0f, persist - float(j - 1));
        ghostPaint.color = {green.r, green.g, green.b, std::clamp(0.18f * gain * wj * fall * share, 0.0f, 1.0f)};
        c.path(ghost, ghostPaint);
        fall *= 0.72f;
      }
      Path beam;
      trace(t, angle, beam, sparkP > 0.002f ? &glints : nullptr, uint32_t(k) * 977u);
      Paint glow = ghostPaint;
      glow.strokeWidth = 12.0f * px * (1.0f + 0.8f * bassP + 0.6f * kickP);
      glow.color = {green.r, green.g, green.b, std::clamp(0.16f * gain * f.glow * (1.0f + 1.0f * kickP + 0.9f * bassP) * share, 0.0f, 1.0f)};
      c.path(beam, glow);
      Paint mid = ghostPaint;
      // Golpes: el haz engorda un instante.
      mid.strokeWidth = 3.6f * px * (1.0f + 1.4f * kickP + 0.6f * bassP);
      mid.color = {green.r, green.g, green.b, std::clamp(0.75f * gain * (1.0f + 0.6f * kickP) * share, 0.0f, 1.0f)};
      c.path(beam, mid);
      Paint core = ghostPaint;
      core.strokeWidth = 1.2f * px * (1.0f + 1.0f * sparkP + 0.5f * kickP);
      // Agudos: el núcleo del haz brilla más y tira hacia el tono más claro.
      const float hot = 0.6f * sparkP;
      core.color = {light.r + (white.r - light.r) * hot, light.g + (white.g - light.g) * hot, light.b + (white.b - light.b) * hot,
                    std::clamp(0.8f * gain * (1.0f + 0.8f * sparkP + 0.5f * kickP) * share, 0.0f, 1.0f)};
      c.path(beam, core);
    }
    if (!glints.empty()) {
      Paint gp;
      gp.blend = Blend::plus;
      gp.color = {white.r, white.g, white.b, std::clamp(0.9f * sparkP, 0.0f, 0.95f)};
      c.points(glints, 2.6f * px, gp);
    }
  }
};
''';

const shaderSources = <String, String>{
  'crt_screen': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // graves, golpe, energía, glow
uniform vec4 uB;   // agudos, destello, fase
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
  // Pantalla de tubo: retícula tenue, brillo central y líneas de barrido.
  vec2 g = abs(fract(p * 8.0 + 0.5) - 0.5) * scale / 8.0;
  float grid = (1.0 - smoothstep(0.0, 1.2, min(g.x, g.y))) * 0.05;
  float axes = (1.0 - smoothstep(0.0, 1.5, min(abs(p.x), abs(p.y)) * scale)) * 0.08;
  vec3 col = uC0 + uC1 * (grid + axes) * (0.6 + 0.4 * uA.w);
  col += uC1 * exp(-dot(p, p) * 3.0) * (0.03 + 0.04 * uA.x + 0.1 * uA.y) * uA.w;
  col *= 0.92 + 0.08 * sin(frag.y * 1.6);
  col *= 1.0 - 0.5 * smoothstep(0.45, 1.3, length(p * vec2(0.9, 0.65)));
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
