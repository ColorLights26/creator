// Píxeles Premium — capa transparente premium. Referencia: propuesta: píxeles.
// Píxeles de luz: cuadraditos nítidos con un resplandor suave que flotan,
// suben o caen, se encienden a escalones y parpadean como una pantalla. Sin
// fondo, encima de cualquier visual. Partículas de verdad simuladas con física
// a paso fijo (turbulencia, remolinos, gravedad, empuje del calor,
// rozamiento), con resplandor suave, núcleo caliente, estela de cometa, luces
// desenfocadas y humo; barato para el móvil (puntos y círculos agrupados).
// Pulso: Golpes lanza una oleada y las aviva; Graves las hincha; Brillos las
// hace centellear.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.slider('tamano', 'Tamaño', min: .5, max: 2, value: 1),
  // MOVIMIENTO
  CreatorModifier.choice('deriva', 'Deriva', options: ['Flotar', 'Subir', 'Caer']),
  // ATMÓSFERA: libres o encajados en una cuadrícula.
  CreatorModifier.slider('rejilla', 'Rejilla', min: 0, max: 1, value: .5),
  // MÚSICA
  CreatorModifier.choice('pulso', 'Pulso', options: ['Golpes', 'Graves', 'Brillos']),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Código', {'deriva': 'Caer', 'rejilla': 1, 'tamano': .8, 'detail': 1.8}),
  CreatorVariation('Polvo Digital', {'deriva': 'Flotar', 'rejilla': 0, 'tamano': 1.3}),
];

