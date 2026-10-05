// Spiral Galaxy — una galaxia espiral que gira despacio sobre el vacío.
// 1500 estrellas en cuatro brazos, con un núcleo cálido y una bruma violeta.
// La energía de la música ya la hacía respirar y Pulso decide qué más se
// ve: con Golpes el centro estalla en un resplandor cálido y las estrellas
// destellan y se hinchan en cada golpe; con Graves la galaxia crece y
// respira con un halo violeta; con Agudos los grupos de estrellas
// centellean de brillo y de tamaño. Sin música se ve igual que siempre.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // FORMA: cuántos brazos tiene la espiral.
  CreatorModifier.steps('brazos', 'Brazos', min: 2, max: 8, value: 4),
  // MÚSICA
  CreatorModifier.choice(
    'pulso',
    'Pulso',
    options: ['Golpes', 'Graves', 'Agudos'],
  ),
  // ATMÓSFERA: de estrellas nítidas a una nebulosa difusa que brilla.
  CreatorModifier.slider('nebulosa', 'Nebulosa', min: 0, max: 1, value: 0),
  // MODO: un gemelo reflejado convierte la espiral en mariposa.
  CreatorModifier.toggle('espejo', 'Espejo', value: false),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Mariposa', {
    'espejo': true,
    'brazos': 2,
    'nebulosa': .45,
    'pulso': 'Graves',
  }),
  CreatorVariation('Nebulosa Viva', {
    'brazos': 6,
    'nebulosa': 1,
    'pulso': 'Agudos',
    'speed': 1.5,
  }),
];

