// Hipercubo 4D Tesseract — Puerto fiel de Visuales Inmersivas v06.
// Proyección ortográfica y de doble perspectiva de un tesseract de 16 vértices
// y 32 aristas rotando simultáneamente en los planos XW e YZ.
const nativeSource = r'''
class Visual final : public Scene {
  static constexpr float kV4[16][4] = {
    {-1,-1,-1,-1}, {1,-1,-1,-1}, {1,1,-1,-1}, {-1,1,-1,-1},
    {-1,-1,1,-1},  {1,-1,1,-1},  {1,1,1,-1},  {-1,1,1,-1},
    {-1,-1,-1,1},  {1,-1,-1,1},  {1,1,-1,1},  {-1,1,-1,1},
    {-1,-1,1,1},   {1,-1,1,1},   {1,1,1,1},   {-1,1,1,1}
  };
  struct Edge { int i, j; };
  std::vector<Edge> edges;
  float angle4D = 0.0f;
  float rotTime = 0.0f;
  float smoothBass = 0.0f;
  float smoothEnergy = 0.0f;
 public:
  void reset(uint32_t seed) override {
    (void)seed;
    edges.clear();
    angle4D = 0.0f;
    rotTime = 0.0f;
    smoothBass = 0.0f;
    smoothEnergy = 0.0f;
    for (int i = 0; i < 16; i++) {
      for (int j = i + 1; j < 16; j++) {
        int diff = 0;
        for (int k = 0; k < 4; k++) {
          if (kV4[i][k] != kV4[j][k]) diff++;
        }
        if (diff == 1) edges.push_back({i, j});
      }
    }
  }
  void update(const Frame& f) override {
    smoothBass += (f.music.bass - smoothBass) * float(1.0 - std::exp(-f.delta * 6.0));
    smoothEnergy += (f.music.energy - smoothEnergy) * float(1.0 - std::exp(-f.delta * 5.0));
    angle4D += float(f.delta) * f.speed * 0.55f * (1.0f + smoothEnergy * 0.4f);
    rotTime += float(f.delta) * f.speed;
  }
  void render(const Frame& f, Canvas& c) const override {
    float w = f.width, h = f.height;
    float t = rotTime;
    Vec2 center{w * 0.5f, h * 0.5f};
    float minDim = std::min(w, h);

    // 1. Fondo cósmico sagrado
    Paint bg = Paint::radial(center, minDim * 0.85f,
      {Color::argb(0xff0f041c), Color::argb(0xff05010b), Color::argb(0xff000000)},
      {0.0f, 0.5f, 1.0f});
    c.rect({0, 0, w, h}, bg);

    // Núcleo sagrado resplandeciente
    float bassPulse = (1.0f + smoothBass * 0.35f);
    Paint coreGlow = Paint::radial(center, minDim * 0.18f * bassPulse,
      {{0.62f, 0.31f, 0.87f, std::clamp(0.40f * f.intensity, 0.0f, 1.0f)}, {0, 0, 0, 0}},
      {0.0f, 1.0f});
    coreGlow.blend = Blend::plus;
    c.circle(center, minDim * 0.18f * bassPulse, coreGlow);

    float cosA = std::cos(angle4D), sinA = std::sin(angle4D);
    float cosB = std::cos(angle4D * 0.7f), sinB = std::sin(angle4D * 0.7f);

    float rotX = 0.35f + std::sin(t * 0.25f) * 0.15f;
    float rotY = t * 0.30f;
    float cosX = std::cos(rotX), sinX = std::sin(rotX);
    float cosY = std::cos(rotY), sinY = std::sin(rotY);

    const float distance4D = 2.4f;
    const float distance3D = 3.6f;
    float scale = minDim * 0.42f * bassPulse;

    Vec2 projected[16];
    float depths[16];

    for (int i = 0; i < 16; i++) {
      float px = kV4[i][0], py = kV4[i][1], pz = kV4[i][2], pw = kV4[i][3];

      // Rotación 4D en planos XW e YZ
      float x1 = px * cosA - pw * sinA;
      float w1 = px * sinA + pw * cosA;

      float y1 = py * cosB - pz * sinB;
      float z1 = py * sinB + pz * cosB;

      // Proyección perspectiva 4D -> 3D
      float f4D = 1.0f / (distance4D - w1);
      float x3 = x1 * f4D;
      float y3 = y1 * f4D;
      float z3 = z1 * f4D;

      // Rotación 3D (pitch & yaw continuos)
      float y3Rot = y3 * cosX - z3 * sinX;
      float z3Rot1 = y3 * sinX + z3 * cosX;

      float x3Rot = x3 * cosY + z3Rot1 * sinY;
      float z3Rot = -x3 * sinY + z3Rot1 * cosY;

      // Proyección perspectiva 3D -> 2D
      float f3D = 1.0f / (distance3D - z3Rot);
      float x2 = center.x + x3Rot * f3D * scale;
      float y2 = center.y + y3Rot * f3D * scale;

      projected[i] = Vec2{x2, y2};
      depths[i] = z3Rot;
    }

    // 2. Renderizar 32 aristas del tesseract con iluminación por profundidad
    for (const auto& e : edges) {
      Vec2 p1 = projected[e.i];
      Vec2 p2 = projected[e.j];
      float avgZ = (depths[e.i] + depths[e.j]) * 0.5f;
      float depthNorm = std::clamp((avgZ + 1.2f) / 2.4f, 0.0f, 1.0f);

      // Color lerp: cian brillante {0, 1, 0.88} en primer plano -> magenta neón {1, 0, 0.5} al fondo
      Color col{
        0.0f * (1.0f - depthNorm) + 1.0f * depthNorm,
        1.0f * (1.0f - depthNorm) + 0.0f * depthNorm,
        0.88f * (1.0f - depthNorm) + 0.5f * depthNorm,
        std::clamp((0.35f + (1.0f - depthNorm) * 0.65f) * f.intensity, 0.0f, 1.0f)
      };

      Paint ep; ep.blend = Blend::plus; ep.color = col;
      ep.strokeWidth = std::clamp(1.2f + (1.0f - depthNorm) * 2.0f, 0.8f, 3.2f);

      Path edgePath;
      edgePath.moveTo(p1.x, p1.y);
      edgePath.lineTo(p2.x, p2.y);
      c.path(edgePath, ep);
    }

    // 3. Renderizar los 16 vértices cuatridimensionales
    for (int i = 0; i < 16; i++) {
      Vec2 pt = projected[i];
      float z = depths[i];
      float depthNorm = std::clamp((z + 1.2f) / 2.4f, 0.0f, 1.0f);
      float rad = std::clamp(2.0f + (1.0f - depthNorm) * 3.5f, 1.5f, 5.5f);

      // Halo del vértice
      Paint vHalo; vHalo.blend = Blend::plus;
      vHalo.color = {0.0f, 1.0f, 0.88f, std::clamp(0.40f * f.intensity, 0.0f, 1.0f)};
      c.circle(pt, rad * 2.0f, vHalo);

      // Núcleo blanco del vértice
      Paint vCore; vCore.blend = Blend::plus;
      vCore.color = {1.0f, 1.0f, 1.0f, std::clamp(0.92f * f.intensity, 0.0f, 1.0f)};
      c.circle(pt, rad, vCore);
    }
  }
};
''';
