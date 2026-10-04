class Visual final : public Scene {
  // Reserve the maximum (detail 2): moving a setting never reallocates or restarts.
  static constexpr int maxStars = 3000;
  struct Star { float radius, offset, lift, drift; int slot, group; };
  std::vector<Star> stars;
  float turn = 0, breath = 0, haze = 0, beats = 0;
 public:
  void reset(uint32_t seed) override {
    Random rng(seed); stars.clear(); stars.reserve(maxStars);
    turn = 0; breath = 0; haze = 0; beats = 0;
    for (int i = 0; i < maxStars; i++) {
      float r = std::sqrt(rng.unit());
      stars.push_back({r, r * 5.8f + (rng.unit() - .5f) * (.25f + r * .8f),
        (rng.unit() - .5f) * (.018f + r * .035f), .7f + rng.unit() * .6f,
        int(rng.unit() * 720), i % 9});
    }
  }
  void update(const Frame& f) override {
    auto m = modifiers(f);
    // Speed always through delta, accumulated: moving it never makes the spin jump.
    turn += float(f.delta) * f.speed * m.giro * .06f;
    float energy = f.music.energy * f.intensity;
    breath += (energy - breath) * float(1 - std::exp(-f.delta * 3));
    // Style "Auto" (option 0) switches between sharp and hazy every 8 beats.
    beats += float(f.music.events[2].size());
    float target = m.estilo == 1 ? 0.f : m.estilo == 2 ? 1.f
                 : (int(beats / 8) % 2 == 1 ? 1.f : 0.f);
    haze += (target - haze) * float(1 - std::exp(-f.delta * 2));
  }
  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    // Palette from metadata: colors[0] background, colors[1..3] accents.
    const auto& pal = f.colors;
    Color deep{pal[0].r * .25f, pal[0].g * .25f, pal[0].b * .25f, 1};
    c.rect({0, 0, f.width, f.height},
           Paint::radial({f.width * .5f, f.height * .47f}, f.height * .75f,
                         {pal[0].opacity(1), deep}));
    c.save(); c.translate(f.width * .5f, f.height * .48f); c.rotate(-.38f);
    float scale = std::min(f.width * .62f, f.height * .42f) * (1 + breath * .045f);
    Paint mist = Paint::radial({0, 0}, scale * .8f,
      {pal[2].opacity((.12f + haze * .2f) * f.glow), pal[2].opacity(0)});
    mist.blend = Blend::plus; c.rect({-scale, -scale, scale * 2, scale * 2}, mist);
    int visible = std::min(maxStars, int(maxStars * .5f * f.detail));
    float arm = float(2 * pi) / float(m.brazos);
    for (int group = 0; group < 9; group++) {
      std::vector<Vec2> batch; batch.reserve(visible / 9 + 1);
      for (int i = 0; i < visible; i++) {
        const auto& s = stars[i];
        if (s.group != group) continue;
        float a = float(s.slot % m.brazos) * arm + s.offset + turn * s.drift;
        batch.push_back({std::cos(a) * s.radius * scale,
          std::sin(a) * s.radius * scale * .49f + s.lift * scale});
      }
      Paint p; p.blend = Blend::plus; p.color = pal[1 + group % 3].opacity(.65f);
      c.points(batch, (.55f + (group / 3) * .5f) * (1 + haze * .8f), p);
    }
    if (m.nucleo) {
      Paint core = Paint::radial({0, 0}, scale * .28f,
        {pal[3].opacity(.92f * std::min(1.f, f.glow)), pal[1].opacity(.22f), pal[1].opacity(0)},
        {0, .22f, 1});
      core.blend = Blend::screen; c.circle({0, 0}, scale * .28f, core);
    }
    c.restore();
  }
};
