// Estela Mágica — capa transparente premium. Referencia: vídeos de stock
// «Sparkling Particle Trail Overlay» y «Magic Particle Swirl». Luces mágicas
// que vuelan haciendo espirales y ondas y dejan una cinta brillante con hebras
// que se enroscan y un rastro de polvo de estrellas que titila y cae. Sin
// fondo, encima de cualquier visual. Partículas simuladas con física a paso
// fijo y dibujadas con resplandor suave, núcleo caliente y estela, más su
// efecto propio; barato para el móvil (puntos agrupados y degradados). Pulso:
// Golpes lanza su efecto con cada golpe y lo aviva; Graves lo hincha; Brillos
// lo hace centellear.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.slider('tamano', 'Tamaño', min: .5, max: 2, value: 1),
  // FORMA: cuántas luces vuelan.
  CreatorModifier.steps('estelas', 'Estelas', min: 1, max: 4, value: 2),
  // MOVIMIENTO: el camino que trazan.
  CreatorModifier.choice('vuelo', 'Vuelo', options: ['Espiral', 'Ondas', 'Libre']),
  // ATMÓSFERA: cuánto polvo de estrellas sueltan.
  CreatorModifier.slider('polvo', 'Polvo de estrellas', min: 0, max: 1, value: .6),
  // MÚSICA
  CreatorModifier.choice('pulso', 'Pulso', options: ['Golpes', 'Graves', 'Brillos']),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Hada', {'estelas': 1, 'vuelo': 'Libre', 'polvo': 1, 'tamano': 1.2}),
  CreatorVariation('Torbellino', {'estelas': 4, 'vuelo': 'Espiral', 'polvo': .5, 'speed': 1.3}),
];

