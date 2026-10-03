// Fuegos Artificiales Transparente — espectáculo pirotécnico sincronizado con la música.
// Versión overlay: mismo movimiento y reacción a la música sin fondo opaco.
// Cada golpe hace estallar una carcasa en el cielo: peonías esféricas,
// crisantemos con chispas que crepitan, sauces dorados que caen despacio y
// anillos. Las estrellas siguen una física de arrastre y gravedad y dejan
// estelas de chispas; el estallido ilumina el humo del cielo. En el drop
// llega un gran final con cuatro carcasas a la vez; sin golpes, el
// espectáculo sigue con lanzamientos regulares.
const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kShells = 8, kStars = 130;
  struct Shell { float x = 0, y = 0, power = 0, seed = 0; int type = 0, color = 0; double born = -100; };
  std::array<Shell, kShells> shells{};
  int next = 0, turn = 0;
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Las estrellas se describen por la edad de su carcasa: idéntico a 30 y 60 FPS.
  double clock = 0, nextAuto = 0.25, sinceFinale = 100;
  Random rng{47};

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  static float hash(float n) {
    float x = std::sin(n) * 43758.5453f;
    return x - std::floor(x);
  }

  static float lifeOf(int type) { return type == 2 ? 3.6f : (type == 1 ? 2.6f : 2.2f); }

  void burst(double born, float power) {
    Shell& s = shells[next];
    next = (next + 1) % kShells;
    s.x = 0.15f + 0.7f * rng.unit();
    s.y = 0.14f + 0.36f * rng.unit();
    s.power = power;
    s.seed = rng.unit() * 90.0f;
    float pick = rng.unit();
    s.type = pick < 0.4f ? 0 : (pick < 0.65f ? 1 : (pick < 0.85f ? 2 : 3));
    s.color = s.type == 2 ? 0 : (turn++ % 3);
    s.born = born;
  }

  // Posición de una estrella con arrastre y gravedad, en píxeles.
  void star(const Shell& sh, int i, float t, float w, float h, float s, float& x, float& y) const {
    float a = hash(sh.seed + float(i) * 1.731f) * 6.2831853f;
    float e = hash(sh.seed * 3.1f + float(i) * 2.377f);
    // Peonía: proyección de una esfera; anillo: todas en el borde, inclinado.
    float rf = sh.type == 3 ? 1.0f : std::sqrt(std::max(0.0f, 1.0f - (2.0f * e - 1.0f) * (2.0f * e - 1.0f)));
    float speed = s * (0.62f + 0.1f * hash(sh.seed + float(i) * 5.3f)) * sh.power;
    float k = sh.type == 2 ? 1.1f : 1.8f;
    float g = s * (sh.type == 2 ? 0.17f : 0.11f);
    float vx = std::cos(a) * rf * speed;
    float vy = std::sin(a) * rf * speed * (sh.type == 3 ? 0.45f : 1.0f);
    float ek = (1.0f - std::exp(-k * t)) / k;
    x = sh.x * w + vx * ek;
    y = sh.y * h + vy * ek + g / k * (t - ek);
  }

 public:
  void reset(uint32_t seed) override {
    rng = Random(seed);
    shells = {};
    next = turn = 0;
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    clock = 0;
    nextAuto = 0.25;
    sinceFinale = 100;
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
    clock += f.delta * f.speed;
    sinceFinale += f.delta;
    if (hit > kick + 0.2f) {
      if (hit > 0.75f && drive > 0.4f && sinceFinale > 6.0) {
        // Gran final: cuatro carcasas a la vez.
        for (int i = 0; i < 4; i++) burst(clock, 1.1f);
        sinceFinale = 0;
      } else {
        burst(clock, 0.75f + 0.4f * hit);
      }
      nextAuto = clock + 1.4;
    }
    // Sin golpes: una carcasa cada 1,6 s, en horarios fijos.
    while (clock >= nextAuto) {
      burst(nextAuto, 0.85f);
      nextAuto += 1.6;
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
  }

  void render(const Frame& f, Canvas& c) const override {
    float amp = f.intensity;
    float w = f.width, h = f.height, s = std::min(w, h);
    std::vector<float> u;
    u.reserve(52);
    u.insert(u.end(), {float(std::fmod(clock, 1000.0)), bass * amp, kick * amp, energy});
    u.insert(u.end(), {f.glow, spark * amp, flash * amp, 0.0f});
    for (int k = 0; k < kShells; k++) {
      const Shell& sh = shells[k];
      float age = float(clock - sh.born);
      float glow = sh.born < -50 ? 0.0f : std::exp(-age * 2.5f) * sh.power * std::clamp(age / 0.04f, 0.0f, 1.0f);
      u.insert(u.end(), {sh.x, sh.y, glow * amp, float(sh.color)});
    }
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("night_sky", {0, 0, w, h}, u);

    float px = s / 400.0f;
    for (int k = 0; k < kShells; k++) {
      const Shell& sh = shells[k];
      if (sh.born < -50) continue;
      float age = float(clock - sh.born);
      float life = lifeOf(sh.type);
      if (age < 0 || age > life) continue;
      float decay = sh.type == 2 ? std::exp(-age * 0.45f) : std::exp(-age * 0.85f);
      decay *= 1.0f - std::clamp((age - life * 0.8f) / (life * 0.2f), 0.0f, 1.0f);
      int trailN = sh.type == 2 ? 6 : 3;
      float gap = sh.type == 2 ? 0.09f : 0.05f;
      std::vector<Vec2> heads, trails;
      heads.reserve(kStars);
      trails.reserve(size_t(kStars * trailN));
      for (int i = 0; i < kStars; i++) {
        // Crisantemo: las estrellas crepitan, se apagan y encienden.
        if (sh.type == 1 && age > 0.6f && hash(float(i) * 3.7f + std::floor(age * 18.0f) + sh.seed) < 0.35f) continue;
        float x, y;
        star(sh, i, age, w, h, s, x, y);
        heads.push_back({x, y});
        for (int j = 1; j <= trailN; j++) {
          float tj = age - gap * float(j);
          if (tj <= 0) break;
          star(sh, i, tj, w, h, s, x, y);
          trails.push_back({x, y});
        }
      }
      const Color& base = f.colors[1 + sh.color];
      float gain = std::clamp(decay * (0.9f + 0.4f * bass + 0.4f * kick) * amp, 0.0f, 1.5f);
      if (!trails.empty()) {
        Paint trail;
        trail.blend = Blend::plus;
        trail.color = {base.r, base.g, base.b, std::clamp(0.5f * gain, 0.0f, 1.0f)};
        c.points(trails, (sh.type == 2 ? 1.8f : 1.5f) * px, trail);
      }
      if (heads.empty()) continue;
      Paint halo;
      halo.blend = Blend::plus;
      halo.color = {base.r, base.g, base.b, std::clamp(0.16f * gain * f.glow, 0.0f, 1.0f)};
      c.points(heads, 7.0f * px, halo);
      Paint head;
      head.blend = Blend::plus;
      float whiten = age < 0.25f ? 0.6f : 0.25f;
      head.color = {std::min(1.0f, base.r + (1.0f - base.r) * whiten), std::min(1.0f, base.g + (1.0f - base.g) * whiten),
                    std::min(1.0f, base.b + (1.0f - base.b) * whiten), std::clamp(0.95f * gain, 0.0f, 1.0f)};
      c.points(heads, (2.3f + 0.8f * spark * amp) * px, head);
    }
  }
};
''';

const shaderSources = <String, String>{
  'night_sky': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // reloj, graves, golpe, energía
uniform vec4 uB;   // glow, agudos, destello
uniform vec4 uS0;  // carcasas: posición (fracción de pantalla), brillo, color
uniform vec4 uS1;
uniform vec4 uS2;
uniform vec4 uS3;
uniform vec4 uS4;
uniform vec4 uS5;
uniform vec4 uS6;
uniform vec4 uS7;
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

vec3 shellColor(float k) {
  return k < 0.5 ? uC1 : (k < 1.5 ? uC2 : uC3);
}

// Resplandor de un estallido sobre el cielo.
vec3 flare(vec2 frag, vec4 S, float scale) {
  if (S.z < 0.003) return vec3(0.0);
  vec2 d = (frag - S.xy * uSize) / scale;
  return shellColor(S.w) * S.z * exp(-dot(d, d) * 9.0);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 uv = frag / uSize;
  vec3 light = vec3(0.0);
  light += flare(frag, uS0, scale);
  light += flare(frag, uS1, scale);
  light += flare(frag, uS2, scale);
  light += flare(frag, uS3, scale);
  light += flare(frag, uS4, scale);
  light += flare(frag, uS5, scale);
  light += flare(frag, uS6, scale);
  light += flare(frag, uS7, scale);
  // Cielo nocturno con humo que los estallidos iluminan.
  float smoke = noise(frag / scale * 3.0 + vec2(uA.x * 0.03, 0.0)) * 0.6 + noise(frag / scale * 7.0 - uA.x * 0.02) * 0.4;
  vec3 col = mix(uC0, uC0 * 2.5 + vec3(0.01, 0.01, 0.03), smoothstep(1.0, 0.0, uv.y) * 0.5);
  col += light * (0.18 + 0.5 * smoothstep(0.35, 0.8, smoke)) * uB.x;
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
