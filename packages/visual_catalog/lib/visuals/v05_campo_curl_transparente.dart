// Campo de Flujo Vectorial Transparente — versión overlay sin fondo opaco.
// Música: la energía acelera el flujo y abre un vórtice central. Pulso elige
// qué marca el ritmo: Golpes hace latir todo el campo hacia fuera desde el
// centro y destellar estelas y cabezas en cada golpe; Graves
// engruesa y enciende las estelas con los graves; Agudos hace centellear las
// cabezas como chispas con los agudos.
// En cada golpe (y al ritmo de los graves) un resplandor local enciende el sujeto.
// Sin música, el campo fluye exactamente como siempre.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // FORMA: tamaño de los remolinos del campo, de grandes corrientes a turbulencia fina.
  CreatorModifier.slider('escala', 'Escala del campo', min: 1, max: 5, value: 2.4),
  // MOVIMIENTO: flujo libre o filamentos que orbitan alrededor del centro.
  CreatorModifier.slider('remolino', 'Remolino', min: 0, max: 1, value: 0),
  // MÚSICA
  CreatorModifier.choice(
    'pulso',
    'Pulso',
    options: ['Golpes', 'Graves', 'Agudos'],
  ),
  // ATMÓSFERA: largo de las estelas, de chispas cortas a hilos largos.
  CreatorModifier.steps('estela', 'Estela', min: 2, max: 24, value: 8),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Galaxia Líquida', {
    'remolino': 1,
    'escala': 1.4,
    'estela': 18,
    'pulso': 'Graves',
  }),
  CreatorVariation('Turbulencia Fina', {
    'escala': 4.6,
    'estela': 4,
    'pulso': 'Agudos',
    'speed': 1.3,
  }),
];

