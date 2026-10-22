// Río de Partículas — capa transparente premium. Referencia: vídeos de stock
// «Particle Wave 4K Motion Background Loop» y «Glowing Silver White Dust
// Particles». Un río de miles de partículas plateadas y carmesí que fluye
// serpenteando por la pantalla, con su resplandor, partículas que se escapan
// en remolinos y olas de luz que lo recorren con la música. Sin fondo, encima
// de cualquier visual. Partículas simuladas con física a paso fijo y dibujadas
// con resplandor suave, núcleo caliente y estela, más su efecto propio; barato
// para el móvil (puntos agrupados y degradados). Pulso: Golpes lanza su efecto
// con cada golpe y lo aviva; Graves lo hincha; Brillos lo hace centellear.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.slider('tamano', 'Tamaño', min: .5, max: 2, value: 1),
  // FORMA: por dónde corre el río.
  CreatorModifier.choice('curso', 'Curso', options: ['Diagonal', 'Vertical', 'Serpiente']),
  // MOVIMIENTO: lo revuelta que va la corriente.
  CreatorModifier.slider('turbulencia', 'Turbulencia', min: 0, max: 1, value: .35),
  // ATMÓSFERA
  CreatorModifier.slider('estela', 'Estela', min: 0, max: 1, value: .25),
  // MÚSICA
  CreatorModifier.choice('pulso', 'Pulso', options: ['Golpes', 'Graves', 'Brillos']),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Galaxia', {'curso': 'Serpiente', 'turbulencia': .7, 'estela': 1, 'detail': 1.7}),
  CreatorVariation('Arteria', {'curso': 'Vertical', 'turbulencia': .1, 'estela': .3, 'tamano': 1.3}),
];

