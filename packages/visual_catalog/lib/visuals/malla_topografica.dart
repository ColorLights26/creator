// Malla Topográfica — puerto de la galería FLUX/10 al motor nativo.
// Terreno en perspectiva con 47 filas y 47 columnas proyectadas, sol en el
// horizonte y scroll continuo. La inclinación táctil se sustituye por deriva
// automática y Grave, ambas función pura del tiempo.
const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int cols = 46;
  static constexpr int rows = 46;
 public:
  void reset(uint32_t seed) override { (void)seed; }
  void update(const Frame& f) override { (void)f; }
  void render(const Frame& f, Canvas& c) const override {
    float w = f.width, h = f.height;
    float t = float(f.time) * f.speed;
    float horizon = h * 0.34f;
    Paint sky = Paint::linear({0, 0}, {0, h},
      {Color::argb(0xff070a10), Color::argb(0xff101a18),
       Color::argb(0xff05070a), Color::argb(0xff04050a)}, {0, 0.33f, 0.36f, 1.0f});
    c.rect({0, 0, w, h}, sky);

    float lean = std::sin(t * 0.21f) * 0.16f * (1.0f + f.music.bass * 0.5f);
    float boost = (0.8f + 0.35f * f.music.energy) * f.intensity;
    if (boost > 1.0f) boost = 1.0f; if (boost < 0.0f) boost = 0.0f;
    float sunX = w * (0.5f + lean);
    Paint sunPaint = Paint::radial({sunX, horizon}, w * 0.5f,
      {{0.776f, 0.910f, 0.310f, 0.42f * boost}, {0.471f, 0.784f, 0.471f, 0.12f * boost},
       {0, 0, 0, 0}}, {0.0f, 0.25f, 1.0f});
    sunPaint.blend = Blend::plus;
    c.rect({0, 0, w, h}, sunPaint);

    float scroll = t * 6.2831853f * 0.55f;
    float f0 = h * 0.95f;
    const float camH = 2.6f, span = 9.0f;
    Path row;
    Paint line;
    line.strokeCap = 1; line.strokeJoin = 1;
    // De lejos a cerca: el trazo más próximo tapa al lejano, sin z-buffer.
    for (int j = rows; j >= 0; j--) {
      float zt = float(j) / float(rows);
      float z = 0.75f * std::pow(26.0f, zt);
      float k = f0 / z;
      row = Path();
      for (int i = 0; i <= cols; i++) {
        float xt = float(i) / float(cols) - 0.5f;
        float x = xt * span * (1.0f + z * 0.35f) + lean * z * 0.6f;
        float hgt = noise3(x * 0.42f, z * 0.24f + scroll, 0.0f) * (0.5f + z * 0.07f);
        float px = w * 0.5f + x * k;
        float py = horizon + (camH - hgt) * k;
        if (i == 0) row.moveTo(px, py); else row.lineTo(px, py);
      }
      float a = (1.0f - zt) * 1.5f;
      if (a > 1.0f) a = 1.0f; if (a < 0.0f) a = 0.0f;
      line.strokeWidth = 0.5f + (1.0f - zt) * 1.4f;
      if (zt < 0.25f) line.color = {0.918f, 1, 0.690f, a * 0.55f * boost};
      else line.color = {0.776f, 0.910f, 0.310f, a * 0.55f * boost};
      c.path(row, line);
    }

    // Verticales cada cuatro columnas en un único Path.
    Path wires;
    for (int i = 0; i <= cols; i += 4) {
      float xt = float(i) / float(cols) - 0.5f;
      bool first = true;
      for (int j = rows; j >= 0; j -= 3) {
        float zt = float(j) / float(rows);
        float z = 0.75f * std::pow(26.0f, zt);
        float k = f0 / z;
        float x = xt * span * (1.0f + z * 0.35f) + lean * z * 0.6f;
        float hgt = noise3(x * 0.42f, z * 0.24f + scroll, 0.0f) * (0.5f + z * 0.07f);
        float px = w * 0.5f + x * k;
        float py = horizon + (camH - hgt) * k;
        if (first) { wires.moveTo(px, py); first = false; }
        else wires.lineTo(px, py);
      }
    }
    line.color = {0.471f, 0.863f, 0.627f, 0.129f * boost};
    line.strokeWidth = 0.7f;
    c.path(wires, line);
  }
  static float noise3(float x, float y, float t) {
    return std::sin(x * 0.9f + t * 0.7f) * 0.5f
      + std::sin(y * 1.1f - t * 0.5f) * 0.34f
      + std::sin((x + y) * 0.6f + t) * 0.16f;
  }
};
''';
