// Bengala — capa transparente premium. Referencia: vídeos de stock «Sparkler
// Overlay» y «4K Sparkles/Lights Transition Overlay». Bengalas que dibujan en
// el aire: dejan un trazo de luz que se apaga despacio, como en una foto de
// larga exposición, y su punta escupe chispas que se parten en dos al volar.
// Sin fondo, encima de cualquier visual. Partículas simuladas con física a
// paso fijo y dibujadas con resplandor suave, núcleo caliente y estela, más su
// efecto propio; barato para el móvil (puntos agrupados y degradados). Pulso:
// Golpes lanza su efecto con cada golpe y lo aviva; Graves lo hincha; Brillos
// lo hace centellear.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.slider('tamano', 'Tamaño', min: .5, max: 2, value: 1),
  // FORMA: cuántas bengalas dibujan a la vez.
  CreatorModifier.steps('trazos', 'Bengalas', min: 1, max: 3, value: 2),
  // MOVIMIENTO: lo que dibujan.
  CreatorModifier.choice('dibujo', 'Dibujo', options: ['Bucles', 'Espiral', 'Ola']),
  // ATMÓSFERA: cuánto tarda en apagarse el trazo de luz.
  CreatorModifier.slider('persistencia', 'Persistencia del trazo', min: .5, max: 4, value: 2.2),
  // MÚSICA
  CreatorModifier.choice('pulso', 'Pulso', options: ['Golpes', 'Graves', 'Brillos']),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Firma de Luz', {'trazos': 1, 'dibujo': 'Bucles', 'persistencia': 4}),
  CreatorVariation('Fiesta', {'trazos': 3, 'dibujo': 'Ola', 'persistencia': 1.2, 'speed': 1.4}),
];

