// Espectro Sonoro Cósmico Transparente — Versión Overlay / Capa transparente.
// Analizador espectral circular con núcleo pulsante de graves,
// 72 barras radiales conectadas al espectro de audio y anillo de resonancia sobre fondo transparente.
// Música: las barras siguen el espectro y el núcleo late con los graves.
// Pulso elige qué más marca el ritmo: Golpes lanza una onda de choque desde
// el núcleo y hace destellar el anillo y las partículas en cada golpe; Graves
// engruesa y enciende el anillo de resonancia con los graves; Agudos hace
// chispear las puntas de las barras y las partículas con los agudos.
// En cada golpe (y al ritmo de los graves) un resplandor local enciende el sujeto.
// Sin música, el orbe reposa exactamente como siempre.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // FORMA: cuántas barras forman el anillo.
  CreatorModifier.steps('barras', 'Barras', min: 24, max: 144, value: 72),
  // MOVIMIENTO: base redonda y quieta o una base que ondula como una flor.
  CreatorModifier.slider('onda', 'Ondulación', min: 0, max: 1, value: 0),
  // MÚSICA
  CreatorModifier.choice(
    'pulso',
    'Pulso',
    options: ['Golpes', 'Graves', 'Agudos'],
  ),
  // MODO: una segunda corona de barras cuelga del anillo hacia el núcleo.
  CreatorModifier.toggle('doble', 'Barras dobles', value: false),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Mandala Sónico', {
    'barras': 144,
    'doble': true,
    'onda': .5,
    'pulso': 'Agudos',
  }),
  CreatorVariation('Flor Pulsar', {
    'barras': 36,
    'onda': 1,
    'pulso': 'Golpes',
    'speed': 1.3,
  }),
];

