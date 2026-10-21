// Reactiva · Chispas Premium — copia momentánea de «Chispas Premium» (chispas_premium.dart, que no se toca).
// Sin música no dibuja nada: el visual original sigue vivo por debajo y
// sólo se deja ver un instante con su momento musical (el golpe grande por
// defecto) y desaparece. Nunca más de tres apariciones por segundo.
//
// Chispas Premium — capa transparente premium. Referencia: vídeo 11 (chispas
// sobre negro). Chispas finas y rapidísimas de núcleo blanco y estela naranja
// que saltan de fuentes de fuego en abanico y caen en arco por su peso; con
// cada golpe, una fuente nueva. Sin fondo, encima de cualquier visual.
// Partículas de verdad simuladas con física a paso fijo (turbulencia,
// remolinos, gravedad, empuje del calor, rozamiento), con resplandor suave,
// núcleo caliente, estela de cometa, luces desenfocadas y humo; barato para el
// móvil (puntos y círculos agrupados). Pulso: Golpes lanza una oleada y las
// aviva; Graves las hincha; Brillos las hace centellear.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.slider('tamano', 'Tamaño', min: .5, max: 2, value: 1),
  // FORMA: lo abiertas que salen.
  CreatorModifier.slider('abanico', 'Abanico', min: 0, max: 1, value: .5),
  // ATMÓSFERA
  CreatorModifier.slider('estela', 'Estela', min: 0, max: 1, value: .6),
  // MOVIMIENTO: cuánto pesan al caer.
  CreatorModifier.slider('caida', 'Caída', min: 0, max: 1, value: .5),
  // MÚSICA
  CreatorModifier.choice('pulso', 'Pulso', options: ['Golpes', 'Graves', 'Brillos']),
  // MOMENTO (versión reactiva): qué la hace aparecer un instante.
  CreatorModifier.choice('aparece', 'Aparece con', options: ['Golpe grande', 'Cada golpe', 'Cada compás', 'Caja']),
  // Cuánto se queda a la vista antes de desaparecer.
  CreatorModifier.slider('permanencia', 'Cuánto se queda', min: .5, max: 2, value: 1),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Soldadura', {'abanico': 1, 'caida': 1, 'estela': 1, 'tamano': .8}),
  CreatorVariation('Bengala', {'abanico': .15, 'caida': .1, 'estela': .4, 'tamano': 1.3}),
];

