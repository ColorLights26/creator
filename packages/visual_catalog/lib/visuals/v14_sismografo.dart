// Sismógrafo — Puerto fiel de Visuales Inmersivas v14.
// Tambor sismográfico de metal cepillado con reflejo anisotrópico, aguja mecánica
// visible, cuadrícula milimétrica en movimiento y trazo fosforescente reactivo.
const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kBufferSize = 512;
  float ringBuffer[kBufferSize];
  int head = 0;

  float phase1 = 0.0f;
  float phase2 = 1.1f;
  float phase3 = 2.4f;
  float phase4 = 0.5f;

  float seismicEnv = 0.0f;
  float seismicPol = 1.0f;
  float sparkSpike = 0.0f;

  float drumScroll = 0.0f;
  float smoothEnergy = 0.0f;
  float smoothBass = 0.0f;

 public:
  void reset(uint32_t seed) override {
    (void)seed;
    for (int i = 0; i < kBufferSize; i++) ringBuffer[i] = 0.0f;
    head = 0;
    phase1 = 0.0f; phase2 = 1.1f; phase3 = 2.4f; phase4 = 0.5f;
    seismicEnv = 0.0f; seismicPol = 1.0f; sparkSpike = 0.0f;
    drumScroll = 0.0f;
    smoothEnergy = 0.0f; smoothBass = 0.0f;
  }

  void update(const Frame& f) override {
    float dt = float(f.delta);
    float speed = (f.reducedMotion ? 0.3f : 1.0f) * f.speed;
    float bpm = (f.music.bpm > 40.0f && f.music.bpm < 240.0f) ? f.music.bpm : 120.0f;
    float osc4Freq = 6.1f * (bpm / 120.0f);

    smoothEnergy += (f.music.energy - smoothEnergy) * float(1.0 - std::exp(-dt * 5.0));
    smoothBass += (f.music.bass - smoothBass) * float(1.0 - std::exp(-dt * 6.0));

    phase1 += dt * 0.7f * 6.2831853f * speed;
    phase2 += dt * 1.3f * 6.2831853f * speed;
    phase3 += dt * 2.9f * 6.2831853f * speed;
    phase4 += dt * osc4Freq * 6.2831853f * speed;

    drumScroll += dt * 48.0f * speed;

    // Disparo sísmico ante bombos
    if (f.music.bass > 0.70f) {
      seismicPol = std::sin(drumScroll * 1.9f) >= 0.0f ? 1.0f : -1.0f;
      float mag = 0.35f + smoothEnergy * 0.85f;
      seismicEnv = std::max(seismicEnv, mag);
    }
    seismicEnv *= std::exp(-dt / 0.24f);

    // Destello de aguja ante chispas
    if (f.music.spark > 0.60f) {
      sparkSpike = (std::cos(drumScroll * 2.7f) >= 0.0f ? 1.0f : -1.0f) * 0.95f;
    } else {
      sparkSpike *= std::exp(-dt / 0.025f);
    }

    float baseOsc =
      std::sin(phase1) * 0.06f +
      std::sin(phase2) * 0.05f +
      std::sin(phase3) * 0.04f +
      std::sin(phase4) * (0.04f + smoothEnergy * 0.09f);

    float seismicCarrier =
      std::sin(phase4 * 1.9f) * seismicEnv * (0.45f + smoothEnergy * 0.55f) +
      seismicPol * seismicEnv * 0.28f * smoothBass;

    float currentSample = std::clamp(baseOsc + seismicCarrier + sparkSpike, -0.92f, 0.92f);

    // Buffer circular
    ringBuffer[head] = currentSample;
    head = (head + 1) % kBufferSize;
  }

  void render(const Frame& f, Canvas& c) const override {
    float w = f.width, h = f.height;
    float boost = std::clamp((0.85f + smoothEnergy * 0.35f) * f.intensity, 0.0f, 1.0f);

    // 1. Fondo de laboratorio #0b0d10
    Paint bg; bg.color = Color::argb(0xff0b0d10);
    c.rect({0, 0, w, h}, bg);

    float drumLeft = w * 0.06f;
    float drumRight = w * 0.86f;
    float drumW = drumRight - drumLeft;
    float drumTop = h * 0.18f;
    float drumBot = h * 0.82f;
    float drumH = drumBot - drumTop;
    float centerY = (drumTop + drumBot) * 0.5f;

    // Sombra del tambor
    Paint drumShadow; drumShadow.color = {0.0f, 0.0f, 0.0f, 0.70f};
    c.rect({drumLeft + 6.0f, drumTop + 12.0f, drumW, drumH}, drumShadow);

    // 2. Tambor cilíndrico de metal cepillado con brillo anisotrópico
    Paint drumGrad = Paint::linear({0.0f, drumTop}, {0.0f, drumBot},
      {Color::argb(0xff14161a), Color::argb(0xff2a2d33), Color::argb(0xff3f444d),
       Color::argb(0xff2a2d33), Color::argb(0xff1b1d22), Color::argb(0xff0e1013)},
      {0.0f, 0.18f, 0.38f, 0.52f, 0.85f, 1.0f});
    c.rect({drumLeft, drumTop, drumW, drumH}, drumGrad);

    // Micro-ranuras horizontales de metal cepillado
    Paint micro; micro.color = {1.0f, 1.0f, 1.0f, 0.035f}; micro.strokeWidth = 1.0f;
    Path grooves;
    for (float y = drumTop + 6.0f; y < drumBot - 6.0f; y += 4.0f) {
      grooves.moveTo(drumLeft, y);
      grooves.lineTo(drumRight, y);
    }
    c.path(grooves, micro);

    // 3. Cuadrícula de escala milimétrica en movimiento
    const float gridStep = 18.0f;
    float scrollOffset = std::fmod(drumScroll, gridStep);
    if (scrollOffset < 0.0f) scrollOffset += gridStep;

    Paint gridPaint;
    gridPaint.color = {0.29f, 0.31f, 0.34f, std::clamp(0.45f * boost, 0.0f, 1.0f)};
    gridPaint.strokeWidth = 0.8f;
    Path gridPath;

    for (float x = drumLeft + gridStep - scrollOffset; x < drumRight; x += gridStep) {
      gridPath.moveTo(x, drumTop + 4.0f);
      gridPath.lineTo(x, drumBot - 4.0f);
    }
    for (float y = centerY; y > drumTop + 8.0f; y -= gridStep) {
      gridPath.moveTo(drumLeft, y);
      gridPath.lineTo(drumRight, y);
    }
    for (float y = centerY + gridStep; y < drumBot - 8.0f; y += gridStep) {
      gridPath.moveTo(drumLeft, y);
      gridPath.lineTo(drumRight, y);
    }
    c.path(gridPath, gridPaint);

    // Línea base central
    Paint baseLine;
    baseLine.color = {0.49f, 0.98f, 1.0f, std::clamp(0.25f * boost, 0.0f, 1.0f)};
    baseLine.strokeWidth = 1.0f;
    Path baseP;
    baseP.moveTo(drumLeft, centerY);
    baseP.lineTo(drumRight, centerY);
    c.path(baseP, baseLine);

    // 4. Trazo sísmico de 512 puntos
    Path tracePath;
    float maxAmp = drumH * 0.41f;
    float stylusX = drumRight - 8.0f;
    float stylusY = centerY;

    for (int i = 0; i < kBufferSize; i++) {
      int bufIdx = (head + i) % kBufferSize;
      float val = ringBuffer[bufIdx];
      float u = float(i) / float(kBufferSize - 1);
      float px = drumLeft + 8.0f + u * (drumW - 16.0f);
      float py = centerY - val * maxAmp;

      if (i == 0) tracePath.moveTo(px, py);
      else tracePath.lineTo(px, py);

      if (i == kBufferSize - 1) {
        stylusX = px;
        stylusY = py;
      }
    }

    // Halo fosforescente aditivo de 4.2px
    Paint traceHalo; traceHalo.blend = Blend::plus;
    traceHalo.color = {0.49f, 0.98f, 1.0f, std::clamp(0.38f * boost, 0.0f, 1.0f)};
    traceHalo.strokeWidth = 4.2f; traceHalo.strokeJoin = 1; traceHalo.strokeCap = 1;
    c.path(tracePath, traceHalo);

    // Línea central de tinta fosforescente cian #7df9ff de 1.6px
    Paint traceCore; traceCore.blend = Blend::plus;
    traceCore.color = {0.49f, 0.98f, 1.0f, std::clamp(0.92f * boost, 0.0f, 1.0f)};
    traceCore.strokeWidth = 1.6f; traceCore.strokeJoin = 1; traceCore.strokeCap = 1;
    c.path(tracePath, traceCore);

    // 5. Brazo mecánico articulado con estilete visible
    float pivotX = w * 0.95f;
    float pivotY = centerY;

    // Caja de pivote
    Paint pivotHead; pivotHead.color = Color::argb(0xff383d47);
    c.circle({pivotX, pivotY}, 14.0f, pivotHead);
    Paint pivotRim; pivotRim.color = Color::argb(0xff687080); pivotRim.strokeWidth = 2.0f;
    c.circle({pivotX, pivotY}, 14.0f, pivotRim);

    // Aguja mecánica de acero de doble tirante
    Paint needleArm; needleArm.color = Color::argb(0xffc8d0dc); needleArm.strokeWidth = 2.6f;
    Path needle;
    needle.moveTo(pivotX, pivotY - 5.0f);
    needle.lineTo(stylusX, stylusY);
    needle.lineTo(pivotX, pivotY + 5.0f);
    c.path(needle, needleArm);

    // Punta brillante del estilete con halo
    Paint tipGlow = Paint::radial({stylusX, stylusY}, 12.0f,
      {{1.0f, 1.0f, 1.0f, 1.0f},
       {0.49f, 0.98f, 1.0f, std::clamp(0.70f * boost, 0.0f, 1.0f)},
       {0, 0, 0, 0}}, {0.0f, 0.35f, 1.0f});
    tipGlow.blend = Blend::plus;
    c.circle({stylusX, stylusY}, 12.0f, tipGlow);
  }
};
''';
