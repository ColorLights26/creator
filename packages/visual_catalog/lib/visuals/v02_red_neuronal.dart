// Red Neuronal Cuántica — Puerto fiel de Visuales Inmersivas v02.
// Plexo sináptico interconectado con potenciales de acción en cascada,
// halos bioluminiscentes e impulsos reactivos al audio.
const nativeSource = r'''
class Visual final : public Scene {
  struct Node { float x, y, vx, vy, size, energy; };
  struct Pulse { int from, to; float prog, speed; int colIdx; };
  std::vector<Node> nodes;
  std::vector<Pulse> pulses;
  int done = 0;
  float fenergy = 0.0f, fbass = 0.0f;

  void step(float w, float h) {
    const float dt = 1.0f / 60.0f;
    for (size_t i = 0; i < nodes.size(); i++) {
      auto& n = nodes[i];
      n.x += n.vx * dt * 60.0f;
      n.y += n.vy * dt * 60.0f;

      if (n.x <= 0.02f) { n.x = 0.02f; n.vx = std::abs(n.vx); }
      if (n.x >= 0.98f) { n.x = 0.98f; n.vx = -std::abs(n.vx); }
      if (n.y <= 0.02f) { n.y = 0.02f; n.vy = std::abs(n.vy); }
      if (n.y >= 0.98f) { n.y = 0.98f; n.vy = -std::abs(n.vy); }

      // Suave atracción hacia el centro pulsante con la música
      float dx = 0.5f - n.x, dy = 0.5f - n.y;
      float d2 = dx * dx + dy * dy;
      if (d2 > 0.001f) {
        float inv = 1.0f / std::sqrt(d2);
        float pull = 0.00008f * (1.0f + fenergy * 2.0f);
        n.vx += dx * inv * pull;
        n.vy += dy * inv * pull;
      }
      n.energy = std::clamp(n.energy * 0.992f, 0.15f, 1.0f);
    }

    // Progreso de pulsos (potenciales de acción)
    for (size_t i = 0; i < pulses.size();) {
      pulses[i].prog += pulses[i].speed;
      if (pulses[i].prog >= 1.0f) {
        if (pulses[i].to < int(nodes.size())) {
          nodes[pulses[i].to].energy = std::min(1.0f, nodes[pulses[i].to].energy + 0.35f);
        }
        pulses.erase(pulses.begin() + i);
      } else {
        i++;
      }
    }

    // Disparos periódicos o rítmicos de nuevos pulsos
    if (pulses.size() < 24 && !nodes.empty()) {
      int from = (done * 7) % int(nodes.size());
      float fx = nodes[from].x * w, fy = nodes[from].y * h;
      for (size_t to = 0; to < nodes.size(); to++) {
        if (int(to) == from) continue;
        float tx = nodes[to].x * w, ty = nodes[to].y * h;
        float ddx = tx - fx, ddy = ty - fy;
        if (ddx * ddx + ddy * ddy < (110.0f * 110.0f)) {
          pulses.push_back({from, int(to), 0.0f, 0.03f + (from % 3) * 0.015f, from % 2});
          break;
        }
      }
    }
    done++;
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    nodes.clear(); nodes.reserve(65);
    pulses.clear(); pulses.reserve(32);
    done = 0;
    for (int i = 0; i < 65; i++) {
      float a = rng.unit() * 6.2831853f;
      float spd = 0.0006f + rng.unit() * 0.0010f;
      nodes.push_back({
        rng.unit(), rng.unit(),
        std::cos(a) * spd, std::sin(a) * spd,
        2.2f + rng.unit() * 2.8f,
        0.3f + rng.unit() * 0.7f
      });
    }
  }

  void update(const Frame& f) override {
    fenergy = f.music.energy;
    fbass = f.music.bass;
    float rate = (f.reducedMotion ? 0.3f : 1.0f) * f.speed;
    int target = int(float(f.time) * rate * 60.0f + 0.001f);
    int guard = 0;
    while (done < target && guard < 16) {
      step(f.width, f.height);
      guard++;
    }
  }

  void render(const Frame& f, Canvas& c) const override {
    float w = f.width, h = f.height;
    Vec2 center{w * 0.5f, h * 0.5f};

    // Fondo radial profundo
    Paint bg = Paint::radial(center, std::max(w, h) * 0.75f,
      {Color::argb(0xff06101e), Color::argb(0xff02060b), Color::argb(0xff000000)},
      {0.0f, 0.5f, 1.0f});
    c.rect({0, 0, w, h}, bg);

    const float connDistSq = 110.0f * 110.0f;

    // Dibujar enlaces sinápticos agrupados
    for (size_t i = 0; i < nodes.size(); i++) {
      float x1 = nodes[i].x * w, y1 = nodes[i].y * h;
      for (size_t j = i + 1; j < nodes.size(); j++) {
        float x2 = nodes[j].x * w, y2 = nodes[j].y * h;
        float dx = x2 - x1, dy = y2 - y1;
        float d2 = dx * dx + dy * dy;
        if (d2 < connDistSq) {
          float dist = std::sqrt(d2);
          float alpha = std::clamp((1.0f - dist / 110.0f) * 0.65f * f.intensity, 0.0f, 1.0f);
          float combE = (nodes[i].energy + nodes[j].energy) * 0.5f;

          // Lerp entre azul profundo {0, 0.33, 1} y cian neón {0, 1, 0.84}
          Color lcol{
            0.0f,
            0.33f * (1.0f - combE) + 1.0f * combE,
            1.0f * (1.0f - combE) + 0.84f * combE,
            alpha
          };
          Paint lp; lp.blend = Blend::plus; lp.color = lcol;
          lp.strokeWidth = std::max(0.6f, 0.8f + combE * 1.2f);
          Path line; line.moveTo(x1, y1); line.lineTo(x2, y2);
          c.path(line, lp);
        }
      }
    }

    // Dibujar potenciales de acción (pulsos de señal)
    for (const auto& p : pulses) {
      if (p.from >= int(nodes.size()) || p.to >= int(nodes.size())) continue;
      float sx = nodes[p.from].x * w, sy = nodes[p.from].y * h;
      float ex = nodes[p.to].x * w, ey = nodes[p.to].y * h;
      float px = sx + (ex - sx) * p.prog;
      float py = sy + (ey - sy) * p.prog;

      Color pcol = (p.colIdx == 0)
        ? Color{0.0f, 1.0f, 0.88f, std::clamp(0.9f * f.intensity, 0.0f, 1.0f)}
        : Color{0.55f, 0.15f, 1.0f, std::clamp(0.9f * f.intensity, 0.0f, 1.0f)};
      Paint pp; pp.blend = Blend::plus; pp.color = pcol;
      c.circle({px, py}, 2.8f, pp);

      // Halo del pulso
      Paint ph; ph.blend = Blend::plus;
      ph.color = {pcol.r, pcol.g, pcol.b, std::clamp(0.35f * f.intensity, 0.0f, 1.0f)};
      c.circle({px, py}, 6.5f, ph);
    }

    // Dibujar nodos sinápticos (núcleo y halo)
    for (const auto& n : nodes) {
      Vec2 pos{n.x * w, n.y * h};
      float rad = n.size * (1.0f + n.energy * 0.45f);

      // Halo
      Paint glow; glow.blend = Blend::plus;
      glow.color = {0.0f, 0.95f, 0.85f, std::clamp((0.2f + n.energy * 0.35f) * f.intensity, 0.0f, 1.0f)};
      c.circle(pos, rad * 2.3f, glow);

      // Núcleo
      Paint core; core.blend = Blend::plus;
      core.color = {
        0.1f * (1.0f - n.energy) + 1.0f * n.energy,
        0.75f * (1.0f - n.energy) + 1.0f * n.energy,
        0.95f * (1.0f - n.energy) + 1.0f * n.energy,
        std::clamp((0.7f + n.energy * 0.3f) * f.intensity, 0.0f, 1.0f)
      };
      c.circle(pos, rad, core);
    }
  }
};
''';
