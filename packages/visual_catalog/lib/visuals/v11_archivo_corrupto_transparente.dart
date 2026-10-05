// Archivo Corrupto Transparente — Versión Overlay / Capa transparente.
// Datamosh digital estructurado con aberración cromática RGB aditiva,
// franja VHS de rodadura inferior y fallas cromáticas sobre fondo transparente.
// Música: la energía y los graves aceleran el datamosh, los bombos fuertes
// lanzan ráfagas de desplazamiento y los agudos saltos cromáticos. Pulso
// elige el resto: Golpes sacude las filas de lado y abre los canales RGB en
// cada golpe; Graves engorda los bloques despacio; Agudos hace temblar la
// separación de color y enciende píxeles muertos que parpadean.
// Además, cada opción de Pulso enciende un resplandor local sobre
// la franja de datos, que late con la música (nunca un velo a pantalla completa).
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // FORMA: bloques finos como líneas o anchos como losas.
  CreatorModifier.slider('bloques', 'Ancho de bloque', min: .4, max: 2.5, value: 1),
  // MOVIMIENTO: deriva fluida o imagen que se congela y avanza a saltos.
  CreatorModifier.choice(
    'caracter',
    'Carácter',
    options: ['Fluido', 'Entrecortado'],
  ),
  // MÚSICA
  CreatorModifier.choice(
    'pulso',
    'Pulso',
    options: ['Golpes', 'Graves', 'Agudos'],
  ),
  // ATMÓSFERA: canales RGB juntos o muy separados.
  CreatorModifier.slider('aberracion', 'Aberración', min: 0, max: 2.5, value: 1),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Señal Rota', {
    'caracter': 'Entrecortado',
    'aberracion': 2.2,
    'bloques': .7,
    'pulso': 'Golpes',
  }),
  CreatorVariation('Losas VHS', {
    'bloques': 2.2,
    'aberracion': .4,
    'pulso': 'Graves',
    'speed': .8,
  }),
];

