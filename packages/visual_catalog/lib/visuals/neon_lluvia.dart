// Neón bajo la Lluvia — puerto de la galería FLUX/10 al motor nativo.
// Cuatro capas de skyline en perspectiva con ventanas encendidas, reflejo mojado
// invertido, rótulos de neón con parpadeo y 380 gotas de lluvia. El skyline se
// dibuja con vectores y puntos, sin imágenes horneadas.
// Música: la energía y los graves animan la lluvia y la ciudad. Pulso elige
// el resto: Golpes hace estallar los rótulos de neón, enciende las ventanas
// y alarga las gotas en cada golpe; Graves levanta y espesa la niebla y
// agranda las ventanas despacio; Agudos hace parpadear ventanas sueltas.
// Además, cada opción de Pulso enciende un resplandor local sobre
// la ciudad y sus rótulos, que late con la música (nunca un velo a pantalla completa).
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // FORMA: llovizna de puntos o largos hilos de agua.
  CreatorModifier.slider('gotas', 'Largo de las gotas', min: .4, max: 3, value: 1),
  // MOVIMIENTO: lluvia vertical o temporal que la inclina.
  CreatorModifier.slider('viento', 'Viento', min: 0, max: 1, value: 0),
  // MÚSICA
  CreatorModifier.choice(
    'pulso',
    'Pulso',
    options: ['Golpes', 'Graves', 'Agudos'],
  ),
  // ATMÓSFERA: la niebla que se posa sobre el horizonte.
  CreatorModifier.slider('niebla', 'Niebla', min: 0, max: 2.5, value: 1),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Temporal', {
    'viento': .8,
    'gotas': 1.8,
    'pulso': 'Golpes',
    'speed': 1.3,
  }),
  CreatorVariation('Bruma Nocturna', {
    'niebla': 2.2,
    'gotas': .6,
    'pulso': 'Graves',
  }),
];

