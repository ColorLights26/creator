// Rayos de Luz con Polvo Dorado — capa transparente premium. Referencia:
// vídeos de stock «Volumetric Light Ray With Golden Dust» y «Light Rays with
// Dust Particles». Haces de luz dorada que entran en diagonal y polvo de oro
// que flota en el aire: fuera de la luz casi no se ve y, al cruzar un haz,
// brilla y destella. Sin fondo, encima de cualquier visual. Partículas
// simuladas con física a paso fijo y dibujadas con resplandor suave, núcleo
// caliente y estela, más su efecto propio; barato para el móvil (puntos
// agrupados y degradados). Pulso: Golpes lanza su efecto con cada golpe y lo
// aviva; Graves lo hincha; Brillos lo hace centellear.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.slider('tamano', 'Tamaño', min: .5, max: 2, value: 1),
  // FORMA: cuántos haces de luz entran.
  CreatorModifier.steps('haces', 'Haces de luz', min: 2, max: 6, value: 4),
  // MOVIMIENTO: cómo se mueve el aire.
  CreatorModifier.choice('corriente', 'Corriente', options: ['Calma', 'Brisa', 'Remolino']),
  // ATMÓSFERA: motas cerca de la cámara, grandes y desenfocadas.
  CreatorModifier.slider('profundidad', 'Profundidad', min: 0, max: 1, value: .4),
  // MÚSICA
  CreatorModifier.choice('pulso', 'Pulso', options: ['Golpes', 'Graves', 'Brillos']),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Catedral', {'haces': 6, 'corriente': 'Calma', 'profundidad': .8}),
  CreatorVariation('Ventana', {'haces': 2, 'corriente': 'Brisa', 'tamano': 1.3}),
];

