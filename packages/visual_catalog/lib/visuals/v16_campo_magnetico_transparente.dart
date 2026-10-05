// Campo Magnético Cuántico Transparente — Versión Overlay / Capa transparente.
// Acelerador electromagnético de alta energía sobre fondo transparente: dipolo con tubos de flujo aurorales,
// plasma de Lorentz en espirales ciclotrón, arcos eléctricos Tesla, ferrofluido reactivo y ondas de choque de inducción.
// La música ya aceleraba el plasma, encendía arcos e invertía el dipolo con
// los graves fuertes; Pulso decide qué más se ve: con Golpes cada golpe
// lanza un anillo de inducción desde cada polo, los polos estallan en un
// resplandor y se encienden limaduras y filamentos; con Graves los tubos de
// flujo se engrosan y los polos respiran con su halo; con Agudos los iones y
// las limaduras chisporrotean y parpadean. Sin música se ve igual que
// siempre.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // FORMA: el dibujo de las limaduras (siguen el campo, lo cruzan o apuntan al polo).
  CreatorModifier.choice(
    'patron',
    'Patrón',
    options: ['Dipolo', 'Equipotencial', 'Radial'],
  ),
  // MOVIMIENTO: iones que resbalan por las líneas o giran en hélices anchas.
  CreatorModifier.slider('ciclotron', 'Ciclotrón', min: 0, max: 4, value: 1),
  // MÚSICA
  CreatorModifier.choice(
    'pulso',
    'Pulso',
    options: ['Golpes', 'Graves', 'Agudos'],
  ),
  // ATMÓSFERA: limaduras de hierro, de nada a agujas largas.
  CreatorModifier.slider('limaduras', 'Limaduras', min: 0, max: 2.5, value: 1),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Laboratorio', {
    'patron': 'Radial',
    'ciclotron': 3,
    'limaduras': .7,
    'pulso': 'Golpes',
  }),
  CreatorVariation('Ferrofluido', {
    'limaduras': 2.5,
    'patron': 'Equipotencial',
    'ciclotron': .4,
    'pulso': 'Graves',
  }),
];

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

  // Música estándar: envolventes y golpe corto (valen 0 sin música).
  float bass = 0, body = 0, spark = 0, energy = 0, drive = 0, slowBass = 0, kick = 0, flash = 0;
  // Segundos reales para los anillos de los golpes y el chisporroteo.
  double clock = 0;
  // Golpes: anillo fijo de ondas de inducción {nacimiento, fuerza}.
  static constexpr int kPulses = 4;
  std::array<double, kPulses> pulseBirth{};
  std::array<float, kPulses> pulsePower{};
  int nextPulse = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

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
    bass = body = spark = energy = drive = slowBass = kick = flash = 0;
    clock = 0;
    pulseBirth.fill(-100.0);
    pulsePower.fill(0.0f);
    nextPulse = 0;

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
        f.len = 0.012f + (1.0f - std::min(r / 0.42f, 1.0f)) * 0.022f;
        f.isPolar = true;
      } else {
        // 30% distribuido por el espacio
        f.x = (rng.unit() - 0.5f) * 1.55f;
        f.y = (rng.unit() - 0.5f) * 1.55f;
        f.len = 0.010f + rng.unit() * 0.014f;
        f.isPolar = false;
      }
      f.angle = rng.unit() * 3.14159265f;
      filings.push_back(f);
    }
  }

  void update(const Frame& f) override {
    float dt = float(f.delta);
    float targetEnergy = f.music.active ? f.music.energy : 0.0f;
    float targetBass = f.music.active ? f.music.bass : 0.0f;
    float targetSpark = f.music.active ? f.music.spark : 0.0f;

    smoothEnergy += (targetEnergy - smoothEnergy) * float(1.0 - std::exp(-dt * 6.0));
    smoothBass += (targetBass - smoothBass) * float(1.0 - std::exp(-dt * 7.0));
    smoothSpark += (targetSpark - smoothSpark) * float(1.0 - std::exp(-dt * 15.0));

    // En silencio reposa en un flujo de Lorentz suave (~0.10f). Con música acelera.
    float audioDrive = 0.10f + smoothEnergy * 0.75f + smoothBass * 0.35f;
    float speedMult = (f.reducedMotion ? 0.3f : 1.0f) * f.speed * audioDrive;
    simTime += dt * speedMult;

    // Inversión de polaridad en caídas de bajos con música activa
    if (f.music.active && f.music.bass > 0.78f && (simTime - lastInvertTime >= 1.6f)) {
      lastInvertTime = simTime;
      targetPolarity *= -1.0f;
      shockRadius1 = 12.0f;
      shockRadius2 = 12.0f;
    }

    if (shockRadius1 > 0.0f) {
      shockRadius1 += dt * 420.0f;
      if (shockRadius1 > 450.0f) shockRadius1 = 0.0f;
    }
    if (shockRadius2 > 0.0f) {
      shockRadius2 += dt * 420.0f;
      if (shockRadius2 > 450.0f) shockRadius2 = 0.0f;
    }

    float targetAngle = (targetPolarity > 0.0f) ? 0.0f : 3.14159265f;
    float angleDiff = targetAngle - polarityAngle;
    while (angleDiff > 3.14159265f) angleDiff -= 6.2831853f;
    while (angleDiff < -3.14159265f) angleDiff += 6.2831853f;
    polarityVel += (angleDiff * 38.0f - polarityVel * 9.5f) * dt;
    polarityAngle += polarityVel * dt;

    float mx = std::cos(polarityAngle);
    float my = std::sin(polarityAngle);

    // Recomputar los 48 tubos de flujo
    for (int l = 0; l < kLines; l++) {
      float side = (l < kLines / 2) ? 1.0f : -1.0f;
      int idx = l % (kLines / 2);
      float frac = float(idx) / float(kLines / 2 - 1);
      float emitterAngle = (frac - 0.5f) * 2.5f;

      float p1x = -0.28f + std::cos(emitterAngle) * 0.038f;
      float p1y = side * (0.015f + std::sin(std::abs(emitterAngle)) * 0.038f);
      float p2x = 0.28f - std::cos(emitterAngle) * 0.038f;
      float p2y = side * (0.015f + std::sin(std::abs(emitterAngle)) * 0.038f);

      float apexDist = 0.16f + std::pow(frac, 1.45f) * 0.72f * (1.0f + smoothBass * 0.40f);
      float apexY = side * apexDist;
      float apexX = (emitterAngle * 0.045f) + std::sin(simTime * 1.8f + float(l) * 0.2f) * (0.012f + smoothEnergy * 0.02f);

      for (int pt = 0; pt < kLinePts; pt++) {
        float u = float(pt) / float(kLinePts - 1);
        float omt = 1.0f - u;
        float bx = omt * omt * p1x + 2.0f * omt * u * apexX + u * u * p2x;
        float by = omt * omt * p1y + 2.0f * omt * u * apexY + u * u * p2y;

        float wav = std::sin(u * 14.0f - simTime * (4.0f + smoothEnergy * 5.0f) + float(l) * 0.35f);
        float wavAmp = (0.003f + smoothSpark * 0.008f) * std::sin(u * 3.14159265f);
        by += wav * wavAmp * side;

        linePts[l][pt] = Vec2{bx, by};
      }
    }

    // Actualizar iones de Lorentz
    for (auto& ion : ions) {
      ion.prog += dt * ion.speed * (0.75f + smoothEnergy * 0.85f);
      if (ion.prog >= 1.0f) ion.prog -= 1.0f;
      ion.phase += dt * (12.0f + smoothSpark * 18.0f);
    }

    // Orientar las 2200 limaduras de hierro
    float alignRate = std::clamp(dt * 18.0f, 0.0f, 1.0f);
    for (auto& fil : filings) {
      Vec2 b = evalFieldDir(fil.x, fil.y, mx, my);
      float targetA = std::atan2(b.y, b.x);
      float deltaA = targetA - fil.angle;
      while (deltaA > 3.14159265f) deltaA -= 6.2831853f;
      while (deltaA < -3.14159265f) deltaA += 6.2831853f;
      fil.angle += deltaA * alignRate;
    }

    // Música estándar: graves, cuerpo, agudos, energía y golpe corto.
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
    const bool fresh = hit > kick + 0.2f;
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    clock += f.delta;
    // Golpes: cada golpe nuevo lanza un anillo de inducción.
    if (fresh) {
      pulseBirth[size_t(nextPulse)] = clock;
      pulsePower[size_t(nextPulse)] = hit;
      nextPulse = (nextPulse + 1) % kPulses;
    }
  }

  void render(const Frame& f, Canvas& c) const override {
    auto g = glide(f);
    const float level = f.intensity;
    // Pulso: cada opción mueve algo distinto y sus pesos mezclan las opciones.
    const float golpe = g.pulso.weight(0) * std::min(kick * level, 1.0f);
    const float graves = g.pulso.weight(1) * std::min(bass * level, 1.0f);
    const float agudos = g.pulso.weight(2) * std::min(spark * level, 1.0f);
    const float tick = float(std::fmod(clock, 1000.0));
    // Patrón: las limaduras siguen el campo (Dipolo, el original), lo cruzan
    // en anillos (Equipotencial) o apuntan a su polo (Radial).
    const float crossW = g.patron.weight(1), radialW = g.patron.weight(2);
    float w = f.width, h = f.height;
    float minDim = std::min(w, h);
    Vec2 center{w * 0.5f, h * 0.5f};
    float boost = std::clamp((0.85f + smoothEnergy * 0.40f) * f.intensity, 0.0f, 1.0f);

    // Sin fondo opaco: lienzo 100% transparente

    // 1. Reflejo difuso central aditivo
    Paint chamberGlow = Paint::radial(center, minDim * 0.45f,
      {{0.0f, 0.94f, 1.0f, std::clamp(0.12f * boost, 0.0f, 1.0f)}, {0, 0, 0, 0}},
      {0.0f, 1.0f});
    chamberGlow.blend = Blend::plus;
    c.circle(center, minDim * 0.45f, chamberGlow);

    // Golpes: cada polo estalla en un resplandor de su color; Graves los hace
    // respirar más suave.
    const float burst = std::min(1.0f, (0.6f * golpe + 0.25f * graves) * f.glow);
    if (burst > 0.001f) {
      for (int k = 0; k < 2; k++) {
        const Vec2 pole{center.x + (k == 0 ? -0.28f : 0.28f) * minDim, center.y};
        const Color tint = k == 0 ? Color{0.2f, 0.95f, 1.0f, 1.0f} : Color{0.8f, 0.45f, 1.0f, 1.0f};
        const float reach = minDim * (0.42f + 0.08f * golpe);
        Paint light = Paint::radial(pole, reach,
          {{tint.r, tint.g, tint.b, burst}, {tint.r, tint.g, tint.b, burst * 0.35f}, {tint.r, tint.g, tint.b, 0}}, {0, 0.4f, 1.0f});
        light.blend = Blend::plus;
        c.circle(pole, reach, light);
      }
    }

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

    // Golpes: un anillo de inducción sale de cada polo y se apaga al crecer.
    const float pulseWeight = g.pulso.weight(0);
    if (pulseWeight > 0.001f) {
      for (int k = 0; k < kPulses; k++) {
        const float age = float(clock - pulseBirth[size_t(k)]);
        if (age < 0.0f || age >= 0.9f) continue;
        const float fade = 1.0f - age / 0.9f;
        const float power = std::min(pulsePower[size_t(k)] * level, 1.0f) * pulseWeight * fade;
        if (power <= 0.001f) continue;
        const float radius = minDim * (0.05f + age * 0.55f);
        Paint ring; ring.blend = Blend::plus; ring.strokeWidth = 3.0f + 5.0f * fade;
        ring.color = {0.0f, 0.94f, 1.0f, std::min(1.0f, 0.85f * power * boost)};
        c.circle({center.x - 0.28f * minDim, center.y}, radius, ring);
        ring.color = {0.75f, 0.35f, 1.0f, std::min(1.0f, 0.85f * power * boost)};
        c.circle({center.x + 0.28f * minDim, center.y}, radius, ring);
      }
    }

    // 2. Campo de limaduras de hierro orientadas (Ferrofluido que vibra con el audio)
    // Limaduras: largo de las agujas (1 es el original; 0 las quita).
    const float needle = g.limaduras;
    if (needle > 0.01f) {
      Path filingsPath;
      float filingLengthMult = 0.5f * (1.0f + smoothBass * 0.45f);

      for (const auto& fil : filings) {
        float sx = center.x + fil.x * minDim;
        float sy = center.y + fil.y * minDim;
        float flen = fil.len * minDim * filingLengthMult * needle;
        float angle = fil.angle;
        if (crossW + radialW > 0.001f) {
          // Las agujas no tienen sentido: se mezclan con el ángulo doble.
          const float toPole = std::atan2(fil.y, fil.x - (fil.x < 0.0f ? -0.28f : 0.28f));
          const float across = angle + float(pi) * 0.5f;
          const float keep = 1.0f - crossW - radialW;
          const float mx2 = keep * std::cos(2.0f * angle) + crossW * std::cos(2.0f * across) + radialW * std::cos(2.0f * toPole);
          const float my2 = keep * std::sin(2.0f * angle) + crossW * std::sin(2.0f * across) + radialW * std::sin(2.0f * toPole);
          angle = 0.5f * std::atan2(my2, mx2);
        }
        float dx = std::cos(angle) * flen;
        float dy = std::sin(angle) * flen;
        filingsPath.moveTo(sx - dx, sy - dy);
        filingsPath.lineTo(sx + dx, sy + dy);
      }
      Paint filPaint; filPaint.blend = Blend::plus;
      // Golpes enciende las limaduras (+80%); Graves las aviva; Agudos las
      // hace chisporrotear.
      filPaint.color = {0.45f, 0.65f, 0.95f, std::clamp(0.40f * boost * (1.0f + golpe * 0.8f + graves * 0.4f
        + agudos * 0.6f * std::sin(tick * 29.0f)), 0.0f, 1.0f)};
      filPaint.strokeWidth = 1.1f;
      c.path(filingsPath, filPaint);
    }

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
    // Graves: el halo de los tubos se engrosa y se aviva con los graves.
    Paint lpGlow; lpGlow.blend = Blend::plus;
    lpGlow.strokeWidth = 3.5f * (1.0f + graves * 0.8f + golpe * 1.2f);
    lpGlow.color = {0.0f, 0.94f, 1.0f, std::clamp(0.22f * boost * (1.0f + graves * 0.6f), 0.0f, 1.0f)};
    c.path(linesCyan, lpGlow);
    lpGlow.color = {0.62f, 0.31f, 0.87f, std::clamp(0.22f * boost * (1.0f + graves * 0.6f), 0.0f, 1.0f)};
    c.path(linesViolet, lpGlow);

    // Filamentos brillantes de flujo
    Paint lpCore; lpCore.blend = Blend::plus;
    lpCore.strokeWidth = 1.3f;
    // Golpes: los filamentos se encienden en cada golpe.
    lpCore.color = {0.50f, 0.95f, 1.0f, std::clamp(0.65f * boost * (1.0f + golpe * 0.6f), 0.0f, 1.0f)};
    c.path(linesCyan, lpCore);
    lpCore.color = {0.85f, 0.50f, 1.0f, std::clamp(0.65f * boost * (1.0f + golpe * 0.6f), 0.0f, 1.0f)};
    c.path(linesViolet, lpCore);

    // 4. Plasma de Lorentz: iones bioluminiscentes en espirales ciclotrón
    const Color ionCols[4] = {
      {1.0f, 1.0f, 1.0f, 1.0f},
      {0.0f, 0.95f, 1.0f, 1.0f},
      {0.75f, 0.35f, 1.0f, 1.0f},
      {1.0f, 0.85f, 0.20f, 1.0f}
    };

    std::vector<Vec2> ionPoints[4];
    for (const auto& ion : ions) {
      int l = ion.lineIdx;
      float pNorm = ion.prog * float(kLinePts - 1);
      int idx0 = std::clamp(int(pNorm), 0, kLinePts - 2);
      float frac = pNorm - float(idx0);

      Vec2 p0 = linePts[l][idx0];
      Vec2 p1 = linePts[l][idx0 + 1];
      float bx = p0.x + (p1.x - p0.x) * frac;
      float by = p0.y + (p1.y - p0.y) * frac;

      // Ciclotrón: radio de la hélice (0 resbalan por la línea, 1 es el original).
      float gyroR = (0.005f + smoothSpark * 0.012f) * (0.8f + 0.4f * std::sin(ion.phase)) * g.ciclotron;
      float px = center.x + (bx + std::cos(ion.phase) * gyroR) * minDim;
      float py = center.y + (by + std::sin(ion.phase) * gyroR) * minDim;
      // Agudos: los iones tiemblan con los agudos.
      if (agudos > 0.001f) {
        px += std::sin(tick * 61.0f + ion.phase * 7.0f) * 1.6f * agudos;
        py += std::cos(tick * 53.0f + ion.phase * 5.0f) * 1.6f * agudos;
      }

      ionPoints[ion.colIdx].push_back({px, py});
    }

    for (int cIdx = 0; cIdx < 4; cIdx++) {
      if (!ionPoints[cIdx].empty()) {
        Paint ip; ip.blend = Blend::plus;
        Color baseCol = ionCols[cIdx];
        ip.color = {baseCol.r, baseCol.g, baseCol.b, std::clamp(0.85f * boost, 0.0f, 1.0f)};
        // Agudos: cada color de iones parpadea a su ritmo.
        const float flick = 1.0f + agudos * 0.5f * (0.5f + 0.5f * std::sin(tick * 29.0f + float(cIdx) * 1.9f));
        c.points(ionPoints[cIdx], (1.8f + smoothSpark * 1.6f) * flick, ip);
      }
    }

    // 5. Arcos eléctricos Tesla bifurcados entre los polos
    if (f.music.active && smoothSpark > 0.35f) {
      Path arcPath;
      float pole1X = center.x - 0.28f * minDim;
      float pole2X = center.x + 0.28f * minDim;
      float baseY = center.y;

      arcPath.moveTo(pole1X, baseY);
      const int kArcSteps = 12;
      for (int step = 1; step < kArcSteps; step++) {
        float u = float(step) / float(kArcSteps);
        float ax = pole1X + (pole2X - pole1X) * u;
        float sag = std::sin(u * 3.14159265f) * (std::sin(simTime * 35.0f + float(step)) * 24.0f * smoothSpark);
        float ay = baseY + sag;
        arcPath.lineTo(ax, ay);
      }
      arcPath.lineTo(pole2X, baseY);

      Paint arcPaint; arcPaint.blend = Blend::plus;
      arcPaint.strokeWidth = 2.2f;
      arcPaint.color = {1.0f, 1.0f, 1.0f, std::clamp(smoothSpark * boost, 0.0f, 1.0f)};
      c.path(arcPath, arcPaint);
    }

    // 6. Polos magnéticos translúcidos con bobinas de cobre
    for (int p = 0; p < 2; p++) {
      float px = (p == 0) ? (center.x - 0.28f * minDim) : (center.x + 0.28f * minDim);
      float py = center.y;
      Color poleColor = (p == 0) ? Color{0.0f, 0.95f, 1.0f, 1.0f} : Color{0.75f, 0.35f, 1.0f, 1.0f};

      // Resplandor del polo
      // Graves: el resplandor del polo crece con los graves.
      Paint poleGlow = Paint::radial({px, py}, minDim * 0.16f * (1.0f + graves * 0.8f),
        {{poleColor.r, poleColor.g, poleColor.b, std::clamp(0.65f * boost, 0.0f, 1.0f)}, {0, 0, 0, 0}},
        {0.0f, 1.0f});
      poleGlow.blend = Blend::plus;
      c.circle({px, py}, minDim * 0.16f * (1.0f + graves * 0.8f), poleGlow);

      // Cilindro del electroimán
      float cylW = minDim * 0.075f;
      float cylH = minDim * 0.14f;

      Paint cylBorder; cylBorder.color = {0.35f, 0.45f, 0.55f, 0.85f}; cylBorder.strokeWidth = 1.8f;
      Path cylBox; cylBox.rect({px - cylW * 0.5f, py - cylH * 0.5f, cylW, cylH});
      c.path(cylBox, cylBorder);

      // Vueltas de bobina de cobre incandescente
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
      // Golpes: el núcleo del emisor late en cada golpe.
      c.circle({px, py}, cylW * 0.22f * (1.0f + golpe * 0.6f), emitterCore);
    }
  }
};
''';