const nativeSource = r'''
class Visual final : public Scene {
  // Se guardan hasta 24 puntos por estela; Estela decide cuántos se dibujan.
  static constexpr int kMaxTrail = 24;
  struct Streamer {
    float x, y, vx, vy, spd, sz;
    int colIdx;
    float trailX[kMaxTrail];
    float trailY[kMaxTrail];
    int trailLen;
  };
  std::vector<Streamer> streamers;
  int done = 0;
  float fenergy = 0.0f;
  // Música: envolventes estándar y golpe (todo vale 0 sin música).
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Reloj del centelleo de los agudos (sólo se ve con música).
  double glint = 0.0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  // Escala del campo (freq, 2,4 la de siempre) y Remolino (swirl, 0 = libre).
  void step(float w, float h, float freq, float swirl) {
    const float dt = 1.0f / 60.0f;
    float time = float(done) * dt;

    for (auto& s : streamers) {
      float rawAngle = std::sin(s.x * freq + time * 0.6f) * std::cos(s.y * freq - time * 0.4f) * 3.14159265f * 3.5f;
      float speedFactor = 0.0010f + 0.0030f * fenergy;
      float targetVx = std::cos(rawAngle) * speedFactor * s.spd;
      float targetVy = std::sin(rawAngle) * speedFactor * s.spd;

      // Vórtice armónico central estimulado por la energía musical (y por Remolino)
      float dx = 0.5f - s.x;
      float dy = 0.5f - s.y;
      float dist = std::sqrt(dx * dx + dy * dy);
      if (dist > 0.02f && dist < 0.45f) {
        float perpDx = -dy / dist;
        float perpDy = dx / dist;
        float strength = (1.0f - dist / 0.45f) * 0.004f * (fenergy + swirl * 1.5f);
        targetVx += perpDx * strength;
        targetVy += perpDy * strength;
      }

      s.vx = s.vx * 0.88f + targetVx * 0.12f;
      s.vy = s.vy * 0.88f + targetVy * 0.12f;

      s.x += s.vx * dt * 60.0f;
      s.y += s.vy * dt * 60.0f;

      bool reset = false;
      if (s.x < 0.0f) { s.x = 1.0f; reset = true; }
      if (s.x > 1.0f) { s.x = 0.0f; reset = true; }
      if (s.y < 0.0f) { s.y = 1.0f; reset = true; }
      if (s.y > 1.0f) { s.y = 0.0f; reset = true; }

      if (reset) {
        s.trailLen = 0;
      }

      // Guardar historial del rastro
      if (s.trailLen < kMaxTrail) {
        s.trailX[s.trailLen] = s.x * w;
        s.trailY[s.trailLen] = s.y * h;
        s.trailLen++;
      } else {
        for (int k = 0; k < kMaxTrail - 1; k++) {
          s.trailX[k] = s.trailX[k + 1];
          s.trailY[k] = s.trailY[k + 1];
        }
        s.trailX[kMaxTrail - 1] = s.x * w;
        s.trailY[kMaxTrail - 1] = s.y * h;
      }
    }
    done++;
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    streamers.clear(); streamers.reserve(380);
    done = 0;
    bass = body = spark = energy = slowBass = kick = flash = drive = 0.0f;
    glint = 0.0;
    for (int i = 0; i < 380; i++) {
      Streamer s;
      s.x = rng.unit(); s.y = rng.unit();
      s.vx = 0.0f; s.vy = 0.0f;
      s.spd = 0.8f + rng.unit() * 0.9f;
      s.sz = 1.1f + rng.unit() * 1.8f;
      s.colIdx = int(rng.unit() * 4.999f);
      s.trailLen = 0;
      streamers.push_back(s);
    }
  }

  void update(const Frame& f) override {
    auto m = modifiers(f);
    fenergy = f.music.active ? f.music.energy : 0.0f;
    float rate = (f.reducedMotion ? 0.3f : 1.0f) * f.speed;
    int target = int(float(f.time) * rate * 60.0f + 0.001f);
    int guard = 0;
    while (done < target && guard < 16) {
      step(f.width, f.height, m.escala, m.remolino);
      guard++;
    }

    // Bloque de música estándar: graves, medios, agudos, energía y golpe.
    const float dt = float(f.delta);
    const Music& mu = f.music;
    bass = follow(bass, mu.bass, 22.0f, 4.5f, dt);
    body = follow(body, mu.body, 12.0f, 3.0f, dt);
    spark = follow(spark, mu.spark, 30.0f, 7.0f, dt);
    energy = follow(energy, mu.energy, 6.0f, 1.8f, dt);
    drive = follow(drive, mu.active ? std::pow(std::clamp(mu.energy, 0.0f, 1.0f), 0.8f) : 0.0f, 3.0f, 0.7f, dt);
    float hit = 0, fl = 0;
    for (const auto& e : mu.events[0]) hit = std::max(hit, e.strength);
    for (const auto& e : mu.events[2]) hit = std::max(hit, e.strength * 0.85f);
    for (const auto& e : mu.events[3]) fl = std::max(fl, e.strength);
    const float onset = std::clamp((mu.bass - slowBass - 0.15f) * 2.5f, 0.0f, 1.0f);
    slowBass = follow(slowBass, mu.bass, 3.0f, 3.0f, dt);
    hit = std::min(std::max(hit, onset), 1.0f);
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    glint += f.delta * f.speed;
  }

  void render(const Frame& f, Canvas& c) const override {
    auto g = glide(f);
    const float amp = f.intensity;
    // Pulso: cada opción mueve algo distinto y sus pesos funden el cambio.
    // Todo se multiplica por señales de música: sin música vale 0.
    const float golpe = g.pulso.weight(0) * std::min(kick * amp, 1.0f);
    const float grave = g.pulso.weight(1) * std::min((bass * 0.8f + body * 0.3f + drive * 0.1f) * amp, 1.2f);
    const float agudo = g.pulso.weight(2) * std::min((spark + flash * 0.4f + energy * 0.1f) * amp, 1.2f);
    const float gt = float(std::fmod(glint, 1000.0));
    float w = f.width, h = f.height;

    // Resplandor local en el corazón del campo: Golpes lo enciende, Graves lo hace respirar.
    const float bloom = std::min(0.6f, (golpe * 0.55f + grave * 0.22f) * f.glow);
    if (bloom > 0.003f) {
      const Vec2 mid{w * 0.5f, h * 0.5f};
      const float R = std::min(w, h) * 0.65f;
      Paint gl = Paint::radial(mid, R,
        {Color{0.0f, 1.0f, 0.8f, bloom}, Color{0.45f, 0.04f, 0.72f, bloom * 0.45f}, Color{0.0f, 0.3f, 0.5f, 0.0f}},
        {0.0f, 0.45f, 1.0f});
      gl.blend = Blend::plus;
      c.circle(mid, R, gl);
    }

    // Paleta neón bioluminiscente
    const uint32_t pal[5] = {0xff00ffcc, 0xff00b4d8, 0xff7209b7, 0xfff72585, 0xff4cc9f0};

    // Estela: cuántos puntos del rastro se dibujan (8 = la de siempre).
    const int keep = std::clamp(int(std::lround(g.estela)), 2, kMaxTrail);
    // Graves engruesa y enciende las estelas; Golpes las hace destellar.
    const float trailLift = 1.0f + golpe * 1.0f + grave * 0.8f;
    const float trailThick = 1.0f + grave * 0.6f + golpe * 1.3f;
    // Golpes: todo el campo late hacia fuera desde el centro; Graves lo hace respirar.
    const float pop = golpe * 0.15f + grave * 0.1f;
    const bool beat = pop > 0.0005f;
    if (beat) {
      c.save();
      c.transform(1.0f + pop, 0.0f, 0.0f, 1.0f + pop, -w * 0.5f * pop, -h * 0.5f * pop);
    }

    // Renderizar rastros agrupados por color
    for (int col = 0; col < 5; col++) {
      Color base = Color::argb(pal[col]);
      Paint tp; tp.blend = Blend::plus;
      tp.color = {base.r, base.g, base.b, std::clamp(0.40f * f.intensity * trailLift, 0.0f, 1.0f)};
      tp.strokeWidth = 1.3f * trailThick;
      tp.strokeCap = 1; tp.strokeJoin = 1;

      Path trailPath;
      for (const auto& s : streamers) {
        const int n = std::min(s.trailLen, keep);
        if (s.colIdx != col || n < 2) continue;
        const int first = s.trailLen - n;
        trailPath.moveTo(s.trailX[first], s.trailY[first]);
        for (int k = first + 1; k < s.trailLen; k++) {
          trailPath.lineTo(s.trailX[k], s.trailY[k]);
        }
      }
      c.path(trailPath, tp);
    }

    // Cabezas brillantes de las partículas
    std::vector<Vec2> heads;
    heads.reserve(streamers.size());
    // Agudos: algunas cabezas centellean como chispas.
    std::vector<Vec2> glints;
    if (agudo > 0.003f) glints.reserve(streamers.size());
    for (size_t i = 0; i < streamers.size(); i++) {
      const auto& s = streamers[i];
      if (s.trailLen > 0) {
        heads.push_back({s.trailX[s.trailLen - 1], s.trailY[s.trailLen - 1]});
        if (agudo > 0.003f && std::sin(gt * 15.0f + float(i) * 2.4f) > -0.2f) glints.push_back(heads.back());
      }
    }
    Paint hp; hp.blend = Blend::plus;
    hp.color = {1.0f, 1.0f, 1.0f, std::clamp(0.9f * f.intensity, 0.0f, 1.0f)};
    c.points(heads, 1.4f * (1.0f + golpe * 1.2f), hp);
    if (!glints.empty()) {
      Paint gp; gp.blend = Blend::plus;
      gp.color = {1.0f, 0.85f, 0.95f, std::clamp(agudo * 0.95f, 0.0f, 1.0f)};
      c.points(glints, 3.0f, gp);
    }
    if (beat) c.restore();
  }
};
''';