const nativeSource = r'''
class Visual final : public Scene {
  // Reservado para detail 2: nunca se reserva memoria al cambiar un ajuste.
  static constexpr int kMax = 3600;
  static constexpr double kStep = 1.0 / 60.0;
  // Pasos simulados antes del primer cuadro: la escena ya empieza viva.
  static constexpr int kWarm = 240;
  static constexpr bool kRays = true;
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
  static constexpr int kHeads = 4;
  static constexpr int kHist = 160;  // más de dos segundos y medio de rastro
  std::array<std::array<Vec2, kHist>, kHeads> hist{};
  std::array<Vec2, kHeads> head{}, headVel{};
  std::array<double, kHeads> emitHead{};
  int histPos = 0, histCount = 0;
  // Camino de la luz i: espiral, ondas o libre (se mezclan al cambiar Vuelo).
  Vec2 headAt(int i, float t) const {
    const float fi = float(i);
    const float sd = std::min(W, H);
    const float cx = W * (0.5f + 0.22f * std::sin(t * 0.13f + fi * 2.1f));
    const float cy = H * (0.5f + 0.26f * std::sin(t * 0.11f + fi * 1.3f));
    const float rr = sd * (0.22f + 0.1f * std::sin(t * 0.5f + fi));
    const float a = (1.15f + 0.22f * fi) * t + fi * 1.57f;
    const float ex = cx + rr * std::cos(a), ey = cy + rr * 1.25f * std::sin(a);
    const float ox = W * (0.5f + 0.46f * std::sin(t * 0.33f + fi * 1.9f));
    const float oy = H * (0.18f + 0.64f * (fi + 0.5f) / 4.0f) + sd * 0.1f * std::sin(t * 2.1f + fi * 1.1f);
    const float lx = W * (0.5f + 0.42f * std::sin(t * 0.47f * (1.0f + 0.13f * fi) + fi * 2.1f));
    const float ly = H * (0.5f + 0.4f * std::sin(t * 0.37f * (1.0f + 0.17f * fi) + fi * 0.7f));
    return {w0 * ex + w1 * ox + w2 * lx, w0 * ey + w1 * oy + w2 * ly};
  }
  void spawn(bool fromBurst, float power) {
    uint32_t k;
    P& p = fresh(k);
    const float h1 = hashU(k + 1u), h2 = hashU(k + 2u), h3 = hashU(k + 3u), h4 = hashU(k + 4u);
    const float h5 = hashU(k + 5u), h6 = hashU(k + 6u), h7 = hashU(k + 7u), h9 = hashU(k + 9u);
    const float TAU = 6.2831853f;
    (void)h1; (void)h2; (void)h3; (void)h4; (void)h5; (void)h6; (void)h7; (void)h9;
    (void)fromBurst; (void)power; (void)TAU;
    // Golpe: cada luz suelta un estallido de chispitas.
    const int hi = int(h7 * std::max(k1, 1.0f)) % kHeads;
    const Vec2 at = head[size_t(hi)];
    const float ang = h1 * TAU;
    const float sp = (0.12f + 0.45f * h2) * (0.6f + 0.5f * power);
    p.x = at.x;
    p.y = at.y;
    p.vx = std::cos(ang) * sp;
    p.vy = std::sin(ang) * sp;
    p.life = 0.7f + 1.0f * h5;
    p.size = 0.0026f * (0.7f + 1.5f * h6 * h6);
    p.heat = 0.0f;
    p.a0 = float(hi);
  }
  void step(float dt) {
    // La hora del propio paso: igual a 30 y a 60 FPS.
    const float t = float(std::fmod(double(steps) * kStep, 4000.0));
    (void)t;
    // Cada luz avanza por su camino, guarda su rastro y suelta polvo de estrellas.
    histPos = (histPos + 1) % kHist;
    histCount = std::min(histCount + 1, kHist);
    for (int i = 0; i < kHeads; i++) {
      const Vec2 at = headAt(i, t);
      headVel[size_t(i)] = histCount <= 1 ? Vec2{0.0f, 0.0f} : Vec2{(at.x - head[size_t(i)].x) / dt, (at.y - head[size_t(i)].y) / dt};
      head[size_t(i)] = at;
      hist[size_t(i)][size_t(histPos)] = at;
      const float alive = std::clamp(k1 - float(i), 0.0f, 1.0f);
      emitHead[size_t(i)] += double(alive * k3) * double(dt);
      while (emitHead[size_t(i)] >= 1.0) {
        emitHead[size_t(i)] -= 1.0;
        uint32_t k;
        P& q = fresh(k);
        const float h1 = hashU(k + 1u), h2 = hashU(k + 2u), h3 = hashU(k + 3u);
        const float h4 = hashU(k + 4u), h5 = hashU(k + 5u), h6 = hashU(k + 6u);
        const float ang = h1 * 6.2831853f;
        const float sp = 0.03f + 0.16f * h2 * h2;
        q.x = at.x + (h3 - 0.5f) * 0.01f;
        q.y = at.y + (h4 - 0.5f) * 0.01f;
        q.vx = headVel[size_t(i)].x * 0.22f + std::cos(ang) * sp;
        q.vy = headVel[size_t(i)].y * 0.22f + std::sin(ang) * sp;
        q.life = 1.0f + 1.8f * h5;
        q.kind = h6 < 0.03f ? 1.0f : 0.0f;
        q.size = q.kind > 0.5f ? 0.01f + 0.012f * h5 : 0.0022f * (0.6f + 2.0f * h6 * h6 * h6);
        q.heat = 0.1f * h3;
        q.a0 = float(i);
      }
    }
    emitAcc += double(rate) * double(dt);
    while (emitAcc >= 1.0) {
      emitAcc -= 1.0;
      spawn(false, 0.0f);
    }
    for (P& p : ps) {
      if (!p.on) continue;
      // Polvo de estrellas: se frena, cae despacio y lo mece el aire.
      const float drag = std::exp(-1.6f * dt);
      p.vx *= drag;
      p.vy = p.vy * drag + 0.05f * dt;
      const Vec2 cv = curl(p.x, p.y, t * 0.4f, 3.0f);
      p.vx += cv.x * 0.025f * dt;
      p.vy += cv.y * 0.025f * dt;
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
    for (auto& hh : hist) hh.fill(Vec2{0.0f, 0.0f});
    head.fill(Vec2{0.0f, 0.0f});
    headVel.fill(Vec2{0.0f, 0.0f});
    emitHead.fill(0.0);
    histPos = 0;
    histCount = 0;
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
    k1 = g.estelas;
    k3 = 170.0f * (0.25f + 0.75f * g.polvo) * f.detail;
    w0 = g.vuelo.weight(0);
    w1 = g.vuelo.weight(1);
    w2 = g.vuelo.weight(2);
    rate = 0.0f;
    rate *= 0.5f * f.detail * (1.0f + 0.5f * std::min(energy * f.intensity, 1.0f));
    sim += f.delta * f.speed;
    const int64_t target = int64_t(std::floor(sim / kStep + 1e-6));
    if (target - steps > kWarm + 240) steps = target - 240;
    while (steps < target) {
      steps++;
      if (burst > 0.0f) {
        const int n = int(45.0f * std::min(burst, 1.5f));
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
      // Rastro: cintas por edad (la más nueva, la más brillante y ancha) y dos
      // hebras que se enroscan alrededor como energía.
      constexpr int kAges = 6;
      Path trail[kAges], strandA[kAges], strandB[kAges];
      bool any[kAges] = {false, false, false, false, false, false};
      const int n = histCount;
      for (int i = 0; i < kHeads; i++) {
        const float alive = std::clamp(k1 - float(i), 0.0f, 1.0f);
        if (alive <= 0.01f || n < 3) continue;
        int lastBin = -1;
        Vec2 prev{0.0f, 0.0f}, prevA{0.0f, 0.0f}, prevB{0.0f, 0.0f};
        for (int j = 0; j < n - 1; j++) {
          const int ia = (histPos - j + kHist) % kHist, ib = (histPos - j - 1 + kHist) % kHist;
          const Vec2 a = hist[size_t(i)][size_t(ia)], nb = hist[size_t(i)][size_t(ib)];
          float tx = nb.x - a.x, ty = nb.y - a.y;
          const float tl = std::sqrt(tx * tx + ty * ty) + 1e-6f;
          tx /= tl;
          ty /= tl;
          const float age = float(j) / float(kHist);
          const float amp = 0.02f * (1.0f - 0.5f * age) * alive;
          const float ph = float(j) * 0.38f - ts * 9.0f + float(i) * 1.7f;
          const Vec2 pa{a.x - ty * amp * std::sin(ph), a.y + tx * amp * std::sin(ph)};
          const Vec2 pb{a.x + ty * amp * std::sin(ph + 1.6f), a.y - tx * amp * std::sin(ph + 1.6f)};
          const int bin = std::min(kAges - 1, j * kAges / kHist);
          if (bin != lastBin) {
            if (j > 0) {
              trail[bin].moveTo(prev.x * s, prev.y * s);
              strandA[bin].moveTo(prevA.x * s, prevA.y * s);
              strandB[bin].moveTo(prevB.x * s, prevB.y * s);
            } else {
              trail[bin].moveTo(a.x * s, a.y * s);
              strandA[bin].moveTo(pa.x * s, pa.y * s);
              strandB[bin].moveTo(pb.x * s, pb.y * s);
            }
            lastBin = bin;
          }
          trail[bin].lineTo(a.x * s, a.y * s);
          strandA[bin].lineTo(pa.x * s, pa.y * s);
          strandB[bin].lineTo(pb.x * s, pb.y * s);
          any[bin] = true;
          prev = a;
          prevA = pa;
          prevB = pb;
        }
      }
      const float lum = (1.0f + 0.5f * golpe) * f.glow;
      const float wide = g.tamano * (1.0f + 0.35f * graves);
      for (int bin = 0; bin < kAges; bin++) {
        if (!any[bin]) continue;
        const float af = (float(bin) + 0.5f) / float(kAges);
        const float fade = (1.0f - af) * std::sqrt(1.0f - af);
        const Color tc = ramp(af * 0.9f);
        Paint gp;
        gp.blend = Blend::plus;
        gp.strokeCap = 1;
        gp.strokeJoin = 1;
        gp.strokeWidth = s * 0.07f * wide * (1.0f - 0.55f * af);
        gp.color = tc.opacity(std::min(0.08f * fade * lum, 1.0f));
        c.path(trail[bin], gp);
        Paint bp = gp;
        bp.strokeWidth = s * 0.02f * wide * (1.0f - 0.5f * af);
        bp.color = tc.opacity(std::min(0.32f * fade * lum, 1.0f));
        c.path(trail[bin], bp);
        Paint cp = gp;
        cp.strokeWidth = std::max(1.0f, s * 0.0048f * wide * (1.0f - 0.5f * af));
        cp.color = mixc(white, tc, af).opacity(std::min(0.85f * fade, 1.0f));
        c.path(trail[bin], cp);
        Paint sp = gp;
        sp.strokeWidth = std::max(1.0f, s * 0.0026f * wide);
        sp.color = mixc(hot, white, 0.3f).opacity(std::min(0.55f * fade * lum, 1.0f));
        c.path(strandA[bin], sp);
        c.path(strandB[bin], sp);
      }
      // La cabeza de cada luz: resplandor, núcleo blanco y destello en cruz.
      for (int i = 0; i < kHeads; i++) {
        const float alive = std::clamp(k1 - float(i), 0.0f, 1.0f);
        if (alive <= 0.01f) continue;
        const Vec2 at{head[size_t(i)].x * s, head[size_t(i)].y * s};
        const float pulse = 1.0f + 0.5f * golpe + 0.35f * graves;
        const float fl = 0.88f + 0.12f * std::sin(t * 17.0f + float(i) * 2.0f);
        const float hr = s * 0.11f * pulse * g.tamano;
        Paint gp = Paint::radial(at, hr, {hot.opacity(std::min(0.42f * alive * fl * f.glow, 1.0f)), mid.opacity(std::min(0.12f * alive, 1.0f)), mid.opacity(0.0f)}, {0.0f, 0.3f, 1.0f});
        gp.blend = Blend::plus;
        c.circle(at, hr, gp);
        const float cr = s * 0.022f * pulse * g.tamano;
        Paint cp = Paint::radial(at, cr, {white.opacity(std::min(0.95f * alive, 1.0f)), hot.opacity(std::min(0.6f * alive, 1.0f)), hot.opacity(0.0f)}, {0.0f, 0.4f, 1.0f});
        cp.blend = Blend::plus;
        c.circle(at, cr, cp);
        const float L = s * 0.075f * pulse * g.tamano;
        const float ang = t * 0.5f + float(i);
        const float ca = std::cos(ang), sa = std::sin(ang);
        Path fp;
        fp.moveTo(at.x - ca * L, at.y - sa * L);
        fp.lineTo(at.x + ca * L, at.y + sa * L);
        fp.moveTo(at.x + sa * L * 0.6f, at.y - ca * L * 0.6f);
        fp.lineTo(at.x - sa * L * 0.6f, at.y + ca * L * 0.6f);
        Paint lp;
        lp.blend = Blend::plus;
        lp.strokeCap = 1;
        lp.strokeWidth = std::max(1.0f, s * 0.0028f);
        lp.color = mixc(hot, white, 0.5f).opacity(std::min(0.5f * alive * fl, 1.0f));
        c.path(fp, lp);
      }
    }
    const float tail = 0.015f;
    for (const P& p : ps) {
      if (!p.on) continue;
      const float u = p.age / p.life;
      float b = 0, r = 0, heat = 0, grey = 0, ray = 0, px = p.x, py = p.y;
      const float in = std::min(u / 0.04f, 1.0f);
      const float out = (1.0f - u) * std::sqrt(1.0f - u);
      const float tw = 0.65f + 0.35f * std::sin(t * (8.0f + 12.0f * p.seed) + p.seed * 50.0f);
      const float s1 = std::max(std::sin(t * (3.0f + 4.0f * p.seed) + p.seed * 70.0f), 0.0f);
      const float s2 = s1 * s1, s4 = s2 * s2;
      const float glint = s4 * s4 * s2;
      b = in * out * (tw + 1.2f * glint) * (p.kind > 0.5f ? 0.45f : 1.0f);
      r = p.size * g.tamano * (1.0f - 0.45f * u) * (1.0f + 0.6f * glint);
      heat = p.heat + 0.95f * u;
      ray = glint > 0.4f ? 1.0f : 0.0f;
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
        const float a = std::min(b * 0.22f, 1.0f);
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
        const float hr = rp * 5.0f * 0.75f;
        const float ha = std::min(b * 0.6f * 0.55f * f.glow, 1.0f);
        if (ha > 0.01f) {
          Paint hp = Paint::radial(at, hr, {col.opacity(ha), col.opacity(ha * 0.28f), col.opacity(0.0f)}, {0.0f, 0.22f, 1.0f});
          hp.blend = Blend::plus;
          c.circle(at, hr, hp);
        }
      }
      cores[size_t(sb * 9 + cb * 3 + bb)].push_back(at);
      if (kRays && ray > 0.5f && b > 0.5f) {
        const float len = rp * (5.0f) * b;
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
        rp.strokeWidth = std::max(0.8f, s * 0.0032f * g.tamano * 0.45f);
        rp.color = mixc(col, white, 0.4f).opacity(std::clamp(bl * 0.65f, 0.0f, 1.0f));
        c.path(rays[size_t(k)], rp);
      }
    }
    // Cada partícula: halos tenues que se suman en un brillo suave, el
    // núcleo y un centro casi blanco.
    for (int sb = 0; sb < 3; sb++) {
      const float rr = s * 0.0032f * g.tamano * (sb == 0 ? 0.55f : (sb == 1 ? 1.0f : 1.8f)) * swell;
      for (int k = 0; k < 9; k++) {
        const auto& pts = cores[size_t(sb * 9 + k)];
        if (pts.empty()) continue;
        const int cb = k / 3;
        const float bl = (float(k % 3) + 0.6f) / 3.0f;
        const Color col = ramp(float(cb) * 0.5f);
        const float ha = bl * 0.6f * f.glow;
        const float hk[3] = {0.55f, 0.36f, 0.24f};
        const float hw[3] = {0.12f, 0.2f, 0.32f};
        for (int i = sb == 2 ? 2 : 0; i < 3; i++) {
          if (ha * hw[i] < 0.004f) continue;
          Paint hp;
          hp.blend = Blend::plus;
          hp.color = col.opacity(std::clamp(ha * hw[i], 0.0f, 1.0f));
          c.points(pts, rr * 5.0f * hk[i], hp);
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
