// Midnight Highway — carretera synthwave hacia un sol rayado de neón.
// Un sol a franjas se hunde tras las montañas mientras la rejilla violeta
// corre hacia el horizonte. Los graves ya encendían la rejilla y Pulso
// decide qué más se ve: con Golpes el sol late con un resplandor cálido
// detrás y la rejilla y el horizonte se encienden en cada golpe; con Graves
// el sol respira con un halo rosa y la rejilla se engrosa; con Agudos titilan
// muchas chispas en los cruces de la rejilla. Sin música se ve igual que
// siempre.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // FORMA: cuántas franjas cortan el sol.
  CreatorModifier.steps('franjas', 'Franjas del sol', min: 3, max: 14, value: 8),
  // MOVIMIENTO: carretera recta, curvas que serpentean u olas en el suelo.
  CreatorModifier.choice(
    'camino',
    'Camino',
    options: ['Recto', 'Curvas', 'Olas'],
  ),
  // MÚSICA
  CreatorModifier.choice(
    'pulso',
    'Pulso',
    options: ['Golpes', 'Graves', 'Agudos'],
  ),
  // ATMÓSFERA: niebla de neón sobre el horizonte.
  CreatorModifier.slider('bruma', 'Bruma', min: 0, max: 1, value: 0),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Carretera Infinita', {
    'camino': 'Curvas',
    'franjas': 12,
    'pulso': 'Golpes',
    'speed': 1.5,
  }),
  CreatorVariation('Mar de Neón', {
    'camino': 'Olas',
    'franjas': 4,
    'bruma': .8,
    'pulso': 'Graves',
  }),
];

