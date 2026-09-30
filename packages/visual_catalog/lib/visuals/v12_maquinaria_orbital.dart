// Maquinaria Orbital — Puerto fiel de Visuales Inmersivas v12.
// Planetario astrológico de relojería en latón y piedra tallada, cuatro esferas
// orbitantes con sombras arrojadas, bisel graduado con glifos y sol central engranado.
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
    smoothEnergy += (f.music.energy - smoothEnergy) * float(1.0 - std::exp(-dt * 5.0));
    smoothBass += (f.music.bass - smoothBass) * float(1.0 - std::exp(-dt * 6.0));
    smoothSpark += (f.music.spark - smoothSpark) * float(1.0 - std::exp(-dt * 15.0));

    float periodStretch = 1.0f + smoothEnergy * 1.2f;
    float speedFactor = ((f.reducedMotion ? 0.25f : 1.0f) * f.speed) / periodStretch;
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

    // 1. Fondo de piedra tallada #14100c con núcleo ámbar
    Paint bg = Paint::radial(center, minDim * 0.75f,
      {Color::argb(0xff1e1812), Color::argb(0xff14100c), Color::argb(0xff090705)},
      {0.0f, 0.55f, 1.0f});
    c.rect({0, 0, w, h}, bg);

    // Barras diagonales estructurales de latón
    Paint crossbar;
    crossbar.color = {0.42f, 0.35f, 0.23f, std::clamp(0.28f * boost, 0.0f, 1.0f)};
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
    bezel.color = {0.72f, 0.63f, 0.42f, std::clamp(0.38f * boost, 0.0f, 1.0f)};
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
    tickPaint.color = {0.72f, 0.63f, 0.42f, std::clamp(0.48f * boost, 0.0f, 1.0f)};
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
        // Rombo con punto central
        glyphsPath.moveTo(gx, gy - glyphR);
        glyphsPath.lineTo(gx + glyphR, gy);
        glyphsPath.lineTo(gx, gy + glyphR);
        glyphsPath.lineTo(gx - glyphR, gy);
        glyphsPath.close();
      } else if (s % 3 == 1) {
        // Círculo / bisector
        glyphsPath.circle({gx, gy}, glyphR * 0.75f);
      } else {
        // Triángulo
        glyphsPath.moveTo(gx, gy - glyphR);
        glyphsPath.lineTo(gx + glyphR * 0.9f, gy + glyphR * 0.8f);
        glyphsPath.lineTo(gx - glyphR * 0.9f, gy + glyphR * 0.8f);
        glyphsPath.close();
      }
    }
    Paint glyphPaint;
    glyphPaint.color = {0.85f, 0.55f, 0.29f, std::clamp(0.65f * boost, 0.0f, 1.0f)};
    glyphPaint.strokeWidth = 1.2f;
    c.path(glyphsPath, glyphPaint);

    // 4 Tornillos ranurados de latón en diagonales
    Paint screwHead; screwHead.color = Color::argb(0xff8b734b);
    Paint screwSlot; screwSlot.color = Color::argb(0xff14100c); screwSlot.strokeWidth = 1.2f;
    for (int k = 0; k < 4; k++) {
      float ang = float(k) * 1.570796f + 0.785398f;
      float sx = std::cos(ang) * (innerR - minDim * 0.018f);
      float sy = std::sin(ang) * (innerR - minDim * 0.018f);
      c.circle({sx, sy}, 4.5f, screwHead);
      Path slot; slot.moveTo(sx - 3.0f, sy - 3.0f); slot.lineTo(sx + 3.0f, sy + 3.0f);
      c.path(slot, screwSlot);
    }

    c.restore();

    // 3. Órbitas elípticas inclinadas con desvanecimiento de profundidad
    for (const auto& p : planets) {
      float orbitR = minDim * p.radiusRatio;
      float cosTilt = std::cos(p.tiltAngle);
      float sinTilt = std::sin(p.tiltAngle);
      float squash = 1.0f - p.inclination * 0.32f;

      for (int half = 0; half < 2; half++) {
        Path orbitHalf;
        int startSeg = half == 0 ? 0 : 64;
        int endSeg = half == 0 ? 64 : 128;
        for (int s = startSeg; s <= endSeg; s++) {
          float theta = (float(s) / 128.0f) * 6.2831853f;
          float lx = std::cos(theta) * orbitR;
          float ly = std::sin(theta) * orbitR * squash;
          float rx = center.x + lx * cosTilt - ly * sinTilt;
          float ry = center.y + lx * sinTilt + ly * cosTilt;
          if (s == startSeg) orbitHalf.moveTo(rx, ry);
          else orbitHalf.lineTo(rx, ry);
        }
        Paint op;
        float alpha = (half == 0 ? 0.35f : 0.14f) * boost;
        op.color = {0.42f, 0.35f, 0.23f, std::clamp(alpha, 0.0f, 1.0f)};
        op.strokeWidth = 1.35f;
        c.path(orbitHalf, op);
      }
    }

    // 4. Sol central iluminado
    float sunR = minDim * 0.056f;
    float bassGlow = std::clamp((0.25f + smoothBass * 0.75f) * f.intensity, 0.0f, 1.0f);

    Paint sunCorona = Paint::radial(center, sunR * 2.8f,
      {{1.0f, 0.88f, 0.59f, std::clamp(0.85f * boost, 0.0f, 1.0f)},
       {0.85f, 0.55f, 0.29f, std::clamp(0.28f * boost, 0.0f, 1.0f)},
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

    // 5. Esferas planetarias con sombra arrojada, halo y destello spark
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

      float dx = px - center.x;
      float dy = py - center.y;
      float dist = std::sqrt(dx * dx + dy * dy);
      if (dist < 1.0f) dist = 1.0f;
      float nx = dx / dist;
      float ny = dy / dist;

      // Sombra cónica arrojada hacia el exterior
      Path shadowPoly;
      shadowPoly.moveTo(px - ny * pr * 0.9f, py + nx * pr * 0.9f);
      shadowPoly.lineTo(px + ny * pr * 0.9f, py - nx * pr * 0.9f);
      shadowPoly.lineTo(px + nx * pr * 3.6f + ny * pr * 0.4f, py + ny * pr * 3.6f - nx * pr * 0.4f);
      shadowPoly.lineTo(px + nx * pr * 3.6f - ny * pr * 0.4f, py + ny * pr * 3.6f + nx * pr * 0.4f);
      shadowPoly.close();

      Paint shadowPaint = Paint::linear({px, py}, {px + nx * pr * 3.6f, py + ny * pr * 3.6f},
        {{0.02f, 0.02f, 0.01f, std::clamp(0.78f * boost, 0.0f, 1.0f)}, {0.02f, 0.02f, 0.01f, 0.0f}},
        {0.0f, 1.0f});
      c.path(shadowPoly, shadowPaint);

      // Halo atmosférico del planeta
      float haloR = pr * (2.6f + smoothSpark * 1.8f);
      Paint halo = Paint::radial({px, py}, haloR,
        {{p.color.r, p.color.g, p.color.b, std::clamp(0.55f * boost, 0.0f, 1.0f)},
         {p.color.r, p.color.g, p.color.b, 0.0f}}, {0.0f, 1.0f});
      halo.blend = Blend::plus;
      c.circle({px, py}, haloR, halo);

      // Esfera 3D iluminada hacia el sol central
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
