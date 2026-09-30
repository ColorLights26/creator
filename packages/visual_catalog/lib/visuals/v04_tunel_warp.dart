// Túnel Hiperdimensional — Puerto fiel de Visuales Inmersivas v04.
// Túnel octagonal de 28 anillos con perspectiva relativista, vigas de torsión
// y singularidad focal pulsante reactiva a la música.
const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kRings = 28;
  static constexpr int kSides = 8;
  static constexpr float kMaxDepth = 1400.0f;
  static constexpr float kMinDepth = 60.0f;
  float warpTravel = 0.0f;
  float twistTime = 0.0f;
  float smoothBass = 0.0f;
  float smoothEnergy = 0.0f;
 public:
  void reset(uint32_t seed) override {
    (void)seed;
    warpTravel = 0.0f;
    twistTime = 0.0f;
    smoothBass = 0.0f;
    smoothEnergy = 0.0f;
  }
  void update(const Frame& f) override {
    float dt = float(f.delta);
    float targetEnergy = f.music.active ? f.music.energy : 0.0f;
    float targetBass = f.music.active ? f.music.bass : 0.0f;
    smoothBass += (targetBass - smoothBass) * float(1.0 - std::exp(-dt * 6.0));
    smoothEnergy += (targetEnergy - smoothEnergy) * float(1.0 - std::exp(-dt * 5.0));

    // En silencio reposa en un avance de túnel suave y contemplativo (~0.09f).
    // Con música acelera a velocidad hiperdimensional y torsión cuántica.
    float speedMult = 0.09f + smoothEnergy * 0.78f + smoothBass * 0.40f;
    warpTravel += dt * f.speed * speedMult;
    twistTime += dt * f.speed * (0.09f + smoothEnergy * 0.75f);
  }
  void render(const Frame& f, Canvas& c) const override {
    float w = f.width, h = f.height;
    Vec2 center{w * 0.5f, h * 0.5f};
    float minDim = std::min(w, h);

    // 1. Vacío cósmico con núcleo focal
    Paint bg = Paint::radial(center, minDim * 0.9f,
      {Color::argb(0xff140026), Color::argb(0xff07000f), Color::argb(0xff000000)},
      {0.0f, 0.45f, 1.0f});
    c.rect({0, 0, w, h}, bg);

    // Resplandor del núcleo focal
    float coreKick = (1.0f + smoothBass * 0.5f);
    Paint coreGlow = Paint::radial(center, 45.0f * coreKick,
      {{0.74f, 0.0f, 1.0f, std::clamp(0.48f * f.intensity, 0.0f, 1.0f)}, {0, 0, 0, 0}},
      {0.0f, 1.0f});
    coreGlow.blend = Blend::plus;
    c.circle(center, 45.0f * coreKick, coreGlow);

    float stepZ = (kMaxDepth - kMinDepth) / float(kRings);
    float animOffset = std::fmod(warpTravel * 0.25f, 1.0f);
    if (animOffset < 0.0f) animOffset += 1.0f;
    animOffset *= stepZ;

    // Almacenar vértices para las vigas longitudinales
    std::vector<std::array<Vec2, kSides>> ringVertices;
    ringVertices.reserve(kRings);

    // Dibujar anillos octogonales desde el fondo hacia el frente
    for (int i = kRings - 1; i >= 0; i--) {
      float z = kMinDepth + float(i) * stepZ - animOffset;
      if (z <= 12.0f) continue;

      float scale = 500.0f / z;
      float radius = 220.0f * scale * (minDim / 400.0f) * (1.0f + smoothBass * 0.12f);
      float twist = (1.0f - z / kMaxDepth) * 2.8f + twistTime * 0.8f;

      float normDepth = std::clamp(z / kMaxDepth, 0.0f, 1.0f);
      float alpha = std::clamp((1.0f - normDepth) * 0.88f * f.intensity, 0.0f, 1.0f);

      // Ciclo cromático entre cian {0, 1, 0.8} y violeta/magenta {0.74, 0, 1}
      float colorPhase = std::fmod(normDepth + warpTravel * 0.15f, 1.0f);
      if (colorPhase < 0.0f) colorPhase += 1.0f;
      Color ringCol{
        std::clamp(0.0f * (1.0f - colorPhase) + 0.74f * colorPhase, 0.0f, 1.0f),
        std::clamp(1.0f * (1.0f - colorPhase) + 0.0f * colorPhase, 0.0f, 1.0f),
        std::clamp(0.8f * (1.0f - colorPhase) + 1.0f * colorPhase, 0.0f, 1.0f),
        alpha
      };
      Paint rp; rp.blend = Blend::plus; rp.color = ringCol;
      rp.strokeWidth = std::clamp(scale * 2.2f, 1.0f, 3.8f);

      Path ringPath;
      std::array<Vec2, kSides> verts;
      for (int s = 0; s < kSides; s++) {
        float angle = (float(s) / float(kSides)) * 6.2831853f + twist;
        float vx = center.x + radius * std::cos(angle);
        float vy = center.y + radius * std::sin(angle);
        verts[s] = Vec2{vx, vy};
        if (s == 0) ringPath.moveTo(vx, vy);
        else ringPath.lineTo(vx, vy);
      }
      ringPath.close();
      c.path(ringPath, rp);

      ringVertices.push_back(verts);
    }

    // 2. Vigas longitudinales de torsión conectando anillos adyacentes
    if (ringVertices.size() >= 2) {
      Paint beamPaint; beamPaint.blend = Blend::plus;
      beamPaint.strokeWidth = 1.0f;

      for (size_t r = 0; r + 1 < ringVertices.size(); r += 2) {
        const auto& cur = ringVertices[r];
        const auto& nxt = ringVertices[r + 1];
        float beamAlpha = std::clamp((0.2f + float(r) / float(ringVertices.size()) * 0.5f) * f.intensity, 0.0f, 0.65f);
        beamPaint.color = {0.0f, 0.9f, 1.0f, beamAlpha};

        Path beams;
        for (int s = 0; s < kSides; s += 2) {
          beams.moveTo(cur[s].x, cur[s].y);
          beams.lineTo(nxt[s].x, nxt[s].y);
        }
        c.path(beams, beamPaint);
      }
    }

    // Singularidad central brillante
    Paint sing; sing.blend = Blend::plus;
    sing.color = {1.0f, 1.0f, 1.0f, std::clamp(0.95f * f.intensity, 0.0f, 1.0f)};
    c.circle(center, 3.6f * coreKick, sing);
  }
};
''';
