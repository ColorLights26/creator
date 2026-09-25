// Programa de ejemplo. Metadata en el archivo compañero.
const nativeSource = r'''
class Visual final : public Scene {
  struct Particle { float x,y,velocity,phase; };
  std::vector<Particle> particles;
  float impulse=0;
 public:
  void reset(uint32_t seed) override {
    Random r(seed);particles.clear();impulse=0;
    for(int i=0;i<240;i++)particles.push_back({r.unit(),r.unit(),.02f+r.unit()*.03f,r.unit()*6.28f});
  }
  void update(const Frame& f) override {
    for(const auto& event:f.music.events[0])impulse=std::max(impulse,event.strength);
    impulse*=float(std::exp(-f.delta*2.2));
    for(auto& p:particles){p.y-=p.velocity*float(f.delta)*f.speed*(1+impulse*3);
      if(p.y<-.03f)p.y+=1.06f;p.phase+=float(f.delta)*.3f;}
  }
  void render(const Frame& f, Canvas& c) const override {
    for(int group=0;group<4;group++){
      std::vector<Vec2> points;
      for(size_t i=group;i<particles.size();i+=4){const auto& p=particles[i];
        points.push_back({(p.x+std::sin(p.phase+p.y*3)*.02f)*f.width,p.y*f.height});}
      Paint paint;paint.blend=Blend::plus;paint.color={1,.65f+group*.05f,.25f+group*.12f,.35f+group*.16f};
      c.points(points,.8f+group*.45f+impulse*.4f,paint);
    }
  }
};
''';
