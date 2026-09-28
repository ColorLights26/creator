// Cintas de Seda — puerto de la galería FLUX/10 al motor nativo.
// Siete curvas de Lissajous convertidas en cintas cerradas por desplazamiento
// normal y rellenas con un degradado lineal de cuatro paradas.
const nativeSource = r'''
class Visual final : public Scene {
  static const int ribbons = 7;
  static const int seg = 72;
 public:
  void reset(uint32_t seed) override { (void)seed; }
  void update(const Frame& f) override { (void)f; }
  void render(const Frame& f, Canvas& c) const override {
    float w = f.width, h = f.height;
    float t = float(f.time) * f.speed;
    float time = t * 6.2831853f;
    float drift = std::sin(time * 0.13f) * 0.12f * f.intensity;
    float cx = w * (0.5f + drift), cy = h * (0.5f + drift);
    float amp = std::min(w, h) * 0.38f;
    float boost = (0.85f + 0.3f * f.music.energy) * f.intensity;
    if (boost > 1.0f) boost = 1.0f; if (boost < 0.0f) boost = 0.0f;
    Paint solid; solid.color = Color::argb(0xf2090510);
    c.rect({0, 0, w, h}, solid);

    const float cfg[7][5] = {
      {2, 3, 0.0f, 0.18f, 22}, {3, 4, 1.1f, 0.24f, 16}, {4, 5, 2.2f, 0.30f, 26},
      {1, 4, 3.3f, 0.14f, 12}, {3, 7, 4.4f, 0.27f, 30}, {5, 6, 5.5f, 0.21f, 18},
      {2, 5, 6.6f, 0.33f, 24}};
    const uint32_t cols[7] = {0xfff27bb6, 0xffa68bff, 0xff58c7f3, 0xffff6a55,
      0xffffd166, 0xff3fd8a5, 0xffece6da};
    for (int r = 0; r < ribbons; r++) {
      float f1 = cfg[r][0], f2 = cfg[r][1], ph = cfg[r][2];
      float rate = cfg[r][3], wid = cfg[r][4];
      float tt = time * rate;
      Color col = Color::argb(cols[r]);
      Path ribbon;
      for (int s = 0; s <= seg; s++) {
        float u = float(s) / float(seg) * 6.2831853f;
        float x = cx + amp * std::sin(f1 * u + tt + ph)
          * (0.72f + 0.28f * std::cos(u * 2.0f + tt));
        float y = cy + amp * 0.86f * std::sin(f2 * u + tt * 1.31f + ph);
        float nx = std::cos(u * 3.0f + tt * 2.0f) * wid
          * (0.35f + 0.65f * std::sin(float(s) / float(seg) * 3.14159265f));
        float ny = std::sin(u * 2.0f - tt) * wid * 0.6f;
        if (s == 0) ribbon.moveTo(x + ny, y + nx);
        else ribbon.lineTo(x + ny, y + nx);
      }
      for (int s = seg; s >= 0; s--) {
        float u = float(s) / float(seg) * 6.2831853f;
        float x = cx + amp * std::sin(f1 * u + tt + ph)
          * (0.72f + 0.28f * std::cos(u * 2.0f + tt));
        float y = cy + amp * 0.86f * std::sin(f2 * u + tt * 1.31f + ph);
        float nx = std::cos(u * 3.0f + tt * 2.0f) * wid
          * (0.35f + 0.65f * std::sin(float(s) / float(seg) * 3.14159265f));
        float ny = std::sin(u * 2.0f - tt) * wid * 0.6f;
        ribbon.lineTo(x - ny, y - nx);
      }
      ribbon.close();
      Paint fill = Paint::linear({cx - amp, cy - amp}, {cx + amp, cy + amp},
        {{col.r, col.g, col.b, 0}, {col.r, col.g, col.b, 0.42f * boost},
         {1, 1, 1, 0.26f * boost}, {col.r, col.g, col.b, 0}}, {0.0f, 0.45f, 0.55f, 1.0f});
      fill.blend = Blend::screen;
      c.path(ribbon, fill);
      Paint edge; edge.blend = Blend::screen;
      edge.color = {0.925f, 0.902f, 0.855f, 0.22f * boost};
      edge.strokeWidth = 0.6f;
      c.path(ribbon, edge);
    }
  }
};
''';
