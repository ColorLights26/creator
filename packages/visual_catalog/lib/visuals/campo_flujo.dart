// Campo de Flujo — puerto de la galería FLUX/10 al motor nativo.
// 1.400 partículas siguiendo un campo sinusoidal, con rastro circular de 5
// muestras. La integración usa paso fijo de 1/60 derivado de f.time: a 30 y a
// 60 FPS se ejecutan exactamente los mismos pasos y el resultado coincide.
const nativeSource = r'''
class Visual final : public Scene {
  static const int kTail = 5;
  int count = 0, done = 0;
  std::vector<float> x, y, life, trail;
  void step(float size_w, float size_h, float rate) {
    // El instante se deriva del contador de pasos, no del fotograma: a 30 y a
    // 60 FPS se aplica exactamente la misma secuencia de campos.
    float time = float(done) * (1.0f / 60.0f) * rate * 6.2831853f;
    for (int i = 0; i < count; i++) {
      if (life[i] <= 0.0f) {
        x[i] = hash11(float(i) * 1.37f + float(done) * 0.017f) * size_w;
        y[i] = hash11(float(i) * 2.71f + float(done) * 0.029f) * size_h;
        for (int k = 0; k < kTail; k++) {
          int o = (i * kTail + k) * 4;
          trail[o] = x[i]; trail[o + 1] = y[i];
          trail[o + 2] = x[i]; trail[o + 3] = y[i];
        }
        life[i] = 1.0f;
      }
      float px = x[i], py = y[i];
      float a = std::sin(px * 0.0031f + time * 0.16f) * 1.5f
        + std::cos(py * 0.0027f - time * 0.13f) * 1.5f
        + std::sin((px + py) * 0.0014f + time * 0.07f) * 1.1f;
      float vx = std::cos(a) * 1.5f, vy = std::sin(a) * 1.5f;
      // Remolino central: sustituye al dedo, con la música como energía.
      float dx = px - size_w * 0.5f, dy = py - size_h * 0.5f;
      float d2 = dx * dx + dy * dy;
      float radius2 = 15000.0f + 12000.0f * fenergy;
      if (d2 < radius2 && d2 > 1.0f) {
        float inv = 1.0f / std::sqrt(d2);
        float k = (1.0f - d2 / radius2) * 2.4f;
        vx += -dy * inv * k; vy += dx * inv * k;
      }
      float nx = px + vx, ny = py + vy;
      x[i] = nx; y[i] = ny;
      life[i] -= 0.0016f;
      int base = i * kTail * 4;
      for (int k = kTail - 1; k > 0; k--) {
        int o = base + k * 4;
        trail[o] = trail[o - 4]; trail[o + 1] = trail[o - 3];
        trail[o + 2] = nx; trail[o + 3] = ny;
      }
      trail[base] = px; trail[base + 1] = py;
      trail[base + 2] = nx; trail[base + 3] = ny;
      if (nx < -30.0f || nx > size_w + 30.0f || ny < -30.0f || ny > size_h + 30.0f)
        life[i] = 0.0f;
    }
    done++;
  }
  float fenergy = 0.0f;
  float lastw = 0.0f, lasth = 0.0f;
  static float hash11(float p) {
    float s = std::sin(p * 12.9898f) * 43758.5453f;
    return s - std::floor(s);
  }
 public:
  void reset(uint32_t seed) override {
    (void)seed;
    count = 1400; done = 0;
    x.assign(count, 0.0f); y.assign(count, 0.0f);
    life.assign(count, 0.0f);
    trail.assign(count * kTail * 4, 0.0f);
    lastw = 0.0f; lasth = 0.0f; fenergy = 0.0f;
  }
  void update(const Frame& f) override {
    if (f.width != lastw || f.height != lasth) {
      // Reconstruye la rejilla con el tamaño real: la escena se previsualiza
      // primero en miniatura y luego a pantalla completa.
      count = int(1400.0f * (0.5f + 0.5f * std::min(1.0f, std::max(0.0f, (f.detail - 0.25f) / 0.75f))));
      x.assign(count, 0.0f); y.assign(count, 0.0f);
      life.assign(count, 0.0f);
      trail.assign(count * kTail * 4, 0.0f);
      lastw = f.width; lasth = f.height; done = 0;
    }
    fenergy = f.music.energy;
    float rate = (f.reducedMotion ? 0.25f : 1.0f) * f.speed;
    int target = int(float(f.time) * rate * 60.0f + 0.001f);
    int guard = 0;
    while (done < target && guard < 16) { step(f.width, f.height, rate); guard++; }
  }
  void render(const Frame& f, Canvas& c) const override {
    float w = f.width, h = f.height;
    Paint bg; bg.color = Color::argb(0xff05090c);
    c.rect({0, 0, w, h}, bg);
    const uint32_t cols[3] = {0xff3fd8a5, 0xffc6e84f, 0xff58c7f3};
    const float alphas[3] = {0.4f, 0.267f, 0.267f};
    int third = (count / 3) * kTail;
    for (int b = 0; b < 3; b++) {
      Path p;
      int from = b * third, to = (b == 2) ? count * kTail : (b + 1) * third;
      for (int i = from; i < to; i++) {
        int base = i * kTail * 4;
        for (int k = 0; k < kTail; k++) {
          int o = base + k * 4;
          p.moveTo(trail[o], trail[o + 1]);
          p.lineTo(trail[o + 2], trail[o + 3]);
        }
      }
      Color cc = Color::argb(cols[b]);
      Paint q; q.blend = Blend::plus;
      q.color = {cc.r, cc.g, cc.b, alphas[b] * f.intensity};
      q.strokeWidth = 1.1f; q.strokeCap = 1; q.strokeJoin = 1;
      c.path(p, q);
    }
  }
};
''';
