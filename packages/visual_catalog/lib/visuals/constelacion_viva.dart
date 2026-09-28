// Constelación Táctil — puerto de la galería FLUX/10 al motor nativo.
// Grafo de vecindad con rejilla espacial: las aristas se agrupan en cuatro
// cubos de alpha para resolverlas en cuatro llamadas. La integración usa paso
// fijo de 1/60 derivado de f.time, idéntico a 30 y a 60 FPS.
const nativeSource = r'''
class Visual final : public Scene {
  static const float kCell = 74.0f;
  struct Node { float x, y, vx, vy, r, phase; };
  std::vector<Node> nodes;
  std::vector<int> head, next;
  int cols = 1, rows = 1, done = 0;
  float lastw = 0, lasth = 0, lastDetail = -1.0f, pull = 0.0f;
  void build(int count, float w, float h) {
    nodes.clear(); nodes.reserve(count);
    Random rng(41);
    for (int i = 0; i < count; i++) {
      Node n;
      n.x = rng.unit() * w; n.y = rng.unit() * h;
      float a = rng.unit() * 6.2831853f;
      float sp = 8.0f + rng.unit() * 22.0f;
      n.vx = std::cos(a) * sp; n.vy = std::sin(a) * sp;
      n.r = 0.9f + rng.unit() * 2.2f;
      n.phase = rng.unit() * 6.2831853f;
      nodes.push_back(n);
    }
    cols = int(std::ceil(w / kCell)); if (cols < 1) cols = 1; if (cols > 512) cols = 512;
    rows = int(std::ceil(h / kCell)); if (rows < 1) rows = 1; if (rows > 1024) rows = 1024;
    head.assign(cols * rows, -1);
    next.assign(nodes.size(), -1);
    done = 0;
  }
  void step(float w, float h) {
    const float dt = 1.0f / 60.0f;
    float force = 12000.0f + pull * 14000.0f;
    float fx = w * 0.5f, fy = h * 0.5f;
    for (size_t i = 0; i < nodes.size(); i++) {
      Node& n = nodes[i];
      float dx = n.x - fx, dy = n.y - fy;
      float d2 = dx * dx + dy * dy;
      if (d2 < force && d2 > 4.0f) {
        float inv = 1.0f / std::sqrt(d2);
        float k = (1.0f - d2 / force) * 140.0f * dt * 8.0f;
        n.vx += dx * inv * k; n.vy += dy * inv * k;
      }
      n.x += n.vx * dt; n.y += n.vy * dt;
      n.vx *= 1.0f - dt * 0.55f; n.vy *= 1.0f - dt * 0.55f;
      if (n.x < 0) { n.x = 0; n.vx = -n.vx; }
      if (n.x > w) { n.x = w; n.vx = -n.vx; }
      if (n.y < 0) { n.y = 0; n.vy = -n.vy; }
      if (n.y > h) { n.y = h; n.vy = -n.vy; }
    }
    done++;
  }
 public:
  void reset(uint32_t seed) override {
    (void)seed;
    nodes.clear(); head.clear(); next.clear();
    lastw = 0; lasth = 0; lastDetail = -1.0f; done = 0; pull = 0.0f;
  }
  void update(const Frame& f) override {
    float density = std::min(1.0f, std::max(0.0f, (f.detail - 0.25f) / 1.75f));
    if (f.width != lastw || f.height != lasth || f.detail != lastDetail) {
      int count = int(190.0f * (0.6f + 0.4f * density));
      if (count < 24) count = 24;
      build(count, f.width, f.height);
      lastw = f.width; lasth = f.height; lastDetail = f.detail;
    }
    pull = f.music.energy;
    float rate = f.reducedMotion ? 0.2f : 1.0f;
    int target = int(float(f.time) * f.speed * rate * 60.0f + 0.001f);
    int guard = 0;
    while (done < target && guard < 16) { step(f.width, f.height); guard++; }
  }
  void render(const Frame& f, Canvas& c) const override {
    float w = f.width, h = f.height;
    float boost = (0.8f + 0.4f * f.music.energy) * f.intensity;
    Paint bg = Paint::radial({w * 0.5f, h * 0.5f}, std::max(w, h) * 0.75f,
      {Color::argb(0xff120f24), Color::argb(0xff080710), Color::argb(0xff04040a)},
      {0.0f, 0.6f, 1.0f});
    c.rect({0, 0, w, h}, bg);

    // Rejilla espacial: cabecera + lista enlazada, cero reservas.
    std::fill(head.begin(), head.end(), -1);
    for (size_t i = 0; i < nodes.size(); i++) {
      int c0 = int(nodes[i].x / kCell);
      int r0 = int(nodes[i].y / kCell);
      if (c0 < 0) c0 = 0; if (c0 > cols - 1) c0 = cols - 1;
      if (r0 < 0) r0 = 0; if (r0 > rows - 1) r0 = rows - 1;
      int idx = r0 * cols + c0;
      next[i] = head[idx];
      head[idx] = int(i);
    }

    // Aristas en cuatro cubos de alpha.
    Path buckets[4];
    const float cell2 = kCell * kCell;
    for (int r = 0; r < rows; r++) {
      for (int cc = 0; cc < cols; cc++) {
        for (int i = head[r * cols + cc]; i != -1; i = next[i]) {
          for (int dr = 0; dr <= 1; dr++) {
            for (int dc = (dr == 0 ? 0 : -1); dc <= 1; dc++) {
              int rr = r + dr, cx = cc + dc;
              if (rr < 0 || rr >= rows || cx < 0 || cx >= cols) continue;
              for (int j = head[rr * cols + cx]; j != -1; j = next[j]) {
                if (j <= i) continue;
                float ddx = nodes[i].x - nodes[j].x, ddy = nodes[i].y - nodes[j].y;
                float d2 = ddx * ddx + ddy * ddy;
                if (d2 > cell2) continue;
                int b = int((1.0f - d2 / cell2) * 3.99f);
                if (b < 0) b = 0; if (b > 3) b = 3;
                buckets[b].moveTo(nodes[i].x, nodes[i].y);
                buckets[b].lineTo(nodes[j].x, nodes[j].y);
              }
            }
          }
        }
      }
    }
    Paint line;
    line.strokeWidth = 0.8f; line.blend = Blend::plus;
    for (int b = 0; b < 4; b++) {
      line.color = {0.651f, 0.545f, 1, (0.08f + float(b) * 0.11f) * boost};
      c.path(buckets[b], line);
    }

    // Nodos: puntos agrupados, con un segundo lote más grande cerca del centro.
    std::vector<Vec2> dim, hot;
    dim.reserve(nodes.size()); hot.reserve(nodes.size());
    float fx = w * 0.5f, fy = h * 0.5f;
    for (const auto& n : nodes) {
      dim.push_back({n.x, n.y});
      float dx = n.x - fx, dy = n.y - fy;
      if (dx * dx + dy * dy < 36100.0f) hot.push_back({n.x, n.y});
    }
    Paint dp; dp.blend = Blend::plus;
    dp.color = {0.796f, 0.722f, 1, 0.55f * boost};
    c.points(dim, 1.1f, dp);
    if (!hot.empty()) {
      Paint hp; hp.blend = Blend::plus;
      hp.color = {0.651f, 0.545f, 1, 0.12f * boost};
      c.points(hot, 6.0f, hp);
    }
  }
};
''';