const nativeSource = r'''
class Visual final : public Scene {
  float road=0;
  // Música: envolventes suavizadas y golpe corto (valen 0 sin música).
  float bass=0,body=0,spark=0,energy=0,drive=0,slowBass=0,kick=0,flash=0;
  // Reloj propio para las chispas de los agudos.
  double clock=0;
  static float follow(float v,float target,float up,float down,float dt){
    return v+(target-v)*(1.0f-std::exp(-(target>v?up:down)*dt));
  }
  static float hashU(uint32_t x){
    x^=x>>16;x*=0x7feb352dU;x^=x>>15;x*=0x846ca68bU;x^=x>>16;
    return float(x&0xffffffu)/16777216.0f;
  }
 public:
  void reset(uint32_t) override {road=0;bass=body=spark=energy=drive=slowBass=kick=flash=0;clock=0;}
  void update(const Frame& f) override {road+=float(f.delta)*f.speed*.18f;
    // Música estándar: graves, cuerpo, agudos, energía y golpe corto.
    const float dt=float(f.delta);
    const Music& mu=f.music;
    bass=follow(bass,mu.bass,22.0f,4.5f,dt);
    body=follow(body,mu.body,12.0f,3.0f,dt);
    spark=follow(spark,mu.spark,30.0f,7.0f,dt);
    energy=follow(energy,mu.energy,6.0f,1.8f,dt);
    drive=follow(drive,mu.active?std::pow(std::clamp(mu.energy,0.0f,1.0f),0.8f):0.0f,3.0f,0.7f,dt);
    float hit=0,fl=0;
    for(const auto& e:mu.events[0])hit=std::max(hit,e.strength);
    for(const auto& e:mu.events[2])hit=std::max(hit,e.strength*0.85f);
    for(const auto& e:mu.events[3])fl=std::max(fl,e.strength);
    const float onset=std::clamp((mu.bass-slowBass-0.15f)*2.5f,0.0f,1.0f);
    slowBass=follow(slowBass,mu.bass,3.0f,3.0f,dt);
    hit=std::min(std::max(hit,onset),1.0f);
    kick=std::max(kick*std::exp(-dt*5.0f),hit);
    flash=std::max(flash*std::exp(-dt*8.0f),std::min(fl,1.0f));
    clock+=f.delta*f.speed;
  }
  void render(const Frame& f, Canvas& c) const override {
    auto g=glide(f);
    const float amp=f.intensity;
    // Pulso: cada opción mueve algo distinto y sus pesos mezclan las opciones.
    const float golpe=g.pulso.weight(0)*std::min(kick*amp,1.0f);
    const float graves=g.pulso.weight(1)*std::min(bass*amp,1.0f);
    const float agudos=g.pulso.weight(2)*std::min(spark*amp,1.0f);
    float w=f.width,h=f.height,horizon=h*.61f;
    c.rect({0,0,w,h},Paint::linear({0,0},{0,h},
      {Color::argb(0xff050722),Color::argb(0xff391b58),Color::argb(0xffee487b),Color::argb(0xff070614)},{0,.38f,.61f,.85f}));
    // Golpes: el sol late en cada golpe (+15%); Graves lo hace respirar (+12%).
    float radius=w*.27f*(1+golpe*.15f+graves*.12f); Vec2 sun={w*.5f,h*.39f};
    if(graves>.001f){
      // Graves: un halo rosa respira alrededor del sol.
      const float reach=radius*(1.3f+graves*.5f);
      Paint halo=Paint::radial(sun,reach,{Color{1,.45f,.55f,std::min(1.0f,.7f*graves)},Color{1,.2f,.6f,.3f*graves},Color{1,.1f,.5f,0}},{.55f,.78f,1});
      halo.blend=Blend::screen;c.circle(sun,reach,halo);
    }
    if(golpe>.001f){
      // Golpes: un resplandor cálido estalla detrás del sol en cada golpe y
      // se cuela entre sus franjas.
      const float flare=std::min(1.0f,.6f*golpe*f.glow);
      Paint burst=Paint::radial(sun,radius*2.6f,{Color{1,.7f,.5f,flare},Color{1,.45f,.55f,flare*.6f},Color{1,.2f,.5f,0}},{0,.4f,1});
      burst.blend=Blend::plus;c.circle(sun,radius*2.6f,burst);
    }
    Path cut;cut.fillRule=FillRule::evenOdd;cut.circle(sun,radius);
    // Franjas del sol: pocas y anchas o muchas y finas (8 es el original).
    const float bands=g.franjas;
    const int whole=int(bands);const float part=bands-float(whole);
    const float gap=.14f*8.0f/bands,ratio=8.0f/bands,thick=ratio*ratio;
    for(int i=0;i<whole+(part>.001f?1:0);i++) {float y=sun.y+radius*(-.1f+i*gap);cut.rect({sun.x-radius,y,radius*2,(2+i*1.2f)*thick*(i<whole?1.0f:part)});}
    c.save();c.clip(cut);
    Path within;within.circle(sun,radius);c.clip(within);
    c.rect({sun.x-radius,sun.y-radius,radius*2,radius*2},Paint::linear({0,sun.y-radius},{0,sun.y+radius},
      {Color::argb(0xfffff39d),Color::argb(0xffff7770),Color::argb(0xffff2cbd)}));c.restore();
    Paint mountain;mountain.color=Color::argb(0xff0a0b27);
    Path ridge;ridge.moveTo(0,horizon).lineTo(0,horizon-25).lineTo(w*.13f,horizon-95)
      .lineTo(w*.27f,horizon-45).lineTo(w*.4f,horizon-100).lineTo(w*.6f,horizon-22)
      .lineTo(w*.83f,horizon-116).lineTo(w,horizon-41).lineTo(w,horizon).close();c.path(ridge,mountain);
    Paint ground;ground.color=Color::argb(0xff080715);c.rect({0,horizon,w,h-horizon},ground);
    c.saveLayer(std::min(1.0f,.65f+f.music.bass*.25f+golpe*.35f),Blend::screen);
    // Golpes engrosa un instante la rejilla (×2,5); Graves, despacio (×1,6).
    Paint grid;grid.color=Color{.55f,.2f,1,1};grid.strokeWidth=1+golpe*1.5f+graves*.6f;
    // Camino: Curvas hace serpentear la carretera; Olas hace ondular el suelo.
    const float curve=g.camino.weight(1),waves=g.camino.weight(2);
    const float bend=std::sin(road*1.9f)*w*.32f*curve;
    for(int i=-10;i<=10;i++){Path p;p.moveTo(w*.5f+i*5,horizon);
      if(curve>.001f)p.quadraticTo(w*.5f+i*(5+w*.22f)*.5f+bend,(horizon+h)*.5f,w*.5f+i*w*.22f,h);
      else p.lineTo(w*.5f+i*w*.22f,h);
      c.path(p,grid);}
    // Altura de una ola en x para la línea i a profundidad t.
    auto swell=[&](float x,int i,float t){
      return t*t*(h-horizon)*.09f*waves*(.5f+.5f*std::sin(x/w*13.2f+float(i)*1.3f+road*4.0f));
    };
    for(int i=0;i<18;i++){float t=std::fmod(i/18.f+road,1.f);float y=horizon+t*t*(h-horizon);Path p;
      if(waves>.001f){
        for(int k=0;k<=24;k++){const float x=w*float(k)/24.0f;
          if(k==0)p.moveTo(x,y-swell(x,i,t));else p.lineTo(x,y-swell(x,i,t));}
      }else p.moveTo(0,y).lineTo(w,y);
      c.path(p,grid);}
    c.restore();
    if(agudos>.001f){
      // Agudos: chispas que titilan en los cruces de la rejilla.
      std::vector<Vec2> sparks;sparks.reserve(96);
      const uint32_t beat=uint32_t(std::fmod(clock*12.0,1.0e6));
      for(int j=0;j<18;j++){float t=std::fmod(j/18.f+road,1.f);float y=horizon+t*t*(h-horizon);
        const float u=(y-horizon)/(h-horizon);
        // Cerca del horizonte las líneas se apiñan: allí saltan menos chispas.
        for(int i=-10;i<=10;i++){
          if(hashU(uint32_t(j*21+i+10)*2654435761u^beat*0x9e3779b9u)>.25f+.45f*u)continue;
          const float x0=w*.5f+i*5,x2=w*.5f+i*w*.22f,x1=w*.5f+i*(5+w*.22f)*.5f+bend;
          const float x=(1-u)*(1-u)*x0+2*u*(1-u)*x1+u*u*x2;
          sparks.push_back({x,y-swell(x,j,t)});
        }
      }
      Paint sp;sp.blend=Blend::plus;sp.color=Color{1,.5f,.9f,std::min(1.0f,agudos*.3f*f.glow)};
      c.points(sparks,(1.8f+agudos*2.0f)*2.2f,sp);
      sp.color=Color{1,.82f,.97f,std::min(1.0f,agudos)};
      c.points(sparks,1.8f+agudos*2.0f,sp);
    }
    // Graves hace crecer el resplandor del horizonte; Golpes lo enciende.
    Paint glow=Paint::radial({w*.5f,horizon},w*.6f*(1+graves*.3f),{Color{1,.12f,.48f,std::min(1.0f,.22f+graves*.3f+golpe*.35f)},Color{1,0,.4f,0}});glow.blend=Blend::screen;
    c.rect({0,horizon-w*.2f,w,w*.4f},glow);
    const float fog=std::clamp(g.bruma,0.0f,1.0f);
    if(fog>.001f){
      // Bruma: niebla de neón posada sobre el horizonte.
      Paint mist=Paint::linear({0,horizon-h*.2f},{0,horizon+h*.3f},
        {Color{1,.3f,.62f,0},Color{1,.32f,.6f,.5f*fog},Color{.6f,.2f,.9f,.2f*fog},Color{.4f,.1f,.7f,0}},{0,.42f,.7f,1});
      mist.blend=Blend::screen;
      c.rect({0,horizon-h*.2f,w,h*.5f},mist);
    }
  }
};
''';