const nativeSource = r'''
class Visual final : public Scene {
  // Reservado para detail 2: nunca se reserva memoria al cambiar un ajuste.
  static constexpr int kMax = 3200;
  static constexpr double kStep = 1.0 / 60.0;
  // Pasos simulados antes del primer cuadro: la escena ya empieza viva.
  static constexpr int kWarm = 120;
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
  static constexpr int kPens = 3;
  static constexpr int kHist = 240;  // hasta cuatro segundos de trazo
  std::array<std::array<Vec2, kHist>, kPens> hist{};
  std::array<Vec2, kPens> tip{}, tipVel{};
  std::array<double, kPens> sparkAcc{};
  int histPos = 0, histCount = 0;
  // Chispas que se parten en el aire: se crean al terminar el paso.
  struct Fork { float x, y, vx, vy, life, size, heat; };
  std::array<Fork, 192> forks{};
  int forkCount = 0;
  // Dónde está la punta de la bengala i: bucles de letra cursiva, una espiral
  // que se abre y se cierra o una ola de lado a lado.
  Vec2 tipAt(int i, float t) const {
    const float fi = float(i);
    const float sd = std::min(W, H);
    const float bx = W * (0.5f + 0.3f * std::sin(t * 0.19f + fi * 2.1f)) + sd * (0.13f * std::cos(1.7f * t + fi) + 0.05f * std::cos(-5.3f * t + fi * 2.0f));
    const float by = H * (0.5f + 0.27f * std::sin(t * 0.15f + fi * 1.4f)) + sd * (0.13f * std::sin(1.7f * t + fi) + 0.05f * std::sin(-5.3f * t + fi * 2.0f));
    const float rr = sd * (0.05f + 0.23f * (0.5f + 0.5f * std::sin(t * 0.31f + fi * 1.7f)));
    const float sx = W * (0.5f + 0.18f * std::sin(t * 0.09f + fi * 2.4f)) + rr * std::cos(2.3f * t + fi * 2.0f);
    const float sy = H * (0.5f + 0.25f * std::sin(t * 0.08f + fi * 1.2f)) + rr * std::sin(2.3f * t + fi * 2.0f);
    const float ox = W * (0.5f + 0.46f * std::sin(t * 0.42f + fi * 2.0f));
    const float oy = H * (0.25f + 0.25f * fi) + sd * 0.11f * std::sin(t * 3.9f + fi);
    return {w0 * bx + w1 * sx + w2 * ox, w0 * by + w1 * sy + w2 * oy};
  }
  void spawn(bool fromBurst, float power) {
    uint32_t k;
    P& p = fresh(k);
    const float h1 = hashU(k + 1u), h2 = hashU(k + 2u), h3 = hashU(k + 3u), h4 = hashU(k + 4u);
    const float h5 = hashU(k + 5u), h6 = hashU(k + 6u), h7 = hashU(k + 7u), h9 = hashU(k + 9u);
    const float TAU = 6.2831853f;
    (void)h1; (void)h2; (void)h3; (void)h4; (void)h5; (void)h6; (void)h7; (void)h9;
    (void)fromBurst; (void)power; (void)TAU;
    // Golpe: la bengala chisporrotea con fuerza.
    const int pi = int(h7 * std::max(k1, 1.0f)) % kPens;
    const Vec2 at = tip[size_t(pi)];
    const float ang = h1 * TAU;
    const float sp = (0.6f + 1.6f * h2) * (0.7f + 0.4f * power);
    p.x = at.x;
    p.y = at.y;
    p.vx = std::cos(ang) * sp;
    p.vy = std::sin(ang) * sp;
    p.life = 0.25f + 0.45f * h3;
    p.size = 0.0024f * (0.6f + 1.4f * h4 * h4);
    p.heat = 0.1f * h5;
    p.a1 = h6 < 0.5f ? 1.0f : 0.0f;
    p.a0 = 0.3f + 0.4f * h9;
  }
  void step(float dt) {
    // La hora del propio paso: igual a 30 y a 60 FPS.
    const float t = float(std::fmod(double(steps) * kStep, 4000.0));
    (void)t;
    // La punta avanza, deja su trazo de luz y escupe chispas.
    histPos = (histPos + 1) % kHist;
    histCount = std::min(histCount + 1, kHist);
    for (int i = 0; i < kPens; i++) {
      const Vec2 at = tipAt(i, t);
      tipVel[size_t(i)] = histCount <= 1 ? Vec2{0.0f, 0.0f} : Vec2{(at.x - tip[size_t(i)].x) / dt, (at.y - tip[size_t(i)].y) / dt};
      tip[size_t(i)] = at;
      hist[size_t(i)][size_t(histPos)] = at;
      const float alive = std::clamp(k1 - float(i), 0.0f, 1.0f);
      sparkAcc[size_t(i)] += double(alive * k3) * double(dt);
      while (sparkAcc[size_t(i)] >= 1.0) {
        sparkAcc[size_t(i)] -= 1.0;
        uint32_t k;
        P& q = fresh(k);
        const float h1 = hashU(k + 1u), h2 = hashU(k + 2u), h3 = hashU(k + 3u), h4 = hashU(k + 4u);
        const float h5 = hashU(k + 5u), h6 = hashU(k + 6u), h7 = hashU(k + 7u);
        const float ang = h1 * 6.2831853f;
        const float sp = 0.3f + 1.2f * h2 * std::sqrt(h2);
        q.x = at.x;
        q.y = at.y;
        q.vx = std::cos(ang) * sp + tipVel[size_t(i)].x * 0.25f;
        q.vy = std::sin(ang) * sp + tipVel[size_t(i)].y * 0.25f;
        q.life = 0.12f + 0.38f * h3;
        q.size = 0.002f * (0.6f + 1.5f * h4 * h4);
        q.heat = 0.12f * h5;
        q.a1 = h6 < 0.38f ? 1.0f : 0.0f;
        q.a0 = 0.3f + 0.4f * h7;
      }
    }
    emitAcc += double(rate) * double(dt);
    while (emitAcc >= 1.0) {
      emitAcc -= 1.0;
      spawn(false, 0.0f);
    }
    for (P& p : ps) {
      if (!p.on) continue;
      // Gravedad y aire; algunas se parten en dos o tres al volar.
      const float drag = std::exp(-1.4f * dt);
      p.vx *= drag;
      p.vy = p.vy * drag + 0.9f * dt;
      if (p.a1 > 0.5f && p.age > p.a0 * p.life && forkCount < int(forks.size()) - 3) {
        p.a1 = 0.0f;
        const float ang0 = std::atan2(p.vy, p.vx);
        const float sp0 = std::sqrt(p.vx * p.vx + p.vy * p.vy) * 0.8f;
        const int nk = 2 + int(p.seed * 1.99f);
        for (int j = 0; j < nk; j++) {
          const float da = (float(j) - 0.5f * float(nk - 1)) * (0.5f + 0.4f * p.seed);
          forks[size_t(forkCount++)] = {p.x, p.y, std::cos(ang0 + da) * sp0, std::sin(ang0 + da) * sp0, (p.life - p.age) * 0.9f, p.size * 0.7f, p.heat + 0.15f};
        }
      }
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.age += dt;
      if (p.age >= p.life || p.x < -0.6f || p.x > W + 0.6f || p.y < -0.6f || p.y > H + 0.6f) p.on = false;
    }
    for (int j = 0; j < forkCount; j++) {
      const Fork fk = forks[size_t(j)];
      uint32_t k;
      P& q = fresh(k);
      q.x = fk.x;
      q.y = fk.y;
      q.vx = fk.vx;
      q.vy = fk.vy;
      q.life = std::max(fk.life, 0.05f);
      q.size = fk.size;
      q.heat = fk.heat;
    }
    forkCount = 0;
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
    tip.fill(Vec2{0.0f, 0.0f});
    tipVel.fill(Vec2{0.0f, 0.0f});
    sparkAcc.fill(0.0);
    histPos = 0;
    histCount = 0;
    forkCount = 0;
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
    k1 = g.trazos;
    k2 = g.persistencia;
    k3 = 300.0f * f.detail;
    w0 = g.dibujo.weight(0);
    w1 = g.dibujo.weight(1);
    w2 = g.dibujo.weight(2);
    rate = 0.0f;
    rate *= 0.5f * f.detail * (1.0f + 0.5f * std::min(energy * f.intensity, 1.0f));
    sim += f.delta * f.speed;
    const int64_t target = int64_t(std::floor(sim / kStep + 1e-6));
    if (target - steps > kWarm + 240) steps = target - 240;
    while (steps < target) {
      steps++;
      if (burst > 0.0f) {
        const int n = int(60.0f * std::min(burst, 1.5f));
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
      // El trazo de luz de cada bengala, como en una foto de larga exposición:
      // se apaga despacio y en él quedan chispitas que titilan.
      constexpr int kAges = 8;
      Path trail[kAges];
      bool any[kAges] = {false, false, false, false, false, false, false, false};
      const int maxAge = std::clamp(int(k2 * 60.0f), 2, kHist - 1);
      const int n = std::min(histCount, maxAge + 1);
      for (int i = 0; i < kPens; i++) {
        const float alive = std::clamp(k1 - float(i), 0.0f, 1.0f);
        if (alive <= 0.01f || n < 3) continue;
        int lastBin = -1;
        Vec2 prev{0.0f, 0.0f};
        for (int j = 0; j < n; j++) {
          const Vec2 a = hist[size_t(i)][size_t((histPos - j + kHist) % kHist)];
          const int bin = std::min(kAges - 1, j * kAges / n);
          if (bin != lastBin) {
            if (j > 0) trail[bin].moveTo(prev.x * s, prev.y * s);
            else trail[bin].moveTo(a.x * s, a.y * s);
            lastBin = bin;
          }
          trail[bin].lineTo(a.x * s, a.y * s);
          any[bin] = true;
          prev = a;
          const uint32_t id = uint32_t(steps - int64_t(j)) * 2654435761u + uint32_t(i) * 97u;
          if (hashU(id) < 0.06f * alive) {
            const float fl = std::max(std::sin(t * 13.0f + hashU(id + 3u) * 40.0f), 0.0f) * (1.0f - float(j) / float(n));
            if (fl > 0.25f) cores[size_t(fl > 0.65f ? 2 : 1)].push_back(Vec2{a.x * s, a.y * s});
          }
        }
      }
      const float lum = (1.0f + 0.6f * golpe) * f.glow;
      const float wide = g.tamano * (1.0f + 0.3f * graves);
      for (int bin = 0; bin < kAges; bin++) {
        if (!any[bin]) continue;
        const float af = (float(bin) + 0.5f) / float(kAges);
        const float fade = (1.0f - af) * std::sqrt(1.0f - af);
        Paint gp;
        gp.blend = Blend::plus;
        gp.strokeCap = 1;
        gp.strokeJoin = 1;
        gp.strokeWidth = s * 0.065f * wide;
        gp.color = mid.opacity(std::min(0.08f * fade * lum, 1.0f));
        c.path(trail[bin], gp);
        Paint bp = gp;
        bp.strokeWidth = s * 0.019f * wide;
        bp.color = mixc(hot, mid, 0.3f + 0.5f * af).opacity(std::min(0.36f * fade * lum, 1.0f));
        c.path(trail[bin], bp);
        Paint cp = gp;
        cp.strokeWidth = std::max(1.0f, s * 0.0058f * wide);
        cp.color = mixc(white, hot, af).opacity(std::min(0.95f * fade, 1.0f));
        c.path(trail[bin], cp);
      }
      // La punta: resplandor que tiembla, núcleo blanco y su crepitar.
      for (int i = 0; i < kPens; i++) {
        const float alive = std::clamp(k1 - float(i), 0.0f, 1.0f);
        if (alive <= 0.01f) continue;
        const Vec2 at{tip[size_t(i)].x * s, tip[size_t(i)].y * s};
        const float fl = 0.8f + 0.2f * std::sin(t * 31.0f + float(i) * 2.0f) * std::sin(t * 17.0f + float(i));
        const float pulse = (1.0f + 0.6f * golpe + 0.3f * graves) * alive;
        const float gr = s * 0.17f * g.tamano * (1.0f + 0.2f * golpe);
        Paint gp = Paint::radial(at, gr, {hot.opacity(std::min(0.36f * fl * pulse * f.glow, 1.0f)), mid.opacity(std::min(0.12f * pulse, 1.0f)), mid.opacity(0.0f)}, {0.0f, 0.25f, 1.0f});
        gp.blend = Blend::plus;
        c.circle(at, gr, gp);
        const float cr = s * 0.026f * g.tamano;
        Paint cp = Paint::radial(at, cr, {white.opacity(std::min(alive, 1.0f)), hot.opacity(std::min(0.7f * alive, 1.0f)), hot.opacity(0.0f)}, {0.0f, 0.35f, 1.0f});
        cp.blend = Blend::plus;
        c.circle(at, cr, cp);
        Path cr2;
        const uint32_t base = uint32_t(steps / 2) * 131u + uint32_t(i) * 7u;
        for (int j = 0; j < 7; j++) {
          const float a = hashU(base + uint32_t(j) * 3u) * 6.2831853f;
          const float L = s * (0.02f + 0.05f * hashU(base + uint32_t(j) * 3u + 1u)) * g.tamano;
          cr2.moveTo(at.x, at.y);
          cr2.lineTo(at.x + std::cos(a) * L, at.y + std::sin(a) * L);
        }
        Paint rp;
        rp.blend = Blend::plus;
        rp.strokeCap = 1;
        rp.strokeWidth = std::max(1.0f, s * 0.0024f);
        rp.color = mixc(hot, white, 0.6f).opacity(std::min(0.7f * alive, 1.0f));
        c.path(cr2, rp);
      }
    }
    const float tail = 0.035f;
    for (const P& p : ps) {
      if (!p.on) continue;
      const float u = p.age / p.life;
      float b = 0, r = 0, heat = 0, grey = 0, ray = 0, px = p.x, py = p.y;
      b = (1.0f - u) * std::sqrt(1.0f - u) * (0.8f + 0.2f * std::sin(t * 50.0f + p.seed * 30.0f));
      r = p.size * g.tamano * (1.0f - 0.5f * u);
      heat = p.heat + 0.9f * u;
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
        const float ha = std::min(b * 0.55f * 0.55f * f.glow, 1.0f);
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
        sp.strokeWidth = std::max(1.0f, s * 0.0032f * g.tamano * swell * (0.7f + 0.3f * float(k % 3)));
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
        rp.strokeWidth = std::max(0.8f, s * 0.0028f * g.tamano * 0.45f);
        rp.color = mixc(col, white, 0.4f).opacity(std::clamp(bl * 0.65f, 0.0f, 1.0f));
        c.path(rays[size_t(k)], rp);
      }
    }
    // Cada partícula: halos tenues que se suman en un brillo suave, el
    // núcleo y un centro casi blanco.
    for (int sb = 0; sb < 3; sb++) {
      const float rr = s * 0.0028f * g.tamano * (sb == 0 ? 0.55f : (sb == 1 ? 1.0f : 1.8f)) * swell;
      for (int k = 0; k < 9; k++) {
        const auto& pts = cores[size_t(sb * 9 + k)];
        if (pts.empty()) continue;
        const int cb = k / 3;
        const float bl = (float(k % 3) + 0.6f) / 3.0f;
        const Color col = ramp(float(cb) * 0.5f);
        const float ha = bl * 0.55f * f.glow;
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
