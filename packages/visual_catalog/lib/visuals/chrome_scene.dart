// Programa de ejemplo. Metadata en el archivo compañero.
const nativeSource = r'''
class Visual final : public Scene {
 public:
  void reset(uint32_t) override {}
  void update(const Frame&) override {}
  void render(const Frame& f, Canvas& c) const override {
    c.material("chrome",{0,0,f.width,f.height},{float(f.time)*f.speed,f.music.bass});
    c.saveLayer(.32f,Blend::screen);
    Paint p;p.color={.7f,.83f,1,.65f};p.strokeWidth=.8f;
    for(int i=0;i<4;i++) {
      float x=f.width*(.16f+i*.23f);
      Path path;path.moveTo(x,0).cubicTo(x+35,f.height*.28f,x-40,f.height*.75f,x,f.height);
      c.path(path,p);
    }
    c.restore();
  }
};
''';

const shaderSources = <String, String>{
  'chrome': r'''
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform float uTime;
uniform float uBass;
out vec4 fragColor;
float field(vec2 p) {
  float sum=0.;
  for(int i=0;i<7;i++) {
    float k=float(i);
    vec2 center=vec2(sin(uTime*.31+k*2.4),cos(uTime*.23+k*1.7))*.47;
    vec2 d=p-center;
    sum+=(.026+.006*sin(k+uTime*.2))/(dot(d,d)+.013);
  }
  return sum;
}
void main() {
  vec2 p=(FlutterFragCoord().xy/uSize-.5)*vec2(uSize.x/uSize.y,1.)*2.;
  float v=field(p),e=.004;
  vec2 g=vec2(field(p+vec2(e,0))-field(p-vec2(e,0)),field(p+vec2(0,e))-field(p-vec2(0,e)));
  vec3 n=normalize(vec3(-g*12.,.45));
  float rim=pow(1.-max(n.z,0.),2.);
  float stripe=.5+.5*sin(n.x*8.+n.y*4.+uTime*.09);
  vec3 metal=mix(vec3(.025,.04,.075),vec3(.77,.86,.94),smoothstep(.35,.7,stripe));
  metal+=pow(max(dot(n,normalize(vec3(-.5,-.6,1.))),0.),55.)*1.8;
  metal+=rim*vec3(.18,.35,.5);
  metal+=vec3(.24,.07,.3)*pow(max(n.y,0.),4.);
  float shape=smoothstep(.86-uBass*.06,.91-uBass*.06,v);
  vec3 bg=vec3(.018,.022,.038)+.02*exp(-dot(p,p));
  fragColor=vec4(mix(bg,metal,shape),1.);
}
''',
};
