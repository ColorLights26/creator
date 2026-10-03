// Haces de Estadio Transparente — iluminación de concierto con cabezas móviles.
// Versión overlay: mismo movimiento y reacción a la música sin fondo opaco.
// Dos filas de focos (arriba y abajo) lanzan conos anchos de luz que atraviesan
// el humo, con dibujos que giran dentro. La coreografía (abanico, convergencia,
// cruce, barrido u ola) y el color de cada fila cambian cada compás; cada golpe
// pulsa el brillo y los cegadores, los graves ensanchan los conos y los agudos
// hacen girar los dibujos. Pide 60 FPS para que los haces barran con fluidez.
const nativeSource = r'''
class Visual final : public Scene {
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0, lows = 0, highs = 0;
  float phase = 0, haze = 0, goboTop = 0, goboBottom = 0, blinder = 0;
  float hueTop = 0, hueBottom = 0, hueTopGoal = 0, hueBottomGoal = 0;
  std::array<float, 12> angle{}, power{};
  int mode = 0, beats = 0;
  Random rng{21};

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  // Desvío de cada foco respecto a la vertical según la figura actual.
  float offset(int i, bool top) const {
    float x = (float(i) - 2.5f) / 2.5f;
    float sway = std::sin(phase * 0.7f + float(i) * 1.1f) * 0.06f;
    float o = 0;
    switch (mode) {
      case 0: o = x * 0.55f; break;                                   // abanico
      case 1: o = -x * 0.42f; break;                                  // convergencia
      case 2: o = (i % 2 == 0 ? 0.62f : -0.62f); break;               // cruce en X
      case 3: o = std::sin(phase * 1.2f) * 0.6f; break;               // barrido paralelo
      default: o = std::sin(phase * 2.0f + float(i) * 0.9f) * 0.45f;  // ola
    }
    return (top ? o : -o) + sway;
  }

 public:
  void reset(uint32_t seed) override {
    rng = Random(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = lows = highs = 0;
    phase = rng.unit() * 10.0f;
    haze = rng.unit() * 10.0f;
    goboTop = goboBottom = blinder = 0;
    hueTop = hueTopGoal = 0.0f;
    hueBottom = hueBottomGoal = 1.0f / 3.0f;
    mode = int(rng.unit() * 5.0f) % 5;
    beats = 0;
    for (int i = 0; i < 12; i++) {
      bool top = i < 6;
      angle[i] = (top ? 3.14159265f : 0.0f) + (top ? -1.0f : 1.0f) * offset(i % 6, top);
      power[i] = 0;
    }
  }

  void update(const Frame& f) override {
    float dt = float(f.delta);
    const Music& m = f.music;
    bass = follow(bass, m.bass, 22.0f, 4.5f, dt);
    body = follow(body, m.body, 12.0f, 3.0f, dt);
    spark = follow(spark, m.spark, 30.0f, 7.0f, dt);
    energy = follow(energy, m.energy, 6.0f, 1.8f, dt);
    drive = follow(drive, m.active ? std::pow(std::clamp(m.energy, 0.0f, 1.0f), 0.8f) : 0.0f, 3.0f, 0.7f, dt);
    float lo = 0, hi = 0;
    for (int i = 0; i < 10; i++) lo = std::max(lo, m.smoothSpectrum[i]);
    for (int i = 18; i < 31; i++) hi = std::max(hi, m.smoothSpectrum[i]);
    lows = follow(lows, lo, 20.0f, 4.0f, dt);
    highs = follow(highs, hi, 20.0f, 4.0f, dt);

    float hit = 0, fl = 0;
    for (const auto& e : m.events[0]) hit = std::max(hit, e.strength);
    for (const auto& e : m.events[2]) hit = std::max(hit, e.strength * 0.85f);
    for (const auto& e : m.events[3]) fl = std::max(fl, e.strength);
    float onset = std::clamp((m.bass - slowBass - 0.15f) * 2.5f, 0.0f, 1.0f);
    slowBass = follow(slowBass, m.bass, 3.0f, 3.0f, dt);
    hit = std::min(std::max(hit, onset), 1.0f);
    if (hit > kick + 0.2f) {
      // Cada golpe es un pulso; la figura y el color cambian cada compás.
      beats++;
      if (beats % 4 == 0) {
        mode = (mode + 1 + int(rng.unit() * 3.0f)) % 5;
        hueTopGoal += 1.0f / 3.0f;
        hueBottomGoal -= 1.0f / 3.0f;
        blinder = std::max(blinder, hit);
      } else {
        blinder = std::max(blinder, hit * 0.35f);
      }
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 9.0f), std::min(fl, 1.0f));
    blinder *= std::exp(-dt * 7.0f);

    phase += dt * f.speed * (0.22f + 0.7f * drive + 0.15f * kick);
    haze += dt * f.speed * (0.15f + 0.3f * drive);
    goboTop += dt * f.speed * (0.5f + 3.0f * spark + 1.0f * highs);
    goboBottom -= dt * f.speed * (0.4f + 2.5f * spark + 1.0f * lows);
    hueTop += (hueTopGoal - hueTop) * (1.0f - std::exp(-dt * 6.0f));
    hueBottom += (hueBottomGoal - hueBottom) * (1.0f - std::exp(-dt * 6.0f));

    // Los focos van hacia su posición de forma rápida pero continua.
    for (int i = 0; i < 12; i++) {
      bool top = i < 6;
      int k = i % 6;
      float goal = (top ? 3.14159265f : 0.0f) + (top ? -1.0f : 1.0f) * offset(k, top);
      angle[i] += (goal - angle[i]) * (1.0f - std::exp(-dt * 4.5f));
      // En silencio sólo la mitad de los focos, tenues; con música, todos.
      float idle = (k % 2 == 0) ? 0.32f : 0.0f;
      float music = 0.35f + 0.75f * energy + 0.6f * kick + (top ? 0.4f * highs : 0.5f * lows);
      float goalPower = m.active ? std::max(idle, music) : idle;
      power[i] = follow(power[i], goalPower, 14.0f, 3.0f, dt);
    }
  }

  void render(const Frame& f, Canvas& c) const override {
    float amp = f.intensity;
    float width = 0.058f + 0.04f * bass * amp + 0.03f * kick * amp;
    std::vector<float> u;
    u.reserve(72);
    u.insert(u.end(), {phase, bass * amp, kick * amp, energy});
    for (int i = 0; i < 12; i++)
      u.insert(u.end(), {angle[i], width, std::min(power[i] * amp, 2.0f), i < 6 ? goboTop : goboBottom});
    u.insert(u.end(), {blinder * amp, flash, f.glow, haze});
    u.insert(u.end(), {hueTop, hueBottom, spark * amp, 0.0f});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("beams", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'beams': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;     // tiempo, graves, golpe, energía
uniform vec4 uT0;    // focos de arriba: ángulo, apertura, potencia, giro del dibujo
uniform vec4 uT1;
uniform vec4 uT2;
uniform vec4 uT3;
uniform vec4 uT4;
uniform vec4 uT5;
uniform vec4 uB0;    // focos de abajo
uniform vec4 uB1;
uniform vec4 uB2;
uniform vec4 uB3;
uniform vec4 uB4;
uniform vec4 uB5;
uniform vec4 uM;     // cegadores, destello, glow, reloj del humo
uniform vec4 uH;     // tono de la fila superior, de la inferior, agudos
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
  for (int i = 0; i < 3; i++) {
    s += a * noise(p);
    p = mat2(1.6, 1.2, -1.2, 1.6) * p;
    a *= 0.5;
  }
  return s / 0.875;
}

vec3 cycle(float x) {
  float f = fract(x) * 3.0;
  vec3 a = f < 1.0 ? uC1 : (f < 2.0 ? uC2 : uC3);
  vec3 b = f < 1.0 ? uC2 : (f < 2.0 ? uC3 : uC1);
  return mix(a, b, smoothstep(0.0, 1.0, fract(f)));
}

// Cono de luz de un foco en `o`: B = (ángulo, apertura, potencia, giro).
vec3 beam(vec2 p, vec2 o, vec4 B, vec3 col, float haze) {
  if (B.z < 0.01) return vec3(0.0);
  vec2 v = p - o;
  float r = length(v);
  float a = atan(v.x, v.y) - B.x;
  a -= 6.2831853 * floor((a + 3.14159265) / 6.2831853);
  // Haces más estrechos que en el fondo: dejan huecos transparentes entre ellos.
  float u = a / (B.y * 0.6);
  float falloff = exp(-r * 0.55);
  float lens = 0.0007 / (r * r + 0.0007);
  vec3 lensCol = mix(col, vec3(1.0), 0.4) * lens * B.z;
  float au = abs(u);
  if (au > 2.2) return lensCol;
  float edge = 1.0 - smoothstep(0.62, 1.0, au);
  // Dibujo del gobo: vetas que giran dentro del haz.
  float gobo = 0.5 + 0.5 * smoothstep(-0.3, 0.7, sin(u * 7.0 + B.w));
  float core = exp(-u * u * 2.5);
  float body = edge * (0.35 + 0.65 * core) * mix(0.3, 1.0, gobo) * haze;
  return col * body * 0.5 * falloff * B.z + lensCol;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  p.y = -p.y;
  vec2 hs = 0.5 * uSize / scale;
  float kick = uA.z;

  float smoke = fbm(p * 1.6 + vec2(uM.w * 0.12, -uM.w * 0.3));
  float haze = 0.22 + 1.0 * smoothstep(0.3, 0.85, smoke);
  vec3 topCol = cycle(uH.x);
  vec3 bottomCol = cycle(uH.y);

  float yt = hs.y + 0.02;
  float yb = -hs.y - 0.02;
  float sx = hs.x * 0.85;
  vec3 light = vec3(0.0);
  light += beam(p, vec2(-sx, yt), uT0, topCol, haze);
  light += beam(p, vec2(-sx * 0.6, yt), uT1, topCol, haze);
  light += beam(p, vec2(-sx * 0.2, yt), uT2, topCol, haze);
  light += beam(p, vec2(sx * 0.2, yt), uT3, topCol, haze);
  light += beam(p, vec2(sx * 0.6, yt), uT4, topCol, haze);
  light += beam(p, vec2(sx, yt), uT5, topCol, haze);
  light += beam(p, vec2(-sx, yb), uB0, bottomCol, haze);
  light += beam(p, vec2(-sx * 0.6, yb), uB1, bottomCol, haze);
  light += beam(p, vec2(-sx * 0.2, yb), uB2, bottomCol, haze);
  light += beam(p, vec2(sx * 0.2, yb), uB3, bottomCol, haze);
  light += beam(p, vec2(sx * 0.6, yb), uB4, bottomCol, haze);
  light += beam(p, vec2(sx, yb), uB5, bottomCol, haze);

  vec3 col = uC0 + light * uM.z;
  col += light * 0.03 * smoke;
  // Cegadores: filas de luz blanca arriba y abajo que estallan con el golpe.
  float edgeDist = min(abs(p.y - yt), abs(p.y - yb));
  col += vec3(1.0, 0.96, 0.9) * uM.x * 0.6 * exp(-edgeDist * 10.0);

  col *= 1.0 - 0.25 * smoothstep(0.7, 1.5, length(p * vec2(0.9, 0.6)));
  col = clamp((col * (2.51 * col + 0.03)) / (col * (2.43 * col + 0.59) + 0.14), 0.0, 1.0);
  col = pow(col, vec3(0.4545));
  // Fondo transparente: el color va premultiplicado y la opacidad sale del
  // brillo, así la luz se compone sobre lo que haya debajo.
  col = clamp(col, 0.0, 1.0);
  // La luz muy tenue se vuelve transparente del todo: sin velo sobre la app.
  float veilPeak = max(col.r, max(col.g, col.b));
  float clearCut = smoothstep(0.08, 0.2, veilPeak);
  col *= clearCut;
  float alpha = clamp(veilPeak * 1.25, 0.0, 1.0) * clearCut;
  fragColor = vec4(col, alpha);
}
""",
};
