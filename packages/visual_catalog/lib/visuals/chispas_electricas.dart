// Chispas Eléctricas — capa transparente premium. Referencia: vídeos de stock
// «Electricity Sparks» y «Lightning on Black». Descargas eléctricas que
// chasquean por la pantalla: arcos en zigzag que se rehacen sin parar, con
// ramas, un halo violeta, un fogonazo donde golpean y una lluvia de chispas.
// Sin fondo, encima de cualquier visual. Partículas simuladas con física a
// paso fijo y dibujadas con resplandor suave, núcleo caliente y estela, más su
// efecto propio; barato para el móvil (puntos agrupados y degradados). Pulso:
// Golpes lanza su efecto con cada golpe y lo aviva; Graves lo hincha; Brillos
// lo hace centellear.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.slider('tamano', 'Tamaño', min: .5, max: 2, value: 1),
  // MOVIMIENTO: cuántas descargas saltan.
  CreatorModifier.slider('descargas', 'Descargas', min: .3, max: 2, value: 1),
  // FORMA: cuánto se ramifican.
  CreatorModifier.slider('ramas', 'Ramificación', min: 0, max: 1, value: .5),
  // MODO: de dónde salen.
  CreatorModifier.choice('origen', 'Origen', options: ['Libre', 'Bordes', 'Centro']),
  // MÚSICA
  CreatorModifier.choice('pulso', 'Pulso', options: ['Golpes', 'Graves', 'Brillos']),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Tormenta', {'descargas': 2, 'ramas': 1, 'origen': 'Libre'}),
  CreatorVariation('Bobina de Tesla', {'origen': 'Centro', 'descargas': 1.6, 'ramas': .7, 'tamano': 1.2}),
];

