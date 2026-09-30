// Salto Hiperespacial — puerto de la galería FLUX/10 al motor nativo.
// Túnel de aros hexagonales/octogonales con 260 estelas estelares aditivas.
// Toda la escena es función pura del tiempo: recycling derivado de f.time.
const nativeSource = r'''
class Visual final : public Scene {
  struct Ring { float z0, rot0, sides; };
  struct Star { float x, y, z0; };
  std::vector<Ring> rings;
  std::vector<Star> stars;
  float travel = 0.0f;
  float rotTime = 0.0f;
  float smoothEnergy = 0.0f;
  float smoothBass = 0.0f;
  static float hash11(float p) {
    float s = std::sin(p * 12.9898f) * 43758.5453f;
    return s - std::floor(s);
  }
  static float safeMod(float v, float m) {
    float r = std::fmod(v, m);
    return r < 0.0f ? r + m : r;
  }
 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    rings.clear(); stars.clear();
    rings.reserve(90); stars.reserve(260);
    travel = 0.0f;
    rotTime = 0.0f;
    smoothEnergy = 0.0f;
    smoothBass = 0.0f;
    for (int i = 0; i < 90; i++) {
      float side = 6.0f;
      float h = hash11(float(i) * 1.37f + float(seed % 997) * 0.013f);
      if (h > 0.5f) side = 8.0f;
      rings.push_back({0.12f + float(i) / 90.0f * 1.9f,
        hash11(float(i) * 3.71f) * 6.2831853f, side});
    }
    for (int i = 0; i < 260; i++)
      stars.push_back({rng.unit() * 2.0f - 1.0f, rng.unit() * 2.0f - 1.0f,
        rng.unit() * 1.6f + 0.1f});
  }
  void update(const Frame& f) override {
    float dt = float(f.delta);
    float targetEnergy = f.music.active ? f.music.energy : 0.0f;
    float targetBass = f.music.active ? f.music.bass : 0.0f;
    smoothEnergy += (targetEnergy - smoothEnergy) * float(1.0 - std::exp(-dt * 6.0));
    smoothBass += (targetBass - smoothBass) * float(1.0 - std::exp(-dt * 6.0));

    // En silencio reposa en un avance estelar suave y sereno (~0.08f).
    // Con música acelera al hiperespacio con gran velocidad de fuga y rotación de túnel.
    float travelDrive = (0.08f + smoothEnergy * 0.72f + smoothBass * 0.40f) * (f.reducedMotion ? 0.35f : 1.0f);
    travel += dt * f.speed * travelDrive;
    float rotDrive = 0.08f + smoothEnergy * 0.65f + smoothBass * 0.25f;
    rotTime += dt * f.speed * rotDrive;
  }
  void render(const Frame& f, Canvas& c) const override {
    float w = f.width, h = f.height;
    float t = rotTime;
    float fmin = std::min(w, h);
    float cx = w * 0.5f + std::sin(t * 1.3f) * 8.0f * f.intensity;
    float cy = h * 0.5f + std::cos(t * 1.1f) * 8.0f * f.intensity;
    float f0 = fmin * 0.62f;
    float boost = std::clamp((0.85f + 0.35f * smoothEnergy + 0.3f * smoothBass) * f.intensity, 0.0f, 1.0f);
    Paint bg; bg.color = Color::argb(0xff04060d);
    c.rect({0, 0, w, h}, bg);

    // ── Estelas: un solo Path, 260 segmentos ──
    Path streaks;
    float streakSpan = 1.7f - 0.08f;
    for (size_t i = 0; i < stars.size(); i++) {
      const Star& s = stars[i];
      float z = safeMod(s.z0 - travel * 1.3333f, streakSpan);
      if (z < 0.08f) z += streakSpan;
      float k1 = f0 / z;
      float k2 = f0 / (z + 0.05f * (1.0f + smoothEnergy * 0.5f));
      streaks.moveTo(cx + s.x * k2, cy + s.y * k2);
      streaks.lineTo(cx + s.x * k1, cy + s.y * k1);
    }
    Paint sp; sp.blend = Blend::plus;
    sp.color = {0.863f, 0.914f, 1.0f, std::clamp(0.498f * boost, 0.0f, 1.0f)};
    sp.strokeWidth = 1.1f; sp.strokeCap = 1; sp.strokeJoin = 1;
    c.path(streaks, sp);

    // ── Aros del túnel ──
    float ringSpan = 2.0f;
    for (size_t i = 0; i < rings.size(); i++) {
      const Ring& r = rings[i];
      float z = safeMod(r.z0 - travel, ringSpan);
      if (z < 0.1f) z += ringSpan;
      float rad = f0 * 0.62f / z;
      if (rad > std::max(w, h) * 1.6f) continue;
      float zt = (1.75f - z) / 1.75f;
      if (zt < 0.0f) zt = 0.0f; if (zt > 1.0f) zt = 1.0f;
      float a = zt * (z * 2.2f < 1.0f ? z * 2.2f : 1.0f);
      int n = int(r.sides);
      float base = r.rot0 + t * 6.2831853f * (0.5f + (1.0f - z) * 0.6f)
        + std::sin(t * 0.7f + float(i) * 1.3f) * 0.35f;
      Path ring;
      for (int sd = 0; sd <= n; sd++) {
        float ang = base + float(sd) / float(n) * 6.2831853f;
        float px = cx + std::cos(ang) * rad;
        float py = cy + std::sin(ang) * rad * 0.94f;
        if (sd == 0) ring.moveTo(px, py); else ring.lineTo(px, py);
      }
      ring.close();
      Paint p; p.blend = Blend::plus;
      if (n == 6) p.color = {0.345f, 0.780f, 0.953f, std::clamp(a * 0.6f * boost, 0.0f, 1.0f)};
      else p.color = {0.651f, 0.545f, 1.0f, std::clamp(a * 0.6f * boost, 0.0f, 1.0f)};
      p.strokeWidth = 0.6f + a * 3.0f; p.strokeCap = 1; p.strokeJoin = 1;
      c.path(ring, p);
    }

    // ── Núcleo: degradado radial en vez de blur real ──
    float gr = f0 * 0.5f;
    Paint glow = Paint::radial({cx, cy}, gr,
      {{1.0f, 1.0f, 1.0f, std::clamp((0.45f + 0.2f * f.music.spark) * boost, 0.0f, 1.0f)},
       {0.345f, 0.780f, 0.953f, std::clamp(0.16f * boost, 0.0f, 1.0f)}, {0, 0, 0, 0}}, {0.0f, 0.35f, 1.0f});
    glow.blend = Blend::plus;
    c.circle({cx, cy}, gr, glow);
  }
};
''';