const nativeSource = r'''
class Visual final : public Scene {
  // Reservado para detail 2: nunca se reserva memoria al cambiar un ajuste.
  static constexpr int kMax = 3200;
  static constexpr double kStep = 1.0 / 60.0;
  // Pasos simulados antes del primer cuadro: la escena ya empieza viva.
  static constexpr int kWarm = 30;
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
  bool seeding = false;
  float pendingWave = 0;
  // Centro del río en el punto sv (0 nace, 1 sale): diagonal, vertical o en
  // serpiente (se mezclan al cambiar Curso).
  Vec2 riverAt(float sv, float t) const {
    const float TAU = 6.2831853f;
    float x = 0.0f, y = 0.0f;
    if (w0 > 0.001f) {
      const float m = 0.11f * std::sin(TAU * 1.1f * sv + t * 0.32f) + 0.04f * std::sin(TAU * 2.7f * sv - t * 0.5f);
      const float dxA = 1.1f * W, dyA = -1.1f * H;
      const float lA = std::sqrt(dxA * dxA + dyA * dyA);
      x += w0 * (-0.05f * W + dxA * sv - dyA / lA * m);
      y += w0 * (1.05f * H + dyA * sv + dxA / lA * m);
    }
    if (w1 > 0.001f) {
      const float m = 0.17f * std::sin(TAU * 0.9f * sv + t * 0.27f) + 0.05f * std::sin(TAU * 2.3f * sv - t * 0.45f);
      x += w1 * (0.5f * W + m);
      y += w1 * (1.05f * H - 1.1f * H * sv);
    }
    if (w2 > 0.001f) {
      const float m = 0.3f * W * std::sin(TAU * sv + t * 0.2f) + 0.04f * std::sin(TAU * 3.1f * sv - t * 0.6f);
      x += w2 * (0.5f * W + m);
      y += w2 * (1.05f * H - 1.1f * H * sv);
    }
    return {x, y};
  }
  float halfWidth(float sv, float t) const {
    return 0.07f * (1.0f + 0.35f * std::sin(6.2831853f * 1.7f * sv + t * 0.4f));
  }
  void spawn(bool fromBurst, float power) {
    uint32_t k;
    P& p = fresh(k);
    const float h1 = hashU(k + 1u), h2 = hashU(k + 2u), h3 = hashU(k + 3u), h4 = hashU(k + 4u);
    const float h5 = hashU(k + 5u), h6 = hashU(k + 6u), h7 = hashU(k + 7u), h9 = hashU(k + 9u);
    const float TAU = 6.2831853f;
    (void)h1; (void)h2; (void)h3; (void)h4; (void)h5; (void)h6; (void)h7; (void)h9;
    (void)fromBurst; (void)power; (void)TAU;
    // En el río: a0 = por dónde va (0 nace, 1 sale), a1 = lo lejos del centro,
    // a2 = su velocidad (más rápida en el centro).
    p.a0 = seeding ? h1 : -0.02f;
    const float bell = (h2 + h3 + h4 + h5) * 0.5f - 1.0f;
    if (h7 < 0.06f) p.a1 = (h6 < 0.5f ? -1.0f : 1.0f) * (1.3f + 1.6f * h2);
    else p.a1 = bell * 1.5f;
    p.kind = h9 < 0.012f ? 1.0f : 0.0f;
    p.life = 80.0f;
    p.size = p.kind > 0.5f ? 0.014f + 0.02f * h3 : 0.0022f * (0.6f + 1.8f * h6 * h6 * h6);
    p.heat = std::min(std::fabs(p.a1) * 0.55f, 1.0f);
    p.a2 = (0.055f + 0.065f * (1.0f - std::min(std::fabs(p.a1), 1.0f))) * (0.85f + 0.3f * h9);
    const float tnow = float(std::fmod(double(steps) * kStep, 4000.0));
    const Vec2 c0 = riverAt(p.a0, tnow), c1 = riverAt(p.a0 + 0.004f, tnow);
    float tx = c1.x - c0.x, ty = c1.y - c0.y;
    const float tl = std::sqrt(tx * tx + ty * ty) + 1e-6f;
    tx /= tl;
    ty /= tl;
    const float hw = halfWidth(p.a0, tnow);
    p.x = c0.x - ty * p.a1 * hw;
    p.y = c0.y + tx * p.a1 * hw;
  }
  void step(float dt) {
    // La hora del propio paso: igual a 30 y a 60 FPS.
    const float t = float(std::fmod(double(steps) * kStep, 4000.0));
    (void)t;

    emitAcc += double(rate) * double(dt);
    while (emitAcc >= 1.0) {
      emitAcc -= 1.0;
      spawn(false, 0.0f);
    }
    for (P& p : ps) {
      if (!p.on) continue;
      // Río abajo; las que se escapan se dejan llevar por remolinos.
      p.a0 += p.a2 * dt;
      if (p.a0 > 1.04f) {
        p.on = false;
        continue;
      }
      const Vec2 c0 = riverAt(p.a0, t), c1 = riverAt(p.a0 + 0.004f, t);
      float tx = c1.x - c0.x, ty = c1.y - c0.y;
      const float tl = std::sqrt(tx * tx + ty * ty) + 1e-6f;
      tx /= tl;
      ty /= tl;
      const float hw = halfWidth(p.a0, t);
      const Vec2 cv = curl(p.a0 * 6.0f, p.a1, t * 0.5f, 1.0f);
      const float tur = k1 * (std::fabs(p.a1) > 1.2f ? 0.06f : 0.02f);
      const float gx = c0.x - ty * p.a1 * hw + cv.x * tur;
      const float gy = c0.y + tx * p.a1 * hw + cv.y * tur;
      p.vx = (gx - p.x) / dt;
      p.vy = (gy - p.y) / dt;
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
    // El río ya corre desde el primer cuadro.
    seeding = true;
    for (int i = 0; i < 1000; i++) spawn(false, 0.0f);
    seeding = false;
    pendingWave = 0;
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
    k1 = g.turbulencia;
    w0 = g.curso.weight(0);
    w1 = g.curso.weight(1);
    w2 = g.curso.weight(2);
    rate = 200.0f;
    if (burst > 0.0f) burst = 0.0f;
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
    {
      // El resplandor del río a lo largo de su curso.
      Path riverP;
      for (int i = 0; i <= 48; i++) {
        const float sv = -0.02f + 1.06f * float(i) / 48.0f;
        const Vec2 q = riverAt(sv, ts);
        if (i == 0) riverP.moveTo(q.x * s, q.y * s);
        else riverP.lineTo(q.x * s, q.y * s);
      }
      const float hwAvg = 0.07f * s * (1.0f + 0.3f * graves);
      const float lum = f.glow * (1.0f + 0.4f * golpe);
      // Seis capas cada vez más estrechas: un brillo que cae suave, sin bordes.
      const float lw[6] = {7.0f, 5.0f, 3.5f, 2.4f, 1.6f, 1.0f};
      const float la[6] = {0.018f, 0.022f, 0.026f, 0.03f, 0.034f, 0.04f};
      for (int l = 0; l < 6; l++) {
        Paint rp;
        rp.blend = Blend::plus;
        rp.strokeCap = 1;
        rp.strokeJoin = 1;
        rp.strokeWidth = hwAvg * lw[l];
        rp.color = mixc(deep, mid, float(l) / 5.0f).opacity(std::min(la[l] * lum, 1.0f));
        c.path(riverP, rp);
      }
      // Donde pasa la ola de luz, el río brilla más.
      const float ws = std::fmod(ts / 5.5f, 1.0f) * 1.5f - 0.25f;
      if (ws > -0.05f && ws < 1.05f) {
        const Vec2 q = riverAt(ws, ts);
        const Vec2 o{q.x * s, q.y * s};
        Paint wp = Paint::radial(o, s * 0.2f, {mixc(mid, hot, 0.5f).opacity(std::min(0.14f * lum, 1.0f)), mid.opacity(std::min(0.04f * lum, 1.0f)), mid.opacity(0.0f)}, {0.0f, 0.4f, 1.0f});
        wp.blend = Blend::plus;
        c.circle(o, s * 0.2f, wp);
      }
      if (burstAge < 2.2f && burstPow > 0.01f) {
        const float bw = burstAge * 0.5f;
        const Vec2 q = riverAt(bw, ts);
        const Vec2 o{q.x * s, q.y * s};
        const float a = std::min(0.4f * burstPow * std::exp(-burstAge * 0.9f) * lum, 1.0f);
        Paint wp = Paint::radial(o, s * 0.26f, {hot.opacity(a), mid.opacity(a * 0.3f), mid.opacity(0.0f)}, {0.0f, 0.35f, 1.0f});
        wp.blend = Blend::plus;
        c.circle(o, s * 0.26f, wp);
      }
    }
    for (auto& v : cores) v.clear();
    for (auto& pth : streaks) pth = Path{};
    for (auto& pth : streaksNear) pth = Path{};
    for (auto& pth : rays) pth = Path{};
    bool anyStreak[9] = {false, false, false, false, false, false, false, false, false};
    bool anyRay[9] = {false, false, false, false, false, false, false, false, false};

    const float tail = 0.012f + 0.08f * g.estela;
    for (const P& p : ps) {
      if (!p.on) continue;
      const float u = p.age / p.life;
      float b = 0, r = 0, heat = 0, grey = 0, ray = 0, px = p.x, py = p.y;
      const float d = std::fabs(p.a1);
      const float coreLit = std::exp(-d * d * 1.8f);
      const float tw = 0.75f + 0.25f * std::sin(t * (2.0f + 4.0f * p.seed) + p.seed * 40.0f);
      // Olas de luz que recorren el río: solas cada pocos segundos y con cada golpe.
      const float ws = std::fmod(ts / 5.5f, 1.0f) * 1.5f - 0.25f;
      float wave = 0.5f * std::exp(-sq((p.a0 - ws) / 0.06f));
      if (burstAge < 4.0f) wave += burstPow * 1.6f * std::exp(-sq((p.a0 - burstAge * 0.5f) / 0.05f));
      const float edgeFade = std::max(std::min(std::min((p.a0 + 0.02f) / 0.06f, (1.04f - p.a0) / 0.06f), 1.0f), 0.0f);
      b = edgeFade * (0.3f + 0.7f * coreLit) * tw * (d > 1.2f ? 0.55f : 1.0f) * (1.0f + wave);
      if (p.kind > 0.5f) b *= 0.5f;
      r = p.size * g.tamano * (1.0f + 0.5f * wave);
      heat = std::min(d * 0.55f, 1.0f) * (1.0f - 0.5f * std::min(wave, 1.0f));
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
        rp.strokeWidth = std::max(0.8f, s * 0.003f * g.tamano * 0.45f);
        rp.color = mixc(col, white, 0.4f).opacity(std::clamp(bl * 0.65f, 0.0f, 1.0f));
        c.path(rays[size_t(k)], rp);
      }
    }
    // Cada partícula: halos tenues que se suman en un brillo suave, el
    // núcleo y un centro casi blanco.
    for (int sb = 0; sb < 3; sb++) {
      const float rr = s * 0.003f * g.tamano * (sb == 0 ? 0.55f : (sb == 1 ? 1.0f : 1.8f)) * swell;
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