const nativeSource = r'''
class Visual final : public Scene {
  // Reservado para detail 2: nunca se reserva memoria al cambiar un ajuste.
  static constexpr int kMax = 800;
  static constexpr double kStep = 1.0 / 60.0;
  // Segundos simulados antes del primer cuadro: la escena ya empieza llena.
  static constexpr int kWarm = 300;
  static constexpr bool kSquares = true;
  static constexpr bool kRays = false;
  static constexpr int kBins = 27;  // tamaño × color × brillo
  // kind: 0 chispa (núcleo, halo y estela), 1 luz desenfocada, 2 humo o llama.
  struct P { float x, y, vx, vy, age, life, size, seed, heat, kind, a0, a1; bool on; };
  std::array<P, kMax> ps{};
  // Simulación a paso fijo: el movimiento es el mismo a 30 y a 60 FPS.
  double sim = 0, emitAcc = 0;
  int64_t steps = 0;
  uint32_t spawned = 0, beats = 0;
  int cursor = 0;
  float W = 1.0f, H = 1.78f;
  float bass = 0, spark = 0, energy = 0, slowBass = 0, kick = 0;
  float burst = 0, burstPow = 0, burstX = 0.5f, burstY = 0.5f, burstAge = 9;
  // Ajustes de movimiento de este cuadro (ya deslizados por el motor).
  float k0 = 1, k1 = 0, k2 = 0, k3 = 0, w0 = 1, w1 = 0, w2 = 0, rate = 1;
  mutable std::array<std::vector<Vec2>, kBins> cores;
  mutable std::array<Path, 9> streaks, streaksNear, rays;
  mutable std::array<Path, kBins> squares;

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
  // Remolinos de aire sin divergencia (rotacional de un potencial): las
  // partículas giran y se enroscan de forma natural.
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
  void spawn(bool fromBurst, float power) {
    const uint32_t k = spawned++ * 9u + 0x9e37u;
    const float h1 = hashU(k + 1u), h2 = hashU(k + 2u), h3 = hashU(k + 3u), h4 = hashU(k + 4u);
    const float h5 = hashU(k + 5u), h6 = hashU(k + 6u), h7 = hashU(k + 7u), h8 = hashU(k + 8u);
    const float TAU = 6.2831853f;
    (void)h1; (void)h2; (void)h3; (void)h4; (void)h5; (void)h6; (void)h7; (void)power; (void)TAU;
    P& p = slot();
    p = P{};
    p.on = true;
    p.seed = h8;
    p.x = fromBurst ? W * (0.15f + 0.7f * burstX) + (h1 - 0.5f) * 0.2f : h1 * W;
    p.y = fromBurst ? H * (0.15f + 0.7f * burstY) + (h2 - 0.5f) * 0.2f : h2 * H;
    p.life = fromBurst ? 0.8f + 0.8f * h5 : 2.0f + 3.0f * h5;
    p.size = 0.006f * (0.6f + 1.4f * h6 * h6);
    p.heat = h3 < 0.34f ? 0.0f : (h3 < 0.67f ? 0.5f : 1.0f);
    p.a0 = h4;
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
      p.vx = w0 * 0.01f * std::sin(t * 0.5f + p.seed * 20.0f);
      p.vy = (-0.05f * w1 + 0.05f * w2) * (0.5f + p.seed) + w0 * 0.01f * std::cos(t * 0.4f + p.seed * 13.0f);
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
    // Pulso en Golpes: cada golpe lanza una oleada; la música fuerte, más.
    if (fresh && mu.active) {
      beats++;
      burst = hit * f.intensity * g.pulso.weight(0);
      burstPow = burst;
      burstX = hashU(beats * 7u + 3u);
      burstY = hashU(beats * 7u + 5u);
      burstAge = 0;
    }
    w0 = g.deriva.weight(0);
    w1 = g.deriva.weight(1);
    w2 = g.deriva.weight(2);
    k1 = g.rejilla;
    rate = 70.0f;
    rate *= 0.5f * f.detail * (1.0f + 0.5f * std::min(energy * f.intensity, 1.0f));
    sim += f.delta * f.speed;
    const int64_t target = int64_t(std::floor(sim / kStep + 1e-6));
    if (target - steps > kWarm + 240) steps = target - 240;
    while (steps < target) {
      steps++;
      if (burst > 0.0f) {
        const int n = int(30.0f * std::min(burst, 1.5f));
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
    // Pulso: Golpes aviva, Graves hincha, Brillos centellea.
    const float golpe = std::min(kick * amp, 1.2f) * g.pulso.weight(0);
    const float graves = std::min(bass * amp, 1.2f) * g.pulso.weight(1);
    const float agudos = std::min(spark * amp, 1.2f) * g.pulso.weight(2);
    const float swell = 1.0f + 0.35f * graves;
    const float lift = 1.0f + 0.5f * golpe;
    const Color hot = f.colors[3], mid = f.colors[2], deep = f.colors[1];
    auto ramp = [&](float u) {
      u = std::clamp(u, 0.0f, 1.0f);
      return u < 0.5f ? mixc(hot, mid, u * 2.0f) : mixc(mid, deep, (u - 0.5f) * 2.0f);
    };
    (void)golpe; (void)graves; (void)agudos; (void)t;
    // Atmósfera (resplandores grandes y suaves) primero.
    {}
    for (auto& v : cores) v.clear();
    for (auto& pth : streaks) pth = Path{};
    for (auto& pth : streaksNear) pth = Path{};
    for (auto& pth : rays) pth = Path{};
    for (auto& pth : squares) pth = Path{};
    bool anyStreak[9] = {false, false, false, false, false, false, false, false, false};
    bool anyRay[9] = {false, false, false, false, false, false, false, false, false};
    const float tail = 0.0f;
    for (const P& p : ps) {
      if (!p.on) continue;
      const float u = p.age / p.life;
      float b = 0, r = 0, heat = 0, grey = 0, ray = 0, px = p.x, py = p.y;
      // Se encienden a escalones y parpadean como una pantalla.
      const float e = std::floor(std::sin(3.14159f * u) * 4.0f) / 4.0f;
      const float blink = std::sin(t * (3.0f + 5.0f * p.a0) + p.seed * 30.0f) > -0.6f ? 1.0f : 0.25f;
      b = std::min(e * 1.3f, 1.0f) * blink;
      r = p.size * g.tamano;
      heat = p.heat;
      // Rejilla: saltan de casilla en casilla.
      const float gs = 0.008f + 0.025f * k1;
      const float snap = std::min(k1 * 3.0f, 1.0f);
      px = mixf(px, std::floor(px / gs + 0.5f) * gs, snap);
      py = mixf(py, std::floor(py / gs + 0.5f) * gs, snap);
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
        // Humo o llama: una bocanada grande y suave.
        const float a = std::min(b * 0.3f, 1.0f);
        Paint hp = Paint::radial(at, rp, {col.opacity(a), col.opacity(a * 0.55f), col.opacity(0.0f)}, {0.0f, 0.45f, 1.0f});
        hp.blend = Blend::plus;
        c.circle(at, rp, hp);
        continue;
      }
      if (p.kind > 0.5f) {
        // Cerca de la cámara: luz grande y desenfocada (degradado plano).
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
        const float hr = rp * 3.2f * 0.75f;
        const float ha = std::min(b * 0.55f * 0.55f * f.glow * (1.0f), 1.0f);
        if (ha > 0.01f) {
          Paint hp = Paint::radial(at, hr, {col.opacity(ha), col.opacity(ha * 0.28f), col.opacity(0.0f)}, {0.0f, 0.22f, 1.0f});
          hp.blend = Blend::plus;
          c.circle(at, hr, hp);
        }
      }
      const int bin = sb * 9 + cb * 3 + bb;
      cores[size_t(bin)].push_back(at);
      if (kSquares) {
        const float hs = s * 0.0045f * g.tamano * (sb == 0 ? 0.55f : (sb == 1 ? 1.0f : 1.8f)) * swell;
        squares[size_t(bin)].rect({at.x - hs, at.y - hs, 2.0f * hs, 2.0f * hs});
      }
      if (kRays && ray > 0.5f && b > 0.55f) {
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
    // Figuras (estelas de cometa, rayos, cuadraditos) antes que los puntos.
    for (int k = 0; k < 9; k++) {
      const float bl = (float(k % 3) + 0.6f) / 3.0f;
      const Color col = ramp(float(k / 3) * 0.5f);
      if (anyStreak[k]) {
        Paint sp;
        sp.blend = Blend::plus;
        sp.strokeCap = 1;
        sp.strokeWidth = std::max(1.0f, s * 0.0035f * g.tamano * swell * (0.7f + 0.3f * float(k % 3)));
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
        rp.strokeWidth = std::max(0.8f, s * 0.0045f * g.tamano * 0.45f);
        rp.color = mixc(col, Color{1, 1, 1, 1}, 0.4f).opacity(std::clamp(bl * 0.65f, 0.0f, 1.0f));
        c.path(rays[size_t(k)], rp);
      }
    }
    if (kSquares) {
      for (int bin = 0; bin < kBins; bin++) {
        if (cores[size_t(bin)].empty()) continue;
        const int k = bin % 9;
        const float bl = (float(k % 3) + 0.6f) / 3.0f;
        Paint qp;
        qp.blend = Blend::plus;
        qp.color = mixc(ramp(float(k / 3) * 0.5f), Color{1, 1, 1, 1}, 0.15f).opacity(std::clamp(bl, 0.0f, 1.0f));
        c.path(squares[size_t(bin)], qp);
      }
    }
    // Cada partícula: halos tenues que se suman en un brillo suave, el
    // núcleo y un centro casi blanco.
    for (int sb = 0; sb < 3; sb++) {
      const float rr = s * 0.0045f * g.tamano * (sb == 0 ? 0.55f : (sb == 1 ? 1.0f : 1.8f)) * swell;
      for (int k = 0; k < 9; k++) {
        const auto& pts = cores[size_t(sb * 9 + k)];
        if (pts.empty()) continue;
        const int cb = k / 3;
        const float bl = (float(k % 3) + 0.6f) / 3.0f;
        const Color col = ramp(float(cb) * 0.5f);
        const float ha = bl * 0.55f * f.glow * (1.0f);
        const float hk[3] = {0.55f, 0.36f, 0.24f};
        const float hw[3] = {0.12f, 0.2f, 0.32f};
        for (int i = sb == 2 ? 2 : 0; i < 3; i++) {
          if (ha * hw[i] < 0.004f) continue;
          Paint hp;
          hp.blend = Blend::plus;
          hp.color = col.opacity(std::clamp(ha * hw[i], 0.0f, 1.0f));
          c.points(pts, rr * 3.2f * hk[i], hp);
        }
        if (kSquares) continue;
        Paint core;
        core.blend = Blend::plus;
        core.color = mixc(col, Color{1, 1, 1, 1}, 0.12f).opacity(std::clamp(bl, 0.0f, 1.0f));
        c.points(pts, std::max(0.8f, rr), core);
        if (k % 3 == 2) {
          Paint hotc;
          hotc.blend = Blend::plus;
          hotc.color = mixc(col, Color{1, 1, 1, 1}, 0.45f).opacity(0.8f);
          c.points(pts, std::max(0.6f, rr * 0.5f), hotc);
        }
      }
    }
  }
};
''';
