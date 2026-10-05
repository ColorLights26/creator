// Campo Magnético Cuántico — Versión ultra-mejorada y espectacular para Visuales Inmersivas v16.
// Acelerador electromagnético de alta energía: dipolo con tubos de flujo aurorales,
// plasma de Lorentz en espirales ciclotrón, arcos eléctricos Tesla, ferrofluido reactivo
// y ondas de choque de inducción expansivas.
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
      // Ciclotrón: radio de la hélice (0 resbalan por la línea, 1 es el original).
      float helixRad = (1.5f + std::sin(ion.prog * 3.14159f) * 4.5f) * g.ciclotron;
      float ipx = basePx + std::cos(helixAngle) * helixRad;
      float ipy = basePy + std::sin(helixAngle) * helixRad;
      // Agudos: los iones tiemblan y parpadean con los agudos.
      float flick = 1.0f;
      if (agudos > 0.001f) {
        ipx += std::sin(tick * 61.0f + ion.phase * 7.0f) * 1.6f * agudos;
        ipy += std::cos(tick * 53.0f + ion.phase * 5.0f) * 1.6f * agudos;
        flick += agudos * 0.5f * (0.5f + 0.5f * std::sin(tick * 29.0f + ion.phase * 5.0f));
      }

      Color ic = ionCols[ion.colIdx];
      Paint ionPaint; ionPaint.blend = Blend::plus;
      ionPaint.color = {ic.r, ic.g, ic.b, std::clamp(0.85f * boost, 0.0f, 1.0f)};
      c.circle({ipx, ipy}, ion.size * (1.0f + smoothEnergy * 0.4f) * flick, ionPaint);
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
      // Graves: el resplandor del polo crece con los graves.
      float coreGlowR = cylW * (1.2f + smoothEnergy * 0.5f + smoothBass * 0.4f) * (1.0f + graves * 0.8f);
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
      // Golpes: el núcleo del emisor late en cada golpe.
      c.circle({px, py}, cylW * 0.22f * (1.0f + golpe * 0.6f), emitterCore);
    }
  }
};
''';