const nativeSource = r'''
class Visual final : public Scene {
  // Reservado para detail 2: nunca se reserva memoria al cambiar un ajuste.
  static constexpr int kMax = 3600;
  static constexpr double kStep = 1.0 / 60.0;
  // Pasos simulados antes del primer cuadro: la escena ya empieza viva.
  static constexpr int kWarm = 600;
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
  // Haz i: dónde entra por arriba, cuánto se inclina al bajar, su anchura
  // arriba y abajo y su luz ahora (como nubes que pasan delante del sol).
  void beam(int i, float t, float& x0, float& slope, float& hw0, float& hw1, float& lit) const {
    const float fi = float(i);
    const float n = std::max(k1, 1.0f);
    x0 = W * (-0.28f + 1.12f * (fi + 0.5f) / n) + 0.04f * std::sin(t * 0.11f + fi * 2.0f);
    slope = 0.36f + 0.05f * std::sin(t * 0.07f + fi * 1.3f);
    hw0 = 0.018f + 0.022f * hashU(uint32_t(i) * 77u + 5u);
    hw1 = hw0 + 0.1f + 0.08f * hashU(uint32_t(i) * 77u + 9u);
    const float a = 0.5f + 0.5f * std::sin(t * 0.23f + fi * 1.7f);
    const float b = 0.5f + 0.5f * std::sin(t * 0.37f + fi * 2.9f);
    lit = (0.45f + 0.55f * a * (0.55f + 0.45f * b)) * std::clamp(k1 - fi, 0.0f, 1.0f);
  }
  void spawn(bool fromBurst, float power) {
    uint32_t k;
    P& p = fresh(k);
    const float h1 = hashU(k + 1u), h2 = hashU(k + 2u), h3 = hashU(k + 3u), h4 = hashU(k + 4u);
    const float h5 = hashU(k + 5u), h6 = hashU(k + 6u), h7 = hashU(k + 7u), h9 = hashU(k + 9u);
    const float TAU = 6.2831853f;
    (void)h1; (void)h2; (void)h3; (void)h4; (void)h5; (void)h6; (void)h7; (void)h9;
    (void)fromBurst; (void)power; (void)TAU;
    if (fromBurst) {
      // Golpe: un soplo de polvo se levanta dentro de un haz.
      float x0, slope, hw0, hw1, lit;
      const int bi = int(burstX * std::max(k1, 1.0f)) % 6;
      beam(bi, float(std::fmod(double(steps) * kStep, 4000.0)), x0, slope, hw0, hw1, lit);
      const float y = H * (0.2f + 0.6f * burstY);
      p.x = x0 + slope * (y + 0.05f) + (h1 - 0.5f) * 0.06f;
      p.y = y + (h2 - 0.5f) * 0.06f;
      const float ang = h3 * TAU;
      const float sp = (0.05f + 0.2f * h4) * (0.6f + 0.4f * power);
      p.vx = std::cos(ang) * sp;
      p.vy = std::sin(ang) * sp;
      p.life = 3.0f + 3.0f * h5;
      p.size = 0.0022f * (0.6f + 1.6f * h6 * h6);
      p.a1 = h9 * TAU;
      return;
    }
    p.kind = h7 < 0.015f + 0.06f * k2 ? 1.0f : 0.0f;
    p.x = (-0.05f + 1.1f * h1) * W;
    p.y = (-0.05f + 1.1f * h2) * H;
    p.life = 8.0f + 6.0f * h5;
    p.size = p.kind > 0.5f ? 0.012f + 0.02f * h6 : 0.0018f * (0.6f + 1.8f * h6 * h6 * h6);
    p.a1 = h3 * TAU;
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
      // Corriente: el polvo flota, lo lleva la brisa o gira en remolinos.
      const Vec2 cv = curl(p.x, p.y, t * 0.3f, 2.2f);
      const float turb = 0.012f * w0 + 0.02f * w1 + 0.06f * w2;
      const float tvx = cv.x * turb + w1 * 0.035f + 0.004f * std::sin(t * 0.4f + p.a1);
      const float tvy = cv.y * turb + 0.006f * w0 - 0.004f * w1;
      const float kk = 1.0f - std::exp(-1.5f * dt);
      p.vx += (tvx - p.vx) * kk;
      p.vy += (tvy - p.vy) * kk;
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
    k1 = g.haces;
    k2 = g.profundidad;
    w0 = g.corriente.weight(0);
    w1 = g.corriente.weight(1);
    w2 = g.corriente.weight(2);
    rate = 330.0f;
    rate *= 0.5f * f.detail * (1.0f + 0.5f * std::min(energy * f.intensity, 1.0f));
    sim += f.delta * f.speed;
    const int64_t target = int64_t(std::floor(sim / kStep + 1e-6));
    if (target - steps > kWarm + 240) steps = target - 240;
    while (steps < target) {
      steps++;
      if (burst > 0.0f) {
        const int n = int(70.0f * std::min(burst, 1.5f));
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
    // Los haces de luz, con su caída suave hacia los bordes y hacia abajo.
    float bx0[6], bsl[6], bh0[6], bh1[6], bli[6], bnorm[6];
    for (int i = 0; i < 6; i++) {
      beam(i, ts, bx0[i], bsl[i], bh0[i], bh1[i], bli[i]);
      bnorm[i] = 1.0f / std::sqrt(1.0f + bsl[i] * bsl[i]);
    }
    const float widen = 1.0f + 0.3f * graves;
    const float beamBoost = (1.0f + 0.9f * golpe + 0.3f * graves) * f.glow;
    for (int i = 0; i < 6; i++) {
      if (bli[i] <= 0.001f) continue;
      const float yTop = -0.05f, yBot = H + 0.05f;
      const float axT = bx0[i], axB = bx0[i] + bsl[i] * (yBot - yTop);
      const float nx = bnorm[i], ny = -bsl[i] * bnorm[i];
      // Ocho capas cada vez más estrechas: un perfil suave, sin bordes.
      for (int l = 0; l < 8; l++) {
        const float wl = 1.9f * std::pow(0.74f, float(l)) * widen;
        const float h0 = bh0[i] * wl, h1 = bh1[i] * wl;
        Path q;
        q.moveTo((axT - nx * h0) * s, (yTop - ny * h0) * s);
        q.lineTo((axT + nx * h0) * s, (yTop + ny * h0) * s);
        q.lineTo((axB + nx * h1) * s, (yBot + ny * h1) * s);
        q.lineTo((axB - nx * h1) * s, (yBot - ny * h1) * s);
        q.close();
        const float a = std::min(0.034f * bli[i] * beamBoost, 1.0f);
        Paint bp = Paint::linear({axT * s, yTop * s}, {axB * s, yBot * s}, {mixc(hot, mid, 0.45f).opacity(a), mid.opacity(a * 0.7f), deep.opacity(0.0f)}, {0.0f, 0.5f, 1.0f});
        bp.blend = Blend::plus;
        c.path(q, bp);
      }
      // Hebras de luz dentro del haz, que se encienden y apagan despacio.
      for (int j = 0; j < 3; j++) {
        const float hj = hashU(uint32_t(i) * 31u + uint32_t(j) * 7u + 3u);
        const float off = (hj - 0.5f) * 1.3f;
        const float wj = 0.12f + 0.12f * hashU(uint32_t(i) * 31u + uint32_t(j) * 7u + 4u);
        const float fl = 0.5f + 0.5f * std::sin(ts * (0.3f + 0.3f * hj) + hj * 20.0f);
        const float h0 = bh0[i] * widen, h1 = bh1[i] * widen;
        Path q;
        q.moveTo((axT + nx * h0 * (off - wj)) * s, (yTop + ny * h0 * (off - wj)) * s);
        q.lineTo((axT + nx * h0 * (off + wj)) * s, (yTop + ny * h0 * (off + wj)) * s);
        q.lineTo((axB + nx * h1 * (off + wj)) * s, (yBot + ny * h1 * (off + wj)) * s);
        q.lineTo((axB + nx * h1 * (off - wj)) * s, (yBot + ny * h1 * (off - wj)) * s);
        q.close();
        const float a = std::min(0.035f * bli[i] * fl * beamBoost, 1.0f);
        Paint bp = Paint::linear({axT * s, yTop * s}, {axB * s, yBot * s}, {mixc(hot, mid, 0.3f).opacity(a), mid.opacity(a * 0.45f), mid.opacity(0.0f)}, {0.0f, 0.45f, 1.0f});
        bp.blend = Blend::plus;
        c.path(q, bp);
      }
      // Por donde entra la luz, arriba, un resplandor.
      const Vec2 o{axT * s, 0.0f};
      const float ga = std::min(0.22f * bli[i] * beamBoost, 1.0f);
      Paint gp = Paint::radial(o, s * 0.32f, {hot.opacity(ga), mid.opacity(ga * 0.3f), mid.opacity(0.0f)}, {0.0f, 0.35f, 1.0f});
      gp.blend = Blend::plus;
      c.circle(o, s * 0.32f, gp);
    }
    for (auto& v : cores) v.clear();
    for (auto& pth : streaks) pth = Path{};
    for (auto& pth : streaksNear) pth = Path{};
    for (auto& pth : rays) pth = Path{};
    bool anyStreak[9] = {false, false, false, false, false, false, false, false, false};
    bool anyRay[9] = {false, false, false, false, false, false, false, false, false};

    const float tail = 0.0f;
    for (const P& p : ps) {
      if (!p.on) continue;
      const float u = p.age / p.life;
      float b = 0, r = 0, heat = 0, grey = 0, ray = 0, px = p.x, py = p.y;
      // Cuánta luz de los haces le cae a esta mota.
      float litSum = 0.0f;
      const float vy = std::clamp((p.y + 0.05f) / (H + 0.1f), 0.0f, 1.0f);
      for (int i = 0; i < 6; i++) {
        if (bli[i] <= 0.001f) continue;
        const float ax = bx0[i] + bsl[i] * (p.y + 0.05f);
        const float hwv = (bh0[i] + (bh1[i] - bh0[i]) * vy) * widen;
        const float d = (p.x - ax) * bnorm[i] / hwv;
        litSum += bli[i] * std::exp(-2.2f * d * d) * (1.0f - 0.5f * vy);
      }
      const float lit = std::min(litSum, 1.4f);
      const float tw = 0.75f + 0.25f * std::sin(t * (1.3f + 2.0f * p.seed) + p.seed * 40.0f);
      // Al girar en la luz, algunas destellan.
      const float s1 = std::max(std::sin(t * (2.0f + 3.0f * p.seed) + p.seed * 90.0f), 0.0f);
      const float s2 = s1 * s1, s4 = s2 * s2;
      const float glint = s4 * s4 * lit;
      const float e = std::max(std::min(std::min(u / 0.08f, (1.0f - u) / 0.08f), 1.0f), 0.0f);
      if (p.kind > 0.5f) {
        b = e * lit * 0.6f;
        r = p.size * g.tamano;
        heat = 0.35f;
      } else {
        b = e * (0.05f + 1.1f * lit * tw + 0.9f * glint);
        r = p.size * g.tamano * (0.85f + 0.4f * lit);
        heat = 1.0f - std::min(lit, 1.0f) * 0.85f;
        ray = glint > 0.45f ? 1.0f : 0.0f;
      }
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
        const float a = std::min(b * 0.24f, 1.0f);
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
        const float ha = std::min(b * 0.65f * 0.55f * f.glow, 1.0f);
        if (ha > 0.01f) {
          Paint hp = Paint::radial(at, hr, {col.opacity(ha), col.opacity(ha * 0.28f), col.opacity(0.0f)}, {0.0f, 0.22f, 1.0f});
          hp.blend = Blend::plus;
          c.circle(at, hr, hp);
        }
      }
      cores[size_t(sb * 9 + cb * 3 + bb)].push_back(at);
      if (kRays && ray > 0.5f && b > 0.5f) {
        const float len = rp * (6.0f) * b;
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
        const float ha = bl * 0.65f * f.glow;
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
