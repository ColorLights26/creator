// Espectro Sonoro Cósmico — Puerto fiel de Visuales Inmersivas v08.
// Analizador espectral circular con núcleo pulsante de graves,
// 72 barras radiales conectadas al espectro de audio y anillo de resonancia.
const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kBarCount = 72;
  float spectralTime = 0.0f;
  float smoothEnergy = 0.0f;
  float smoothBass = 0.0f;
 public:
  void reset(uint32_t seed) override {
    (void)seed;
    spectralTime = 0.0f;
    smoothEnergy = 0.0f;
    smoothBass = 0.0f;
  }
  void update(const Frame& f) override {
    float dt = float(f.delta);
    float targetEnergy = f.music.active ? f.music.energy : 0.0f;
    float targetBass = f.music.active ? f.music.bass : 0.0f;
    smoothEnergy += (targetEnergy - smoothEnergy) * float(1.0 - std::exp(-dt * 6.0));
    smoothBass += (targetBass - smoothBass) * float(1.0 - std::exp(-dt * 8.0));

    // En silencio reposa en un orbe tranquilo (~0.08f).
    // Con música la rotación y el pulso se acoplan a la señal.
    float audioDrive = 0.08f + smoothEnergy * 0.72f + smoothBass * 0.35f;
    spectralTime += dt * f.speed * audioDrive;
  }
  void render(const Frame& f, Canvas& c) const override {
    float w = f.width, h = f.height;
    float t = spectralTime;
    Vec2 center{w * 0.5f, h * 0.5f};
    float minDim = std::min(w, h);

    // 1. Fondo cósmico radial
    Paint bg = Paint::radial(center, minDim * 0.9f,
      {Color::argb(0xff130324), Color::argb(0xff06010d), Color::argb(0xff000000)},
      {0.0f, 0.45f, 1.0f});
    c.rect({0, 0, w, h}, bg);

    // 2. Núcleo central pulsante: en silencio está sereno (kick = 0)
    float kick = (f.music.active ? smoothBass * 1.5f : 0.0f) * f.intensity;
    float baseRadius = minDim * 0.12f * (1.0f + kick * 0.28f);

    // Resplandor del núcleo
    float glowAlpha = f.music.active ? (0.25f + smoothEnergy * 0.35f) : 0.15f;
    Paint coreGlow = Paint::radial(center, baseRadius * 1.6f,
      {{1.0f, 0.0f, 0.5f, std::clamp(glowAlpha * f.intensity, 0.0f, 1.0f)}, {0, 0, 0, 0}},
      {0.0f, 1.0f});
    coreGlow.blend = Blend::plus;
    c.circle(center, baseRadius * 1.6f, coreGlow);

    // Esfera interior del núcleo
    Paint coreSphere = Paint::radial(center, baseRadius * 0.85f,
      {Color{1.0f, 1.0f, 1.0f, 1.0f}, Color::argb(0xff00f0ff), Color::argb(0xff7000ff)},
      {0.0f, 0.4f, 1.0f});
    coreSphere.blend = Blend::plus;
    c.circle(center, baseRadius * 0.85f, coreSphere);

    // 3. Renderizar las 72 barras radiales
    const float angleStep = 6.2831853f / float(kBarCount);
    std::vector<Vec2> sparkCaps;
    sparkCaps.reserve(kBarCount);

    for (int i = 0; i < kBarCount; i++) {
      float angle = float(i) * angleStep - 3.14159265f * 0.5f;

      // Frecuencia normalizada (sub-graves simétricos y agudos laterales)
      float normFreq = std::abs((float(i) / (float(kBarCount) * 0.5f)) - 1.0f);
      int specIdx = std::clamp(int(normFreq * 30.0f), 0, 30);
      float realAudio = f.music.active ? f.music.spectrum[specIdx] : 0.0f;
      float smoothAudio = f.music.active ? f.music.smoothSpectrum[specIdx] : 0.0f;

      // En silencio las barras descansan en un anillo limpio sin brincar a lo loco
      float barVal = f.music.active ? std::max(realAudio * 1.8f, smoothAudio * 1.3f) : 0.015f;
      float barLength = minDim * (0.018f + barVal * 0.18f + kick * (1.0f - normFreq) * 0.12f);

      float cosA = std::cos(angle), sinA = std::sin(angle);
      float sx = center.x + baseRadius * cosA;
      float sy = center.y + baseRadius * sinA;
      float ex = center.x + (baseRadius + barLength) * cosA;
      float ey = center.y + (baseRadius + barLength) * sinA;

      // Color lerp: cian {0, 1, 0.88} a magenta {1, 0, 0.33}
      Color barCol{
        0.0f * (1.0f - normFreq) + 1.0f * normFreq,
        1.0f * (1.0f - normFreq) + 0.0f * normFreq,
        0.88f * (1.0f - normFreq) + 0.33f * normFreq,
        std::clamp(0.85f * f.intensity, 0.0f, 1.0f)
      };
      Paint bp; bp.blend = Blend::plus; bp.color = barCol;
      bp.strokeWidth = std::max(1.2f, minDim * 0.008f);
      bp.strokeCap = 1;

      Path barPath; barPath.moveTo(sx, sy); barPath.lineTo(ex, ey);
      c.path(barPath, bp);

      // Chispas en los picos de energía
      if (barLength > minDim * 0.14f) {
        float spx = center.x + (baseRadius + barLength + 4.0f) * cosA;
        float spy = center.y + (baseRadius + barLength + 4.0f) * sinA;
        sparkCaps.push_back({spx, spy});
      }
    }

    if (!sparkCaps.empty()) {
      Paint spk; spk.blend = Blend::plus;
      spk.color = {1.0f, 1.0f, 1.0f, std::clamp(0.95f * f.intensity, 0.0f, 1.0f)};
      c.points(sparkCaps, 2.0f, spk);
    }

    // 4. Anillo de resonancia exterior
    float ringRadius = baseRadius + minDim * 0.22f;
    Paint ringPaint; ringPaint.blend = Blend::plus;
    ringPaint.color = {0.0f, 1.0f, 0.88f, std::clamp(0.25f * f.intensity, 0.0f, 1.0f)};
    ringPaint.strokeWidth = 1.4f;
    c.circle(center, ringRadius, ringPaint);

    // 5. Partículas armónicas en órbita
    std::vector<Vec2> orbiters;
    orbiters.reserve(8);
    for (int p = 0; p < 8; p++) {
      float pAngle = t * (0.8f + float(p) * 0.2f) + float(p) * (3.14159265f / 4.0f);
      float radOffset = std::sin(pAngle * 3.0f) * 12.0f;
      float ox = center.x + (ringRadius + radOffset) * std::cos(pAngle);
      float oy = center.y + (ringRadius + radOffset) * std::sin(pAngle);
      orbiters.push_back({ox, oy});
    }
    Paint orbPaint; orbPaint.blend = Blend::plus;
    orbPaint.color = {1.0f, 0.0f, 0.63f, std::clamp(0.85f * f.intensity, 0.0f, 1.0f)};
    c.points(orbiters, 2.8f, orbPaint);
  }
};
''';
