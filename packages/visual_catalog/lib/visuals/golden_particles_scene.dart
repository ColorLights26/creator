// Golden Drift — motas doradas que suben despacio como polvo encendido.
// Las partículas ascienden con un leve vaivén, en cuatro tamaños y tonos de
// oro. Cada impacto de la música las empuja hacia arriba y, además, Pulso
// decide qué se ve: con Golpes las motas se hinchan, se encienden y florecen
// en un halo de bokeh en cada golpe; con Graves el enjambre se abre, engorda y
// brilla con los graves; con Agudos la mitad de las motas centellea y tiembla.
// Sin música se ve igual que siempre.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // FORMA: cuántas motas suben.
  CreatorModifier.steps('motas', 'Motas', min: 60, max: 480, value: 240),
  // MOVIMIENTO: subida recta o serpenteante.
  CreatorModifier.slider('vaiven', 'Vaivén', min: 0, max: 4, value: 1),
  // MÚSICA
  CreatorModifier.choice(
    'pulso',
    'Pulso',
    options: ['Golpes', 'Graves', 'Agudos'],
  ),
  // ATMÓSFERA: una cola de luz bajo cada mota.
  CreatorModifier.slider('estela', 'Estela', min: 0, max: 1, value: 0),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Enjambre', {
    'motas': 480,
    'vaiven': 2.5,
    'pulso': 'Agudos',
    'estela': .35,
  }),
  CreatorVariation('Cometas Lentos', {
    'motas': 100,
    'vaiven': .3,
    'estela': 1,
    'pulso': 'Graves',
    'speed': .6,
  }),
];

const nativeSource = r'''
class Visual final : public Scene {
  struct Particle { float x,y,velocity,phase; };
  // Se reserva el máximo de Motas: cambiar el ajuste nunca reserva memoria.
  static constexpr int kMax=480;
  std::vector<Particle> particles;
  float impulse=0;
  // Música: envolventes suavizadas y golpe corto (valen 0 sin música).
  float bass=0,body=0,spark=0,energy=0,drive=0,slowBass=0,kick=0,flash=0;
  // Reloj propio para el centelleo de los agudos.
  double clock=0;
  static float follow(float v,float target,float up,float down,float dt){
    return v+(target-v)*(1.0f-std::exp(-(target>v?up:down)*dt));
  }
 public:
  void reset(uint32_t seed) override {
    Random r(seed);particles.clear();particles.reserve(kMax);impulse=0;
    bass=body=spark=energy=drive=slowBass=kick=flash=0;clock=0;
    // Las primeras 240 son las de siempre; las demás sólo aparecen con Motas.
    for(int i=0;i<kMax;i++)particles.push_back({r.unit(),r.unit(),.02f+r.unit()*.03f,r.unit()*6.28f});
  }
  void update(const Frame& f) override {
    for(const auto& event:f.music.events[0])impulse=std::max(impulse,event.strength);
    impulse*=float(std::exp(-f.delta*2.2));
    for(auto& p:particles){p.y-=p.velocity*float(f.delta)*f.speed*(1+impulse*3);
      if(p.y<-.03f)p.y+=1.06f;p.phase+=float(f.delta)*.3f;}
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
    // Motas: cuántas se dibujan de las reservadas (240 es el original).
    const int visible=std::clamp(int(g.motas),0,kMax);
    // Vaivén: 0 sube recto, 1 es el original, 4 serpentea ancho y apretado.
    const float sway=g.vaiven;
    const float curl=1+(sway-1)*.5f;
    const float trail=std::clamp(g.estela,0.0f,1.0f);
    const float tick=float(std::fmod(clock,1000.0));
    for(int group=0;group<4;group++){
      std::vector<Vec2> points;points.reserve(size_t(visible/4+1));
      for(int i=group;i<visible;i+=4){const auto& p=particles[size_t(i)];
        // Graves abre el enjambre desde el centro; Agudos lo hace temblar.
        const float open=(p.x-.5f)*graves*.12f;
        const float jx=std::sin(tick*41.0f+float(i)*2.3f)*agudos*.004f;
        const float jy=std::cos(tick*37.0f+float(i)*1.7f)*agudos*.003f;
        points.push_back({(p.x+std::sin(p.phase+p.y*3*curl)*.02f*sway+open+jx)*f.width,(p.y+jy)*f.height});}
      // Golpes enciende las motas; Agudos las hace titilar por grupos.
      const float twinkle=.5f+.5f*std::sin(tick*9.0f+float(group)*1.7f);
      const float alpha=std::min(1.0f,.35f+group*.16f+golpe*.6f+agudos*twinkle*.35f);
      // Golpes las hincha un 20%; Graves, un 15% que respira.
      const float size=(.8f+group*.45f+impulse*.4f)*(1+golpe*.2f+graves*.15f);
      if(trail>.001f){
        // Estela: una cola de luz bajo cada mota que dibuja su vaivén; la
        // mitad cercana brilla más que la lejana.
        Path near,far;
        for(int i=group;i<visible;i+=4){const auto& p=particles[size_t(i)];
          const float open=(p.x-.5f)*graves*.12f;
          for(int k=0;k<=4;k++){
            const float y=p.y+float(k)*(.01f+p.velocity*.6f)*trail;
            const Vec2 q{(p.x+std::sin(p.phase+y*3*curl)*.02f*sway+open)*f.width,y*f.height};
            if(k==0)near.moveTo(q.x,q.y);else if(k<=2)near.lineTo(q.x,q.y);
            if(k==2)far.moveTo(q.x,q.y);else if(k>2)far.lineTo(q.x,q.y);
          }
        }
        Paint tp;tp.blend=Blend::plus;tp.strokeWidth=size*1.1f;tp.strokeCap=1;tp.strokeJoin=1;
        tp.color={1,.6f+group*.05f,.2f+group*.1f,std::min(1.0f,alpha*trail*.2f)};
        c.path(far,tp);
        tp.color.a=std::min(1.0f,alpha*trail*.45f);
        c.path(near,tp);
      }
      // Golpes y Graves: cada mota florece en un halo de luz, como un bokeh.
      const float bloom=std::min(1.0f,(golpe*.4f+graves*.25f)*f.glow);
      if(bloom>.001f){
        Paint halo;halo.blend=Blend::plus;halo.color={1,.6f+group*.05f,.25f+group*.1f,bloom};
        c.points(points,size*6.0f,halo);
      }
      Paint paint;paint.blend=Blend::plus;paint.color={1,.65f+group*.05f,.25f+group*.12f,alpha};
      c.points(points,size,paint);
      if(agudos>.001f){
        // Agudos: la mitad de las motas centellea, cada una a su ritmo.
        std::vector<Vec2> lit;lit.reserve(points.size());
        for(size_t k=0;k<points.size();k++)
          if(std::sin(tick*11.0f+float(k*4+size_t(group))*2.39f)>0.0f)lit.push_back(points[k]);
        Paint sp;sp.blend=Blend::plus;sp.color={1,.85f,.6f,std::min(1.0f,agudos*.3f*f.glow)};
        c.points(lit,size*4.5f,sp);
        sp.color={1,.92f,.75f,std::min(1.0f,agudos)};
        c.points(lit,size*2.0f,sp);
      }
    }
  }
};
''';
