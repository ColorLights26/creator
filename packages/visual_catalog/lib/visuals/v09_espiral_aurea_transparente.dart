// Espiral Áurea Sagrada Transparente — Puerto fiel de Visuales Inmersivas v09.
// Versión overlay: mismo movimiento y reacción a la música sin fondo opaco.
// Distribución de filotaxis áurea de 750 nodos con ángulo de divergencia de 137.5°,
// ciclo cromático HSV de Fibonacci y núcleo de singularidad.
const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kNodeCount = 750;
  static constexpr float kGoldenAngle = 2.39996323f; // ~137.507764 grados
  float spiralAngle = 0.0f;
  float colorTime = 0.0f;
  float smoothBass = 0.0f;
  float smoothEnergy = 0.0f;

  static Color hsvToRgb(float h, float s, float v, float a) {
    float c = v * s;
    float x = c * (1.0f - std::abs(std::fmod(h / 60.0f, 2.0f) - 1.0f));
    float m = v - c;
    float r = 0, g = 0, b = 0;
    if (h < 60.0f) { r = c; g = x; b = 0; }
    else if (h < 120.0f) { r = x; g = c; b = 0; }
    else if (h < 180.0f) { r = 0; g = c; b = x; }
    else if (h < 240.0f) { r = 0; g = x; b = c; }
    else if (h < 300.0f) { r = x; g = 0; b = c; }
    else { r = c; g = 0; b = x; }
    return Color{
      std::clamp(r + m, 0.0f, 1.0f),
      std::clamp(g + m, 0.0f, 1.0f),
      std::clamp(b + m, 0.0f, 1.0f),
      std::clamp(a, 0.0f, 1.0f)
    };
  }

 public:
  void reset(uint32_t seed) override {
    (void)seed;
    spiralAngle = 0.0f;
    colorTime = 0.0f;
    smoothBass = 0.0f;
    smoothEnergy = 0.0f;
  }
  void update(const Frame& f) override {
    float dt = float(f.delta);
    float targetEnergy = f.music.active ? f.music.energy : 0.0f;
    float targetBass = f.music.active ? f.music.bass : 0.0f;
    smoothBass += (targetBass - smoothBass) * float(1.0 - std::exp(-dt * 6.0));
    smoothEnergy += (targetEnergy - smoothEnergy) * float(1.0 - std::exp(-dt * 5.0));

    // En silencio reposa en un giro áureo meditativo (~0.05f).
    // Con música la espiral acelera y desata ondas cromáticas al ritmo.
    float rate = 0.05f + smoothEnergy * 0.35f + smoothBass * 0.20f;
    spiralAngle += dt * f.speed * rate;
    colorTime += dt * f.speed * (0.08f + smoothEnergy * 0.72f);
  }
  void render(const Frame& f, Canvas& c) const override {
    float w = f.width, h = f.height;
    Vec2 center{w * 0.5f, h * 0.5f};
    float minDim = std::min(w, h);
    float maxDim = std::max(w, h);

    // 1. Sin fondo: el overlay deja ver lo que hay detrás.

    // Resplandor de la singularidad central
    float bassBreath = 1.0f + smoothBass * 0.32f;
    Paint singGlow = Paint::radial(center, 40.0f * bassBreath,
      {{0.0f, 1.0f, 0.84f, std::clamp(0.40f * f.intensity, 0.0f, 1.0f)}, {0, 0, 0, 0}},
      {0.0f, 1.0f});
    singGlow.blend = Blend::plus;
    c.circle(center, 40.0f * bassBreath, singGlow);

    // 2. Nodos de la filotaxis áurea
    float cConst = (minDim * 0.021f) * bassBreath;
    float maxRadius = maxDim * 0.72f;

    for (int n = 1; n < kNodeCount; n++) {
      float fn = float(n);
      float theta = fn * kGoldenAngle + spiralAngle;
      float r = cConst * std::sqrt(fn);
      if (r > maxRadius) break;

      float px = center.x + r * std::cos(theta);
      float py = center.y + r * std::sin(theta);

      float hue = std::fmod(fn * 0.45f + colorTime * 25.0f, 360.0f);
      if (hue < 0.0f) hue += 360.0f;
      float alpha = std::clamp((0.40f + (fn / float(kNodeCount)) * 0.60f) * f.intensity, 0.0f, 1.0f);

      Color nodeCol = hsvToRgb(hue, 0.85f, 1.0f, alpha);
      Paint np; np.blend = Blend::plus; np.color = nodeCol;
      float nodeRad = (1.4f + std::sqrt(fn / float(kNodeCount)) * 2.6f) * (minDim / 400.0f);

      c.circle({px, py}, std::max(0.6f, nodeRad), np);
    }

    // 3. Singularidad blanca en el origen
    Paint singCenter; singCenter.blend = Blend::plus;
    singCenter.color = {1.0f, 1.0f, 1.0f, std::clamp(0.95f * f.intensity, 0.0f, 1.0f)};
    c.circle(center, 3.5f, singCenter);
  }
};
''';
