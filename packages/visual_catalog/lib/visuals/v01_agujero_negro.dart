// Agujero Negro & Acreción — Puerto fiel de Visuales Inmersivas v01.
// Disco de acreción relativista con corrimiento Doppler, chorros polares bipolares,
// anillo fotónico ISCO y curvatura gravitacional de Einstein.
const nativeSource = r'''
class Visual final : public Scene {
  struct DiskParticle { float radius, angle, speed, size; };
  struct JetParticle { float z, speedZ, spread, size; };
  struct Star { float x, y, phase; };
  std::vector<DiskParticle> disk;
  std::vector<JetParticle> jets;
  std::vector<Star> stars;
  float jetTravel = 0.0f;
  float diskTime = 0.0f;
  float smoothEnergy = 0.0f;
  float smoothBass = 0.0f;
 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    jetTravel = 0.0f;
    diskTime = 0.0f;
    smoothEnergy = 0.0f;
    smoothBass = 0.0f;
    disk.clear(); disk.reserve(650);
    for (int i = 0; i < 650; i++) {
      float r = 55.0f + rng.unit() * 160.0f;
      float a = rng.unit() * 6.2831853f;
      float spd = (1.2f / std::sqrt(r)) * 0.045f;
      float sz = 1.0f + rng.unit() * 2.2f;
      disk.push_back({r, a, spd, sz});
    }
    jets.clear(); jets.reserve(120);
    for (int i = 0; i < 120; i++) {
      float z = (rng.unit() - 0.5f) * 220.0f;
      float spd = (1.5f + rng.unit() * 3.0f) * (rng.unit() > 0.5f ? 1.0f : -1.0f);
      float sp = rng.unit() * 12.0f;
      float sz = 1.2f + rng.unit() * 2.0f;
      jets.push_back({z, spd, sp, sz});
    }
    stars.clear(); stars.reserve(60);
    for (int i = 0; i < 60; i++) {
      stars.push_back({rng.unit(), rng.unit(), rng.unit() * 6.2831853f});
    }
  }
  void update(const Frame& f) override {
    float dt = float(f.delta);
    float targetEnergy = f.music.active ? f.music.energy : 0.0f;
    float targetBass = f.music.active ? f.music.bass : 0.0f;
    smoothEnergy += (targetEnergy - smoothEnergy) * float(1.0 - std::exp(-dt * 6.0));
    smoothBass += (targetBass - smoothBass) * float(1.0 - std::exp(-dt * 6.0));

    // En silencio reposa en una órbita relativista pausada (~0.10f).
    // Con música acelera el disco de acreción y desata los chorros polares.
    float diskDrive = 0.10f + smoothEnergy * 0.75f + smoothBass * 0.35f;
    diskTime += dt * f.speed * diskDrive;

    float jetRate = 8.0f + smoothEnergy * 65.0f + smoothBass * 35.0f;
    jetTravel += dt * f.speed * jetRate;
  }
  void render(const Frame& f, Canvas& c) const override {
    float w = f.width, h = f.height;
    float t = diskTime;
    Vec2 center{w * 0.5f, h * 0.5f};
    float minDim = std::min(w, h);
    float holeRadius = minDim * 0.11f;

    // 1. Fondo cósmico profundo
    Paint bg = Paint::radial(center, minDim * 0.85f,
      {Color::argb(0xff0d061a), Color::argb(0xff040208), Color::argb(0xff000000)},
      {0.0f, 0.45f, 1.0f});
    c.rect({0, 0, w, h}, bg);

    // Estrellas de fondo con centelleo armónico
    std::vector<Vec2> starPoints;
    starPoints.reserve(stars.size());
    for (const auto& s : stars) {
      starPoints.push_back({s.x * w, s.y * h});
    }
    float starTwinkle = 0.35f + 0.35f * std::sin(t * 2.5f);
    Paint starPaint; starPaint.blend = Blend::plus;
    starPaint.color = {1.0f, 1.0f, 1.0f, std::clamp(starTwinkle * f.intensity, 0.0f, 1.0f)};
    c.points(starPoints, 1.1f, starPaint);

    // 2. Halo de curvatura gravitacional exterior (anillo de Einstein)
    float bassBoost = (0.85f + 0.35f * smoothBass) * f.intensity;
    Paint halo1 = Paint::radial(center, holeRadius * 3.2f,
      {{0.29f, 0.08f, 0.55f, std::clamp(0.35f * bassBoost, 0.0f, 1.0f)}, {0, 0, 0, 0}},
      {0.0f, 1.0f});
    halo1.blend = Blend::plus;
    c.circle(center, holeRadius * 3.2f, halo1);

    Paint halo2 = Paint::radial(center, holeRadius * 2.0f,
      {{1.0f, 0.43f, 0.0f, std::clamp(0.24f * bassBoost, 0.0f, 1.0f)}, {0, 0, 0, 0}},
      {0.0f, 1.0f});
    halo2.blend = Blend::plus;
    c.circle(center, holeRadius * 2.0f, halo2);

    // 3. Chorros relativistas polares bipolares
    for (const auto& j : jets) {
      float jz = std::fmod(j.z + j.speedZ * jetTravel + 24000.0f, 480.0f) - 240.0f;
      float prog = std::clamp(std::abs(jz) / 240.0f, 0.0f, 1.0f);
      float alpha = std::clamp((1.0f - prog) * 0.82f * f.intensity, 0.0f, 1.0f);
      float xOff = std::sin(jz * 0.05f + t * 2.0f) * j.spread * (1.0f + prog * 2.0f);
      float jx = center.x + xOff * (minDim / 400.0f);
      float jy = center.y + jz * (minDim / 400.0f);

      Color jcol{
        std::clamp(0.0f * (1.0f - prog) + 0.83f * prog, 0.0f, 1.0f),
        std::clamp(0.9f * (1.0f - prog) + 0.0f * prog, 0.0f, 1.0f),
        std::clamp(1.0f * (1.0f - prog) + 0.98f * prog, 0.0f, 1.0f),
        alpha
      };
      Paint jp; jp.blend = Blend::plus; jp.color = jcol;
      c.circle({jx, jy}, std::max(0.5f, j.size * (1.0f - prog * 0.5f)), jp);
    }

    // 4. Disco de acreción 3D con corrimiento Doppler
    float pitch = 0.50f + std::sin(t * 0.18f) * 0.12f;
    float yaw = t * 0.35f;
    float cosPitch = std::cos(pitch);
    float sinPitch = std::sin(pitch);
    float diskScale = (minDim / 400.0f) * (1.0f + smoothBass * 0.15f);

    struct Proj { Vec2 pt; float size; Color col; };
    std::vector<Proj> backPts, frontPts;
    backPts.reserve(350); frontPts.reserve(350);

    for (const auto& p : disk) {
      float effAngle = p.angle + p.speed * t * 70.0f + yaw;
      float rawX = p.radius * std::cos(effAngle) * diskScale;
      float rawY = p.radius * std::sin(effAngle) * diskScale;

      float rotX = rawX;
      float rotY = rawY * cosPitch;
      float rotZ = rawY * sinPitch;

      float doppler = (std::sin(effAngle) + 1.0f) * 0.5f;
      float dAlpha = std::clamp((0.4f + doppler * 0.6f) * f.intensity, 0.0f, 1.0f);

      Color col{
        std::clamp(1.0f * (1.0f - doppler) + 0.0f * doppler, 0.0f, 1.0f),
        std::clamp(0.34f * (1.0f - doppler) + 0.9f * doppler, 0.0f, 1.0f),
        std::clamp(0.13f * (1.0f - doppler) + 1.0f * doppler, 0.0f, 1.0f),
        dAlpha
      };

      Proj pr{{center.x + rotX, center.y + rotY}, p.size * diskScale, col};
      if (rotZ < 0.0f) backPts.push_back(pr);
      else frontPts.push_back(pr);
    }

    // Partículas detrás del horizonte
    for (const auto& pr : backPts) {
      Paint p; p.blend = Blend::plus; p.color = pr.col;
      c.circle(pr.pt, pr.size, p);
    }

    // 5. Arco de deflexión gravitacional de Einstein sobre el horizonte
    Path arc;
    const int arcSteps = 36;
    float arcR = holeRadius * 1.25f;
    for (int i = 0; i <= arcSteps; i++) {
      float a = -3.14159265f * 0.85f + (float(i) / float(arcSteps)) * 3.14159265f * 1.7f;
      float ax = center.x + std::cos(a) * arcR;
      float ay = center.y + std::sin(a) * arcR * cosPitch * 1.4f;
      if (i == 0) arc.moveTo(ax, ay); else arc.lineTo(ax, ay);
    }
    Paint arcPaint; arcPaint.blend = Blend::plus;
    arcPaint.color = {1.0f, 0.67f, 0.25f, std::clamp(0.65f * bassBoost, 0.0f, 1.0f)};
    arcPaint.strokeWidth = 3.0f; arcPaint.strokeCap = 1; arcPaint.strokeJoin = 1;
    c.path(arc, arcPaint);

    // 6. Horizonte de Sucesos (Vacío Absoluto)
    Paint holePaint; holePaint.color = Color::argb(0xff030305);
    c.circle(center, holeRadius, holePaint);

    // 7. Esfera de fotones (Anillo ISCO)
    Paint iscoPaint; iscoPaint.blend = Blend::plus;
    iscoPaint.color = {1.0f, 0.85f, 0.35f, std::clamp(0.92f * bassBoost, 0.0f, 1.0f)};
    iscoPaint.strokeWidth = 2.4f;
    c.circle(center, holeRadius + 1.2f, iscoPaint);

    // 8. Partículas delante del horizonte
    for (const auto& pr : frontPts) {
      Paint p; p.blend = Blend::plus; p.color = pr.col;
      c.circle(pr.pt, pr.size, p);
    }
  }
};
''';
