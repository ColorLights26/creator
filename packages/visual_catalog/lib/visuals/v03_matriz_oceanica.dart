// Matriz Oceánica 3D — Puerto fiel de Visuales Inmersivas v03.
// Perspectiva retrowave con oleaje multi-armónico, sol synthwave con persianas
// y líneas de malla que transicionan de cian a magenta neón.
const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kCols = 26;
  static constexpr int kRows = 24;
  float waveTime = 0.0f;
  float smoothEnergy = 0.0f;
  float smoothBass = 0.0f;
 public:
  void reset(uint32_t seed) override {
    (void)seed;
    waveTime = 0.0f;
    smoothEnergy = 0.0f;
    smoothBass = 0.0f;
  }
  void update(const Frame& f) override {
    float dt = float(f.delta);
    float targetEnergy = f.music.active ? f.music.energy : 0.0f;
    float targetBass = f.music.active ? f.music.bass : 0.0f;
    smoothEnergy += (targetEnergy - smoothEnergy) * float(1.0 - std::exp(-dt * 5.0));
    smoothBass += (targetBass - smoothBass) * float(1.0 - std::exp(-dt * 6.0));

    // En silencio reposa en un suave oleaje de marea nocturna (~0.10f).
    // Con música acelera el tren de olas synthwave al compás del beat.
    float audioDrive = 0.10f + smoothEnergy * 0.78f + smoothBass * 0.35f;
    waveTime += dt * f.speed * audioDrive;
  }
  void render(const Frame& f, Canvas& c) const override {
    float w = f.width, h = f.height;
    float t = waveTime;
    float horizonY = h * 0.40f;
    float centerX = w * 0.5f;

    // 1. Cielo cyberpunk con degradado lineal
    Paint sky = Paint::linear({centerX, 0.0f}, {centerX, h},
      {Color::argb(0xff070014), Color::argb(0xff1b0336), Color::argb(0xff03010a)},
      {0.0f, 0.5f, 1.0f});
    c.rect({0, 0, w, h}, sky);

    // 2. Sol distante Synthwave
    Vec2 sunCenter{centerX, horizonY - 15.0f};
    float sunRadius = std::min(w, h) * 0.22f;
    Paint sun = Paint::radial(sunCenter, sunRadius,
      {{1.0f, 0.0f, 0.5f, std::clamp(0.95f * f.intensity, 0.0f, 1.0f)},
       {1.0f, 0.47f, 0.0f, std::clamp(0.85f * f.intensity, 0.0f, 1.0f)},
       {0.0f, 0.0f, 0.0f, 0.0f}},
      {0.0f, 0.55f, 1.0f});
    sun.blend = Blend::plus;
    c.circle(sunCenter, sunRadius, sun);

    // Persianas horizontales cortando el sol (estilo neón retro)
    Paint blind; blind.color = Color::argb(0xff070014);
    blind.strokeWidth = 2.4f;
    float blindTop = sunCenter.y - sunRadius * 0.35f;
    float blindBottom = sunCenter.y + sunRadius * 0.90f;
    for (float by = blindTop; by < blindBottom; by += 8.0f) {
      Path bp; bp.moveTo(sunCenter.x - sunRadius, by); bp.lineTo(sunCenter.x + sunRadius, by);
      c.path(bp, blind);
    }

    // 3. Proyección 3D de la malla oceánica
    const float fov = 260.0f;
    const float gridSpacingX = 40.0f;
    const float gridSpacingZ = 34.0f;
    const float nearZ = 60.0f;
    float camHeight = 150.0f + std::sin(t * 0.5f) * 15.0f;
    float waveBass = (1.0f + f.music.bass * 0.75f);

    Vec2 proj[kRows][kCols];

    for (int r = 0; r < kRows; r++) {
      float z = nearZ + float(r) * gridSpacingZ;
      float depthFactor = fov / (z + 120.0f);

      for (int col = 0; col < kCols; col++) {
        float worldX = (float(col) - float(kCols) * 0.5f) * gridSpacingX;

        // Armónicos de olas
        float wave1 = std::sin(worldX * 0.015f + t * 1.5f) * 24.0f * waveBass;
        float wave2 = std::cos(z * 0.020f - t * 1.8f) * 20.0f * waveBass;
        float wave3 = std::sin((worldX + z) * 0.010f + t * 1.1f) * 16.0f * waveBass;
        float worldY = camHeight + wave1 + wave2 + wave3;

        float px = centerX + worldX * depthFactor;
        float py = horizonY + worldY * depthFactor;
        proj[r][col] = Vec2{px, py};
      }
    }

    // 4. Renderizar líneas de fila (olas horizontales) con niebla de profundidad
    for (int r = 0; r < kRows; r++) {
      float depth = float(r) / float(kRows - 1);
      float alpha = std::clamp((1.0f - depth * 0.75f) * f.intensity, 0.05f, 1.0f);

      // Desplazamiento cromático: cian brillante adelante -> magenta vivo en el horizonte
      Color rowCol{
        0.0f * (1.0f - depth) + 1.0f * depth,
        1.0f * (1.0f - depth) + 0.0f * depth,
        0.95f * (1.0f - depth) + 0.47f * depth,
        alpha
      };
      Paint rp; rp.blend = Blend::plus; rp.color = rowCol;
      rp.strokeWidth = std::max(0.6f, 2.2f * (1.0f - depth * 0.7f));

      Path rowPath;
      rowPath.moveTo(proj[r][0].x, proj[r][0].y);
      for (int col = 1; col < kCols; col++) {
        rowPath.lineTo(proj[r][col].x, proj[r][col].y);
      }
      c.path(rowPath, rp);
    }

    // Renderizar líneas de columna (longitudinales hacia el horizonte)
    Paint colPaint; colPaint.blend = Blend::plus;
    colPaint.color = {0.0f, 1.0f, 0.84f, std::clamp(0.35f * f.intensity, 0.0f, 1.0f)};
    colPaint.strokeWidth = 0.9f;
    for (int col = 0; col < kCols; col += 2) {
      Path colPath;
      colPath.moveTo(proj[0][col].x, proj[0][col].y);
      for (int r = 1; r < kRows; r++) {
        colPath.lineTo(proj[r][col].x, proj[r][col].y);
      }
      c.path(colPath, colPaint);
    }

    // Crestas iluminadas (destellos blancos en picos de olas)
    std::vector<Vec2> crests;
    crests.reserve(24);
    for (int r = 0; r < 6; r++) {
      for (int col = 2; col < kCols - 2; col += 3) {
        crests.push_back(proj[r][col]);
      }
    }
    Paint crestPaint; crestPaint.blend = Blend::plus;
    crestPaint.color = {1.0f, 1.0f, 1.0f, std::clamp(0.85f * f.intensity, 0.0f, 1.0f)};
    c.points(crests, 1.8f, crestPaint);
  }
};
''';
