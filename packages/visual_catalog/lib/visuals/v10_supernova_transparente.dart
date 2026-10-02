// Supernova & Termodinámica Transparente — versión overlay sin fondo opaco.
const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kParticleCount = 360;
  struct StellarParticle {
    float x, y, vx, vy, energy, size;
    int colIdx;
  };
  std::vector<StellarParticle> particles;
  int done = 0;
  float fenergy = 0.0f, fbass = 0.0f;
  bool fActive = false;
  float shockRadius = 0.0f;

  void step(float w, float h) {
    const float dt = 1.0f / 60.0f;
    float cx = w * 0.5f, cy = h * 0.5f;

    // Disparo de ondas de choque exclusivamente ante bombos reales con música activa
    if (shockRadius > 0.0f) {
      shockRadius += 16.0f;
      if (shockRadius > std::max(w, h) * 1.2f) {
        shockRadius = 0.0f;
      }
    } else if (fActive && fbass > 0.65f) {
      shockRadius = 10.0f;
      float blast = 14.0f + fenergy * 18.0f;
      for (auto& p : particles) {
        float dx = p.x - cx, dy = p.y - cy;
        float dist = std::max(12.0f, std::sqrt(dx * dx + dy * dy));
        float angle = std::atan2(dy, dx);
        float speed = std::clamp(blast * 110.0f / dist, 3.0f, 26.0f);
        p.vx = std::cos(angle) * speed;
        p.vy = std::sin(angle) * speed;
        p.energy = 1.0f;
      }
    }

    for (auto& p : particles) {
      // Gravedad central suave
      float dx = cx - p.x;
      float dy = cy - p.y;
      float dist = std::max(30.0f, std::sqrt(dx * dx + dy * dy));
      float grav = 0.07f;
      float perpX = -dy / dist;
      float perpY = dx / dist;

      p.vx += (dx / dist) * grav + perpX * 0.035f;
      p.vy += (dy / dist) * grav + perpY * 0.035f;

      p.vx *= 0.985f;
      p.vy *= 0.985f;

      p.x += p.vx * dt * 60.0f;
      p.y += p.vy * dt * 60.0f;

      if (p.x < 0.0f) { p.x = 0.0f; p.vx = -p.vx * 0.6f; }
      if (p.x > w) { p.x = w; p.vx = -p.vx * 0.6f; }
      if (p.y < 0.0f) { p.y = 0.0f; p.vy = -p.vy * 0.6f; }
      if (p.y > h) { p.y = h; p.vy = -p.vy * 0.6f; }

      p.energy = std::clamp(p.energy * 0.993f, 0.15f, 1.0f);
    }
    done++;
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    particles.clear(); particles.reserve(kParticleCount);
    done = 0; shockRadius = 0.0f; fActive = false; fenergy = 0.0f; fbass = 0.0f;
    for (int i = 0; i < kParticleCount; i++) {
      float a = rng.unit() * 6.2831853f;
      float dist = 20.0f + rng.unit() * 180.0f;
      float spd = (rng.unit() - 0.5f) * 2.2f;
      particles.push_back({
        std::cos(a) * dist, std::sin(a) * dist,
        std::sin(a) * spd, -std::cos(a) * spd,
        rng.unit(),
        1.2f + rng.unit() * 2.2f,
        int(rng.unit() * 4.999f)
      });
    }
  }

  void update(const Frame& f) override {
    fActive = f.music.active;
    fenergy = f.music.active ? f.music.energy : 0.0f;
    fbass = f.music.active ? f.music.bass : 0.0f;
    float rate = (f.reducedMotion ? 0.3f : 1.0f) * f.speed;
    int target = int(float(f.time) * rate * 60.0f + 0.001f);
    int guard = 0;
    while (done < target && guard < 16) {
      step(f.width, f.height);
      guard++;
    }
  }

  void render(const Frame& f, Canvas& c) const override {
    float w = f.width, h = f.height;
    float t = float(f.time) * f.speed;
    Vec2 center{w * 0.5f, h * 0.5f};
    float maxDim = std::max(w, h);

    // 2. Remanente central (Púlsar ultra-denso con haz rotatorio)
    float bassKick = (1.0f + f.music.bass * 0.5f);
    Paint pulsarGlow = Paint::radial(center, 50.0f * bassKick,
      {{1.0f, 0.35f, 0.0f, std::clamp(0.40f * f.intensity, 0.0f, 1.0f)}, {0, 0, 0, 0}},
      {0.0f, 1.0f});
    pulsarGlow.blend = Blend::plus;
    c.circle(center, 50.0f * bassKick, pulsarGlow);

    Paint pulsarCore; pulsarCore.blend = Blend::plus;
    pulsarCore.color = {1.0f, 1.0f, 1.0f, std::clamp(0.95f * f.intensity, 0.0f, 1.0f)};
    c.circle(center, 5.0f * bassKick, pulsarCore);

    // Haces de emisión del púlsar rotando a gran velocidad
    float beamAngle = t * 4.0f;
    float beamLen = 35.0f * bassKick;
    Paint beamPaint; beamPaint.blend = Blend::plus;
    beamPaint.color = {0.0f, 0.9f, 1.0f, std::clamp(0.6f * f.intensity, 0.0f, 1.0f)};
    beamPaint.strokeWidth = 2.0f;
    Path beams;
    beams.moveTo(center.x - std::cos(beamAngle) * beamLen, center.y - std::sin(beamAngle) * beamLen);
    beams.lineTo(center.x + std::cos(beamAngle) * beamLen, center.y + std::sin(beamAngle) * beamLen);
    c.path(beams, beamPaint);

    // 3. Onda de choque expansiva
    if (shockRadius > 0.0f) {
      float shockAlpha = std::clamp((1.0f - shockRadius / (maxDim * 1.2f)) * f.intensity, 0.0f, 1.0f);
      Paint shockPaint; shockPaint.blend = Blend::plus;
      shockPaint.color = {1.0f, 0.84f, 0.0f, shockAlpha};
      shockPaint.strokeWidth = std::clamp(4.0f * shockAlpha, 1.0f, 4.0f);
      c.circle(center, shockRadius, shockPaint);
    }

    // 4. Renderizar partículas termodinámicas con estelas de velocidad
    const uint32_t thermalPal[5] = {0xffff5722, 0xffffd600, 0xff00e5ff, 0xffff007f, 0xffe040fb};

    for (const auto& p : particles) {
      float speed = std::sqrt(p.vx * p.vx + p.vy * p.vy);
      float trailLen = std::clamp(speed * 1.5f, 2.0f, 24.0f);
      float normVx = (speed > 0.01f) ? (p.vx / speed) : 0.0f;
      float normVy = (speed > 0.01f) ? (p.vy / speed) : 0.0f;

      float px = (done == 0 ? center.x + p.x : p.x);
      float py = (done == 0 ? center.y + p.y : p.y);
      float tailX = px - normVx * trailLen;
      float tailY = py - normVy * trailLen;

      Color base = Color::argb(thermalPal[p.colIdx]);
      Color col{
        base.r * (1.0f - p.energy) + 1.0f * p.energy,
        base.g * (1.0f - p.energy) + 1.0f * p.energy,
        base.b * (1.0f - p.energy) + 1.0f * p.energy,
        std::clamp((0.40f + p.energy * 0.60f) * f.intensity, 0.0f, 1.0f)
      };

      Paint partPaint; partPaint.blend = Blend::plus;
      partPaint.color = col;
      partPaint.strokeWidth = std::max(1.0f, p.size);
      partPaint.strokeCap = 1;

      Path pLine; pLine.moveTo(tailX, tailY); pLine.lineTo(px, py);
      c.path(pLine, partPaint);
    }
  }
};
''';