const nativeSource = r'''
class Visual final : public Scene {
  struct CorruptRow {
    float baseShift;
    float blockWidth;
    float blockHeight;
    float chromaOffset;
    float seedPhase;
    float burstShift;
    float burstLife;
    bool hasAlert;
  };

  std::vector<CorruptRow> rows;
  float simTime = 0.0f;
  float lastBurstTime = -10.0f;
  float sparkChromaTimer = 0.0f;
  float trackingY = 0.88f;
  float smoothEnergy = 0.0f;
  float smoothBass = 0.0f;
  // Envolventes de la música para Pulso (cero en silencio).
  float bass = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }
  static float hashU(uint32_t x) {
    x ^= x >> 16; x *= 0x7feb352dU; x ^= x >> 15; x *= 0x846ca68bU; x ^= x >> 16;
    return float(x & 0xffffffu) / 16777216.0f;
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    rows.clear();
    rows.reserve(90);
    simTime = 0.0f;
    lastBurstTime = -10.0f;
    sparkChromaTimer = 0.0f;
    trackingY = 0.88f;
    smoothEnergy = 0.0f;
    smoothBass = 0.0f;
    bass = spark = energy = slowBass = kick = flash = 0.0f;

    for (int i = 0; i < 90; i++) {
      CorruptRow r;
      r.baseShift = (rng.unit() - 0.5f) * 24.0f;
      r.blockWidth = 8.0f + rng.unit() * 32.0f;
      r.blockHeight = 2.0f + rng.unit() * 4.0f;
      r.chromaOffset = 4.0f + rng.unit() * 14.0f;
      r.seedPhase = rng.unit() * 6.2831853f;
      r.burstShift = 0.0f;
      r.burstLife = 0.0f;
      r.hasAlert = rng.unit() < 0.14f;
      rows.push_back(r);
    }
  }

  void update(const Frame& f) override {
    float dt = float(f.delta);
    // Música para Pulso: envolventes y golpes (todo vale cero en silencio).
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
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));

    float targetEnergy = f.music.active ? f.music.energy : 0.0f;
    float targetBass = f.music.active ? f.music.bass : 0.0f;
    float targetSpark = f.music.active ? f.music.spark : 0.0f;

    smoothEnergy += (targetEnergy - smoothEnergy) * float(1.0 - std::exp(-dt * 5.0));
    smoothBass += (targetBass - smoothBass) * float(1.0 - std::exp(-dt * 6.0));

    // En silencio reposa en un barrido CRT limpio con mínima deriva (~0.12f).
    // Con música acelera el datamosh glitch y los saltos cromáticos.
    float audioDrive = 0.12f + smoothEnergy * 0.72f + smoothBass * 0.35f;
    float speedMult = (f.reducedMotion ? 0.25f : 1.0f) * f.speed * audioDrive;
    simTime += dt * speedMult;

    // Detección de ráfaga de desplazamiento en bombos fuertes con música activa
    if (f.music.active && (targetSpark > 0.65f || smoothBass > 0.72f) && (simTime - lastBurstTime >= 1.8f)) {
      lastBurstTime = simTime;
      Random burstRng(uint32_t(simTime * 1000.0f) ^ 0x30303);
      int centerRow = int(burstRng.unit() * 70.0f) + 10;
      for (int i = 0; i < 90; i++) {
        if (std::abs(i - centerRow) < 22 || burstRng.unit() < 0.28f) {
          rows[i].burstLife = 0.30f;
          float sgn = burstRng.unit() > 0.5f ? 1.0f : -1.0f;
          rows[i].burstShift = sgn * (28.0f + burstRng.unit() * 65.0f);
        }
      }
    }

    // Salto cromático de 120ms en chispas agudas con música activa
    if (f.music.active && targetSpark > 0.60f) {
      sparkChromaTimer = 0.12f;
    }
    if (sparkChromaTimer > 0.0f) {
      sparkChromaTimer = std::max(0.0f, sparkChromaTimer - dt);
    }

    for (auto& r : rows) {
      if (r.burstLife > 0.0f) {
        r.burstLife = std::max(0.0f, r.burstLife - dt);
      }
    }
  }

  void render(const Frame& f, Canvas& c) const override {
    auto g = glide(f);
    float w = f.width, h = f.height;
    float time = simTime;
    // Carácter: Entrecortado congela la imagen y la hace avanzar a saltos.
    if (g.caracter.weight(1) > 0.0f) {
      const float stepped = std::floor(simTime * 5.0f) / 5.0f;
      time = simTime * g.caracter.weight(0) + stepped * g.caracter.weight(1);
    }
    const float amp = f.intensity;
    // Pulso: sus pesos reparten la reacción; todo vale cero sin música.
    const float punch = std::min(kick * amp, 1.0f) * g.pulso.weight(0);
    const float swell = std::min(bass * amp, 1.0f) * g.pulso.weight(1);
    const float glint = std::min(spark * amp, 1.0f) * g.pulso.weight(2);
    const uint32_t tick = uint32_t(std::floor(simTime * 24.0f));
    std::vector<Vec2> deadPixels;

    // Sin fondo opaco: lienzo 100% transparente para efecto HUD / filtro glitch

    // Resplandor local de la música sobre la franja de datos (nunca a pantalla
    // completa): magenta en cada golpe, violeta con los graves y cian que
    // parpadea con los agudos.
    if (punch > 0.0f || swell > 0.0f || glint > 0.0f) {
      const float side = std::min(w, h);
      const float auraR = side * 0.62f * (1.0f + 0.12f * punch + 0.15f * swell);
      const float flicker = 0.55f + 0.45f * std::sin(simTime * 61.0f);
      const float warm = (0.4f * punch + 0.3f * swell) * f.glow;
      const float cool = (0.18f * swell + 0.32f * glint * flicker) * f.glow;
      Paint aura = Paint::radial({w * 0.5f, h * 0.45f}, auraR,
        {{std::clamp(0.4f + 0.6f * warm / std::max(warm + cool, 0.001f), 0.0f, 1.0f), 0.3f,
          std::clamp(0.53f + 0.47f * cool / std::max(warm + cool, 0.001f), 0.0f, 1.0f), std::clamp(warm + cool, 0.0f, 1.0f)},
         {1.0f, 0.18f, 0.53f, std::clamp((warm + cool) * 0.35f, 0.0f, 1.0f)},
         {1.0f, 0.18f, 0.53f, 0.0f}}, {0.0f, 0.5f, 1.0f});
      aura.blend = Blend::plus;
      c.circle({w * 0.5f, h * 0.45f}, auraR, aura);
    }

    float chromaJump = sparkChromaTimer > 0.0f ? 18.0f * (sparkChromaTimer / 0.12f) : 0.0f;
    float densityThreshold = 0.25f + smoothEnergy * 0.58f;
    // Golpes y Graves: se encienden más filas de datos.
    if (punch > 0.0f || swell > 0.0f) densityThreshold += 0.22f * punch + 0.18f * swell;
    float rowStep = h / 90.0f;

    Path pathR, pathB, pathLuma, pathAlert;

    for (int i = 0; i < 90; i++) {
      const auto& r = rows[i];

      // Onda de datamosh continuo
      float structuralWave =
        std::sin(float(i) * 0.16f + time * 1.8f + r.seedPhase) *
        std::cos(float(i) * 0.05f - time * 0.9f);
      float activeScore = std::abs(structuralWave) + (r.burstLife > 0.0f ? 0.8f : 0.0f);
      if (activeScore < 1.0f - densityThreshold) continue;

      float y = float(i) * rowStep;
      float bh = r.blockHeight;
      // Graves: los bloques engordan despacio; Golpes: de golpe.
      if (swell > 0.0f || punch > 0.0f) bh *= 1.0f + 0.9f * swell + 1.1f * punch;
      float bw = r.blockWidth * (w / 380.0f);
      // Ancho de bloque (1 = el original).
      bw *= g.bloques;
      float burstFactor = r.burstLife / 0.30f;
      float shiftX = w * 0.5f + structuralWave * (w * 0.26f) + r.baseShift + r.burstShift * burstFactor;
      // Golpes: cada golpe sacude la fila hacia un lado.
      if (punch > 0.0f) shiftX += punch * w * 0.09f * (std::sin(r.seedPhase * 7.0f) >= 0.0f ? 1.0f : -1.0f);
      float cOff = r.chromaOffset + chromaJump + burstFactor * 12.0f;
      // Aberración: separación de los canales (1 = la original).
      cOff *= g.aberracion;
      // Golpes abre los canales; Agudos los hace temblar.
      if (punch > 0.0f || glint > 0.0f) cOff += punch * 14.0f + glint * 14.0f * std::sin(simTime * 57.0f + float(i) * 1.3f);

      int clusterCount = r.burstLife > 0.0f ? 4 : 2;
      for (int k = 0; k < clusterCount; k++) {
        float bx = shiftX + float(k - 1) * (bw * 1.35f);

        // Canal Rojo desplazado hacia la izquierda
        pathR.rect({bx - cOff, y, bw, bh});

        // Canal Azul desplazado hacia la derecha
        float yOffB = sparkChromaTimer > 0.0f ? 2.0f : 0.0f;
        pathB.rect({bx + cOff, y + yOffB, bw, bh});

        // Bloque central Luma
        pathLuma.rect({bx, y, bw * 0.78f, bh});

        if (r.hasAlert && k == 0 && (r.burstLife > 0.0f || structuralWave > 0.65f)) {
          pathAlert.rect({bx + bw * 0.9f, y, 10.0f, bh + 1.0f});
        }

        // Agudos: píxeles muertos que parpadean sobre los bloques.
        if (glint > 0.0f && hashU(uint32_t(i * 4 + k) * 2654435761u + tick * 40503u) < glint * 0.8f) {
          deadPixels.push_back({bx + bw * hashU(uint32_t(i * 4 + k) * 747796405u + tick), y + bh * 0.5f});
        }
      }
    }

    // Dibujado aditivo de canales RGB
    float boost = std::clamp((0.75f + smoothEnergy * 0.35f) * f.intensity, 0.0f, 1.0f);

    // Canal Magenta #ff2e88
    Paint pR; pR.blend = Blend::plus;
    pR.color = {1.0f, 0.18f, 0.53f, std::clamp(0.78f * boost + 0.22f * punch, 0.0f, 1.0f)};
    c.path(pathR, pR);

    // Canal Cian #00f0ff
    Paint pB; pB.blend = Blend::plus;
    pB.color = {0.0f, 0.94f, 1.0f, std::clamp(0.78f * boost + 0.22f * punch, 0.0f, 1.0f)};
    c.path(pathB, pB);

    // Canal Luma claro
    Paint pLuma; pLuma.blend = Blend::plus;
    pLuma.color = {0.90f, 0.94f, 1.0f, std::clamp(0.42f * boost + 0.58f * punch, 0.0f, 1.0f)};
    c.path(pathLuma, pLuma);

    // Canal de alertas doradas #ffe14d
    Paint pAlert; pAlert.blend = Blend::plus;
    pAlert.color = {1.0f, 0.88f, 0.30f, std::clamp(0.95f * boost, 0.0f, 1.0f)};
    c.path(pathAlert, pAlert);

    if (!deadPixels.empty()) {
      Paint dead; dead.blend = Blend::plus;
      dead.color = {0.92f, 0.96f, 1.0f, std::clamp(1.0f * glint, 0.0f, 1.0f)};
      c.points(deadPixels, 2.4f, dead);
    }

    // Franja VHS rodante de sincronismo inferior
    float trackNormY = 0.89f + 0.04f * std::sin(time * 1.7f);
    float trackY = h * trackNormY;
    float trackH = 18.0f + smoothBass * 14.0f;
    // Golpes: la franja VHS se ensancha con cada golpe.
    if (punch > 0.0f) trackH *= 1.0f + 1.2f * punch;

    Paint trackGrad = Paint::linear({0.0f, trackY}, {0.0f, trackY + trackH},
      {{1.0f, 0.18f, 0.53f, 0.0f},
       {0.0f, 0.94f, 1.0f, std::clamp(0.35f * boost, 0.0f, 1.0f)},
       {1.0f, 0.18f, 0.53f, std::clamp(0.45f * boost, 0.0f, 1.0f)},
       {0.04f, 0.04f, 0.07f, 0.0f}},
      {0.0f, 0.35f, 0.65f, 1.0f});
    trackGrad.blend = Blend::plus;
    c.rect({0, trackY, w, trackH}, trackGrad);

    // Rasgaduras de sincronismo horizontales en la franja
    Path tearPath;
    for (int k = 0; k < 6; k++) {
      float sliceX = std::fmod(time * 220.0f + float(k) * 83.0f, w + 40.0f) - 20.0f;
      tearPath.rect({sliceX, trackY + float(k) * 2.5f, 36.0f, 1.8f});
    }
    Paint tearPaint; tearPaint.blend = Blend::plus;
    tearPaint.color = {1.0f, 0.88f, 0.30f, std::clamp(0.55f * boost, 0.0f, 1.0f)};
    c.path(tearPath, tearPaint);
  }
};
''';
