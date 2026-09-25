// Programa de ejemplo. Metadata en el archivo compañero.
const nativeSource = r'''
class Visual final : public Scene {
  float road=0;
 public:
  void reset(uint32_t) override {road=0;}
  void update(const Frame& f) override {road+=float(f.delta)*f.speed*.18f;}
  void render(const Frame& f, Canvas& c) const override {
    float w=f.width,h=f.height,horizon=h*.61f;
    c.rect({0,0,w,h},Paint::linear({0,0},{0,h},
      {Color::argb(0xff050722),Color::argb(0xff391b58),Color::argb(0xffee487b),Color::argb(0xff070614)},{0,.38f,.61f,.85f}));
    float radius=w*.27f; Vec2 sun={w*.5f,h*.39f};
    Path cut;cut.fillRule=FillRule::evenOdd;cut.circle(sun,radius);
    for(int i=0;i<8;i++) {float y=sun.y+radius*(-.1f+i*.14f);cut.rect({sun.x-radius,y,radius*2,2+i*1.2f});}
    c.save();c.clip(cut);
    Path within;within.circle(sun,radius);c.clip(within);
    c.rect({sun.x-radius,sun.y-radius,radius*2,radius*2},Paint::linear({0,sun.y-radius},{0,sun.y+radius},
      {Color::argb(0xfffff39d),Color::argb(0xffff7770),Color::argb(0xffff2cbd)}));c.restore();
    Paint mountain;mountain.color=Color::argb(0xff0a0b27);
    Path ridge;ridge.moveTo(0,horizon).lineTo(0,horizon-25).lineTo(w*.13f,horizon-95)
      .lineTo(w*.27f,horizon-45).lineTo(w*.4f,horizon-100).lineTo(w*.6f,horizon-22)
      .lineTo(w*.83f,horizon-116).lineTo(w,horizon-41).lineTo(w,horizon).close();c.path(ridge,mountain);
    Paint ground;ground.color=Color::argb(0xff080715);c.rect({0,horizon,w,h-horizon},ground);
    c.saveLayer(.65f+f.music.bass*.25f,Blend::screen);
    Paint grid;grid.color=Color{.55f,.2f,1,1};grid.strokeWidth=1;
    for(int i=-10;i<=10;i++){Path p;p.moveTo(w*.5f+i*5,horizon).lineTo(w*.5f+i*w*.22f,h);c.path(p,grid);}
    for(int i=0;i<18;i++){float t=std::fmod(i/18.f+road,1.f);float y=horizon+t*t*(h-horizon);Path p;p.moveTo(0,y).lineTo(w,y);c.path(p,grid);}
    c.restore();
    Paint glow=Paint::radial({w*.5f,horizon},w*.6f,{Color{1,.12f,.48f,.22f},Color{1,0,.4f,0}});glow.blend=Blend::screen;
    c.rect({0,horizon-w*.2f,w,w*.4f},glow);
  }
};
''';
