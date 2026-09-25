class Visual final : public Scene {
  struct Star { float radius, angle, lift, drift; int group; };
  std::vector<Star> stars;
  float turn = 0, breath = 0;
 public:
  void reset(uint32_t seed) override {
    Random rng(seed); stars.clear(); stars.reserve(1500); turn=0; breath=0;
    for(int i=0;i<1500;i++) {
      float r=std::sqrt(rng.unit()); int arm=i%4;
      stars.push_back({r, float(arm*pi/2)+r*5.8f+(rng.unit()-.5f)*(.25f+r*.8f),
        (rng.unit()-.5f)*(.018f+r*.035f), .7f+rng.unit()*.6f, i%9});
    }
  }
  void update(const Frame& f) override {
    turn += float(f.delta)*f.speed*.06f;
    float target=f.music.energy;
    breath += (target-breath)*float(1-std::exp(-f.delta*3));
  }
  void render(const Frame& f, Canvas& c) const override {
    Paint sky=Paint::radial({f.width*.5f,f.height*.47f},f.height*.75f,
      {Color::argb(0xff151031),Color::argb(0xff03040d)});
    c.rect({0,0,f.width,f.height},sky);
    c.save(); c.translate(f.width*.5f,f.height*.48f); c.rotate(-.38f);
    float scale=std::min(f.width*.62f,f.height*.42f)*(1+breath*.045f);
    Paint haze=Paint::radial({0,0},scale*.8f,{Color{.24f,.1f,.5f,.2f},Color{.08f,.02f,.3f,0}});
    haze.blend=Blend::plus; c.rect({-scale,-scale,scale*2,scale*2},haze);
    for(int group=0;group<9;group++) {
      std::vector<Vec2> batch;batch.reserve(170);
      for(const auto& s:stars) if(s.group==group) {
        float a=s.angle+turn*s.drift;
        batch.push_back({std::cos(a)*s.radius*scale,
          std::sin(a)*s.radius*scale*.49f+s.lift*scale});
      }
      Paint p;p.blend=Blend::plus;
      p.color=group%3==0?Color{.58f,.69f,1,.65f}:group%3==1?Color{1,.67f,.48f,.6f}:Color{.9f,.72f,1,.72f};
      c.points(batch,.55f+(group/3)*.5f,p);
    }
    Paint core=Paint::radial({0,0},scale*.28f,{Color{1,.87f,.68f,.92f},Color{.65f,.34f,.75f,.22f},Color{.2f,.1f,.6f,0}},{0,.22f,1});
    core.blend=Blend::screen;c.circle({0,0},scale*.28f,core);c.restore();
  }
};
