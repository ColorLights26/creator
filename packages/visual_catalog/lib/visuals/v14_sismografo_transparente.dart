// Sismógrafo Transparente — Versión Overlay / Capa transparente.
// Trazo sísmico analítico continuo flotante con cuadrícula milimétrica HUD y aguja reactiva al bajo.
const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kTracePoints = 256;
  static constexpr int kMaxShocks = 8;
  struct Shock {
    float time;
    float mag;
    float pol;
  };
  Shock shocks[kMaxShocks];
  int shockHead = 0;
  float lastShockTime = -100.0f;

  float simTime = 0.0f;
  float drumScroll = 0.0f;
  float smoothEnergy = 0.0f;
  float smoothBass = 0.0f;
  float smoothSpark = 0.0f;
  float currentBpm = 120.0f;

 public:
  void reset(uint32_t seed) override {
    (void)seed;
    simTime = 0.0f;
    drumScroll = 0.0f;
    smoothEnergy = 0.0f;
    smoothBass = 0.0f;
    smoothSpark = 0.0f;
    currentBpm = 120.0f;
    shockHead = 0;
    lastShockTime = -100.0f;
    for (int i = 0; i < kMaxShocks; i++) {
      shocks[i] = {-100.0f, 0.0f, 1.0f};
    }
  }

  void update(const Frame& f) override {
    float dt = float(f.delta);
    float targetEnergy = f.music.active ? f.music.energy : 0.0f;
    float targetBass = f.music.active ? f.music.bass : 0.0f;
    float targetSpark = f.music.active ? f.music.spark : 0.0f;

    smoothEnergy += (targetEnergy - smoothEnergy) * float(1.0 - std::exp(-dt * 5.0));
    smoothBass += (targetBass - smoothBass) * float(1.0 - std::exp(-dt * 6.0));
    smoothSpark += (targetSpark - smoothSpark) * float(1.0 - std::exp(-dt * 15.0));

    // En silencio reposa en un rodillo calmado (~0.12f). Con música rueda a velocidad de registro.
    float audioDrive = 0.12f + smoothEnergy * 0.72f + smoothBass * 0.35f;
    float speed = (f.reducedMotion ? 0.3f : 1.0f) * f.speed * audioDrive;
    simTime += dt * speed;
    drumScroll += dt * 48.0f * speed;

    currentBpm = (f.music.bpm > 40.0f && f.music.bpm < 240.0f) ? f.music.bpm : 120.0f;

    // Disparo sísmico ante bombos con música activa
    if (f.music.active && f.music.bass > 0.70f && (simTime - lastShockTime > 0.15f)) {
      lastShockTime = simTime;
      float pol = (std::sin(drumScroll * 1.9f) >= 0.0f) ? 1.0f : -1.0f;
      float mag = 0.40f + smoothEnergy * 0.90f;
      shocks[shockHead] = {simTime, mag, pol};
      shockHead = (shockHead + 1) % kMaxShocks;
    }
  }

  void render(const Frame& f, Canvas& c) const override {
    float w = f.width, h = f.height;
    float boost = std::clamp((0.85f + smoothEnergy * 0.35f) * f.intensity, 0.0f, 1.0f);

    float drumLeft = w * 0.06f;
    float drumRight = w * 0.86f;
    float drumW = drumRight - drumLeft;
    float drumTop = h * 0.18f;
    float drumBot = h * 0.82f;
    float drumH = drumBot - drumTop;
    float centerY = (drumTop + drumBot) * 0.5f;

    // 1. Cuadrícula HUD milimétrica flotante en movimiento (sin fondo opaco)
    const float gridStep = 18.0f;
    float scrollOffset = std::fmod(drumScroll, gridStep);
    if (scrollOffset < 0.0f) scrollOffset += gridStep;

    Paint gridPaint;
    gridPaint.color = {0.0f, 0.95f, 0.70f, std::clamp(0.18f * boost, 0.0f, 1.0f)};
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
    baseLine.color = {0.49f, 0.98f, 1.0f, std::clamp(0.35f * boost, 0.0f, 1.0f)};
    baseLine.strokeWidth = 1.0f;
    Path baseP;
    baseP.moveTo(drumLeft, centerY);
    baseP.lineTo(drumRight, centerY);
    c.path(baseP, baseLine);

    // 2. Trazo sísmico analítico continuo (tiempo real 30/60 FPS continuo)
    Path tracePath;
    float maxAmp = drumH * 0.41f;
    float windowDuration = (drumW - 16.0f) / 48.0f;
    float osc4Freq = 6.1f * (currentBpm / 120.0f);

    float stylusX = drumRight - 8.0f;
    float stylusY = centerY;

    for (int i = 0; i < kTracePoints; i++) {
      float u = float(i) / float(kTracePoints - 1);
      float px = drumLeft + 8.0f + u * (drumW - 16.0f);
      float tSample = simTime - (1.0f - u) * windowDuration;

      // Armónicos base continuos: en silencio es un micro-temblor fino (0.006f), con música oscila
      float tremorAmp = 0.006f + smoothEnergy * 0.14f;
      float baseOsc =
        (std::sin(tSample * 0.7f * 6.2831853f) * 0.35f +
         std::sin(tSample * 1.3f * 6.2831853f + 1.1f) * 0.30f +
         std::sin(tSample * 2.9f * 6.2831853f + 2.4f) * 0.20f +
         std::sin(tSample * osc4Freq * 6.2831853f + 0.5f) * 0.35f) * tremorAmp;

      // Contribución de ondas sísmicas recientes
      float shockContrib = 0.0f;
      for (int s = 0; s < kMaxShocks; s++) {
        float age = tSample - shocks[s].time;
        if (age >= 0.0f && age < 1.4f) {
          float env = shocks[s].mag * std::exp(-age / 0.24f);
          float carrier = std::sin(age * 36.0f) * (0.45f + smoothEnergy * 0.55f) +
                          shocks[s].pol * 0.28f * smoothBass;
          shockContrib += env * carrier;
        }
      }

      float spark = (i == kTracePoints - 1) ? smoothSpark * 0.25f : 0.0f;
      float val = std::clamp(baseOsc + shockContrib + spark, -0.92f, 0.92f);
      float py = centerY - val * maxAmp;

      if (i == 0) tracePath.moveTo(px, py);
      else tracePath.lineTo(px, py);

      if (i == kTracePoints - 1) {
        stylusX = px;
        stylusY = py;
      }
    }

    // Halo fosforescente aditivo de 4.2px
    Paint traceHalo; traceHalo.blend = Blend::plus;
    traceHalo.color = {0.49f, 0.98f, 1.0f, std::clamp(0.45f * boost, 0.0f, 1.0f)};
    traceHalo.strokeWidth = 4.2f; traceHalo.strokeJoin = 1; traceHalo.strokeCap = 1;
    c.path(tracePath, traceHalo);

    // Línea central de tinta fosforescente cian #7df9ff de 1.6px
    Paint traceCore; traceCore.blend = Blend::plus;
    traceCore.color = {0.49f, 0.98f, 1.0f, std::clamp(0.95f * boost, 0.0f, 1.0f)};
    traceCore.strokeWidth = 1.6f; traceCore.strokeJoin = 1; traceCore.strokeCap = 1;
    c.path(tracePath, traceCore);

    // 3. Brazo mecánico articulado con estilete visible
    float pivotX = w * 0.95f;
    float pivotY = centerY;

    // Caja de pivote translúcida
    Paint pivotHead; pivotHead.color = {0.22f, 0.24f, 0.28f, 0.70f};
    c.circle({pivotX, pivotY}, 14.0f, pivotHead);
    Paint pivotRim; pivotRim.color = {0.50f, 0.60f, 0.70f, 0.85f}; pivotRim.strokeWidth = 2.0f;
    c.circle({pivotX, pivotY}, 14.0f, pivotRim);

    // Aguja mecánica de acero de doble tirante
    Paint needleArm; needleArm.color = {0.85f, 0.90f, 0.96f, 0.90f}; needleArm.strokeWidth = 2.6f;
    Path needle;
    needle.moveTo(pivotX, pivotY - 5.0f);
    needle.lineTo(stylusX, stylusY);
    needle.lineTo(pivotX, pivotY + 5.0f);
    c.path(needle, needleArm);

    // Punta brillante del estilete con halo
    Paint tipGlow = Paint::radial({stylusX, stylusY}, 12.0f,
      {{1.0f, 1.0f, 1.0f, 1.0f},
       {0.49f, 0.98f, 1.0f, std::clamp(0.75f * boost, 0.0f, 1.0f)},
       {0, 0, 0, 0}}, {0.0f, 0.35f, 1.0f});
    tipGlow.blend = Blend::plus;
    c.circle({stylusX, stylusY}, 12.0f, tipGlow);
  }
};
''';
