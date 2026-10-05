// Supernova & Termodinámica — Puerto fiel de Visuales Inmersivas v10.
// Explosión de colapso de núcleo estelar con 360 partículas termodinámicas,
// ondas de choque sónicas expansivas y remanente de púlsar central.
// Música: los graves fuertes siguen disparando la gran onda de choque que
// barre las partículas y el púlsar late con ellos. Pulso elige el resto:
// Golpes lanza en cada golpe un anillo corto desde el púlsar, que da un salto,
// y enciende toda la nube; Graves hincha la nube despacio y engrosa sus
// estelas; Agudos hace centellear partículas hacia el blanco y aviva los haces.
// Además, cada opción de Pulso enciende un resplandor local sobre
// el púlsar, que late con la música (nunca un velo a pantalla completa).
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // MOVIMIENTO: caída casi recta al núcleo o gran remolino orbital.
  CreatorModifier.slider('remolino', 'Remolino', min: .2, max: 2.2, value: 1),
  // MÚSICA
  CreatorModifier.choice(
    'pulso',
    'Pulso',
    options: ['Golpes', 'Graves', 'Agudos'],
  ),
  // ATMÓSFERA: estelas cortas como chispas o largas como rayos.
  CreatorModifier.slider('estela', 'Estela', min: .3, max: 3, value: 1),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Galaxia Viva', {
    'remolino': 2,
    'estela': 1.8,
    'pulso': 'Graves',
  }),
  CreatorVariation('Colapso', {
    'remolino': .3,
    'estela': .5,
    'pulso': 'Agudos',
    'speed': 1.3,
  }),
];

