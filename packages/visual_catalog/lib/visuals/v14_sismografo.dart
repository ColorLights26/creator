// Sismógrafo — Puerto fiel de Visuales Inmersivas v14.
// Tambor sismográfico de metal cepillado con reflejo anisotrópico, aguja mecánica
// visible, cuadrícula milimétrica en movimiento y trazo analítico continuo a 30/60 FPS.
// Música: la energía y los graves hacen rodar el tambor y agitan el trazo, y
// los bombos fuertes provocan sacudidas sísmicas. Pulso elige el resto:
// Golpes convierte cada golpe en una sacudida, enciende la punta del estilete
// y deja una marca ámbar en el papel; Graves engrosa el trazo y lo ondula
// despacio; Agudos le añade un temblor fino y hace chispear la punta.
// Además, cada opción de Pulso enciende un resplandor local sobre
// el tambor y la punta del estilete, que late con la música (nunca un velo a pantalla completa).
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // FORMA: una estación o una red de estaciones con varios trazos.
  CreatorModifier.steps('canales', 'Canales', min: 1, max: 3, value: 1),
  // MOVIMIENTO: tierra en calma o con temblor de fondo constante.
  CreatorModifier.slider('actividad', 'Actividad sísmica', min: 0, max: 1, value: 0),
  // MÚSICA
  CreatorModifier.choice(
    'pulso',
    'Pulso',
    options: ['Golpes', 'Graves', 'Agudos'],
  ),
  // ATMÓSFERA: tinta fina y nítida o fósforo que se derrama en luz.
  CreatorModifier.slider('tinta', 'Halo de tinta', min: .3, max: 3, value: 1),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Red Sísmica', {
    'canales': 3,
    'actividad': .5,
    'pulso': 'Golpes',
  }),
  CreatorVariation('Fósforo Neón', {
    'tinta': 2.6,
    'actividad': .25,
    'pulso': 'Graves',
  }),
];

