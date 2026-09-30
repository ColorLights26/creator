// Campo Magnético Cuántico — Versión ultra-mejorada y espectacular para Visuales Inmersivas v16.
// Acelerador electromagnético de alta energía: dipolo con tubos de flujo aurorales,
// plasma de Lorentz en espirales ciclotrón, arcos eléctricos Tesla, ferrofluido reactivo
// y ondas de choque de inducción expansivas.
const nativeSource = r'''
class Visual final : public Scene {
  struct PlasmaIon {
    int lineIdx;
    float prog;
    float speed;
    float phase;
    float size;
    int colIdx;
  };

  struct Filing {
    float x, y;
    float angle;
    float len;
    bool isPolar;
  };

  static constexpr int kLines = 48;
  static constexpr int kLinePts = 64;
  static constexpr int kIonCount = 380;
  static constexpr int kFilingCount = 2200;

  // Tubos de flujo magnético precalculados por fotograma
  Vec2 linePts[kLines][kLinePts];

  std::vector<PlasmaIon> ions;
  std::vector<Filing> filings;

  float simTime = 0.0f;
  float smoothEnergy = 0.0f;
  float smoothBass = 0.0f;
  float smoothSpark = 0.0f;

  float targetPolarity = 1.0f;
  float polarityAngle = 0.0f;
  float polarityVel = 0.0f;
  float lastInvertTime = -10.0f;

  float shockRadius1 = 0.0f;
  float shockRadius2 = 0.0f;

  static Vec2 evalFieldDir(float x, float y, float mx, float my) {
    const float soft2 = 0.014f;
    float bx = 0.0f, by = 0.0f;

    for (int p = 0; p < 2; p++) {
      float px = (p == 0) ? -0.28f : 0.28f;
      float sign = (p == 0) ? 1.0f : -1.0f;
      float dx = x - px;
      float dy = y;
      float r2 = dx * dx + dy * dy + soft2;
      float invR25 = 1.0f / (r2 * std::sqrt(r2));
      float invR35 = invR25 / r2;

      float mDotD = sign * (mx * dx + my * dy);
      float dVdx = sign * mx * invR25 - 3.0f * dx * mDotD * invR35;
      float dVdy = sign * my * invR25 - 3.0f * dy * mDotD * invR35;

      bx -= dVdx;
      by -= dVdy;
    }

    float len = std::sqrt(bx * bx + by * by);
    if (len < 1e-5f) return Vec2{0.0f, 1.0f};
    return Vec2{bx / len, by / len};
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    simTime = 0.0f;
    smoothEnergy = 0.0f;
    smoothBass = 0.0f;
    smoothSpark = 0.0f;
    targetPolarity = 1.0f;
    polarityAngle = 0.0f;
    polarityVel = 0.0f;
    lastInvertTime = -10.0f;
    shockRadius1 = 0.0f;
    shockRadius2 = 0.0f;

    ions.clear();
    ions.reserve(kIonCount);
    for (int i = 0; i < kIonCount; i++) {
      ions.push_back({
        i % kLines,
        rng.unit(),
        0.35f + rng.unit() * 0.55f,
        rng.unit() * 6.2831853f,
        1.2f + rng.unit() * 2.2f,
        int(rng.unit() * 3.999f)
      });
    }

    filings.clear();
    filings.reserve(kFilingCount);
    for (int i = 0; i < kFilingCount; i++) {
      Filing f;
      if (i < 1500) {
        // 70% concentrado cerca de los dos polos
        float poleX = (i % 2 == 0) ? -0.28f : 0.28f;
        float r = std::pow(rng.unit(), 1.8f) * 0.42f + 0.025f;
        float th = rng.unit() * 6.2831853f;
        f.x = poleX + std::cos(th) * r;
        f.y = std::sin(th) * r * 0.85f;
        f.len = 0.008f + rng.unit() * 0.006f;
        f.isPolar = true;
      } else {
        // 30% ambiente
        f.x = (rng.unit() - 0.5f) * 1.15f;
        f.y = (rng.unit() - 0.5f) * 0.95f;
        f.len = 0.006f + rng.unit() * 0.005f;
        f.isPolar = false;
      }
      Vec2 b = evalFieldDir(f.x, f.y, 1.0f, 0.0f);
      f.angle = std::atan2(b.y, b.x);
      filings.push_back(f);
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

    // En silencio reposa en un flujo magnético laminar lento (~0.10f).
    // Con música acelera el flujo de iones Lorentz y desata arcos e inversiones de dipolo.
    float audioDrive = 0.10f + smoothEnergy * 0.76f + smoothBass * 0.35f;
    float speedMult = (f.reducedMotion ? 0.3f : 1.0f) * f.speed * audioDrive;
    simTime += dt * speedMult;

    // Inversión física del dipolo ante bombos rítmicos marcados con música activa
    if (f.music.active && !f.reducedMotion && f.music.bass > 0.80f && (simTime - lastInvertTime > 1.8f)) {
      lastInvertTime = simTime;
      targetPolarity *= -1.0f;
      shockRadius1 = 15.0f;
      shockRadius2 = 15.0f;
    }

    // Ondas de choque de inducción
    if (shockRadius1 > 0.0f) {
      shockRadius1 += dt * 320.0f;
      if (shockRadius1 > 450.0f) shockRadius1 = 0.0f;
    }
    if (shockRadius2 > 0.0f) {
      shockRadius2 += dt * 320.0f;
      if (shockRadius2 > 450.0f) shockRadius2 = 0.0f;
    }

    // Muelle físico con amortiguamiento crítico para la orientación del dipolo
    float targetAngle = (targetPolarity > 0.0f) ? 0.0f : 3.14159265f;
    float omega = 9.5f;
    float diffAngle = targetAngle - polarityAngle;
    polarityVel += (diffAngle * omega * omega - 2.0f * omega * 0.78f * polarityVel) * dt;
    polarityAngle += polarityVel * dt;

    float mx = std::cos(polarityAngle);
    float my = std::sin(polarityAngle);

    // Integración de los 48 tubos de flujo
    float stepDt = 0.0022f;
    for (int l = 0; l < kLines; l++) {
      float ang = (float(l) / float(kLines)) * 6.2831853f;
      float startPole = (l % 2 == 0) ? -0.28f : 0.28f;
      float x = startPole + std::cos(ang) * 0.038f;
      float y = std::sin(ang) * 0.038f;
      float dirSign = (l % 2 == 0) ? 1.0f : -1.0f;

      for (int pt = 0; pt < kLinePts; pt++) {
        linePts[l][pt] = Vec2{x, y};
        for (int sub = 0; sub < 4; sub++) {
          Vec2 b = evalFieldDir(x, y, mx, my);
          x += b.x * stepDt * dirSign;
          y += b.y * stepDt * dirSign;
        }
      }
    }

    // Actualización de iones de plasma (movimiento de Lorentz a lo largo de las líneas)
    float ionSpeedFactor = (1.0f + smoothEnergy * 0.85f);
    for (auto& ion : ions) {
      ion.prog += dt * ion.speed * 0.45f * ionSpeedFactor;
      if (ion.prog >= 1.0f) {
        ion.prog = std::fmod(ion.prog, 1.0f);
      }
    }

    // Alineación física de limaduras de hierro con amortiguamiento
    float alignRate = std::min(1.0f, dt * 14.0f);
    for (auto& fil : filings) {
      Vec2 b = evalFieldDir(fil.x, fil.y, mx, my);
      float targetA = std::atan2(b.y, b.x);
      float deltaA = targetA - fil.angle;
      while (deltaA > 3.14159265f) deltaA -= 6.2831853f;
      while (deltaA < -3.14159265f) deltaA += 6.2831853f;
      fil.angle += deltaA * alignRate;
    }
  }

  void render(const Frame& f, Canvas& c) const override {
    float w = f.width, h = f.height;
    float minDim = std::min(w, h);
    Vec2 center{w * 0.5f, h * 0.5f};
    float boost = std::clamp((0.85f + smoothEnergy * 0.40f) * f.intensity, 0.0f, 1.0f);

    float mx = std::cos(polarityAngle);

    // 1. Cámara oscura de laboratorio electromagnético #080b12
    Paint bg = Paint::radial(center, minDim * 0.85f,
      {Color::argb(0xff101726), Color::argb(0xff080b12), Color::argb(0xff030407)},
      {0.0f, 0.55f, 1.0f});
    c.rect({0, 0, w, h}, bg);

    // Reflejo difuso central
    Paint chamberGlow = Paint::radial(center, minDim * 0.45f,
      {{0.0f, 0.94f, 1.0f, std::clamp(0.12f * boost, 0.0f, 1.0f)}, {0, 0, 0, 0}},
      {0.0f, 1.0f});
    chamberGlow.blend = Blend::plus;
    c.circle(center, minDim * 0.45f, chamberGlow);

    // Ondas de choque de inducción expansivas
    if (shockRadius1 > 0.0f) {
      float alpha = std::clamp((1.0f - shockRadius1 / 450.0f) * 0.40f * boost, 0.0f, 1.0f);
      Paint shk; shk.blend = Blend::plus; shk.strokeWidth = 2.0f;
      shk.color = {0.0f, 0.94f, 1.0f, alpha};
      c.circle({center.x - 0.28f * minDim, center.y}, shockRadius1, shk);
    }
    if (shockRadius2 > 0.0f) {
      float alpha = std::clamp((1.0f - shockRadius2 / 450.0f) * 0.40f * boost, 0.0f, 1.0f);
      Paint shk; shk.blend = Blend::plus; shk.strokeWidth = 2.0f;
      shk.color = {0.62f, 0.31f, 0.87f, alpha};
      c.circle({center.x + 0.28f * minDim, center.y}, shockRadius2, shk);
    }

    // 2. Campo de limaduras de hierro orientadas (Ferrofluido que vibra con el audio)
    Path filingsPath;
    float filingLengthMult = 0.5f * (1.0f + smoothBass * 0.45f);

    for (const auto& fil : filings) {
      float sx = center.x + fil.x * minDim;
      float sy = center.y + fil.y * minDim;
      float flen = fil.len * minDim * filingLengthMult;
      float dx = std::cos(fil.angle) * flen;
      float dy = std::sin(fil.angle) * flen;
      filingsPath.moveTo(sx - dx, sy - dy);
      filingsPath.lineTo(sx + dx, sy + dy);
    }
    Paint filPaint; filPaint.blend = Blend::plus;
    filPaint.color = {0.45f, 0.65f, 0.95f, std::clamp(0.40f * boost, 0.0f, 1.0f)};
    filPaint.strokeWidth = 1.1f;
    c.path(filingsPath, filPaint);

    // 3. Tubos de flujo magnético en arco (Cian -> Violeta -> Azul)
    Path linesCyan, linesViolet;

    for (int l = 0; l < kLines; l++) {
      Path& curPath = (l % 2 == 0) ? linesCyan : linesViolet;
      bool first = true;
      for (int pt = 0; pt < kLinePts; pt++) {
        float sx = center.x + linePts[l][pt].x * minDim;
        float sy = center.y + linePts[l][pt].y * minDim;
        if (first) { curPath.moveTo(sx, sy); first = false; }
        else curPath.lineTo(sx, sy);
      }
    }

    // Halo ancho de los tubos de flujo
    Paint lpGlow; lpGlow.blend = Blend::plus;
    lpGlow.strokeWidth = 3.5f;
    lpGlow.color = {0.0f, 0.94f, 1.0f, std::clamp(0.22f * boost, 0.0f, 1.0f)};
    c.path(linesCyan, lpGlow);
    lpGlow.color = {0.62f, 0.31f, 0.87f, std::clamp(0.22f * boost, 0.0f, 1.0f)};
    c.path(linesViolet, lpGlow);

    // Filamentos brillantes de flujo
    Paint lpCore; lpCore.blend = Blend::plus;
    lpCore.strokeWidth = 1.3f;
    lpCore.color = {0.50f, 0.95f, 1.0f, std::clamp(0.65f * boost, 0.0f, 1.0f)};
    c.path(linesCyan, lpCore);
    lpCore.color = {0.85f, 0.50f, 1.0f, std::clamp(0.65f * boost, 0.0f, 1.0f)};
    c.path(linesViolet, lpCore);

    // 4. Plasma de Lorentz: iones bioluminiscentes en espirales ciclotrón
    const Color ionCols[4] = {
      {1.0f, 1.0f, 1.0f, 1.0f},
      {0.0f, 0.95f, 1.0f, 1.0f},
      {0.75f, 0.35f, 1.0f, 1.0f},
      {1.0f, 0.85f, 0.20f, 1.0f}
    };

    for (const auto& ion : ions) {
      int lIdx = ion.lineIdx;
      float fIdx = ion.prog * float(kLinePts - 1);
      int p0 = std::clamp(int(fIdx), 0, kLinePts - 2);
      int p1 = p0 + 1;
      float frac = fIdx - float(p0);

      Vec2 pt0 = linePts[lIdx][p0];
      Vec2 pt1 = linePts[lIdx][p1];
      float basePx = center.x + (pt0.x + (pt1.x - pt0.x) * frac) * minDim;
      float basePy = center.y + (pt0.y + (pt1.y - pt0.y) * frac) * minDim;

      // Espiral de ciclotrón transversal a la línea de campo
      float helixAngle = ion.prog * 35.0f + ion.phase + simTime * 6.0f;
      float helixRad = (1.5f + std::sin(ion.prog * 3.14159f) * 4.5f);
      float ipx = basePx + std::cos(helixAngle) * helixRad;
      float ipy = basePy + std::sin(helixAngle) * helixRad;

      Color ic = ionCols[ion.colIdx];
      Paint ionPaint; ionPaint.blend = Blend::plus;
      ionPaint.color = {ic.r, ic.g, ic.b, std::clamp(0.85f * boost, 0.0f, 1.0f)};
      c.circle({ipx, ipy}, ion.size * (1.0f + smoothEnergy * 0.4f), ionPaint);
    }

    // 5. Arcos eléctricos Tesla de alta tensión ante transients y chispas
    if (smoothSpark > 0.18f || smoothBass > 0.75f) {
      float p1x = center.x - 0.28f * minDim;
      float p2x = center.x + 0.28f * minDim;
      float sparkInt = std::max(smoothSpark, (smoothBass - 0.65f) * 2.0f);

      Path lightning;
      lightning.moveTo(p1x, center.y);
      const int arcSteps = 16;
      for (int s = 1; s < arcSteps; s++) {
        float u = float(s) / float(arcSteps);
        float lx = p1x + (p2x - p1x) * u;
        float envelope = std::sin(u * 3.14159265f);
        float jitterY = std::sin(float(s) * 17.3f + simTime * 120.0f) * 28.0f * envelope * sparkInt;
        float jitterX = std::cos(float(s) * 11.7f + simTime * 95.0f) * 8.0f * envelope * sparkInt;
        lightning.lineTo(lx + jitterX, center.y + jitterY);
      }
      lightning.lineTo(p2x, center.y);

      // Resplandor del rayo
      Paint arcGlow; arcGlow.blend = Blend::plus;
      arcGlow.strokeWidth = 5.5f;
      arcGlow.color = {0.0f, 0.85f, 1.0f, std::clamp(0.60f * sparkInt * boost, 0.0f, 1.0f)};
      c.path(lightning, arcGlow);

      // Núcleo blanco del rayo
      Paint arcCore; arcCore.blend = Blend::plus;
      arcCore.strokeWidth = 2.0f;
      arcCore.color = {1.0f, 1.0f, 1.0f, std::clamp(0.95f * sparkInt * boost, 0.0f, 1.0f)};
      c.path(lightning, arcCore);
    }

    // 6. Dos Electroimanes Industriales con bobinas de cobre incandescentes
    for (int p = 0; p < 2; p++) {
      float poleSign = (p == 0) ? -1.0f : 1.0f;
      float px = center.x + poleSign * 0.28f * minDim;
      float py = center.y;
      float cylW = minDim * 0.088f;
      float cylH = minDim * 0.155f;

      bool isNorth = (poleSign * mx >= 0.0f);
      Color poleTint = isNorth ? Color{0.0f, 0.94f, 1.0f, 1.0f} : Color{0.75f, 0.25f, 1.0f, 1.0f};

      // Resplandor de inducción del polo
      float coreGlowR = cylW * (1.2f + smoothEnergy * 0.5f + smoothBass * 0.4f);
      Paint coreGlow = Paint::radial({px, py}, coreGlowR,
        {{1.0f, 1.0f, 1.0f, std::clamp(0.75f * boost, 0.0f, 1.0f)},
         {poleTint.r, poleTint.g, poleTint.b, std::clamp(0.40f * boost, 0.0f, 1.0f)},
         {0, 0, 0, 0}}, {0.0f, 0.45f, 1.0f});
      coreGlow.blend = Blend::plus;
      c.circle({px, py}, coreGlowR, coreGlow);

      // Cuerpo cilíndrico de acero de alta densidad
      Paint cylBody; cylBody.color = Color::argb(0xff181d26);
      c.rect({px - cylW * 0.5f, py - cylH * 0.5f, cylW, cylH}, cylBody);

      Paint cylBorder; cylBorder.color = Color::argb(0xff3c4657); cylBorder.strokeWidth = 1.8f;
      Path cylBox; cylBox.rect({px - cylW * 0.5f, py - cylH * 0.5f, cylW, cylH});
      c.path(cylBox, cylBorder);

      // 5 Vueltas de bobina de cobre incandescente (#b87333 / oro fundido)
      Path copperCoils;
      for (int turn = 0; turn < 5; turn++) {
        float ty = py - cylH * 0.35f + (float(turn) / 4.0f) * (cylH * 0.70f);
        copperCoils.moveTo(px - cylW * 0.58f, ty - 3.5f);
        copperCoils.cubicTo(
          px - cylW * 0.2f, ty + 5.0f,
          px + cylW * 0.2f, ty - 5.0f,
          px + cylW * 0.58f, ty + 3.5f
        );
      }
      Paint coilPaint;
      coilPaint.color = {0.92f, 0.55f, 0.20f, std::clamp(0.95f * boost, 0.0f, 1.0f)};
      coilPaint.strokeWidth = 3.6f;
      c.path(copperCoils, coilPaint);

      // Brillo especular sobre el cobre
      Paint coilSpec; coilSpec.blend = Blend::plus;
      coilSpec.color = {1.0f, 0.90f, 0.70f, std::clamp(0.60f * boost, 0.0f, 1.0f)};
      coilSpec.strokeWidth = 1.4f;
      c.path(copperCoils, coilSpec);

      // Núcleo blanco del emisor de campo
      Paint emitterCore; emitterCore.blend = Blend::plus;
      emitterCore.color = {1.0f, 1.0f, 1.0f, std::clamp(0.92f * boost, 0.0f, 1.0f)};
      c.circle({px, py}, cylW * 0.22f, emitterCore);
    }
  }
};
''';
