// Campo de Flujo Vectorial — Puerto fiel de Visuales Inmersivas v05.
// 380 filamentos guiados por campo analítico de rotacional curl noise
// con amortiguamiento de inercia y estelas de trayectoria.
const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kMaxTrail = 8;
  struct Streamer {
    float x, y, vx, vy, spd, sz;
    int colIdx;
    float trailX[kMaxTrail];
    float trailY[kMaxTrail];
    int trailLen;
  };
  std::vector<Streamer> streamers;
  int done = 0;
  float fenergy = 0.0f;

  void step(float w, float h) {
    const float dt = 1.0f / 60.0f;
    const float freq = 2.4f;
    float time = float(done) * dt;

    for (auto& s : streamers) {
      float rawAngle = std::sin(s.x * freq + time * 0.6f) * std::cos(s.y * freq - time * 0.4f) * 3.14159265f * 3.5f;
      float speedFactor = 0.0010f + 0.0030f * fenergy;
      float targetVx = std::cos(rawAngle) * speedFactor * s.spd;
      float targetVy = std::sin(rawAngle) * speedFactor * s.spd;

      // Vórtice armónico central estimulado por la energía musical
      float dx = 0.5f - s.x;
      float dy = 0.5f - s.y;
      float dist = std::sqrt(dx * dx + dy * dy);
      if (dist > 0.02f && dist < 0.45f) {
        float perpDx = -dy / dist;
        float perpDy = dx / dist;
        float strength = (1.0f - dist / 0.45f) * 0.004f * fenergy;
        targetVx += perpDx * strength;
        targetVy += perpDy * strength;
      }

      s.vx = s.vx * 0.88f + targetVx * 0.12f;
      s.vy = s.vy * 0.88f + targetVy * 0.12f;

      s.x += s.vx * dt * 60.0f;
      s.y += s.vy * dt * 60.0f;

      bool reset = false;
      if (s.x < 0.0f) { s.x = 1.0f; reset = true; }
      if (s.x > 1.0f) { s.x = 0.0f; reset = true; }
      if (s.y < 0.0f) { s.y = 1.0f; reset = true; }
      if (s.y > 1.0f) { s.y = 0.0f; reset = true; }

      if (reset) {
        s.trailLen = 0;
      }

      // Guardar historial del rastro
      if (s.trailLen < kMaxTrail) {
        s.trailX[s.trailLen] = s.x * w;
        s.trailY[s.trailLen] = s.y * h;
        s.trailLen++;
      } else {
        for (int k = 0; k < kMaxTrail - 1; k++) {
          s.trailX[k] = s.trailX[k + 1];
          s.trailY[k] = s.trailY[k + 1];
        }
        s.trailX[kMaxTrail - 1] = s.x * w;
        s.trailY[kMaxTrail - 1] = s.y * h;
      }
    }
    done++;
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    streamers.clear(); streamers.reserve(380);
    done = 0;
    for (int i = 0; i < 380; i++) {
      Streamer s;
      s.x = rng.unit(); s.y = rng.unit();
      s.vx = 0.0f; s.vy = 0.0f;
      s.spd = 0.8f + rng.unit() * 0.9f;
      s.sz = 1.1f + rng.unit() * 1.8f;
      s.colIdx = int(rng.unit() * 4.999f);
      s.trailLen = 0;
      streamers.push_back(s);
    }
  }

  void update(const Frame& f) override {
    fenergy = f.music.active ? f.music.energy : 0.0f;
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

    // Fondo oscuro con matiz azul profundo
    Paint bg; bg.color = Color::argb(0xff03070e);
    c.rect({0, 0, w, h}, bg);

    // Paleta neón bioluminiscente
    const uint32_t pal[5] = {0xff00ffcc, 0xff00b4d8, 0xff7209b7, 0xfff72585, 0xff4cc9f0};

    // Renderizar rastros agrupados por color
    for (int col = 0; col < 5; col++) {
      Color base = Color::argb(pal[col]);
      Paint tp; tp.blend = Blend::plus;
      tp.color = {base.r, base.g, base.b, std::clamp(0.40f * f.intensity, 0.0f, 1.0f)};
      tp.strokeWidth = 1.3f;
      tp.strokeCap = 1; tp.strokeJoin = 1;

      Path trailPath;
      for (const auto& s : streamers) {
        if (s.colIdx != col || s.trailLen < 2) continue;
        trailPath.moveTo(s.trailX[0], s.trailY[0]);
        for (int k = 1; k < s.trailLen; k++) {
          trailPath.lineTo(s.trailX[k], s.trailY[k]);
        }
      }
      c.path(trailPath, tp);
    }

    // Cabezas brillantes de las partículas
    std::vector<Vec2> heads;
    heads.reserve(streamers.size());
    for (const auto& s : streamers) {
      if (s.trailLen > 0) {
        heads.push_back({s.trailX[s.trailLen - 1], s.trailY[s.trailLen - 1]});
      }
    }
    Paint hp; hp.blend = Blend::plus;
    hp.color = {1.0f, 1.0f, 1.0f, std::clamp(0.9f * f.intensity, 0.0f, 1.0f)};
    c.points(heads, 1.4f, hp);
  }
};
''';
