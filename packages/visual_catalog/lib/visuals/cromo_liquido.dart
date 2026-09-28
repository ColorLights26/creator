// Cromo Líquido — port de la galería immersive a escena nativa.
// Gotas orgánicas de metal fundido flotando sobre fondo oscuro.
const nativeSource = r'''
class Visual final : public Scene {
  struct Blob { float fx, fy, fr, p1, p2; };
  std::vector<Blob> blobs;
  float energy = 0;
 public:
  void reset(uint32_t seed) override {
    Random rng(seed); blobs.clear(); energy = 0;
    for (int i = 0; i < 7; i++)
      blobs.push_back({0.5f, 0.5f, 0.14f + rng.unit() * 0.13f,
        rng.unit() * 6.2831853f, rng.unit() * 6.2831853f});
  }
  void update(const Frame& f) override {
    energy += (f.music.energy - energy) * float(1.0 - std::exp(-f.delta * 3.0));
  }
  void render(const Frame& f, Canvas& c) const override {
    float w = f.width, h = f.height;
    float t = float(f.time) * f.speed;
    Paint bg; bg.color = Color::argb(0xff03000c);
    c.rect({0, 0, w, h}, bg);
    const uint32_t pal[7] = {0xff3b12a0, 0xff5b1ec4, 0xff8a2be2,
      0xffb14be4, 0xffff3ea5, 0xffff7ec2, 0xffffd1f3};
    for (int i = 0; i < 7; i++) {
      const Blob& b = blobs[i];
      float bx = w * (0.5f + std::sin(t * (0.23f + float(i) * 0.045f) + b.p1) * 0.33f);
      float by = h * (0.5f + std::sin(t * (0.19f + float(i) * 0.037f) + b.p2) * 0.36f);
      float r = b.fr * w * (1.0f + energy * 0.25f);
      Color hi = Color::argb(pal[i]);
      Paint blob = Paint::radial({bx, by}, r,
        {{hi.r, hi.g, hi.b, (0.85f + energy * 0.15f) * f.intensity},
         {hi.r * 0.45f, hi.g * 0.35f, hi.b * 0.9f, 0.35f * f.intensity},
         {0.01f, 0.0f, 0.05f, 0}}, {0, 0.55f, 1.0f});
      blob.blend = Blend::screen;
      c.circle({bx, by}, r, blob);
    }
    Paint shade = Paint::radial({w * 0.5f, h * 0.5f}, std::max(w, h) * 0.75f,
      {{0, 0, 0, 0}, {0, 0, 0, 0.45f}}, {0.55f, 1.0f});
    c.rect({0, 0, w, h}, shade);
  }
};
''';
