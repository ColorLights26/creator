// Maquinaria Orbital Transparente — Versión Overlay / Capa transparente.
// Planetario astrológico de relojería en latón y piedra tallada, cuatro esferas
// orbitantes, bisel graduado con glifos y sol central engranado sobre fondo transparente.
const nativeSource = r'''
class Visual final : public Scene {
  struct Planet {
    float radiusRatio;
    float size;
    float basePeriod;
    float inclination;
    float tiltAngle;
    bool retrograde;
    Color color;
    float angle;
  };

  std::vector<Planet> planets;
  float clockTime = 0.0f;
  float smoothEnergy = 0.0f;
  float smoothBass = 0.0f;
  float smoothSpark = 0.0f;

 public:
  void reset(uint32_t seed) override {
    (void)seed;
    planets.clear();
    planets.reserve(4);
    clockTime = 0.0f;
    smoothEnergy = 0.0f;
    smoothBass = 0.0f;
    smoothSpark = 0.0f;

    // Cobre
    planets.push_back({0.19f, 8.5f, 14.0f, 0.0f, 0.20f, false, {0.85f, 0.55f, 0.29f, 1.0f}, 0.8f});
    // Bronce
    planets.push_back({0.27f, 7.0f, 8.5f, 0.36f, 0.65f, false, {0.72f, 0.63f, 0.42f, 1.0f}, 2.3f});
    // Acero
    planets.push_back({0.35f, 9.5f, 11.2f, 0.42f, -0.50f, false, {0.44f, 0.62f, 0.77f, 1.0f}, 4.1f});
    // Jade (retrogrado)
    planets.push_back({0.42f, 6.5f, 6.8f, 0.15f, 1.10f, true, {0.37f, 0.75f, 0.63f, 1.0f}, 5.4f});
  }

  void update(const Frame& f) override {
    float dt = float(f.delta);
    float targetEnergy = f.music.active ? f.music.energy : 0.0f;
    float targetBass = f.music.active ? f.music.bass : 0.0f;
    float targetSpark = f.music.active ? f.music.spark : 0.0f;
    smoothEnergy += (targetEnergy - smoothEnergy) * float(1.0 - std::exp(-dt * 5.0));
    smoothBass += (targetBass - smoothBass) * float(1.0 - std::exp(-dt * 6.0));
    smoothSpark += (targetSpark - smoothSpark) * float(1.0 - std::exp(-dt * 15.0));

    // En silencio reposa en un tic-tac de reloj celestial sereno y majestuoso (~0.12f).
    // Con música la maquinaria de relojería se revoluciona al compás del ritmo.
    float audioDrive = 0.12f + smoothEnergy * 0.76f + smoothBass * 0.35f;
    float speedFactor = (f.reducedMotion ? 0.25f : 1.0f) * f.speed * audioDrive;
    clockTime += dt * speedFactor;

    for (auto& p : planets) {
      float dir = p.retrograde ? -1.0f : 1.0f;
      p.angle += dir * (6.2831853f / p.basePeriod) * dt * speedFactor;
    }
  }

  void render(const Frame& f, Canvas& c) const override {
    float w = f.width, h = f.height;
    float minDim = std::min(w, h);
    Vec2 center{w * 0.5f, h * 0.5f};
    float time = clockTime;
    float boost = std::clamp((0.85f + smoothEnergy * 0.35f) * f.intensity, 0.0f, 1.0f);

    // Sin fondo opaco: lienzo 100% transparente para efecto HUD / astrolabio flotante

    // 1. Barras diagonales estructurales de latón
    Paint crossbar;
    crossbar.color = {0.72f, 0.60f, 0.40f, std::clamp(0.38f * boost, 0.0f, 1.0f)};
    crossbar.strokeWidth = 1.5f;
    Path cross;
    for (int a = 0; a < 4; a++) {
      float ang = (float(a) * 3.14159265f * 0.5f) + 0.785398f;
      cross.moveTo(center.x + std::cos(ang) * minDim * 0.07f, center.y + std::sin(ang) * minDim * 0.07f);
      cross.lineTo(center.x + std::cos(ang) * minDim * 0.46f, center.y + std::sin(ang) * minDim * 0.46f);
    }
    c.path(cross, crossbar);

    // 2. Bisel exterior de la corona graduada con 96 muescas y glifos
    float crownTilt = (f.music.flow - 0.5f) * 0.16f;
    float outerR = minDim * 0.455f;
    float innerR = minDim * 0.415f;

    c.save();
    c.translate(center.x, center.y);
    c.rotate(crownTilt);

    // Aros del bisel
    Paint bezel;
    bezel.color = {0.85f, 0.72f, 0.48f, std::clamp(0.48f * boost, 0.0f, 1.0f)};
    bezel.strokeWidth = 1.8f;
    c.circle({0, 0}, outerR, bezel);
    c.circle({0, 0}, innerR, bezel);

    // 96 marcas graduadas en el bisel
    Path ticks;
    for (int i = 0; i < 96; i++) {
      float ang = (float(i) / 96.0f) * 6.2831853f;
      bool isMajor = (i % 8 == 0);
      float r0 = isMajor ? innerR : innerR + (outerR - innerR) * 0.45f;
      ticks.moveTo(std::cos(ang) * r0, std::sin(ang) * r0);
      ticks.lineTo(std::cos(ang) * outerR, std::sin(ang) * outerR);
    }
    Paint tickPaint;
    tickPaint.color = {0.85f, 0.72f, 0.48f, std::clamp(0.55f * boost, 0.0f, 1.0f)};
    tickPaint.strokeWidth = 1.0f;
    c.path(ticks, tickPaint);

    // 12 Glifos geométricos abstractos
    float midRingR = (outerR + innerR) * 0.5f;
    float glyphR = minDim * 0.012f;
    Path glyphsPath;
    for (int s = 0; s < 12; s++) {
      float ang = (float(s) / 12.0f) * 6.2831853f + 0.130899f;
      float gx = std::cos(ang) * midRingR;
      float gy = std::sin(ang) * midRingR;

      if (s % 3 == 0) {
        glyphsPath.moveTo(gx, gy - glyphR);
        glyphsPath.lineTo(gx + glyphR, gy);
        glyphsPath.lineTo(gx, gy + glyphR);
        glyphsPath.lineTo(gx - glyphR, gy);
        glyphsPath.close();
      } else if (s % 3 == 1) {
        glyphsPath.circle({gx, gy}, glyphR * 0.75f);
      } else {
        glyphsPath.moveTo(gx, gy - glyphR);
        glyphsPath.lineTo(gx + glyphR, gy + glyphR * 0.8f);
        glyphsPath.lineTo(gx - glyphR, gy + glyphR * 0.8f);
        glyphsPath.close();
      }
    }
    Paint glyphPaint;
    glyphPaint.color = {0.95f, 0.82f, 0.55f, std::clamp(0.70f * boost, 0.0f, 1.0f)};
    glyphPaint.strokeWidth = 1.2f;
    c.path(glyphsPath, glyphPaint);

    c.restore();

    // 3. Órbitas elípticas de latón grabadas con tren de engranajes
    for (size_t i = 0; i < planets.size(); i++) {
      const auto& p = planets[i];
      float orbitR = minDim * p.radiusRatio;

      c.save();
      c.translate(center.x, center.y);
      c.rotate(p.tiltAngle);

      Paint orbitPaint;
      orbitPaint.color = {0.75f, 0.65f, 0.45f, std::clamp(0.25f * boost, 0.0f, 1.0f)};
      orbitPaint.strokeWidth = 1.0f;

      Path orbitPath;
      float bAxis = orbitR * (1.0f - p.inclination * 0.32f);
      const int kEllipsePts = 48;
      for (int ep = 0; ep <= kEllipsePts; ep++) {
        float ea = (float(ep) / float(kEllipsePts)) * 6.2831853f;
        float ex = std::cos(ea) * orbitR;
        float ey = std::sin(ea) * bAxis;
        if (ep == 0) orbitPath.moveTo(ex, ey);
        else orbitPath.lineTo(ex, ey);
      }
      c.path(orbitPath, orbitPaint);

      // Engranaje anular dentado concéntrico en la órbita 2
      if (i == 1) {
        float gearR = orbitR * 0.96f;
        int teeth = 36;
        Path gearPath;
        for (int t = 0; t < teeth; t++) {
          float a0 = (float(t) / float(teeth)) * 6.2831853f + time * 0.12f;
          float a1 = a0 + (6.2831853f / float(teeth)) * 0.5f;
          float tr0 = gearR - 2.5f;
          float tr1 = gearR + 2.5f;
          gearPath.moveTo(std::cos(a0) * tr0, std::sin(a0) * tr0);
          gearPath.lineTo(std::cos(a0) * tr1, std::sin(a0) * tr1);
          gearPath.lineTo(std::cos(a1) * tr1, std::sin(a1) * tr1);
          gearPath.lineTo(std::cos(a1) * tr0, std::sin(a1) * tr0);
        }
        Paint gearPaint;
        gearPaint.color = {0.68f, 0.58f, 0.38f, std::clamp(0.35f * boost, 0.0f, 1.0f)};
        gearPaint.strokeWidth = 1.0f;
        c.path(gearPath, gearPaint);
      }

      c.restore();
    }

    // 4. Sol central de latón macizo con engranaje solar y corona flamígera
    float sunR = minDim * 0.052f;
    float bassGlow = std::clamp(0.35f + smoothBass * 0.65f, 0.0f, 1.0f);

    Paint sunCorona = Paint::radial(center, sunR * 2.8f,
      {{1.0f, 0.85f, 0.40f, std::clamp(0.45f * bassGlow * boost, 0.0f, 1.0f)},
       {0, 0, 0, 0}}, {0.0f, 0.45f, 1.0f});
    sunCorona.blend = Blend::plus;
    c.circle(center, sunR * 2.8f, sunCorona);

    Paint sunBody = Paint::radial({center.x - sunR * 0.3f, center.y - sunR * 0.3f}, sunR,
      {Color::argb(0xfffff4d2), Color::argb(0xffd99b4a), Color::argb(0xff6b4820)},
      {0.0f, 0.6f, 1.0f});
    c.circle(center, sunR, sunBody);

    // Índice dorado giratorio esmaltado (reloj mecánico)
    c.save();
    c.translate(center.x, center.y);
    c.rotate(time * 0.25f);
    Path needle;
    needle.moveTo(0.0f, -sunR * 1.30f);
    needle.lineTo(sunR * 0.28f, 0.0f);
    needle.lineTo(0.0f, sunR * 0.55f);
    needle.lineTo(-sunR * 0.28f, 0.0f);
    needle.close();
    Paint needlePaint;
    needlePaint.color = {1.0f, 0.85f, 0.35f, bassGlow};
    needlePaint.blend = Blend::plus;
    c.path(needle, needlePaint);
    c.restore();

    // 5. Esferas planetarias con halo y destello spark
    for (const auto& p : planets) {
      float orbitR = minDim * p.radiusRatio;
      float cosTilt = std::cos(p.tiltAngle);
      float sinTilt = std::sin(p.tiltAngle);
      float squash = 1.0f - p.inclination * 0.32f;

      float lx = std::cos(p.angle) * orbitR;
      float ly = std::sin(p.angle) * orbitR * squash;
      float px = center.x + lx * cosTilt - ly * sinTilt;
      float py = center.y + lx * sinTilt + ly * cosTilt;

      float depthScale = 1.0f + std::sin(p.angle) * p.inclination * 0.22f;
      float pr = p.size * (minDim / 420.0f) * depthScale;

      // Halo atmosférico del planeta
      float haloR = pr * (2.6f + smoothSpark * 1.8f);
      Paint halo = Paint::radial({px, py}, haloR,
        {{p.color.r, p.color.g, p.color.b, std::clamp(0.55f * boost, 0.0f, 1.0f)},
         {p.color.r, p.color.g, p.color.b, 0.0f}}, {0.0f, 1.0f});
      halo.blend = Blend::plus;
      c.circle({px, py}, haloR, halo);

      // Esfera 3D iluminada hacia el sol central
      float dx = px - center.x;
      float dy = py - center.y;
      float dist = std::sqrt(dx * dx + dy * dy);
      if (dist < 1.0f) dist = 1.0f;
      float nx = dx / dist;
      float ny = dy / dist;

      float lightX = px - nx * pr * 0.42f;
      float lightY = py - ny * pr * 0.42f;
      Paint spherePaint = Paint::radial({lightX, lightY}, pr * 1.35f,
        {{1.0f, 0.99f, 0.96f, 1.0f},
         p.color,
         Color::argb(0xff120f0b)}, {0.0f, 0.45f, 1.0f});
      c.circle({px, py}, pr, spherePaint);

      // Destello en chispas agudas (90ms)
      if (smoothSpark > 0.02f) {
        Paint sparkPaint; sparkPaint.blend = Blend::plus;
        sparkPaint.color = {1.0f, 0.98f, 0.92f, std::clamp(smoothSpark * 0.90f * f.intensity, 0.0f, 1.0f)};
        c.circle({px, py}, pr * (1.0f + smoothSpark * 0.55f), sparkPaint);
      }
    }
  }
};
''';