const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kTracePoints = 256;
  static constexpr int kMaxShocks = 8;
  static constexpr int kMaxMarks = 8;
  struct Shock {
    float time;
    float mag;
    float pol;
  };
  Shock shocks[kMaxShocks];
  int shockHead = 0;
  float lastShockTime = -100.0f;
  // Marcas de los golpes en el papel (Pulso: Golpes).
  Shock marks[kMaxMarks];
  int markHead = 0;

  float simTime = 0.0f;
  float drumScroll = 0.0f;
  float smoothEnergy = 0.0f;
  float smoothBass = 0.0f;
  float smoothSpark = 0.0f;
  float currentBpm = 120.0f;
  // Envolventes de la música para Pulso (cero en silencio).
  float bass = 0, treble = 0, energy = 0, slowBass = 0;
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
    markHead = 0;
    for (int i = 0; i < kMaxMarks; i++) {
      marks[i] = {-100.0f, 0.0f, 1.0f};
    }
    bass = treble = energy = slowBass = kick = flash = 0.0f;
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

    // Música para Pulso: envolventes y golpes (todo vale cero en silencio).
    const Music& mu = f.music;
    bass = follow(bass, mu.bass, 22.0f, 4.5f, dt);
    treble = follow(treble, mu.spark, 30.0f, 7.0f, dt);
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
    if (fresh) {
      marks[markHead] = {simTime, hit, 1.0f};
      markHead = (markHead + 1) % kMaxMarks;
    }
    // Golpes: cada golpe es una sacudida sísmica.
    auto m = modifiers(f);
    if (m.pulso == 0 && fresh && (simTime - lastShockTime > 0.15f)) {
      lastShockTime = simTime;
      float pol = (std::sin(drumScroll * 1.9f) >= 0.0f) ? 1.0f : -1.0f;
      shocks[shockHead] = {simTime, (0.35f + 0.55f * hit) * std::min(f.intensity, 1.5f), pol};
      shockHead = (shockHead + 1) % kMaxShocks;
    }
  }

  void render(const Frame& f, Canvas& c) const override {
    float w = f.width, h = f.height;
    float boost = std::clamp((0.85f + smoothEnergy * 0.35f) * f.intensity, 0.0f, 1.0f);
    auto m = modifiers(f);
    auto g = glide(f);
    const float amp = f.intensity;
    // Pulso: sus pesos reparten la reacción; todo vale cero sin música.
    const float punch = std::min(kick * amp, 1.0f) * g.pulso.weight(0);
    const float swell = std::min(bass * amp, 1.0f) * g.pulso.weight(1);
    const float glint = std::min(treble * amp, 1.0f) * g.pulso.weight(2);
    const float activity = g.actividad;
    const float ink = g.tinta;

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

    // Resplandor local de la música sobre el tambor (nunca a pantalla
    // completa): cian en cada golpe y con los graves; con los agudos, el
    // resplandor parpadea y chispean los cruces de la cuadrícula.
    if (punch > 0.0f || swell > 0.0f || glint > 0.0f) {
      const Vec2 drumCenter{drumLeft + drumW * 0.5f, centerY};
      const float auraR = drumW * 0.58f * (1.0f + 0.1f * punch + 0.12f * swell);
      const float flicker = 0.55f + 0.45f * std::sin(float(f.time) * 47.0f);
      const float lit = (0.36f * punch + 0.3f * swell + 0.22f * glint * flicker) * f.glow;
      // Una elipse con la forma del tambor, sin bordes duros.
      Paint aura = Paint::radial({0.0f, 0.0f}, auraR,
        {{0.49f, 0.98f, 1.0f, std::clamp(lit, 0.0f, 1.0f)},
         {0.49f, 0.98f, 1.0f, std::clamp(lit * 0.45f, 0.0f, 1.0f)},
         {0.49f, 0.98f, 1.0f, 0.0f}}, {0.0f, 0.5f, 1.0f});
      aura.blend = Blend::plus;
      c.save();
      c.translate(drumCenter.x, drumCenter.y);
      c.scale(1.0f, std::max(0.2f, drumH / drumW) * 1.1f);
      c.circle({0.0f, 0.0f}, auraR, aura);
      c.restore();
      if (glint > 0.0f) {
        const uint32_t tick = uint32_t(std::floor(f.time * 12.0));
        std::vector<Vec2> gridSparks;
        int col = 0;
        for (float x = drumLeft + gridStep - scrollOffset; x < drumRight; x += gridStep, col++) {
          int row = 0;
          for (float y = centerY - gridStep * std::floor((centerY - drumTop - 8.0f) / gridStep); y < drumBot - 8.0f; y += gridStep, row++) {
            if (hashU(uint32_t(col * 131 + row) * 2654435761u + tick * 40503u) < glint * 0.3f) gridSparks.push_back({x, y});
          }
        }
        if (!gridSparks.empty()) {
          Paint gs; gs.blend = Blend::plus;
          gs.color = {0.75f, 1.0f, 1.0f, std::clamp(glint, 0.0f, 1.0f)};
          c.points(gridSparks, 1.9f, gs);
        }
      }
    }

    // Línea base central
    Paint baseLine;
    baseLine.color = {0.49f, 0.98f, 1.0f, std::clamp(0.25f * boost, 0.0f, 1.0f)};
    baseLine.strokeWidth = 1.0f;
    Path baseP;
    baseP.moveTo(drumLeft, centerY);
    baseP.lineTo(drumRight, centerY);
    c.path(baseP, baseLine);

    // 4. Trazo sísmico analítico continuo (tiempo real 30/60 FPS continuo)
    // Canales: cada estación tiene su carril; las lejanas reciben las
    // sacudidas más tarde y más débiles. Con 1 canal es el trazo original.
    const int lanes = std::clamp(m.canales, 1, 3);
    float maxAmp = drumH * 0.41f;
    float windowDuration = (drumW - 16.0f) / 48.0f;
    float osc4Freq = 6.1f * (currentBpm / 120.0f);

    std::array<Path, 3> tracePaths;
    std::array<Vec2, 3> styli;
    for (int ch = 0; ch < lanes; ch++) {
      Path& tracePath = tracePaths[ch];
      const float laneY = lanes == 1 ? centerY : drumTop + drumH * (float(ch) + 0.5f) / float(lanes);
      const float laneAmp = lanes == 1 ? maxAmp : maxAmp * 1.15f / float(lanes);
      const float lag = float(ch) * 0.18f;
      const float fade = 1.0f - 0.22f * float(ch);
      const float phase = float(ch) * 1.7f;
      if (lanes > 1) {
        Path laneBase;
        laneBase.moveTo(drumLeft, laneY);
        laneBase.lineTo(drumRight, laneY);
        c.path(laneBase, baseLine);
      }

      float stylusX = drumRight - 8.0f;
      float stylusY = laneY;

      for (int i = 0; i < kTracePoints; i++) {
        float u = float(i) / float(kTracePoints - 1);
        float px = drumLeft + 8.0f + u * (drumW - 16.0f);
        float tSample = simTime - (1.0f - u) * windowDuration;
        // Cada estación tiene su propio ruido y recibe las ondas con retraso.
        float tLocal = tSample + phase;
        float tShock = tSample - lag;

        // Armónicos base continuos: en silencio es un micro-temblor fino (0.006f), con música oscila
        float tremorAmp = 0.006f + smoothEnergy * 0.14f;
        // Actividad sísmica: temblor de fondo propio, también en silencio.
        if (activity > 0.0f) tremorAmp += activity * 0.09f;
        float baseOsc =
          (std::sin(tLocal * 0.7f * 6.2831853f) * 0.35f +
           std::sin(tLocal * 1.3f * 6.2831853f + 1.1f) * 0.30f +
           std::sin(tLocal * 2.9f * 6.2831853f + 2.4f) * 0.20f +
           std::sin(tLocal * osc4Freq * 6.2831853f + 0.5f) * 0.35f) * tremorAmp;

        // Contribución de ondas sísmicas recientes
        float shockContrib = 0.0f;
        for (int s = 0; s < kMaxShocks; s++) {
          float age = tShock - shocks[s].time;
          if (age >= 0.0f && age < 1.4f) {
            float env = shocks[s].mag * std::exp(-age / 0.24f);
            env *= fade;
            float carrier = std::sin(age * 36.0f) * (0.45f + smoothEnergy * 0.55f) +
                            shocks[s].pol * 0.28f * smoothBass;
            shockContrib += env * carrier;
          }
        }

        float spark = (i == kTracePoints - 1) ? smoothSpark * 0.25f : 0.0f;
        float val = std::clamp(baseOsc + shockContrib + spark, -0.92f, 0.92f);
        // Graves: ondulación lenta; Agudos: temblor fino.
        if (swell > 0.0f || glint > 0.0f) {
          val = std::clamp(val + swell * 0.22f * std::sin(tLocal * 0.9f * 6.2831853f + 0.7f) +
                           glint * 0.1f * std::sin(tLocal * 97.3f) * std::sin(tLocal * 41.7f + float(i)), -0.92f, 0.92f);
        }
        float py = laneY - val * laneAmp;

        if (i == 0) tracePath.moveTo(px, py);
        else tracePath.lineTo(px, py);

        if (i == kTracePoints - 1) {
          stylusX = px;
          stylusY = py;
        }
      }
      styli[ch] = {stylusX, stylusY};
    }

    // Golpes: cada golpe deja una marca ámbar en el borde del papel.
    const float markWeight = g.pulso.weight(0);
    if (markWeight > 0.0f) {
      Path markPath;
      int markCount = 0;
      for (int k = 0; k < kMaxMarks; k++) {
        const float age = simTime - marks[k].time;
        const float x = drumRight - 8.0f - age * 48.0f;
        if (marks[k].mag <= 0.0f || age < 0.0f || x < drumLeft) continue;
        const float len = 6.0f + 10.0f * marks[k].mag;
        markPath.moveTo(x, drumTop + 3.0f).lineTo(x, drumTop + 3.0f + len);
        markPath.moveTo(x, drumBot - 3.0f).lineTo(x, drumBot - 3.0f - len);
        markCount++;
      }
      if (markCount > 0) {
        Paint markPaint; markPaint.blend = Blend::plus;
        markPaint.color = {1.0f, 0.62f, 0.25f, std::clamp(0.85f * markWeight * std::min(amp, 1.0f), 0.0f, 1.0f)};
        markPaint.strokeWidth = 1.8f;
        c.path(markPath, markPaint);
      }
    }

    for (int ch = 0; ch < lanes; ch++) {
      const Path& tracePath = tracePaths[ch];
      // Halo fosforescente aditivo de 4.2px (Halo de tinta: más fino o más ancho)
      Paint traceHalo; traceHalo.blend = Blend::plus;
      traceHalo.color = {0.49f, 0.98f, 1.0f, std::clamp(0.38f * boost * std::min(ink, 1.6f) + 0.4f * swell + 0.5f * punch, 0.0f, 1.0f)};
      traceHalo.strokeWidth = 4.2f * ink; traceHalo.strokeJoin = 1; traceHalo.strokeCap = 1;
      // Graves: el trazo se engrosa despacio.
      // Graves y Golpes: el trazo se engrosa.
      if (swell > 0.0f || punch > 0.0f) traceHalo.strokeWidth *= 1.0f + 1.2f * swell + 1.4f * punch;
      c.path(tracePath, traceHalo);

      // Línea central de tinta fosforescente cian #7df9ff de 1.6px
      Paint traceCore; traceCore.blend = Blend::plus;
      traceCore.color = {0.49f, 0.98f, 1.0f, std::clamp(0.92f * boost, 0.0f, 1.0f)};
      traceCore.strokeWidth = 1.6f; traceCore.strokeJoin = 1; traceCore.strokeCap = 1;
      if (swell > 0.0f || punch > 0.0f) traceCore.strokeWidth *= 1.0f + 0.8f * swell + 0.9f * punch;
      c.path(tracePath, traceCore);
    }

    // 5. Brazo mecánico articulado con estilete visible
    float pivotX = w * 0.95f;
    float pivotY = centerY;

    // Caja de pivote
    Paint pivotHead; pivotHead.color = Color::argb(0xff383d47);
    c.circle({pivotX, pivotY}, 14.0f, pivotHead);
    Paint pivotRim; pivotRim.color = Color::argb(0xff687080); pivotRim.strokeWidth = 2.0f;
    c.circle({pivotX, pivotY}, 14.0f, pivotRim);

    // Golpes: la punta se enciende; Agudos: chispea.
    const float tipR = 12.0f * std::clamp(ink, 0.6f, 1.8f) *
                       (1.0f + 0.8f * punch + 0.5f * glint * (0.5f + 0.5f * std::sin(float(f.time) * 53.0f)));
    for (int ch = 0; ch < lanes; ch++) {
      const float stylusX = styli[ch].x, stylusY = styli[ch].y;
      // Aguja mecánica de acero de doble tirante
      Paint needleArm; needleArm.color = Color::argb(0xffc8d0dc); needleArm.strokeWidth = 2.6f;
      Path needle;
      needle.moveTo(pivotX, pivotY - 5.0f);
      needle.lineTo(stylusX, stylusY);
      needle.lineTo(pivotX, pivotY + 5.0f);
      c.path(needle, needleArm);

      // Golpes y Graves: un resplandor rodea la punta del estilete.
      if (punch > 0.0f || swell > 0.0f) {
        const float flareR = drumH * 0.3f * (1.0f + 0.12f * swell);
        Paint flare = Paint::radial({stylusX, stylusY}, flareR,
          {{0.49f, 0.98f, 1.0f, std::clamp((0.4f * punch + 0.25f * swell) * f.glow, 0.0f, 1.0f)}, {0.49f, 0.98f, 1.0f, 0.0f}}, {0.0f, 1.0f});
        flare.blend = Blend::plus;
        c.circle({stylusX, stylusY}, flareR, flare);
      }
      // Punta brillante del estilete con halo
      Paint tipGlow = Paint::radial({stylusX, stylusY}, tipR,
        {{1.0f, 1.0f, 1.0f, 1.0f},
         {0.49f, 0.98f, 1.0f, std::clamp(0.70f * boost, 0.0f, 1.0f)},
         {0, 0, 0, 0}}, {0.0f, 0.35f, 1.0f});
      tipGlow.blend = Blend::plus;
      c.circle({stylusX, stylusY}, tipR, tipGlow);
    }
  }
};
''';
