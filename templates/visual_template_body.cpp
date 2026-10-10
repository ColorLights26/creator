class Visual final : public Scene {
  // Reserve the maximum (detail 2): changing a setting never reallocates.
  static constexpr int maxStars = 3000;
  struct Star { float radius, offset, lift, drift, arm, twin; int color; };
  std::vector<Star> stars;
  // One point batch per accent color, refilled every frame without allocating.
  mutable std::array<std::vector<Vec2>, 3> batches;
  float clock = 0, breath = 0, beat = 0;
 public:
  void reset(uint32_t seed) override {
    Random rng(seed); stars.clear(); stars.reserve(maxStars);
    clock = 0; breath = 0; beat = 0;
    for (int i = 0; i < maxStars; i++) {
      float r = std::sqrt(rng.unit());
      stars.push_back({r, r * 5.8f + (rng.unit() - .5f) * (.25f + r * .8f),
        (rng.unit() - .5f) * (.018f + r * .035f), .7f + rng.unit() * .6f,
        rng.unit(), rng.unit(), i % 3});
    }
    // Its own stars plus the mirrored twins of the previous color.
    for (auto& batch : batches) { batch.clear(); batch.reserve(2 * (maxStars / 3 + 1)); }
  }
  void update(const Frame& f) override {
    // Motion only: an own clock follows Velocidad and matches at 30 and 60 FPS.
    const float d = float(f.delta);
    clock += d * f.speed;
    // Music: the bass breathes slowly; each beat is a short accent that fades.
    breath += (f.music.bass * f.intensity - breath) * (1 - std::exp(-d * 4));
    if (!f.music.events[2].empty()) beat = std::min(1.f, f.intensity);
    beat *= std::exp(-d * 5);
  }
  void render(const Frame& f, Canvas& c) const override {
    // Look is computed here, so every setting shows even while paused.
    // Creator measures retained textures and validates every setting/profile.
    auto g = glide(f);  // transitions: gliding decimals, a 0..1 fade, weights
    const auto& pal = f.colors;
    // Pulso decides how the music shows; its weights blend the options.
    const float graves = g.pulso.weight(0) * breath;
    const float golpes = g.pulso.weight(1) * beat;
    const float brillos = g.pulso.weight(2) * f.music.spark * f.intensity;
    // Pass 1, sourceOver: the background.
    Color deep{pal[0].r * .25f, pal[0].g * .25f, pal[0].b * .25f, 1};
    c.rect({0, 0, f.width, f.height},
           Paint::radial({f.width * .5f, f.height * .47f}, f.height * .75f,
                         {pal[0].opacity(1), deep}));
    // Pass 2, screen: the nebula and the core share their blend, so one pass.
    const Vec2 center{f.width * .5f, f.height * .48f};
    // Music grows the galaxy 20% at most, even with intensity 2.
    const float scale = std::min(f.width * .62f, f.height * .42f) * (1 + std::min(graves, 1.f) * .2f);
    // Estela: from sharp stars (0) to a soft, glowing nebula (1).
    const float haze = g.estela;
    Paint mist = Paint::radial(center, scale * (.6f + haze * .5f),
      {pal[2].opacity((.05f + haze * .35f) * f.glow), pal[2].opacity(0)});
    mist.blend = Blend::screen;
    c.rect({center.x - scale * 1.2f, center.y - scale * 1.2f, scale * 2.4f, scale * 2.4f}, mist);
    Paint core = Paint::radial(center, scale * .28f,
      {pal[3].opacity(.92f * std::min(1.f, f.glow)), pal[1].opacity(.22f), pal[1].opacity(0)},
      {0, .22f, 1});
    core.blend = Blend::screen;
    c.circle(center, scale * (.28f + golpes * .08f), core);
    // The galaxy is tilted in C++: cheaper than a save/rotate/restore per star.
    const float cosTilt = std::cos(-.38f), sinTilt = std::sin(-.38f);
    auto place = [&](float x, float y) {
      return Vec2{center.x + x * cosTilt - y * sinTilt, center.y + x * sinTilt + y * cosTilt};
    };
    // Brazos glides (5.4 arms): each star sits at its share of the circle, so
    // arms spread apart smoothly while the count changes.
    const int fewer = int(std::floor(g.brazos)), more = fewer + 1;
    const float between = g.brazos - float(fewer);
    auto armAngle = [](float share, int arms) {
      return std::floor(share * float(arms)) * float(2 * pi) / float(arms);
    };
    const int visible = std::min(maxStars, int(maxStars * .5f * f.detail));
    for (auto& batch : batches) batch.clear();
    for (int i = 0; i < visible; i++) {
      const auto& s = stars[i];
      const float from = armAngle(s.arm, fewer), to = armAngle(s.arm, more);
      const float a = from + (to - from) * between + s.offset + clock * .06f * s.drift;
      const float x = std::cos(a) * s.radius * scale;
      const float y = std::sin(a) * s.radius * scale * .49f + s.lift * scale;
      batches[s.color].push_back(place(x, y));
      // Espejo: as it fades in, more stars gain a mirrored twin in the next
      // color, until the spiral becomes a symmetric butterfly.
      if (s.twin < g.espejo) batches[(s.color + 1) % 3].push_back(place(-x, y));
    }
    // Figures first, then one points() call per color (never one per star):
    // the engine preserves their order and reuses source textures.
    for (int k = 0; k < 3; k++) {
      const float twinkle = .5f + .5f * std::sin(clock * 9 + k * 2.1f);
      Paint p; p.blend = Blend::plus;
      const float alpha = std::min(1.f, .55f + golpes * .45f + brillos * twinkle * .6f);
      const float size = (.6f + k * .45f) * (1 + haze * 1.6f + golpes * .25f);
      p.color = pal[1 + k].opacity(alpha);
      c.points(batches[k], size, p);
    }
  }
};
