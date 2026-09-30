// Archivo Corrupto — Puerto fiel de Visuales Inmersivas v11.
// Datamosh digital estructurado con aberración cromática RGB aditiva,
// barrido CRT y franja VHS de rodadura inferior reactiva al ritmo.
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
    float w = f.width, h = f.height;
    float time = simTime;

    // 1. Degradado base cyberpunk: #0a0a12 a #1a1030
    Paint bg = Paint::linear({0.0f, 0.0f}, {0.0f, h},
      {Color::argb(0xff0a0a12), Color::argb(0xff120d22), Color::argb(0xff1a1030)},
      {0.0f, 0.5f, 1.0f});
    c.rect({0, 0, w, h}, bg);

    // Barrido CRT: líneas horizontales sutiles cada 4px
    Paint scanline;
    scanline.color = {0.02f, 0.015f, 0.04f, 0.45f};
    scanline.strokeWidth = 1.4f;
    Path scanlines;
    for (float y = 0.0f; y < h; y += 4.0f) {
      scanlines.moveTo(0.0f, y);
      scanlines.lineTo(w, y);
    }
    c.path(scanlines, scanline);

    float chromaJump = sparkChromaTimer > 0.0f ? 18.0f * (sparkChromaTimer / 0.12f) : 0.0f;
    float densityThreshold = 0.25f + smoothEnergy * 0.58f;
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
      float bw = r.blockWidth * (w / 380.0f);
      float burstFactor = r.burstLife / 0.30f;
      float shiftX = w * 0.5f + structuralWave * (w * 0.26f) + r.baseShift + r.burstShift * burstFactor;
      float cOff = r.chromaOffset + chromaJump + burstFactor * 12.0f;

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
      }
    }

    // Dibujado aditivo de canales RGB
    float boost = std::clamp((0.75f + smoothEnergy * 0.35f) * f.intensity, 0.0f, 1.0f);

    // Canal Magenta #ff2e88
    Paint pR; pR.blend = Blend::plus;
    pR.color = {1.0f, 0.18f, 0.53f, std::clamp(0.78f * boost, 0.0f, 1.0f)};
    c.path(pathR, pR);

    // Canal Cian #00f0ff
    Paint pB; pB.blend = Blend::plus;
    pB.color = {0.0f, 0.94f, 1.0f, std::clamp(0.78f * boost, 0.0f, 1.0f)};
    c.path(pathB, pB);

    // Canal Luma claro
    Paint pLuma; pLuma.blend = Blend::plus;
    pLuma.color = {0.90f, 0.94f, 1.0f, std::clamp(0.42f * boost, 0.0f, 1.0f)};
    c.path(pathLuma, pLuma);

    // Canal de alertas doradas #ffe14d
    Paint pAlert; pAlert.blend = Blend::plus;
    pAlert.color = {1.0f, 0.88f, 0.30f, std::clamp(0.95f * boost, 0.0f, 1.0f)};
    c.path(pathAlert, pAlert);

    // 2. Franja VHS rodante de sincronismo inferior
    float trackNormY = 0.89f + 0.04f * std::sin(time * 1.7f);
    float trackY = h * trackNormY;
    float trackH = 18.0f + smoothBass * 14.0f;

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