const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kParticleCount = 360;
  struct StellarParticle {
    float x, y, vx, vy, energy, size;
    int colIdx;
  };
  std::vector<StellarParticle> particles;
  int done = 0;
  float fenergy = 0.0f, fbass = 0.0f;
  bool fActive = false;
  float shockRadius = 0.0f;
  // Envolventes de la música (cero en silencio) y el anillo del último golpe.
  float bass = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0;
  double ringAge = 100.0;
  float ringPower = 0.0f;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }
  static float hashU(uint32_t x) {
    x ^= x >> 16; x *= 0x7feb352dU; x ^= x >> 15; x *= 0x846ca68bU; x ^= x >> 16;
    return float(x & 0xffffffu) / 16777216.0f;
  }

  void step(float w, float h, float swirlExtra) {
    const float dt = 1.0f / 60.0f;
    float cx = w * 0.5f, cy = h * 0.5f;

    // Disparo de ondas de choque exclusivamente ante bombos reales con música activa
    if (shockRadius > 0.0f) {
      shockRadius += 16.0f;
      if (shockRadius > std::max(w, h) * 1.2f) {
        shockRadius = 0.0f;
      }
    } else if (fActive && fbass > 0.65f) {
      shockRadius = 10.0f;
      float blast = 14.0f + fenergy * 18.0f;
      for (auto& p : particles) {
        float dx = p.x - cx, dy = p.y - cy;
        float dist = std::max(12.0f, std::sqrt(dx * dx + dy * dy));
        float angle = std::atan2(dy, dx);
        float speed = std::clamp(blast * 110.0f / dist, 3.0f, 26.0f);
        p.vx = std::cos(angle) * speed;
        p.vy = std::sin(angle) * speed;
        p.energy = 1.0f;
      }
    }

    for (auto& p : particles) {
      // Gravedad central suave
      float dx = cx - p.x;
      float dy = cy - p.y;
      float dist = std::max(30.0f, std::sqrt(dx * dx + dy * dy));
      float grav = 0.07f;
      float perpX = -dy / dist;
      float perpY = dx / dist;

      p.vx += (dx / dist) * grav + perpX * 0.035f;
      p.vy += (dy / dist) * grav + perpY * 0.035f;
      // Remolino: empuje tangencial extra (cero con el valor inicial).
      if (swirlExtra != 0.0f) {
        p.vx += perpX * swirlExtra;
        p.vy += perpY * swirlExtra;
      }

      p.vx *= 0.985f;
      p.vy *= 0.985f;

      p.x += p.vx * dt * 60.0f;
      p.y += p.vy * dt * 60.0f;

      if (p.x < 0.0f) { p.x = 0.0f; p.vx = -p.vx * 0.6f; }
      if (p.x > w) { p.x = w; p.vx = -p.vx * 0.6f; }
      if (p.y < 0.0f) { p.y = 0.0f; p.vy = -p.vy * 0.6f; }
      if (p.y > h) { p.y = h; p.vy = -p.vy * 0.6f; }

      p.energy = std::clamp(p.energy * 0.993f, 0.15f, 1.0f);
    }
    done++;
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    particles.clear(); particles.reserve(kParticleCount);
    done = 0; shockRadius = 0.0f; fActive = false; fenergy = 0.0f; fbass = 0.0f;
    bass = spark = energy = slowBass = kick = flash = 0.0f;
    ringAge = 100.0; ringPower = 0.0f;
    for (int i = 0; i < kParticleCount; i++) {
      float a = rng.unit() * 6.2831853f;
      float dist = 20.0f + rng.unit() * 180.0f;
      float spd = (rng.unit() - 0.5f) * 2.2f;
      particles.push_back({
        std::cos(a) * dist, std::sin(a) * dist,
        std::sin(a) * spd, -std::cos(a) * spd,
        rng.unit(),
        1.2f + rng.unit() * 2.2f,
        int(rng.unit() * 4.999f)
      });
    }
  }

  void update(const Frame& f) override {
    // Música: envolventes y golpes (todo vale cero en silencio).
    const float dt = float(f.delta);
    const Music& mu = f.music;
    bass = follow(bass, mu.bass, 22.0f, 4.5f, dt);
    spark = follow(spark, mu.spark, 30.0f, 7.0f, dt);
    energy = follow(energy, mu.energy, 6.0f, 1.8f, dt);
    float hit = 0, fl = 0;
    for (const auto& e : mu.events[0]) hit = std::max(hit, e.strength);
    for (const auto& e : mu.events[2]) hit = std::max(hit, e.strength * 0.85f);
    for (const auto& e : mu.events[3]) fl = std::max(fl, e.strength);
    const float onset = std::clamp((mu.bass - slowBass - 0.15f) * 2.5f, 0.0f, 1.0f);
    slowBass = follow(slowBass, mu.bass, 3.0f, 3.0f, dt);
    hit = std::min(std::max(hit, onset), 1.0f);
    const bool fresh = hit > kick + 0.2f;
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    ringAge += f.delta;
    if (fresh) { ringAge = 0.0; ringPower = hit; }
    // Remolino: 1 conserva el empuje tangencial original.
    const float swirlExtra = 0.035f * (glide(f).remolino - 1.0f);

    fActive = f.music.active;
    fenergy = f.music.active ? f.music.energy : 0.0f;
    fbass = f.music.active ? f.music.bass : 0.0f;
    float rate = (f.reducedMotion ? 0.3f : 1.0f) * f.speed;
    int target = int(float(f.time) * rate * 60.0f + 0.001f);
    int guard = 0;
    while (done < target && guard < 16) {
      step(f.width, f.height, swirlExtra);
      guard++;
    }
  }

  void render(const Frame& f, Canvas& c) const override {
    auto g = glide(f);
    float w = f.width, h = f.height;
    float t = float(f.time) * f.speed;
    Vec2 center{w * 0.5f, h * 0.5f};
    float maxDim = std::max(w, h);
    const float amp = f.intensity;
    // Pulso: sus pesos reparten la reacción; todo vale cero sin música.
    const float punch = std::min(kick * amp, 1.0f) * g.pulso.weight(0);
    const float swell = std::min(bass * amp, 1.0f) * g.pulso.weight(1);
    const float glint = std::min(spark * amp, 1.0f) * g.pulso.weight(2);
    const float trail = g.estela;

    // 1. Fondo vacío espacial
    Paint bg; bg.color = Color::argb(0xff030107);
    c.rect({0, 0, w, h}, bg);

    // 2. Remanente central (Púlsar ultra-denso con haz rotatorio)
    float bassKick = (1.0f + f.music.bass * 0.5f);
    // Resplandor local de la música alrededor del púlsar (nunca a pantalla
    // completa): Golpes lo enciende en cada golpe, Graves lo hace respirar y
    // Agudos lo hace parpadear en cian.
    const float side = std::min(w, h);
    if (punch > 0.0f || swell > 0.0f) {
      const float auraR = side * 0.46f * (1.0f + 0.15f * swell + 0.12f * punch);
      Paint aura = Paint::radial(center, auraR,
        {{1.0f, 0.34f, 0.13f, std::clamp((0.42f * punch + 0.34f * swell) * f.glow, 0.0f, 1.0f)},
         {1.0f, 0.34f, 0.13f, std::clamp((0.18f * punch + 0.14f * swell) * f.glow, 0.0f, 1.0f)},
         {1.0f, 0.34f, 0.13f, 0.0f}}, {0.0f, 0.5f, 1.0f});
      aura.blend = Blend::plus;
      c.circle(center, auraR, aura);
    }
    if (glint > 0.0f) {
      const float flicker = 0.6f + 0.4f * std::sin(t * 47.0f);
      Paint shimmer = Paint::radial(center, side * 0.34f,
        {{0.0f, 0.9f, 1.0f, std::clamp(0.36f * glint * flicker * f.glow, 0.0f, 1.0f)}, {0.0f, 0.9f, 1.0f, 0.0f}}, {0.0f, 1.0f});
      shimmer.blend = Blend::plus;
      c.circle(center, side * 0.34f, shimmer);
    }
    // Golpes: el púlsar da un salto; Graves: su halo crece y brilla despacio.
    const float glowR = 50.0f * bassKick * (1.0f + 0.2f * punch + 0.15f * swell);
    Paint pulsarGlow = Paint::radial(center, glowR,
      {{1.0f, 0.35f, 0.0f, std::clamp(0.40f * f.intensity + 0.5f * punch + 0.4f * swell, 0.0f, 1.0f)}, {0, 0, 0, 0}},
      {0.0f, 1.0f});
    pulsarGlow.blend = Blend::plus;
    c.circle(center, glowR, pulsarGlow);

    Paint pulsarCore; pulsarCore.blend = Blend::plus;
    pulsarCore.color = {1.0f, 1.0f, 1.0f, std::clamp(0.95f * f.intensity, 0.0f, 1.0f)};
    c.circle(center, 5.0f * bassKick * (1.0f + 0.6f * punch), pulsarCore);

    // Haces de emisión del púlsar rotando a gran velocidad (Agudos: se avivan)
    float beamAngle = t * 4.0f;
    float beamLen = 35.0f * bassKick * (1.0f + 0.6f * glint);
    Paint beamPaint; beamPaint.blend = Blend::plus;
    beamPaint.color = {0.0f, 0.9f, 1.0f, std::clamp(0.6f * f.intensity + 0.4f * glint, 0.0f, 1.0f)};
    beamPaint.strokeWidth = 2.0f;
    if (glint > 0.0f) beamPaint.strokeWidth *= 1.0f + 1.2f * glint;
    Path beams;
    beams.moveTo(center.x - std::cos(beamAngle) * beamLen, center.y - std::sin(beamAngle) * beamLen);
    beams.lineTo(center.x + std::cos(beamAngle) * beamLen, center.y + std::sin(beamAngle) * beamLen);
    c.path(beams, beamPaint);

    // 3. Onda de choque expansiva
    if (shockRadius > 0.0f) {
      float shockAlpha = std::clamp((1.0f - shockRadius / (maxDim * 1.2f)) * f.intensity, 0.0f, 1.0f);
      Paint shockPaint; shockPaint.blend = Blend::plus;
      shockPaint.color = {1.0f, 0.84f, 0.0f, shockAlpha};
      shockPaint.strokeWidth = std::clamp(4.0f * shockAlpha, 1.0f, 4.0f);
      c.circle(center, shockRadius, shockPaint);
    }

    // Golpes: un anillo de choque corto sale del púlsar con cada golpe.
    const float ringFade = ringPower * float(std::exp(-ringAge * 3.0)) * g.pulso.weight(0);
    if (ringFade > 0.01f) {
      Paint ring; ring.blend = Blend::plus;
      ring.color = {1.0f, 0.62f, 0.22f, std::clamp(0.95f * ringFade * amp, 0.0f, 1.0f)};
      ring.strokeWidth = 2.5f + 6.0f * ringFade;
      c.circle(center, 50.0f * bassKick + float(ringAge) * maxDim * 0.55f, ring);
    }

    // 4. Renderizar partículas termodinámicas con estelas de velocidad
    const uint32_t thermalPal[5] = {0xffff5722, 0xffffd600, 0xff00e5ff, 0xffff007f, 0xffe040fb};
    const uint32_t twinkleTick = uint32_t(std::floor(t * 14.0f));

    for (size_t i = 0; i < particles.size(); i++) {
      const auto& p = particles[i];
      float speed = std::sqrt(p.vx * p.vx + p.vy * p.vy);
      float trailLen = std::clamp(speed * 1.5f, 2.0f, 24.0f);
      // Estela: más corta o más larga que la original (1 = igual).
      trailLen *= trail;
      float normVx = (speed > 0.01f) ? (p.vx / speed) : 0.0f;
      float normVy = (speed > 0.01f) ? (p.vy / speed) : 0.0f;

      float px = (done == 0 ? center.x + p.x : p.x);
      float py = (done == 0 ? center.y + p.y : p.y);
      // Graves: la nube se hincha desde el púlsar.
      if (swell > 0.0f) {
        px = center.x + (px - center.x) * (1.0f + 0.14f * swell);
        py = center.y + (py - center.y) * (1.0f + 0.14f * swell);
      }
      float tailX = px - normVx * trailLen;
      float tailY = py - normVy * trailLen;

      Color base = Color::argb(thermalPal[p.colIdx]);
      // Transición termodinámica hacia el blanco en alta energía
      Color col{
        base.r * (1.0f - p.energy) + 1.0f * p.energy,
        base.g * (1.0f - p.energy) + 1.0f * p.energy,
        base.b * (1.0f - p.energy) + 1.0f * p.energy,
        std::clamp((0.40f + p.energy * 0.60f) * f.intensity, 0.0f, 1.0f)
      };
      // Golpes: la nube entera se enciende; Agudos: algunas partículas centellean.
      if (punch > 0.0f || glint > 0.0f) {
        const float sparkle = hashU(uint32_t(i) * 2654435761u + twinkleTick * 40503u) < glint * 0.9f ? glint : 0.0f;
        col.r = std::min(1.0f, col.r + (1.0f - col.r) * 0.8f * sparkle);
        col.g = std::min(1.0f, col.g + (1.0f - col.g) * 0.8f * sparkle);
        col.b = std::min(1.0f, col.b + (1.0f - col.b) * 0.8f * sparkle);
        col.a = std::clamp(col.a + 0.65f * punch + 0.6f * sparkle, 0.0f, 1.0f);
      }

      Paint partPaint; partPaint.blend = Blend::plus;
      partPaint.color = col;
      partPaint.strokeWidth = std::max(1.0f, p.size);
      // Graves y Golpes: estelas más gruesas.
      if (swell > 0.0f || punch > 0.0f) partPaint.strokeWidth *= 1.0f + 0.6f * swell + 0.9f * punch;
      partPaint.strokeCap = 1;

      Path pLine; pLine.moveTo(tailX, tailY); pLine.lineTo(px, py);
      c.path(pLine, partPaint);
    }
  }
};
''';