const nativeSource = r'''
class Visual final : public Scene {
  struct Bld { float x, w, h; };
  struct Win { float x, y; };
  struct Layer { std::vector<Bld> blds; std::vector<Win> wins;
                 float speed, shade, depth, height; };
  std::vector<Layer> layers;
  struct Drop { float x, y, v, len; };
  std::vector<Drop> drops;
  float lastw = 0, lasth = 0, lastDetail = -1.0f;
  static float hash01(int i, int salt) {
    float s = std::sin(float(i) * 12.9898f + float(salt) * 78.233f) * 43758.5453f;
    return s - std::floor(s);
  }
  void build(float w, float h, float detail) {
    float horizon = h * 0.66f;
    layers.clear();
    for (int li = 0; li < 4; li++) {
      Layer L;
      L.depth = float(li) / 3.0f;
      L.speed = 3.0f + L.depth * 22.0f;
      int sh = 10 + int((1.0f - L.depth) * 22.0f);
      L.shade = float(sh);
      L.height = horizon * (0.32f + L.depth * 0.66f);
      int steps = int(w / 30.0f) + 6;
      if (steps > 48) steps = 48;
      // El paso de la ventana escala con la altura de la capa: en pantallas
      // grandes el número de puntos se disparaba y reventaba el presupuesto
      // de 1 MiB de comandos del motor.
      float wyStep = std::max(9.0f, L.height / 40.0f);
      // El paso horizontal sigue a la pantalla para que el skyline siempre la
      // cubra entera, tenga el ancho que tenga.
      float xStep = w / float(steps);
      for (int i = 0; i < steps; i++) {
        Bld b;
        b.x = (float(i) + hash01(i, li) * 0.6f) * xStep;
        b.w = xStep * (0.5f + hash01(i, li + 91) * 1.5f) * (0.5f + L.depth * 0.5f);
        b.h = L.height * (0.28f + hash01(i, li + 173) * 0.72f);
        L.blds.push_back(b);
        if (L.depth > 0.35f) {
          float top = L.height - b.h;
          float wxStep = std::max(7.0f, b.w / 8.0f);
          for (float wy = 6.0f; wy < b.h - 8.0f; wy += wyStep) {
            for (float wx = 3.0f; wx < b.w - 6.0f; wx += wxStep) {
              if (hash01(int(wx) * 7 + int(wy) * 13, li + 311) > 0.62f)
                L.wins.push_back({b.x + wx, top + wy});
            }
          }
        }
      }
      layers.push_back(L);
    }
    int ndrops = int(380.0f * std::min(1.0f, std::max(0.4f, detail)));
    drops.clear(); drops.reserve(ndrops);
    for (int i = 0; i < ndrops; i++)
      drops.push_back({hash01(i, 7) * w, hash01(i, 29) * h,
        520.0f + hash01(i, 53) * 620.0f, 8.0f + hash01(i, 71) * 26.0f});
  }
  float rainTime = 0.0f;
  float smoothEnergy = 0.0f;
  float smoothBass = 0.0f;
  // Envolventes de la música para Pulso (cero en silencio).
  float bass = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0;
  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }
  static float hashU(uint32_t x) {
    x ^= x >> 16; x *= 0x7feb352dU; x ^= x >> 15; x *= 0x846ca68bU; x ^= x >> 16;
    return float(x & 0xffffffu) / 16777216.0f;
  }
 public:
  void reset(uint32_t seed) override {
    (void)seed;
    layers.clear(); drops.clear();
    rainTime = 0.0f; smoothEnergy = 0.0f; smoothBass = 0.0f;
    lastw = 0; lasth = 0; lastDetail = -1.0f;
    bass = spark = energy = slowBass = kick = flash = 0.0f;
  }
  void update(const Frame& f) override {
    float dt = float(f.delta);
    float targetEnergy = f.music.active ? f.music.energy : 0.0f;
    float targetBass = f.music.active ? f.music.bass : 0.0f;
    smoothEnergy += (targetEnergy - smoothEnergy) * float(1.0 - std::exp(-dt * 5.0));
    smoothBass += (targetBass - smoothBass) * float(1.0 - std::exp(-dt * 6.0));

    // En silencio reposa en una llovizna urbana tranquila (~0.12f).
    // Con música la lluvia y la ciudad cobran dinamismo y resplandor.
    float audioDrive = 0.12f + smoothEnergy * 0.76f + smoothBass * 0.35f;
    rainTime += dt * f.speed * audioDrive;

    if (f.width != lastw || f.height != lasth || f.detail != lastDetail) {
      build(f.width, f.height, f.detail);
      lastw = f.width; lasth = f.height; lastDetail = f.detail;
    }

    // Música para Pulso: envolventes y golpes (todo vale cero en silencio).
    const Music& mu = f.music;
    bass = follow(bass, mu.bass, 22.0f, 4.5f, dt);
    spark = follow(spark, mu.spark, 30.0f, 7.0f, dt);
    energy = follow(energy, mu.energy, 6.0f, 1.8f, dt);
    float hit = 0, fl = 0;
    for (const auto& e : mu.events[0]) hit = std::max(hit, e.strength);
    for (const auto& e : mu.events[2]) hit = std::max(hit, e.strength * 0.85f);
    for (const auto& e : mu.events[3]) fl = std::max(fl, e.strength);
    const float onset = std::clamp((mu.bass - slowBass - 0.15f) * 2.5f, 0.0f, 1.0f);
    slowBass = follow(slowBass, mu.bass, 3.0f, 3.0f, dt);
    hit = std::min(std::max(hit, onset), 1.0f);
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
  }
  void render(const Frame& f, Canvas& c) const override {
    float w = f.width, h = f.height;
    float t = rainTime;
    float horizon = h * 0.66f;
    float boost = std::clamp((0.85f + 0.35f * smoothEnergy) * f.intensity, 0.0f, 1.0f);
    auto g = glide(f);
    const float amp = f.intensity;
    // Pulso: sus pesos reparten la reacción; todo vale cero sin música.
    const float punch = std::min(kick * amp, 1.0f) * g.pulso.weight(0);
    const float swell = std::min(bass * amp, 1.0f) * g.pulso.weight(1);
    const float glint = std::min(spark * amp, 1.0f) * g.pulso.weight(2);
    const uint32_t tick = uint32_t(std::floor(f.time * 10.0));
    std::vector<Vec2> twinkle;
    Paint sky = Paint::linear({0, 0}, {0, h},
      {Color::argb(0xff05060c), Color::argb(0xff131a2c), Color::argb(0xff2a1c2c),
       Color::argb(0xff0a0c14), Color::argb(0xff04050a)}, {0, 0.42f, 0.63f, 0.67f, 1.0f});
    c.rect({0, 0, w, h}, sky);

    // Rótulos de neón con parpadeo eléctrico.
    const uint32_t neon[4] = {0xffff6a55, 0xff58c7f3, 0xff3fd8a5, 0xffffd166};
    Paint add; add.blend = Blend::plus;
    for (int i = 0; i < 7; i++) {
      float ph = float(i) * 1.7f;
      float flick = 0.55f + 0.45f * std::sin(t * 44.0f + ph) * std::sin(t * 14.0f + ph * 2.0f);
      if (flick < 0.06f) flick = 0.06f;
      if (flick > 1.0f) flick = 1.0f;
      Color cc = Color::argb(neon[i % 4]);
      // Golpes: los rótulos estallan de luz con cada golpe.
      add.color = {cc.r, cc.g, cc.b, std::min(1.0f, flick * 0.85f * boost + 0.4f * punch)};
      int sw = int(w) - 90; if (sw < 1) sw = 1;
      int shh = int(horizon * 0.5f); if (shh < 1) shh = 1;
      float x = float((i * 137) % sw) + 30.0f;
      float y = horizon - 40.0f - float((i * 211) % shh);
      c.rect({x, y, 8.0f + float((i * 7) % 26), 18.0f + float((i * 13) % 54)}, add);
      if (punch > 0.0f) {
        // Un halo de neón alrededor de cada rótulo.
        const Vec2 signCenter{x + 4.0f + float((i * 7) % 26) * 0.5f, y + 9.0f + float((i * 13) % 54) * 0.5f};
        const float flareR = 26.0f + float((i * 13) % 54);
        Paint flare = Paint::radial(signCenter, flareR,
          {{cc.r, cc.g, cc.b, std::clamp(0.45f * punch * f.glow, 0.0f, 1.0f)}, {cc.r, cc.g, cc.b, 0.0f}}, {0.0f, 1.0f});
        flare.blend = Blend::plus;
        c.circle(signCenter, flareR, flare);
      }
    }

    // 1. Ciudad en capas (sin clip innecesario).
    for (size_t li = 0; li < layers.size(); li++) {
      const Layer& L = layers[li];
      float period = std::max(w, 1.0f);
      float off = std::fmod(t * L.speed, period);
      float alpha = 0.35f + L.depth * 0.65f;
      for (int rep = 0; rep < 2; rep++) {
        float dx = -off + float(rep) * period;
        Path body;
        for (const auto& b : L.blds)
          body.rect({dx + b.x, L.height - b.h, b.w - 2.0f, b.h});
        Paint fill;
        fill.color = {L.shade / 255.0f, (L.shade + 3.0f) / 255.0f,
          (L.shade + 10.0f) / 255.0f, alpha};
        c.path(body, fill);
        if (!L.wins.empty()) {
          // Cada ventana suma su luz dos veces. Con alfa doble cabe en una sola
          // pasada (mismo píxel); si el doble pasa de 1 se dibuja dos veces.
          const float wa = std::min(1.0f, 0.5f * alpha * boost + 0.6f * punch);
          const int copies = wa * 2.0f <= 1.0f ? 1 : 2;
          std::vector<Vec2> win;
          win.reserve(L.wins.size() * size_t(copies));
          for (size_t k = 0; k < L.wins.size(); k++) {
            const auto& p = L.wins[k];
            for (int n = 0; n < copies; n++) win.push_back({dx + p.x, p.y});
            // Agudos: ventanas sueltas parpadean.
            if (glint > 0.0f && hashU(uint32_t(k * 4 + li) * 2654435761u + tick * 40503u) < glint * 0.3f) {
              twinkle.push_back({dx + p.x, p.y});
            }
          }
          Paint wp; wp.blend = Blend::plus;
          // Golpes: las ventanas se encienden; Graves: crecen despacio.
          wp.color = {1, 0.851f, 0.627f, copies == 1 ? wa * 2.0f : wa};
          c.points(win, 1.7f * (1.0f + 0.6f * swell + 0.5f * punch), wp);
        }
      }
    }
    if (!twinkle.empty()) {
      Paint tw; tw.blend = Blend::plus;
      tw.color = {1.0f, 0.93f, 0.8f, std::clamp(0.9f * glint, 0.0f, 1.0f)};
      c.points(twinkle, 2.4f, tw);
    }

    // Resplandor local de la música sobre la ciudad (nunca a pantalla
    // completa): coral de neón en cada golpe y con los graves, azul que
    // parpadea con los agudos.
    if (punch > 0.0f || swell > 0.0f || glint > 0.0f) {
      const Vec2 cityCenter{w * 0.5f, horizon * 0.62f};
      const float auraR = std::max(w, horizon) * 0.62f * (1.0f + 0.1f * punch + 0.12f * swell);
      const float flicker = 0.55f + 0.45f * std::sin(float(f.time) * 43.0f);
      const float warm = (0.36f * punch + 0.28f * swell) * f.glow;
      const float cool = 0.26f * glint * flicker * f.glow;
      if (warm > 0.0f) {
        Paint aura = Paint::radial(cityCenter, auraR,
          {{1.0f, 0.42f, 0.33f, std::clamp(warm, 0.0f, 1.0f)},
           {1.0f, 0.42f, 0.33f, std::clamp(warm * 0.4f, 0.0f, 1.0f)},
           {1.0f, 0.42f, 0.33f, 0.0f}}, {0.0f, 0.5f, 1.0f});
        aura.blend = Blend::plus;
        c.circle(cityCenter, auraR, aura);
      }
      if (cool > 0.0f) {
        Paint shimmer = Paint::radial(cityCenter, auraR,
          {{0.35f, 0.78f, 0.95f, std::clamp(cool, 0.0f, 1.0f)}, {0.35f, 0.78f, 0.95f, 0.0f}}, {0.0f, 1.0f});
        shimmer.blend = Blend::plus;
        c.circle(cityCenter, auraR, shimmer);
      }
    }

    // 2. Reflejo mojado invertido. La ciudad acaba sobre el horizonte, así que
    // su reflejo cae entero entre el horizonte y el borde inferior: no hace
    // falta recortarlo (cada recorte costaba una pasada más por dibujo).
    c.save();
    c.translate(0, horizon);
    c.scale(1, -0.42f);
    c.translate(0, -horizon);
    for (size_t li = 0; li < layers.size(); li++) {
      const Layer& L = layers[li];
      float period = std::max(w, 1.0f);
      float off = std::fmod(t * L.speed, period);
      float alpha = (0.35f + L.depth * 0.65f) * 0.2f;
      for (int rep = 0; rep < 2; rep++) {
        float dx = -off + float(rep) * period;
        Path body;
        for (const auto& b : L.blds)
          body.rect({dx + b.x, L.height - b.h, b.w - 2.0f, b.h});
        Paint fill;
        fill.color = {L.shade / 255.0f, (L.shade + 3.0f) / 255.0f,
          (L.shade + 10.0f) / 255.0f, alpha};
        c.path(body, fill);
        if (!L.wins.empty()) {
          // Alfa doble (siempre <= 0,2) en vez de cada ventana repetida.
          std::vector<Vec2> win;
          win.reserve(L.wins.size());
          for (const auto& p : L.wins) win.push_back({dx + p.x, p.y});
          Paint wp; wp.blend = Blend::plus;
          wp.color = {1, 0.851f, 0.627f, 2.0f * 0.1f * (0.35f + L.depth * 0.65f) * boost};
          c.points(win, 1.7f, wp);
        }
      }
    }
    c.restore();

    // Niebla en el horizonte (Niebla: 0 la quita; Graves la levanta y espesa).
    const float mist = g.niebla;
    if (mist > 0.001f || swell > 0.0f) {
      const float fogK = (0.5f + 0.5f * mist) * (1.0f + 0.5f * swell);
      float fogTop = horizon - h * 0.18f;
      float fogH = h * 0.22f;
      if (fogK != 1.0f) {
        fogTop = horizon - h * 0.18f * fogK;
        fogH = h * 0.22f * fogK;
      }
      Paint fog = Paint::linear({0, fogTop}, {0, fogTop + fogH},
        {{0.47f, 0.314f, 0.408f, 0}, {0.588f, 0.373f, 0.471f, std::min(1.0f, 0.6f * boost * std::min(mist, 1.6f) + 0.2f * swell)}});
      c.rect({0, fogTop, w, fogH}, fog);
    }

    // Lluvia: un solo Path con un segmento por gota.
    // Largo de las gotas (Golpes las estira) y Viento, que inclina la lluvia.
    const float dropLen = g.gotas * (1.0f + 0.8f * punch);
    const float slant = g.viento * 0.6f;
    const bool plainRain = dropLen == 1.0f && slant <= 0.0f;
    Path rain;
    float wind = std::sin(t * 0.23f) * 40.0f;
    for (const auto& d : drops) {
      float y = std::fmod(d.y + t * d.v, h + 60.0f) - 20.0f;
      float x = slant > 0.0f ? std::fmod(d.x + wind * (y / h) + slant * y, w) : std::fmod(d.x + wind * (y / h), w);
      if (x < 0) x += w;
      rain.moveTo(x, y);
      if (plainRain) {
        rain.lineTo(x - wind * 0.02f, y + d.len);
      } else {
        const float len = d.len * dropLen;
        rain.lineTo(x - wind * 0.02f + slant * len, y + len);
      }
    }
    Paint rp; rp.blend = Blend::plus;
    rp.color = {0.745f, 0.843f, 1, std::min(1.0f, 0.42f * boost + 0.45f * punch)};
    rp.strokeWidth = 1.0f; rp.strokeCap = 1; rp.strokeJoin = 1;
    c.path(rain, rp);
  }
};
''';
