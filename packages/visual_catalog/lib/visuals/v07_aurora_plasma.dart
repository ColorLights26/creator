// Aurora Boreal de Plasma — Puerto fiel de Visuales Inmersivas v07.
// Cortinas de plasma ionizado con multi-armónicos, filamentos centrales,
// estrellas centelleantes y silueta montañosa sobre noche polar.
const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kRibbons = 5;
  static constexpr int kSteps = 24;
  struct Star { float x, y, phase; };
  std::vector<Star> stars;
  float auroraTime = 0.0f;
  float smoothBass = 0.0f;
  float smoothEnergy = 0.0f;
 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    stars.clear(); stars.reserve(70);
    auroraTime = 0.0f;
    smoothBass = 0.0f;
    smoothEnergy = 0.0f;
    for (int i = 0; i < 70; i++) {
      stars.push_back({rng.unit(), rng.unit() * 0.72f, rng.unit() * 6.2831853f});
    }
  }
  void update(const Frame& f) override {
    float dt = float(f.delta);
    float targetEnergy = f.music.active ? f.music.energy : 0.0f;
    float targetBass = f.music.active ? f.music.bass : 0.0f;
    smoothBass += (targetBass - smoothBass) * float(1.0 - std::exp(-dt * 5.0));
    smoothEnergy += (targetEnergy - smoothEnergy) * float(1.0 - std::exp(-dt * 5.0));

    // En silencio reposa en un oleaje majestuoso de noche polar (~0.12f).
    // Con música acelera la danza de viento solar ionizado y pulsa la amplitud.
    float audioDrive = 0.12f + smoothEnergy * 0.75f + smoothBass * 0.35f;
    auroraTime += dt * f.speed * audioDrive;
  }
  void render(const Frame& f, Canvas& c) const override {
    float w = f.width, h = f.height;
    float t = auroraTime;
    float centerX = w * 0.5f;

    // 1. Fondo cielo polar
    Paint sky = Paint::linear({centerX, 0.0f}, {centerX, h},
      {Color::argb(0xff010610), Color::argb(0xff03141f), Color::argb(0xff000508)},
      {0.0f, 0.5f, 1.0f});
    c.rect({0, 0, w, h}, sky);

    // 2. Estrellas con centelleo polar
    std::vector<Vec2> starPts;
    starPts.reserve(stars.size());
    for (const auto& s : stars) {
      starPts.push_back({s.x * w, s.y * h});
    }
    float twinkle = 0.35f + 0.35f * std::sin(t * 2.2f);
    Paint starPaint; starPaint.blend = Blend::plus;
    starPaint.color = {1.0f, 1.0f, 1.0f, std::clamp((0.25f + twinkle) * f.intensity, 0.0f, 1.0f)};
    c.points(starPts, 1.2f, starPaint);

    // 3. Cortinas de plasma ionizado
    const uint32_t rCols[kRibbons][2] = {
      {0xff00ffa3, 0xff00d2ff},
      {0xff00e5ff, 0xff7000ff},
      {0xff00ff77, 0xff00c6ff},
      {0xff9d4edd, 0xffff007f},
      {0xff00ffb2, 0xff3a86ff}
    };

    float stepW = w / float(kSteps - 1);
    float solarWind = 1.0f + smoothBass * 0.35f;

    for (int r = 0; r < kRibbons; r++) {
      float phaseOffset = float(r) * 1.25f;
      float baseY = h * 0.22f + float(r) * (h * 0.09f);

      Path ribbonPath;
      Vec2 pts[kSteps];
      for (int i = 0; i < kSteps; i++) {
        float x = float(i) * stepW;
        float normX = x / w;

        float w1 = std::sin(normX * 4.0f + t * 0.8f + phaseOffset) * 45.0f * solarWind;
        float w2 = std::cos(normX * 8.0f - t * 0.6f + phaseOffset) * 25.0f * solarWind;
        float w3 = std::sin(normX * 12.0f + t * 1.2f) * 12.0f;
        float y = baseY + w1 + w2 + w3;
        pts[i] = Vec2{x, y};
      }

      // Trazar spline suave
      ribbonPath.moveTo(pts[0].x, pts[0].y);
      for (int i = 0; i < kSteps - 1; i++) {
        float mx = (pts[i].x + pts[i + 1].x) * 0.5f;
        float my = (pts[i].y + pts[i + 1].y) * 0.5f;
        ribbonPath.quadraticTo(pts[i].x, pts[i].y, mx, my);
      }
      ribbonPath.lineTo(pts[kSteps - 1].x, pts[kSteps - 1].y);

      Color c1 = Color::argb(rCols[r][0]);
      Color c2 = Color::argb(rCols[r][1]);

      // Velo ancho difuso de plasma (múltiples pasadas para crear volumen)
      float strokeW = (32.0f - float(r) * 3.5f) * (h / 600.0f);
      Paint ribbonGlow; ribbonGlow.blend = Blend::plus;
      ribbonGlow.color = {c1.r, c1.g, c1.b, std::clamp(0.22f * f.intensity, 0.0f, 1.0f)};
      ribbonGlow.strokeWidth = strokeW * 1.8f;
      ribbonGlow.strokeCap = 1; ribbonGlow.strokeJoin = 1;
      c.path(ribbonPath, ribbonGlow);

      Paint ribbonMid; ribbonMid.blend = Blend::plus;
      ribbonMid.color = {c2.r, c2.g, c2.b, std::clamp(0.38f * f.intensity, 0.0f, 1.0f)};
      ribbonMid.strokeWidth = strokeW;
      ribbonMid.strokeCap = 1; ribbonMid.strokeJoin = 1;
      c.path(ribbonPath, ribbonMid);

      // Filamento central brillante
      Paint coreFilament; coreFilament.blend = Blend::plus;
      coreFilament.color = {1.0f, 1.0f, 1.0f, std::clamp(0.48f * f.intensity, 0.0f, 1.0f)};
      coreFilament.strokeWidth = 2.4f;
      coreFilament.strokeCap = 1; coreFilament.strokeJoin = 1;
      c.path(ribbonPath, coreFilament);
    }

    // 4. Siluetas montañosas en primer plano
    Path mountains;
    mountains.moveTo(0.0f, h);
    mountains.lineTo(0.0f, h * 0.84f);
    mountains.lineTo(w * 0.22f, h * 0.76f);
    mountains.lineTo(w * 0.45f, h * 0.82f);
    mountains.lineTo(w * 0.72f, h * 0.73f);
    mountains.lineTo(w, h * 0.86f);
    mountains.lineTo(w, h);
    mountains.close();

    Paint mountainPaint; mountainPaint.color = Color::argb(0xff010408);
    c.path(mountains, mountainPaint);
  }
};
''';