const nativeSource = r'''
class Base_ final : public Scene {
  // Reservado para detail 2: nunca se reserva memoria al cambiar un ajuste.
  static constexpr int kMax = 800;
  static constexpr double kStep = 1.0 / 60.0;
  // Segundos simulados antes del primer cuadro: la escena ya empieza llena.
  static constexpr int kWarm = 120;
  static constexpr bool kSquares = false;
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
    // Fuentes de chispas abajo; con un golpe, una fuente nueva en otro sitio.
    const float e = std::floor(h1 * 3.0f);
    const float ox = fromBurst ? W * (0.15f + 0.7f * burstX) : W * (0.2f + 0.3f * e) + (h2 - 0.5f) * 0.04f;
    const float oy = fromBurst ? H * (0.45f + 0.4f * burstY) : H * 0.94f;
    const float ang = -1.5708f + (h3 - 0.5f) * (0.3f + 2.4f * k1) * (fromBurst ? 1.4f : 1.0f);
    const float spd = (0.6f + 1.0f * h4) * (fromBurst ? 1.2f + 0.4f * power : 1.0f);
    p.x = ox;
    p.y = oy;
    p.vx = std::cos(ang) * spd;
    p.vy = std::sin(ang) * spd;
    p.life = 0.5f + 0.9f * h5;
    p.size = 0.0036f * (0.7f + 1.3f * h6 * h6 * h6);
    p.heat = 0.25f * h7;
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
      // Gravedad (Caída), rozamiento y un temblor de aire.
      p.vy += (0.5f + 2.4f * k2) * dt;
      const float drag = std::exp(-0.7f * dt);
      p.vx *= drag;
      p.vy *= drag;
      p.vx += 0.15f * std::sin(t * 9.0f + p.seed * 40.0f) * dt;
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
    k1 = g.abanico;
    k2 = g.caida;
    rate = 150.0f;
    rate *= 0.5f * f.detail * (1.0f + 0.5f * std::min(energy * f.intensity, 1.0f));
    sim += f.delta * f.speed;
    const int64_t target = int64_t(std::floor(sim / kStep + 1e-6));
    if (target - steps > kWarm + 240) steps = target - 240;
    while (steps < target) {
      steps++;
      if (burst > 0.0f) {
        const int n = int(55.0f * std::min(burst, 1.5f));
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
    {
      // El punto caliente de cada fuente, y el fogonazo de la nueva.
      for (int i = 0; i < 3; i++) {
        const Vec2 o{f.width * (0.2f + 0.3f * float(i)), f.height * 0.94f};
        const float fr = s * 0.12f * (1.0f + 0.3f * std::sin(t * 13.0f + float(i) * 2.0f));
        Paint hp = Paint::radial(o, fr, {hot.opacity(0.22f), mid.opacity(0.06f), mid.opacity(0.0f)}, {0.0f, 0.4f, 1.0f});
        hp.blend = Blend::plus;
        c.circle(o, fr, hp);
      }
      const float fl = burstPow * std::exp(-burstAge * 5.0f);
      if (fl > 0.01f) {
        const Vec2 o{f.width * (0.15f + 0.7f * burstX), f.height * (0.45f + 0.4f * burstY)};
        Paint hp = Paint::radial(o, s * 0.35f, {hot.opacity(std::min(0.5f * fl, 1.0f)), mid.opacity(std::min(0.12f * fl, 1.0f)), mid.opacity(0.0f)}, {0.0f, 0.3f, 1.0f});
        hp.blend = Blend::plus;
        c.circle(o, s * 0.35f, hp);
      }
    }
    for (auto& v : cores) v.clear();
    for (auto& pth : streaks) pth = Path{};
    for (auto& pth : streaksNear) pth = Path{};
    for (auto& pth : rays) pth = Path{};
    for (auto& pth : squares) pth = Path{};
    bool anyStreak[9] = {false, false, false, false, false, false, false, false, false};
    bool anyRay[9] = {false, false, false, false, false, false, false, false, false};
    const float tail = 0.03f + 0.06f * g.estela;
    for (const P& p : ps) {
      if (!p.on) continue;
      const float u = p.age / p.life;
      float b = 0, r = 0, heat = 0, grey = 0, ray = 0, px = p.x, py = p.y;
      const float in = std::min(u / 0.03f, 1.0f);
      b = in * (1.0f - u) * std::sqrt(1.0f - u) * (0.8f + 0.2f * std::sin(t * 40.0f + p.seed * 30.0f));
      r = p.size * (1.0f - 0.4f * u) * g.tamano;
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
        const float hr = rp * 5.0f * 0.75f;
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
        const float hs = s * 0.0038f * g.tamano * (sb == 0 ? 0.55f : (sb == 1 ? 1.0f : 1.8f)) * swell;
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
        sp.strokeWidth = std::max(1.0f, s * 0.0034f * g.tamano * swell * (0.7f + 0.3f * float(k % 3)));
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
        rp.strokeWidth = std::max(0.8f, s * 0.0038f * g.tamano * 0.45f);
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
      const float rr = s * 0.0038f * g.tamano * (sb == 0 ? 0.55f : (sb == 1 ? 1.0f : 1.8f)) * swell;
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
          c.points(pts, rr * 5.0f * hk[i], hp);
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

// Versión reactiva momentánea: el visual original sigue vivo por debajo, pero
// sólo se deja ver un instante cuando llega su momento musical. Sin música no
// dibuja nada.
class Visual final : public Scene {
  static constexpr double kGap_ = 0.34;  // nunca más de 3 apariciones por segundo
  static constexpr float kMin_ = 0.004f;
  static constexpr int kShows_ = 6;
  struct Show_ { double start = -100.0; float span = 0.0f; };
  Base_ base_;
  std::array<Show_, kShows_> shows_{};
  int cursor_ = 0, beats_ = 0;
  double now_ = 0.0, last_ = -100.0, lastImpact_ = -100.0, lastBig_ = -100.0;
  float impactMean_ = 0.0f;

  // Entra en 60 ms y se desvanece suave hasta el final de su tiempo.
  float visible_() const {
    float v = 0.0f;
    for (const Show_& s : shows_) {
      const double age = now_ - s.start;
      if (age < 0.0 || age >= double(s.span)) continue;
      const double in = 0.06;
      float e = 1.0f;
      if (age < in) {
        e = float(age / in);
      } else {
        const float x = float((age - in) / std::max(double(s.span) - in, 0.05));
        const float k = 1.0f - std::clamp(x, 0.0f, 1.0f);
        e = k * std::sqrt(k);
      }
      v = std::max(v, e);
    }
    return v;
  }

 public:
  void reset(uint32_t seed) override {
    Scene& base = base_;
    base.reset(seed);
    shows_ = {};
    cursor_ = beats_ = 0;
    now_ = 0.0;
    last_ = lastImpact_ = lastBig_ = -100.0;
    impactMean_ = 0.0f;
  }
  void update(const Frame& f) override {
    Scene& base = base_;
    base.update(f);
    now_ += f.delta;
    const auto m = modifiers(f);
    const Music& mu = f.music;
    float big = 0.0f, kick = 0.0f, snare = 0.0f;
    bool bar = false;
    for (const Event& e : mu.events[0]) {  // bombo
      const float s = std::max(e.strength, 0.05f);
      kick = std::max(kick, s);
      // Golpe grande: el primero tras una pausa o uno claramente más fuerte que los últimos.
      if (now_ - lastImpact_ > 1.5 || s > std::max(0.3f, impactMean_ * 1.3f)) big = std::max(big, s);
      impactMean_ = impactMean_ <= 0.0f ? s : impactMean_ + (s - impactMean_) * 0.25f;
      lastImpact_ = now_;
    }
    for (const Event& e : mu.events[1])  // caja o palmada (los platillos no)
      if (e.band != 3) snare = std::max(snare, std::max(e.strength, 0.05f));
    for (size_t i = 0; i < mu.events[2].size(); i++)  // primer pulso de cada compás
      if (beats_++ % 4 == 0) bar = true;
    for (const Event& e : mu.events[3]) big = std::max(big, std::max(e.strength, 0.6f));  // gran momento
    if (big > 0.0f) {
      if (now_ - lastBig_ < 2.5) big = 0.0f;
      else lastBig_ = now_;
    }
    // Cuánto se queda a la vista según el momento que la llama.
    static constexpr float spans[4] = {1.2f, 0.32f, 0.8f, 0.3f};
    const int which = std::clamp(m.aparece, 0, 3);
    const bool go = which == 0 ? big > 0.0f : which == 1 ? kick > 0.0f : which == 2 ? bar : snare > 0.0f;
    if (!go || now_ - last_ < kGap_) return;
    last_ = now_;
    shows_[cursor_] = Show_{now_, spans[which] * m.permanencia};
    cursor_ = (cursor_ + 1) % kShows_;
  }
  void render(const Frame& f, Canvas& c) const override {
    const float v = visible_();
    if (v < kMin_) return;
    const Scene& base = base_;
    if (v > 0.995f) {
      base.render(f, c);
      return;
    }
    c.saveLayer(v);
    base.render(f, c);
    c.restore();
  }
};
''';
