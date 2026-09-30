// Neón bajo la Lluvia — puerto de la galería FLUX/10 al motor nativo.
// Cuatro capas de skyline en perspectiva con ventanas encendidas, reflejo mojado
// invertido, rótulos de neón con parpadeo y 380 gotas de lluvia. El skyline se
// dibuja con vectores y puntos, sin imágenes horneadas.
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
 public:
  void reset(uint32_t seed) override {
    (void)seed;
    layers.clear(); drops.clear();
    rainTime = 0.0f; smoothEnergy = 0.0f; smoothBass = 0.0f;
    lastw = 0; lasth = 0; lastDetail = -1.0f;
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
  }
  void render(const Frame& f, Canvas& c) const override {
    float w = f.width, h = f.height;
    float t = rainTime;
    float horizon = h * 0.66f;
    float boost = std::clamp((0.85f + 0.35f * smoothEnergy) * f.intensity, 0.0f, 1.0f);
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
      add.color = {cc.r, cc.g, cc.b, flick * 0.85f * boost};
      int sw = int(w) - 90; if (sw < 1) sw = 1;
      int shh = int(horizon * 0.5f); if (shh < 1) shh = 1;
      float x = float((i * 137) % sw) + 30.0f;
      float y = horizon - 40.0f - float((i * 211) % shh);
      c.rect({x, y, 8.0f + float((i * 7) % 26), 18.0f + float((i * 13) % 54)}, add);
    }

    // Ciudad en dos pasadas: normal y reflejo mojado invertido.
    for (size_t li = 0; li < layers.size(); li++) {
      const Layer& L = layers[li];
      float period = std::max(w, 1.0f);
      float off = std::fmod(t * L.speed, period);
      float alpha = 0.35f + L.depth * 0.65f;
      for (int pass = 0; pass < 2; pass++) {
        c.save();
        Path clip;
        if (pass == 0) clip.rect({0, 0, w, horizon});
        else {
          clip.rect({0, horizon, w, h - horizon});
          c.clip(clip);
          c.translate(0, horizon);
          c.scale(1, -0.42f);
          c.translate(0, -horizon);
        }
        if (pass == 0) c.clip(clip);
        for (int rep = 0; rep < 2; rep++) {
          float dx = -off + float(rep) * period;
          Path body;
          for (const auto& b : L.blds)
            body.rect({dx + b.x, L.height - b.h, b.w - 2.0f, b.h});
          Paint fill;
          fill.color = {L.shade / 255.0f, (L.shade + 3.0f) / 255.0f,
            (L.shade + 10.0f) / 255.0f, pass == 0 ? alpha : alpha * 0.2f};
          c.path(body, fill);
          if (!L.wins.empty()) {
            std::vector<Vec2> win;
            win.reserve(L.wins.size() * 2);
            for (const auto& p : L.wins) {
              win.push_back({dx + p.x, p.y});
              win.push_back({dx + p.x, p.y});
            }
            Paint wp; wp.blend = Blend::plus;
            wp.color = {1, 0.851f, 0.627f, (pass == 0 ? 0.5f : 0.1f) * alpha * boost};
            c.points(win, 1.7f, wp);
          }
        }
        c.restore();
      }
    }

    // Niebla en el horizonte.
    float fogTop = horizon - h * 0.18f;
    Paint fog = Paint::linear({0, fogTop}, {0, fogTop + h * 0.22f},
      {{0.47f, 0.314f, 0.408f, 0}, {0.588f, 0.373f, 0.471f, 0.6f * boost}});
    c.rect({0, fogTop, w, h * 0.22f}, fog);

    // Lluvia: un solo Path con un segmento por gota.
    Path rain;
    float wind = std::sin(t * 0.23f) * 40.0f;
    for (const auto& d : drops) {
      float y = std::fmod(d.y + t * d.v, h + 60.0f) - 20.0f;
      float x = std::fmod(d.x + wind * (y / h), w);
      if (x < 0) x += w;
      rain.moveTo(x, y);
      rain.lineTo(x - wind * 0.02f, y + d.len);
    }
    Paint rp; rp.blend = Blend::plus;
    rp.color = {0.745f, 0.843f, 1, 0.42f * boost};
    rp.strokeWidth = 1.0f; rp.strokeCap = 1; rp.strokeJoin = 1;
    c.path(rain, rp);
  }
};
''';
