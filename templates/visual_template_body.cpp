class Visual final : public Scene {
  // Reserve the maximum (detail 2): changing a setting never reallocates.
  static constexpr int maxStars = 3000;
  struct Star { float radius, offset, lift, drift, arm; int group; };
  std::vector<Star> stars;
  float clock = 0, breath = 0, beat = 0;
 public:
  void reset(uint32_t seed) override {
    Random rng(seed); stars.clear(); stars.reserve(maxStars);
    clock = 0; breath = 0; beat = 0;
    for (int i = 0; i < maxStars; i++) {
      float r = std::sqrt(rng.unit());
      stars.push_back({r, r * 5.8f + (rng.unit() - .5f) * (.25f + r * .8f),
        (rng.unit() - .5f) * (.018f + r * .035f), .7f + rng.unit() * .6f,
        rng.unit(), i % 9});
    }
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
    auto g = glide(f);  // transitions: gliding decimals, a 0..1 fade, weights
    const auto& pal = f.colors;
    // Pulso decides how the music shows; its weights blend the options.
    const float graves = g.pulso.weight(0) * breath;
    const float golpes = g.pulso.weight(1) * beat;
    const float brillos = g.pulso.weight(2) * f.music.spark * f.intensity;
    Color deep{pal[0].r * .25f, pal[0].g * .25f, pal[0].b * .25f, 1};
    c.rect({0, 0, f.width, f.height},
           Paint::radial({f.width * .5f, f.height * .47f}, f.height * .75f,
                         {pal[0].opacity(1), deep}));
    c.save(); c.translate(f.width * .5f, f.height * .48f); c.rotate(-.38f);
    // Music grows the galaxy 20% at most, even with intensity 2.
    const float scale = std::min(f.width * .62f, f.height * .42f) * (1 + std::min(graves, 1.f) * .2f);
    // Estela: from sharp stars (0) to a soft, glowing nebula (1).
    const float haze = g.estela;
    Paint mist = Paint::radial({0, 0}, scale * (.6f + haze * .5f),
      {pal[2].opacity((.05f + haze * .35f) * f.glow), pal[2].opacity(0)});
    mist.blend = Blend::plus;
    c.rect({-scale * 1.2f, -scale * 1.2f, scale * 2.4f, scale * 2.4f}, mist);
    // Brazos glides (5.4 arms): each star sits at its share of the circle, so
    // arms spread apart smoothly while the count changes.
    const int fewer = int(std::floor(g.brazos)), more = fewer + 1;
    const float between = g.brazos - float(fewer);
    auto armAngle = [](float share, int arms) {
      return std::floor(share * float(arms)) * float(2 * pi) / float(arms);
    };
    const int visible = std::min(maxStars, int(maxStars * .5f * f.detail));
    Paint core = Paint::radial({0, 0}, scale * .28f,
      {pal[3].opacity(.92f * std::min(1.f, f.glow)), pal[1].opacity(.22f), pal[1].opacity(0)},
      {0, .22f, 1});
    core.blend = Blend::screen;
    c.circle({0, 0}, scale * (.28f + golpes * .08f), core);
    for (int group = 0; group < 9; group++) {
      std::vector<Vec2> batch, mirror;
      batch.reserve(visible / 9 + 1); mirror.reserve(visible / 9 + 1);
      for (int i = 0; i < visible; i++) {
        const auto& s = stars[i];
        if (s.group != group) continue;
        const float from = armAngle(s.arm, fewer), to = armAngle(s.arm, more);
        const float a = from + (to - from) * between + s.offset + clock * .06f * s.drift;
        const Vec2 point{std::cos(a) * s.radius * scale,
                         std::sin(a) * s.radius * scale * .49f + s.lift * scale};
        batch.push_back(point);
        mirror.push_back({-point.x, point.y});
      }
      const float twinkle = .5f + .5f * std::sin(clock * 9 + group * 1.7f);
      Paint p; p.blend = Blend::plus;
      const float alpha = std::min(1.f, .55f + golpes * .45f + brillos * twinkle * .6f);
      const float size = (.55f + (group / 3) * .5f) * (1 + haze * 1.6f + golpes * .25f);
      p.color = pal[1 + group % 3].opacity(alpha);
      c.points(batch, size, p);
      // Espejo: a mirrored twin turns the spiral into a symmetric butterfly.
      if (g.espejo > 0) {
        p.color = pal[1 + (group + 1) % 3].opacity(alpha * g.espejo);
        c.points(mirror, size, p);
      }
    }
    c.restore();
  }
};
