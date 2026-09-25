const nativeSource = r'''
class Visual final : public Scene {
 public:
  void reset(uint32_t) override {} void update(const Frame&) override {}
  void render(const Frame& f, Canvas& c) const override {
    c.scale(f.width/320,f.height/568);
    Paint p;p.color={0,0,0,1};c.rect({0,0,320,568},p);
    c.image("checker",{0,0,80,80});
    c.material("sample",{80,0,80,80},{1},{"checker"});
    c.saveLayer(.5f);p.color={1,0,0,1};
    c.rect({0,100,60,60},p);c.rect({20,120,60,60},p);c.restore();
    c.save();Path clip;clip.moveTo(100,100).lineTo(180,100).lineTo(180,180).lineTo(100,180).close();
    c.clip(clip);c.save();Path inner;inner.moveTo(120,100).lineTo(180,100).lineTo(180,180).lineTo(120,180).close();c.clip(inner);
    Path holes;holes.fillRule=FillRule::evenOdd;holes.moveTo(100,100).lineTo(180,100).lineTo(180,180).lineTo(100,180).close();
    holes.moveTo(130,130).lineTo(150,130).lineTo(150,150).lineTo(130,150).close();
    p.color={1,1,1,1};c.path(holes,p);c.restore();c.restore();
    p.blend=Blend::plus;p.color={.25f,0,0,1};c.rect({0,200,80,80},p);
    p.color={0,.25f,0,1};c.rect({0,200,80,80},p);
    p.blend=Blend::screen;p.color={.5f,0,0,1};c.rect({80,200,80,80},p);
    p.color={0,.5f,0,1};c.rect({80,200,80,80},p);
  }
};
''';
const shaderSources = <String, String>{
  'sample': r'''
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform float uOpacity;
uniform sampler2D uImage;
out vec4 fragColor;
void main(){fragColor=texture(uImage,FlutterFragCoord().xy/uSize)*uOpacity;}
''',
};