const nativeSource = r'''
class Visual final : public Scene {
  struct Star { float radius, angle, lift, drift; int group; float spread; };
  std::vector<Star> stars;
  float turn = 0, breath = 0;
  // Música: envolventes suavizadas y golpe corto (valen 0 sin música).
  float bass = 0, body = 0, spark = 0, energy = 0, drive = 0, slowBass = 0, kick = 0, flash = 0;
  // Reloj propio para el centelleo de los agudos.
  double clock = 0;
  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }
  // Ángulo del brazo de la estrella i cuando la espiral tiene `arms` brazos.
  static float armAngle(size_t i, int arms) {
    return float(double(int(i % size_t(arms))) * pi * 2 / double(arms));
  }
 public:
  void reset(uint32_t seed) override {
    Random rng(seed); stars.clear(); stars.reserve(1500); turn=0; breath=0;
    bass = body = spark = energy = drive = slowBass = kick = flash = 0; clock = 0;
    for(int i=0;i<1500;i++) {
      float r=std::sqrt(rng.unit()); int arm=i%4;
      // El desorden de cada estrella se guarda aparte: con más brazos se aprieta.
      const float spread=(rng.unit()-.5f)*(.25f+r*.8f);
      stars.push_back({r, float(arm*pi/2)+r*5.8f+spread,
        (rng.unit()-.5f)*(.018f+r*.035f), .7f+rng.unit()*.6f, i%9, spread});
    }
  }
  void update(const Frame& f) override {
    turn += float(f.delta)*f.speed*.06f;
    float target=f.music.energy;
    breath += (target-breath)*float(1-std::exp(-f.delta*3));
    // Música estándar: graves, cuerpo, agudos, energía y golpe corto.
    const float dt = float(f.delta);
    const Music& mu = f.music;
    bass = follow(bass, mu.bass, 22.0f, 4.5f, dt);
    body = follow(body, mu.body, 12.0f, 3.0f, dt);
    spark = follow(spark, mu.spark, 30.0f, 7.0f, dt);
    energy = follow(energy, mu.energy, 6.0f, 1.8f, dt);
    drive = follow(drive, mu.active ? std::pow(std::clamp(mu.energy, 0.0f, 1.0f), 0.8f) : 0.0f, 3.0f, 0.7f, dt);
    float hit = 0, fl = 0;
    for (const auto& e : mu.events[0]) hit = std::max(hit, e.strength);
    for (const auto& e : mu.events[2]) hit = std::max(hit, e.strength * 0.85f);
    for (const auto& e : mu.events[3]) fl = std::max(fl, e.strength);
    const float onset = std::clamp((mu.bass - slowBass - 0.15f) * 2.5f, 0.0f, 1.0f);
    slowBass = follow(slowBass, mu.bass, 3.0f, 3.0f, dt);
    hit = std::min(std::max(hit, onset), 1.0f);
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    clock += f.delta * f.speed;
  }
  void render(const Frame& f, Canvas& c) const override {
    auto g = glide(f);
    const float amp = f.intensity;
    // Pulso: cada opción mueve algo distinto y sus pesos mezclan las opciones.
    const float golpe = g.pulso.weight(0) * std::min(kick * amp, 1.0f);
    const float graves = g.pulso.weight(1) * std::min(bass * amp, 1.0f);
    const float agudos = g.pulso.weight(2) * std::min(spark * amp, 1.0f);
    Paint sky=Paint::radial({f.width*.5f,f.height*.47f},f.height*.75f,
      {Color::argb(0xff151031),Color::argb(0xff03040d)});
    c.rect({0,0,f.width,f.height},sky);
    c.save(); c.translate(f.width*.5f,f.height*.48f); c.rotate(-.38f);
    // Graves: la galaxia crece hasta un 12% más con los graves.
    float scale=std::min(f.width*.62f,f.height*.42f)*(1+breath*.045f)*(1+graves*.12f);
    Paint haze=Paint::radial({0,0},scale*.8f,{Color{.24f,.1f,.5f,.2f},Color{.08f,.02f,.3f,0}});
    haze.blend=Blend::plus; c.rect({-scale,-scale,scale*2,scale*2},haze);
    // Golpes: el centro estalla en un resplandor cálido; Graves: un halo
    // violeta que respira alrededor de los brazos.
    const float burst = std::min(1.0f, (.55f * golpe) * f.glow);
    const float swell = std::min(1.0f, (.35f * graves) * f.glow);
    if (burst + swell > .001f) {
      Paint light = Paint::radial({0, 0}, scale * (1.1f + swell * .3f),
        {Color{1, .8f, .62f, std::min(1.0f, burst + swell * .5f)}, Color{.7f, .45f, 1, std::min(1.0f, burst * .35f + swell * .6f)},
         Color{.3f, .15f, .7f, 0}}, {0, .35f, 1});
      light.blend = Blend::plus;
      c.circle({0, 0}, scale * (1.1f + swell * .3f), light);
    }
    const float neb = std::clamp(g.nebulosa, 0.0f, 1.0f);
    if (neb > .001f) {
      // Nebulosa: una bruma de color envuelve los brazos.
      Paint mist = Paint::radial({0, 0}, scale * (.7f + neb * .4f),
        {Color{.55f, .3f, .95f, .3f * neb}, Color{.95f, .45f, .6f, .12f * neb}, Color{.2f, .1f, .6f, 0}}, {0, .5f, 1});
      mist.blend = Blend::plus;
      c.rect({-scale * 1.2f, -scale * 1.2f, scale * 2.4f, scale * 2.4f}, mist);
    }
    // Brazos se desliza (5.4 brazos): cada estrella va de su brazo entre N al
    // de N+1, así los brazos se abren sin saltos. Con 4 queda el original.
    const int fewer = int(std::floor(g.brazos)), more = fewer + 1;
    const float between = g.brazos - float(fewer);
    const bool reshaped = g.brazos != 4.0f;
    // Con más de 4 brazos el desorden se estrecha para que no se mezclen.
    const float tighten = std::min(1.0f, 4.0f / g.brazos);
    const float mirror = std::clamp(g.espejo, 0.0f, 1.0f);
    const float tick = float(std::fmod(clock, 1000.0));
    for(int group=0;group<9;group++) {
      std::vector<Vec2> batch;batch.reserve(170);
      std::vector<Vec2> twin;
      if (mirror > 0) twin.reserve(170);
      for(size_t i=0;i<stars.size();i++) { const auto& s=stars[i]; if(s.group!=group) continue;
        float a=s.angle+turn*s.drift;
        if (reshaped) {
          const float from = armAngle(i, fewer), to = armAngle(i, more);
          a += from + (to - from) * between - float(int(i % 4)*pi/2) + s.spread * (tighten - 1.0f);
        }
        const Vec2 point{std::cos(a)*s.radius*scale,
          std::sin(a)*s.radius*scale*.49f+s.lift*scale};
        batch.push_back(point);
        if (mirror > 0) twin.push_back({-point.x, point.y});
      }
      Paint p;p.blend=Blend::plus;
      p.color=group%3==0?Color{.58f,.69f,1,.65f}:group%3==1?Color{1,.67f,.48f,.6f}:Color{.9f,.72f,1,.72f};
      // Golpes enciende las estrellas; Agudos las hace centellear por grupos.
      const float twinkle = .5f + .5f * std::sin(tick * 9.0f + float(group) * 1.7f);
      p.color.a = std::min(1.0f, p.color.a * (1 - neb * .35f) + golpe * .6f + graves * .25f + agudos * twinkle * .7f);
      // Nebulosa hace las estrellas difusas; Golpes las hincha un 20%, Graves
      // un 15% y Agudos las hace parpadear de tamaño.
      const float size = (.55f+(group/3)*.5f) * (1 + neb * 1.2f + golpe * .2f + graves * .15f + agudos * twinkle * .5f);
      c.points(batch,size,p);
      if (mirror > 0) {
        // Espejo: el gemelo reflejado se funde poco a poco.
        p.color.a *= mirror;
        c.points(twin, size, p);
      }
    }
    // Golpes: el núcleo late hasta un 18% más grande.
    const float coreR = scale*.28f*(1+golpe*.18f);
    Paint core=Paint::radial({0,0},coreR,{Color{1,.87f,.68f,.92f},Color{.65f,.34f,.75f,.22f},Color{.2f,.1f,.6f,0}},{0,.22f,1});
    core.blend=Blend::screen;c.circle({0,0},coreR,core);c.restore();
  }
};
''';