const nativeSource = r'''
class Visual final : public Scene {
  // Reservado para detail 2: nunca se reserva memoria al cambiar un ajuste.
  static constexpr int kMax = 2000;
  static constexpr double kStep = 1.0 / 60.0;
  // Pasos simulados antes del primer cuadro: la escena ya empieza viva.
  static constexpr int kWarm = 60;
  static constexpr bool kRays = false;
  static constexpr int kBins = 27;  // tamaño × color × brillo
  // kind: 0 chispa (núcleo, halo y estela), 1 luz desenfocada, 2 nube.
  struct P { float x, y, vx, vy, age, life, size, seed, heat, kind, a0, a1, a2; bool on; };
  std::array<P, kMax> ps{};
  // Simulación a paso fijo: el movimiento es el mismo a 30 y a 60 FPS.
  double sim = 0, emitAcc = 0;
  int64_t steps = 0;
  uint32_t spawned = 0, beats = 0;
  int cursor = 0;
  float W = 1.0f, H = 1.78f;
  float bass = 0, spark = 0, energy = 0, slowBass = 0, kick = 0;
  float burst = 0, burstPow = 0, burstX = 0.5f, burstY = 0.5f, burstAge = 9;
  // Ajustes de este cuadro (ya deslizados por el motor).
  float k0 = 1, k1 = 0, k2 = 0, k3 = 0, w0 = 1, w1 = 0, w2 = 0, rate = 1;
  mutable std::array<std::vector<Vec2>, kBins> cores;
  mutable std::array<Path, 9> streaks, streaksNear, rays;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }
  static float hashU(uint32_t x) {
    x ^= x >> 16; x *= 0x7feb352dU; x ^= x >> 15; x *= 0x846ca68bU; x ^= x >> 16;
    return float(x & 0xffffffu) / 16777216.0f;
  }
  static float mixf(float a, float b, float t) { return a + (b - a) * t; }
  static Color mixc(const Color& a, const Color& b, float t) {
    return {mixf(a.r, b.r, t), mixf(a.g, b.g, t), mixf(a.b, b.b, t), 1.0f};
  }
  static float sq(float x) { return x * x; }
  // Remolinos de aire sin divergencia (rotacional de un potencial).
  static Vec2 curl(float x, float y, float t, float scale) {
    const float a = x * scale, b = y * scale;
    const float A = a * 1.1f + t * 0.31f, B = b * 1.3f - t * 0.23f;
    const float C = a * 0.7f - b * 1.9f + t * 0.37f, E = b * 2.3f + a * 0.4f - t * 0.29f;
    const float dpa = 1.1f * std::cos(A) * std::cos(B) + 0.35f * std::cos(C) + 0.2f * std::cos(E);
    const float dpb = -1.3f * std::sin(A) * std::sin(B) - 0.95f * std::cos(C) + 1.15f * std::cos(E);
    return {dpb, -dpa};
  }
  P& slot() {
    P& p = ps[size_t(cursor)];
    cursor = (cursor + 1) % kMax;
    return p;
  }
  // Una partícula nueva y su clave de azar (determinista).
  P& fresh(uint32_t& k) {
    k = spawned++ * 9u + 0x9e37u;
    P& p = slot();
    p = P{};
    p.on = true;
    p.seed = hashU(k + 8u);
    return p;
  }
  struct Arc { int64_t born; float x0, y0, x1, y1, life, power; uint32_t seed; bool on; };
  static constexpr int kArcs = 16;
  std::array<Arc, kArcs> arcs{};
  int arcCursor = 0;
  double arcAcc = 0;
  uint32_t arcCount = 0;
  float bigArc = 0;
  // Lluvia de chispas donde golpea un arco.
  void spray(float x, float y, int n, float power) {
    for (int j = 0; j < n; j++) {
      uint32_t k;
      P& q = fresh(k);
      const float h1 = hashU(k + 1u), h2 = hashU(k + 2u), h3 = hashU(k + 3u), h4 = hashU(k + 4u);
      const float ang = h1 * 6.2831853f;
      const float sp = (0.25f + 0.9f * h2 * h2) * power;
      q.x = x;
      q.y = y;
      q.vx = std::cos(ang) * sp;
      q.vy = std::sin(ang) * sp - 0.15f * power;
      q.life = 0.18f + 0.5f * h3;
      q.size = 0.0018f * (0.6f + 1.6f * h4 * h4);
      q.heat = 0.15f * h2;
    }
  }
  // Un arco nuevo: libre, desde un borde o desde el centro (según Origen).
  void newArc(float power) {
    const uint32_t id = arcCount++;
    const uint32_t hs = id * 2654435761u + 0x51ed27u;
    const float h1 = hashU(hs + 1u), h2 = hashU(hs + 2u), h3 = hashU(hs + 3u), h4 = hashU(hs + 4u);
    const float h5 = hashU(hs + 5u), h7 = hashU(hs + 7u);
    float x0 = 0, y0 = 0;
    float ang = h4 * 6.2831853f;
    const float len = (0.2f + 0.42f * h3) * (0.8f + 0.4f * std::min(power, 1.5f));
    if (h7 < w0) {
      x0 = W * (0.1f + 0.8f * h1);
      y0 = H * (0.08f + 0.84f * h2);
    } else if (h7 < w0 + w1) {
      const int side = int(h1 * 3.999f);
      x0 = side == 0 ? 0.0f : (side == 1 ? W : W * h2);
      y0 = side == 2 ? 0.0f : (side == 3 ? H : H * h2);
      ang = std::atan2(H * 0.5f - y0, W * 0.5f - x0) + (h4 - 0.5f) * 1.2f;
    } else {
      x0 = W * 0.5f + (h1 - 0.5f) * 0.06f;
      y0 = H * 0.5f + (h2 - 0.5f) * 0.06f;
    }
    const float x1 = x0 + std::cos(ang) * len, y1 = y0 + std::sin(ang) * len;
    Arc& a = arcs[size_t(arcCursor)];
    arcCursor = (arcCursor + 1) % kArcs;
    a = {steps, x0, y0, x1, y1, (0.12f + 0.3f * h5) * (power > 1.0f ? 1.8f : 1.0f), power, hs, true};
    spray(x1, y1, int((10.0f + 22.0f * power) * k3), power);
  }
  void spawn(bool fromBurst, float power) {
    uint32_t k;
    P& p = fresh(k);
    const float h1 = hashU(k + 1u), h2 = hashU(k + 2u), h3 = hashU(k + 3u), h4 = hashU(k + 4u);
    const float h5 = hashU(k + 5u), h6 = hashU(k + 6u), h7 = hashU(k + 7u), h9 = hashU(k + 9u);
    const float TAU = 6.2831853f;
    (void)h1; (void)h2; (void)h3; (void)h4; (void)h5; (void)h6; (void)h7; (void)h9;
    (void)fromBurst; (void)power; (void)TAU;
    p.life = 0.1f;
  }
  void step(float dt) {
    // La hora del propio paso: igual a 30 y a 60 FPS.
    const float t = float(std::fmod(double(steps) * kStep, 4000.0));
    (void)t;
    // Saltan descargas al azar; con cada golpe, una grande y su eco.
    arcAcc += double(2.2f + 4.8f * k1) * double(dt);
    while (arcAcc >= 1.0) {
      arcAcc -= 1.0;
      newArc(0.55f + 0.45f * hashU(arcCount * 31u + 7u));
    }
    if (bigArc > 0.0f) {
      newArc(1.0f + bigArc);
      newArc(0.8f + 0.5f * bigArc);
      bigArc = 0.0f;
    }
    // Mientras dura, cada arco escupe chispitas por donde golpea.
    for (Arc& a : arcs) {
      if (!a.on) continue;
      const float age = float(double(steps - a.born) * kStep);
      if (age > a.life) {
        a.on = false;
        continue;
      }
      if (hashU(uint32_t(steps) * 13u + a.seed) < 0.35f) spray(a.x1, a.y1, 1, a.power * 0.7f);
    }
    emitAcc += double(rate) * double(dt);
    while (emitAcc >= 1.0) {
      emitAcc -= 1.0;
      spawn(false, 0.0f);
    }
    for (P& p : ps) {
      if (!p.on) continue;
      const float drag = std::exp(-1.2f * dt);
      p.vx *= drag;
      p.vy = p.vy * drag + 1.1f * dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.age += dt;
      if (p.age >= p.life || p.x < -0.6f || p.x > W + 0.6f || p.y < -0.6f || p.y > H + 0.6f) p.on = false;
    }

  }

 public:
  void reset(uint32_t seed) override {
    for (auto& p : ps) p = P{};
    sim = emitAcc = 0;
    steps = -kWarm;
    spawned = seed * 2654435761u;
    beats = 0;
    cursor = 0;
    bass = spark = energy = slowBass = kick = 0;
    burst = burstPow = 0;
    burstAge = 9;
    for (auto& v : cores) {
      v.clear();
      v.reserve(size_t(kMax));
    }
    for (auto& a : arcs) a = Arc{};
    arcCursor = 0;
    arcAcc = 0;
    arcCount = 0;
    bigArc = 0;
  }

  void update(const Frame& f) override {
    auto g = glide(f);
    const float dt = float(f.delta);
    const Music& mu = f.music;
    W = f.width / std::min(f.width, f.height);
    H = f.height / std::min(f.width, f.height);
    bass = follow(bass, mu.bass, 22.0f, 4.5f, dt);
    spark = follow(spark, mu.spark, 30.0f, 7.0f, dt);
    energy = follow(energy, mu.energy, 6.0f, 1.8f, dt);
    float hit = 0;
    for (const auto& e : mu.events[0]) hit = std::max(hit, e.strength);
    for (const auto& e : mu.events[2]) hit = std::max(hit, e.strength * 0.85f);
    const float onset = std::clamp((mu.bass - slowBass - 0.15f) * 2.5f, 0.0f, 1.0f);
    slowBass = follow(slowBass, mu.bass, 3.0f, 3.0f, dt);
    hit = std::min(std::max(hit, onset), 1.0f);
    const bool fresh = hit > kick + 0.2f;
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    burstAge += dt * f.speed;
    // Pulso en Golpes: cada golpe lanza su efecto; la música fuerte, más.
    if (fresh && mu.active) {
      beats++;
      burst = hit * f.intensity * g.pulso.weight(0);
      burstPow = burst;
      burstX = hashU(beats * 7u + 3u);
      burstY = hashU(beats * 7u + 5u);
      burstAge = 0;
    }
    k1 = g.descargas + 1.5f * std::min(spark * f.intensity, 1.0f) * g.pulso.weight(2);
    k2 = g.ramas;
    k3 = f.detail;
    w0 = g.origen.weight(0);
    w1 = g.origen.weight(1);
    w2 = g.origen.weight(2);
    rate = 0.0f;
    // Golpe: una descarga grande (en vez de una ráfaga de partículas).
    if (burst > 0.0f) {
      bigArc = std::max(bigArc, burst);
      burst = 0.0f;
    }
    rate *= 0.5f * f.detail * (1.0f + 0.5f * std::min(energy * f.intensity, 1.0f));
    sim += f.delta * f.speed;
    const int64_t target = int64_t(std::floor(sim / kStep + 1e-6));
    if (target - steps > kWarm + 240) steps = target - 240;
    while (steps < target) {
      steps++;
      if (burst > 0.0f) {
        const int n = int(0.0f * std::min(burst, 1.5f));
        for (int i = 0; i < n; i++) spawn(true, burst);
        burst = 0;
      }
      step(float(kStep));
    }
  }

  void render(const Frame& f, Canvas& c) const override {
    auto g = glide(f);
    const float amp = f.intensity;
    const float s = std::min(f.width, f.height);
    const float t = float(std::fmod(sim, 4000.0));
    // La hora del último paso: la misma que usó la simulación.
    const float ts = float(std::fmod(double(steps) * kStep, 4000.0));
    // Pulso: Golpes aviva, Graves hincha, Brillos centellea.
    const float golpe = std::min(kick * amp, 1.2f) * g.pulso.weight(0);
    const float graves = std::min(bass * amp, 1.2f) * g.pulso.weight(1);
    const float agudos = std::min(spark * amp, 1.2f) * g.pulso.weight(2);
    const float swell = 1.0f + 0.35f * graves;
    const float lift = 1.0f + 0.5f * golpe;
    const Color hot = f.colors[3], mid = f.colors[2], deep = f.colors[1];
    const Color white{1.0f, 1.0f, 1.0f, 1.0f};
    auto ramp = [&](float u) {
      u = std::clamp(u, 0.0f, 1.0f);
      return u < 0.5f ? mixc(hot, mid, u * 2.0f) : mixc(mid, deep, (u - 0.5f) * 2.0f);
    };
    (void)golpe; (void)graves; (void)agudos; (void)t; (void)ts; (void)white;
    // Atmósfera (luces grandes y suaves) primero.

    for (auto& v : cores) v.clear();
    for (auto& pth : streaks) pth = Path{};
    for (auto& pth : streaksNear) pth = Path{};
    for (auto& pth : rays) pth = Path{};
    bool anyStreak[9] = {false, false, false, false, false, false, false, false, false};
    bool anyRay[9] = {false, false, false, false, false, false, false, false, false};
    {
      // Rayos eléctricos: un zigzag fractal que se rehace 30 veces por segundo,
      // con ramas, un halo violeta y un fogonazo donde nace y donde golpea.
      Path bolt[3];
      bool any[3] = {false, false, false};
      Vec2 pts[33];
      Vec2 q[9];
      const float thick = g.tamano * (1.0f + 0.6f * graves);
      for (const Arc& a : arcs) {
        if (!a.on) continue;
        const float age = float(double(steps - a.born) * kStep);
        const float ua = age / a.life;
        if (ua >= 1.0f) continue;
        const uint32_t js = a.seed + uint32_t((steps - a.born) / 2) * 7919u;
        const float flick = hashU(js + 11u) < 0.22f ? 0.3f : 1.0f;
        const float env = std::min(ua / 0.08f, 1.0f) * (1.0f - ua * ua);
        const float br = std::clamp(env * flick * (0.8f + 0.45f * std::min(a.power, 1.5f)), 0.0f, 1.0f);
        const int bin = br < 0.33f ? 0 : (br < 0.66f ? 1 : 2);
        const float dx = a.x1 - a.x0, dy = a.y1 - a.y0;
        const float len = std::sqrt(dx * dx + dy * dy);
        const float nx = -dy / std::max(len, 1e-4f), ny = dx / std::max(len, 1e-4f);
        pts[0] = {a.x0, a.y0};
        pts[32] = {a.x1, a.y1};
        int lev = 0;
        for (int st = 32; st > 1; st /= 2, lev++) {
          const float ampl = len * 0.22f * std::pow(0.56f, float(lev));
          for (int i = st / 2; i < 33; i += st) {
            const Vec2 A = pts[i - st / 2], B = pts[i + st / 2];
            const float off = (hashU(js + uint32_t(i) * 31u + uint32_t(lev) * 977u) - 0.5f) * 2.0f * ampl;
            pts[i] = {0.5f * (A.x + B.x) + nx * off, 0.5f * (A.y + B.y) + ny * off};
          }
        }
        bolt[bin].moveTo(pts[0].x * s, pts[0].y * s);
        for (int i = 1; i < 33; i++) bolt[bin].lineTo(pts[i].x * s, pts[i].y * s);
        any[bin] = true;
        const int bbin = std::max(bin - 1, 0);
        for (int i = 4; i < 30; i += 3) {
          if (hashU(js + uint32_t(i) * 113u) > k2 * 0.45f) continue;
          const float side = hashU(js + uint32_t(i) * 7u) < 0.5f ? -1.0f : 1.0f;
          const float ba = std::atan2(dy, dx) + side * (0.4f + 0.6f * hashU(js + uint32_t(i) * 17u));
          const float bl = len * (0.12f + 0.25f * hashU(js + uint32_t(i) * 23u)) * (1.0f - float(i) / 40.0f);
          const float bnx = -std::sin(ba), bny = std::cos(ba);
          q[0] = pts[i];
          q[8] = {pts[i].x + std::cos(ba) * bl, pts[i].y + std::sin(ba) * bl};
          int lv = 0;
          for (int st = 8; st > 1; st /= 2, lv++) {
            const float ampl = bl * 0.25f * std::pow(0.55f, float(lv));
            for (int m = st / 2; m < 9; m += st) {
              const Vec2 A = q[m - st / 2], B = q[m + st / 2];
              const float off = (hashU(js + uint32_t(i) * 401u + uint32_t(m) * 37u + uint32_t(lv) * 991u) - 0.5f) * 2.0f * ampl;
              q[m] = {0.5f * (A.x + B.x) + bnx * off, 0.5f * (A.y + B.y) + bny * off};
            }
          }
          bolt[bbin].moveTo(q[0].x * s, q[0].y * s);
          for (int m = 1; m < 9; m++) bolt[bbin].lineTo(q[m].x * s, q[m].y * s);
          any[bbin] = true;
        }
        const Vec2 e1{a.x1 * s, a.y1 * s}, e0{a.x0 * s, a.y0 * s};
        const float fr = s * 0.14f * std::min(a.power, 1.6f) * (0.6f + 0.4f * br);
        Paint fp = Paint::radial(e1, fr, {mixc(hot, white, 0.3f).opacity(std::min(0.55f * br * f.glow, 1.0f)), mid.opacity(std::min(0.18f * br, 1.0f)), deep.opacity(0.0f)}, {0.0f, 0.3f, 1.0f});
        fp.blend = Blend::plus;
        c.circle(e1, fr, fp);
        Paint op = Paint::radial(e0, fr * 0.5f, {hot.opacity(std::min(0.35f * br, 1.0f)), mid.opacity(std::min(0.1f * br, 1.0f)), deep.opacity(0.0f)}, {0.0f, 0.35f, 1.0f});
        op.blend = Blend::plus;
        c.circle(e0, fr * 0.5f, op);
      }
      const float lum = (1.0f + 0.6f * golpe) * f.glow;
      for (int bin = 0; bin < 3; bin++) {
        if (!any[bin]) continue;
        const float bl = (float(bin) + 0.6f) / 3.0f;
        Paint gp;
        gp.blend = Blend::plus;
        gp.strokeCap = 1;
        gp.strokeJoin = 1;
        gp.strokeWidth = s * 0.034f * thick;
        gp.color = deep.opacity(std::min(0.13f * bl * lum, 1.0f));
        c.path(bolt[bin], gp);
        Paint mp = gp;
        mp.strokeWidth = s * 0.011f * thick;
        mp.color = mid.opacity(std::min(0.5f * bl * lum, 1.0f));
        c.path(bolt[bin], mp);
        Paint cp = gp;
        cp.strokeWidth = std::max(1.2f, s * 0.004f * thick);
        cp.color = mixc(hot, white, 0.5f).opacity(std::min(0.95f * bl, 1.0f));
        c.path(bolt[bin], cp);
      }
      // En el modo Centro, la esfera de la bobina que zumba.
      if (w2 > 0.01f) {
        const Vec2 o{W * 0.5f * s, H * 0.5f * s};
        const float hum = 0.85f + 0.15f * std::sin(t * 40.0f) * std::sin(t * 23.0f);
        const float orr = s * 0.09f * g.tamano * (1.0f + 0.3f * golpe);
        Paint sp = Paint::radial(o, orr, {mixc(hot, white, 0.4f).opacity(std::min(0.6f * w2 * hum, 1.0f)), mid.opacity(std::min(0.22f * w2 * hum, 1.0f)), deep.opacity(0.0f)}, {0.0f, 0.35f, 1.0f});
        sp.blend = Blend::plus;
        c.circle(o, orr, sp);
      }
    }
    const float tail = 0.03f;
    for (const P& p : ps) {
      if (!p.on) continue;
      const float u = p.age / p.life;
      float b = 0, r = 0, heat = 0, grey = 0, ray = 0, px = p.x, py = p.y;
      b = (1.0f - u) * std::sqrt(1.0f - u) * (0.75f + 0.25f * std::sin(t * 60.0f + p.seed * 30.0f));
      r = p.size * g.tamano * (1.0f - 0.5f * u);
      heat = p.heat + 0.8f * u;
      (void)ray;
      b *= lift;
      if (p.seed > 0.55f) b *= 1.0f + agudos * (0.5f + 0.5f * std::sin(t * 23.0f + p.seed * 70.0f));
      b = std::clamp(b, 0.0f, 1.0f);
      if (b < 0.02f) continue;
      r *= swell;
      const Vec2 at{px * s, py * s};
      Color col = ramp(heat);
      if (grey > 0.0f) {
        const float lum = 0.3f * col.r + 0.59f * col.g + 0.11f * col.b;
        col = mixc(col, Color{lum, lum, lum, 1}, grey);
      }
      const float rp = r * s;
      if (p.kind > 1.5f) {
        // Nube: una bocanada grande y suave.
        const float a = std::min(b * 0.16f, 1.0f);
        Paint hp = Paint::radial(at, rp, {col.opacity(a), col.opacity(a * 0.55f), col.opacity(0.0f)}, {0.0f, 0.45f, 1.0f});
        hp.blend = Blend::plus;
        c.circle(at, rp, hp);
        continue;
      }
      if (p.kind > 0.5f) {
        // Cerca de la cámara: luz grande y desenfocada.
        const float a = std::min(b * 0.2f, 1.0f);
        Paint hp = Paint::radial(at, rp, {col.opacity(a), col.opacity(a * 0.8f), col.opacity(0.0f)}, {0.0f, 0.6f, 1.0f});
        hp.blend = Blend::plus;
        c.circle(at, rp, hp);
        continue;
      }
      const int sb = rp < 1.3f ? 0 : (rp < 2.4f ? 1 : 2);
      const int cb = heat < 0.25f ? 0 : (heat < 0.75f ? 1 : 2);
      const int bb = b < 0.35f ? 0 : (b < 0.7f ? 1 : 2);
      if (sb == 2) {
        // Las grandes: resplandor de degradado real, sin aros.
        const float hr = rp * 4.5f * 0.75f;
        const float ha = std::min(b * 0.5f * 0.55f * f.glow, 1.0f);
        if (ha > 0.01f) {
          Paint hp = Paint::radial(at, hr, {col.opacity(ha), col.opacity(ha * 0.28f), col.opacity(0.0f)}, {0.0f, 0.22f, 1.0f});
          hp.blend = Blend::plus;
          c.circle(at, hr, hp);
        }
      }
      cores[size_t(sb * 9 + cb * 3 + bb)].push_back(at);
      if (kRays && ray > 0.5f && b > 0.5f) {
        const float len = rp * (0.0f) * b;
        const int k = cb * 3 + bb;
        rays[size_t(k)].moveTo(at.x - len, at.y);
        rays[size_t(k)].lineTo(at.x + len, at.y);
        rays[size_t(k)].moveTo(at.x, at.y - len);
        rays[size_t(k)].lineTo(at.x, at.y + len);
        anyRay[k] = true;
      }
      const float sp = std::sqrt(p.vx * p.vx + p.vy * p.vy);
      if (tail > 0.0f && sp * tail * s > 2.0f) {
        const int k = cb * 3 + bb;
        streaks[size_t(k)].moveTo(at.x - p.vx * tail * s, at.y - p.vy * tail * s);
        streaks[size_t(k)].lineTo(at.x, at.y);
        streaksNear[size_t(k)].moveTo(at.x - p.vx * tail * s * 0.4f, at.y - p.vy * tail * s * 0.4f);
        streaksNear[size_t(k)].lineTo(at.x, at.y);
        anyStreak[k] = true;
      }
    }
    // Figuras (estelas de cometa, rayos) antes que los puntos.
    for (int k = 0; k < 9; k++) {
      const float bl = (float(k % 3) + 0.6f) / 3.0f;
      const Color col = ramp(float(k / 3) * 0.5f);
      if (anyStreak[k]) {
        Paint sp;
        sp.blend = Blend::plus;
        sp.strokeCap = 1;
        sp.strokeWidth = std::max(1.0f, s * 0.003f * g.tamano * swell * (0.7f + 0.3f * float(k % 3)));
        sp.color = col.opacity(std::clamp(bl * 0.32f, 0.0f, 1.0f));
        Paint far = sp;
        far.strokeWidth *= 0.65f;
        c.path(streaks[size_t(k)], far);
        sp.color = col.opacity(std::clamp(bl * 0.55f, 0.0f, 1.0f));
        c.path(streaksNear[size_t(k)], sp);
      }
      if (anyRay[k]) {
        Paint rp;
        rp.blend = Blend::plus;
        rp.strokeCap = 1;
        rp.strokeWidth = std::max(0.8f, s * 0.0026f * g.tamano * 0.45f);
        rp.color = mixc(col, white, 0.4f).opacity(std::clamp(bl * 0.65f, 0.0f, 1.0f));
        c.path(rays[size_t(k)], rp);
      }
    }
    // Cada partícula: halos tenues que se suman en un brillo suave, el
    // núcleo y un centro casi blanco.
    for (int sb = 0; sb < 3; sb++) {
      const float rr = s * 0.0026f * g.tamano * (sb == 0 ? 0.55f : (sb == 1 ? 1.0f : 1.8f)) * swell;
      for (int k = 0; k < 9; k++) {
        const auto& pts = cores[size_t(sb * 9 + k)];
        if (pts.empty()) continue;
        const int cb = k / 3;
        const float bl = (float(k % 3) + 0.6f) / 3.0f;
        const Color col = ramp(float(cb) * 0.5f);
        const float ha = bl * 0.5f * f.glow;
        const float hk[3] = {0.55f, 0.36f, 0.24f};
        const float hw[3] = {0.12f, 0.2f, 0.32f};
        for (int i = sb == 2 ? 2 : 0; i < 3; i++) {
          if (ha * hw[i] < 0.004f) continue;
          Paint hp;
          hp.blend = Blend::plus;
          hp.color = col.opacity(std::clamp(ha * hw[i], 0.0f, 1.0f));
          c.points(pts, rr * 4.5f * hk[i], hp);
        }
        Paint core;
        core.blend = Blend::plus;
        core.color = mixc(col, white, 0.12f).opacity(std::clamp(bl, 0.0f, 1.0f));
        c.points(pts, std::max(0.8f, rr), core);
        if (k % 3 == 2) {
          Paint hotc;
          hotc.blend = Blend::plus;
          hotc.color = mixc(col, white, 0.45f).opacity(0.8f);
          c.points(pts, std::max(0.6f, rr * 0.5f), hotc);
        }
      }
    }
  }
};
''';