const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kBarCount = 72;
  float spectralTime = 0.0f;
  float smoothEnergy = 0.0f;
  float smoothBass = 0.0f;
  // Música: envolventes estándar y golpe (todo vale 0 sin música).
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float punch = 0, flash = 0, drive = 0;
  // Onda de choque del último golpe: segundos desde que nació y su fuerza.
  float waveAge = 10.0f, wavePower = 0.0f;
  // Reloj propio de la ondulación y del centelleo (igual a 30 y 60 FPS).
  double flow = 0.0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }
 public:
  void reset(uint32_t seed) override {
    (void)seed;
    spectralTime = 0.0f;
    smoothEnergy = 0.0f;
    smoothBass = 0.0f;
    bass = body = spark = energy = slowBass = punch = flash = drive = 0.0f;
    waveAge = 10.0f;
    wavePower = 0.0f;
    flow = 0.0;
  }
  void update(const Frame& f) override {
    float dt = float(f.delta);
    float targetEnergy = f.music.active ? f.music.energy : 0.0f;
    float targetBass = f.music.active ? f.music.bass : 0.0f;
    smoothEnergy += (targetEnergy - smoothEnergy) * float(1.0 - std::exp(-dt * 6.0));
    smoothBass += (targetBass - smoothBass) * float(1.0 - std::exp(-dt * 8.0));

    // En silencio reposa en un orbe tranquilo (~0.08f).
    // Con música la rotación y el pulso se acoplan a la señal.
    float audioDrive = 0.08f + smoothEnergy * 0.72f + smoothBass * 0.35f;
    spectralTime += dt * f.speed * audioDrive;

    // Bloque de música estándar: graves, medios, agudos, energía y golpe.
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
    const bool fresh = hit > punch + 0.2f;
    punch = std::max(punch * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    // Cada golpe nuevo lanza una onda de choque desde el núcleo.
    waveAge = std::min(waveAge + dt, 100.0f);
    if (fresh) {
      waveAge = 0.0f;
      wavePower = hit;
    }
    flow += f.delta * f.speed;
  }
  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    auto g = glide(f);
    const float amp = f.intensity;
    // Pulso: cada opción mueve algo distinto y sus pesos funden el cambio.
    // Todo se multiplica por señales de música: sin música vale 0.
    const float golpe = g.pulso.weight(0) * std::min(punch * amp, 1.0f);
    const float onda = g.pulso.weight(0) * std::min(wavePower * amp, 1.0f) * std::exp(-waveAge * 1.8f);
    const float grave = g.pulso.weight(1) * std::min((bass * 0.8f + body * 0.3f + drive * 0.1f) * amp, 1.2f);
    const float agudo = g.pulso.weight(2) * std::min((spark + flash * 0.4f + energy * 0.1f) * amp, 1.2f);
    const float ft = float(std::fmod(flow, 1000.0));
    float w = f.width, h = f.height;
    float t = spectralTime;
    Vec2 center{w * 0.5f, h * 0.5f};
    float minDim = std::min(w, h);

    // Sin fondo opaco: lienzo 100% transparente

    // 1. Núcleo central pulsante: en silencio está sereno (kick = 0)
    float kick = (f.music.active ? smoothBass * 1.5f : 0.0f) * f.intensity;
    float baseRadius = minDim * 0.12f * (1.0f + kick * 0.28f);
    // Golpes: el orbe entero salta en cada golpe; Graves: respira con los graves.
    baseRadius *= 1.0f + golpe * 0.15f + grave * 0.12f;

    // Resplandor del núcleo
    float glowAlpha = f.music.active ? (0.25f + smoothEnergy * 0.35f) : 0.15f;
    Paint coreGlow = Paint::radial(center, baseRadius * 1.6f,
      {{1.0f, 0.0f, 0.5f, std::clamp(glowAlpha * f.intensity * (1.0f + grave * 0.8f + golpe * 0.8f), 0.0f, 1.0f)}, {0, 0, 0, 0}},
      {0.0f, 1.0f});
    coreGlow.blend = Blend::plus;
    c.circle(center, baseRadius * 1.6f, coreGlow);

    // Esfera interior del núcleo
    Paint coreSphere = Paint::radial(center, baseRadius * 0.85f,
      {Color{1.0f, 1.0f, 1.0f, 1.0f}, Color::argb(0xff00f0ff), Color::argb(0xff7000ff)},
      {0.0f, 0.4f, 1.0f});
    coreSphere.blend = Blend::plus;
    c.circle(center, baseRadius * 0.85f, coreSphere);

    // Resplandor local del orbe hasta el anillo: Golpes lo enciende, Graves lo hace respirar.
    // Agudos: el resplandor titila con los agudos.
    const float bloom = std::min(0.55f, (golpe * 0.48f + grave * 0.28f + agudo * 0.15f * (0.6f + 0.4f * std::sin(ft * 23.0f))) * f.glow);
    if (bloom > 0.003f) {
      const float R = baseRadius + minDim * 0.38f;
      Paint gl = Paint::radial(center, R,
        {Color{1.0f, 0.2f, 0.7f, bloom}, Color{0.2f, 0.9f, 1.0f, bloom * 0.45f}, Color{0.3f, 0.0f, 0.6f, 0.0f}},
        {0.0f, 0.45f, 1.0f});
      gl.blend = Blend::plus;
      c.circle(center, R, gl);
    }

    // Golpes: una onda de choque sale del núcleo y cruza el anillo.
    if (onda > 0.003f) {
      Paint sp; sp.blend = Blend::plus;
      sp.color = {0.6f, 1.0f, 0.95f, std::clamp(onda * 0.9f, 0.0f, 1.0f)};
      sp.strokeWidth = 2.0f + 4.0f * onda;
      c.circle(center, baseRadius + waveAge * minDim * 0.75f, sp);
    }

    // 2. Renderizar las barras radiales (72 = el anillo de siempre)
    const int bars = std::clamp(m.barras, 24, 144);
    const float thin = std::min(1.0f, float(kBarCount) / float(bars));
    const float angleStep = 6.2831853f / float(bars);
    std::vector<Vec2> sparkCaps;
    sparkCaps.reserve(bars);
    // Agudos: chispas que saltan de punta en punta.
    std::vector<Vec2> tips;
    if (agudo > 0.003f) tips.reserve(bars);
    // Barras dobles: la segunda corona cuelga del anillo de resonancia.
    const float outerRing = baseRadius + minDim * 0.22f;

    for (int i = 0; i < bars; i++) {
      float angle = float(i) * angleStep - 3.14159265f * 0.5f;

      // Frecuencia normalizada (sub-graves simétricos y agudos laterales)
      float normFreq = std::abs((float(i) / (float(bars) * 0.5f)) - 1.0f);
      int specIdx = std::clamp(int(normFreq * 30.0f), 0, 30);
      float realAudio = f.music.active ? f.music.spectrum[specIdx] : 0.0f;
      float smoothAudio = f.music.active ? f.music.smoothSpectrum[specIdx] : 0.0f;

      // En silencio las barras descansan en un anillo limpio sin brincar a lo loco
      float barVal = f.music.active ? std::max(realAudio * 1.8f, smoothAudio * 1.3f) : 0.015f;
      float barLength = minDim * (0.018f + barVal * 0.18f + kick * (1.0f - normFreq) * 0.12f);

      float cosA = std::cos(angle), sinA = std::sin(angle);
      // Ondulación: la base ondula como una flor de seis pétalos que gira.
      float bR = baseRadius;
      if (g.onda > 0.0f) bR *= 1.0f + g.onda * 0.22f * std::sin(angle * 6.0f + ft * 1.7f);
      float sx = center.x + bR * cosA;
      float sy = center.y + bR * sinA;
      float ex = center.x + (bR + barLength) * cosA;
      float ey = center.y + (bR + barLength) * sinA;

      // Color lerp: cian {0, 1, 0.88} a magenta {1, 0, 0.33}
      Color barCol{
        0.0f * (1.0f - normFreq) + 1.0f * normFreq,
        1.0f * (1.0f - normFreq) + 0.0f * normFreq,
        0.88f * (1.0f - normFreq) + 0.33f * normFreq,
        std::clamp(0.85f * f.intensity * (1.0f + golpe * 0.8f), 0.0f, 1.0f)
      };
      Paint bp; bp.blend = Blend::plus; bp.color = barCol;
      bp.strokeWidth = std::max(1.2f, minDim * 0.008f) * thin * (1.0f + golpe * 1.2f + grave * 0.6f);
      bp.strokeCap = 1;

      Path barPath; barPath.moveTo(sx, sy); barPath.lineTo(ex, ey);
      c.path(barPath, bp);

      // Chispas en los picos de energía
      if (barLength > minDim * 0.14f) {
        float spx = center.x + (bR + barLength + 4.0f) * cosA;
        float spy = center.y + (bR + barLength + 4.0f) * sinA;
        sparkCaps.push_back({spx, spy});
      }
      if (agudo > 0.003f && std::sin(ft * 15.0f + float(i) * 2.3f) > -0.2f) {
        tips.push_back({center.x + (bR + barLength + 3.0f) * cosA, center.y + (bR + barLength + 3.0f) * sinA});
      }

      if (g.doble > 0.0f) {
        const float inner = std::max(baseRadius * 1.1f, outerRing - barLength * 0.7f);
        Path hang;
        hang.moveTo(center.x + outerRing * cosA, center.y + outerRing * sinA);
        hang.lineTo(center.x + inner * cosA, center.y + inner * sinA);
        bp.color = barCol.opacity(barCol.a * 0.8f * g.doble);
        c.path(hang, bp);
      }
    }

    if (!sparkCaps.empty()) {
      Paint spk; spk.blend = Blend::plus;
      spk.color = {1.0f, 1.0f, 1.0f, std::clamp(0.95f * f.intensity, 0.0f, 1.0f)};
      c.points(sparkCaps, 2.0f, spk);
    }
    if (!tips.empty()) {
      Paint tp; tp.blend = Blend::plus;
      tp.color = {1.0f, 0.55f, 0.95f, std::clamp(agudo * 0.9f, 0.0f, 1.0f)};
      c.points(tips, 3.0f, tp);
    }

    // 3. Anillo de resonancia exterior: Graves lo engruesa, Golpes lo hace destellar.
    float ringRadius = baseRadius + minDim * 0.22f;
    Paint ringPaint; ringPaint.blend = Blend::plus;
    ringPaint.color = {0.0f, 1.0f, 0.88f, std::clamp(0.25f * f.intensity + golpe * 0.6f + grave * 0.5f, 0.0f, 1.0f)};
    ringPaint.strokeWidth = 1.4f * (1.0f + grave * 1.5f + golpe * 1.5f);
    c.circle(center, ringRadius, ringPaint);

    // 4. Partículas armónicas en órbita
    std::vector<Vec2> orbiters;
    orbiters.reserve(8);
    for (int p = 0; p < 8; p++) {
      float pAngle = t * (0.8f + float(p) * 0.2f) + float(p) * (3.14159265f / 4.0f);
      float radOffset = std::sin(pAngle * 3.0f) * 12.0f;
      float ox = center.x + (ringRadius + radOffset) * std::cos(pAngle);
      float oy = center.y + (ringRadius + radOffset) * std::sin(pAngle);
      orbiters.push_back({ox, oy});
    }
    Paint orbPaint; orbPaint.blend = Blend::plus;
    orbPaint.color = {1.0f, 0.0f, 0.63f, std::clamp(0.85f * f.intensity, 0.0f, 1.0f)};
    const float orbTwinkle = agudo * (0.5f + 0.5f * std::sin(ft * 21.0f));
    c.points(orbiters, 2.8f * (1.0f + golpe * 1.2f + orbTwinkle * 0.8f), orbPaint);
  }
};
''';
