// Maquinaria Orbital Transparente — Versión Overlay / Capa transparente.
// Planetario astrológico de relojería en latón y piedra tallada, cuatro esferas
// orbitantes, bisel graduado con glifos y sol central engranado sobre fondo transparente.
// Música: la energía y los graves revolucionan la maquinaria y los agudos
// hacen destellar los planetas. Pulso elige el resto: Golpes hace latir el sol
// y lanza un anillo de latón hasta el bisel, que se enciende, en cada golpe;
// Graves enciende y engrosa las órbitas y agranda la corona del sol despacio;
// Agudos hace centellear los glifos de la corona.
// Además, cada opción de Pulso enciende un resplandor local sobre
// la maquinaria, que late con la música (nunca un velo a pantalla completa).
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // FORMA: órbitas vistas desde arriba o muy inclinadas.
  CreatorModifier.slider('inclinacion', 'Inclinación', min: 0, max: 3, value: 1),
  // MOVIMIENTO: los planos de las órbitas giran como un giroscopio.
  CreatorModifier.slider('precesion', 'Precesión', min: 0, max: 1, value: 0),
  // MÚSICA
  CreatorModifier.choice(
    'pulso',
    'Pulso',
    options: ['Golpes', 'Graves', 'Agudos'],
  ),
  // ATMÓSFERA: esferas de metal desnudas o envueltas en luz.
  CreatorModifier.slider('halo', 'Halo', min: 0, max: 2.5, value: 1),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Giroscopio', {
    'precesion': 1,
    'inclinacion': 2.6,
    'pulso': 'Graves',
  }),
  CreatorVariation('Astrolabio Plano', {
    'inclinacion': 0,
    'halo': 2.2,
    'pulso': 'Agudos',
  }),
];

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
  // Fase de la precesión (sólo se ve si Precesión > 0).
  double precPhase = 0.0;
  // Envolventes de la música para Pulso (cero en silencio) y el último golpe.
  float bass = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0;
  double ringAge = 100.0;
  float ringPower = 0.0f;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }
  static float hashU(uint32_t x) {
    x ^= x >> 16; x *= 0x7feb352dU; x ^= x >> 15; x *= 0x846ca68bU; x ^= x >> 16;
    return float(x & 0xffffffu) / 16777216.0f;
  }
  // Precesión: cada plano gira a su ritmo, en sentidos alternos.
  float tiltOf(size_t i, float base, float prec) const {
    if (prec <= 0.0f) return base;
    const float rate = (i % 2 == 0 ? 1.0f : -1.0f) * (0.6f + 0.25f * float(i));
    return base + float(std::fmod(precPhase, 1000.0)) * rate * prec;
  }

 public:
  void reset(uint32_t seed) override {
    (void)seed;
    planets.clear();
    planets.reserve(4);
    clockTime = 0.0f;
    smoothEnergy = 0.0f;
    smoothBass = 0.0f;
    smoothSpark = 0.0f;
    precPhase = 0.0;
    bass = spark = energy = slowBass = kick = flash = 0.0f;
    ringAge = 100.0; ringPower = 0.0f;

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

    precPhase += f.delta * double(f.speed) * (f.reducedMotion ? 0.1 : 0.35);
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
    const bool fresh = hit > kick + 0.2f;
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    ringAge += f.delta;
    if (fresh) { ringAge = 0.0; ringPower = hit; }
  }

  void render(const Frame& f, Canvas& c) const override {
    float w = f.width, h = f.height;
    float minDim = std::min(w, h);
    Vec2 center{w * 0.5f, h * 0.5f};
    float time = clockTime;
    float boost = std::clamp((0.85f + smoothEnergy * 0.35f) * f.intensity, 0.0f, 1.0f);
    auto g = glide(f);
    const float amp = f.intensity;
    // Pulso: sus pesos reparten la reacción; todo vale cero sin música.
    const float punch = std::min(kick * amp, 1.0f) * g.pulso.weight(0);
    const float swell = std::min(bass * amp, 1.0f) * g.pulso.weight(1);
    const float glint = std::min(spark * amp, 1.0f) * g.pulso.weight(2);
    const float tiltK = g.inclinacion;
    const float prec = g.precesion;

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

    // Resplandor local de la música sobre la maquinaria (nunca a pantalla
    // completa): cobre en cada golpe y con los graves, azul acero que
    // parpadea con los agudos.
    if (punch > 0.0f || swell > 0.0f || glint > 0.0f) {
      const float auraR = minDim * 0.6f * (1.0f + 0.12f * punch + 0.15f * swell);
      const float flicker = 0.55f + 0.45f * std::sin(float(f.time) * 43.0f);
      const float warm = (0.4f * punch + 0.32f * swell) * f.glow;
      const float cool = 0.3f * glint * flicker * f.glow;
      Paint auraWarm = Paint::radial(center, auraR,
        {{0.85f, 0.55f, 0.29f, std::clamp(warm, 0.0f, 1.0f)},
         {0.85f, 0.55f, 0.29f, std::clamp(warm * 0.7f, 0.0f, 1.0f)},
         {0.85f, 0.55f, 0.29f, 0.0f}}, {0.0f, 0.62f, 1.0f});
      auraWarm.blend = Blend::plus;
      if (warm > 0.0f) c.circle(center, auraR, auraWarm);
      Paint auraCool = Paint::radial(center, auraR,
        {{0.44f, 0.62f, 0.77f, std::clamp(cool, 0.0f, 1.0f)}, {0.44f, 0.62f, 0.77f, 0.0f}}, {0.0f, 1.0f});
      auraCool.blend = Blend::plus;
      if (cool > 0.0f) c.circle(center, auraR, auraCool);
    }

    // 2. Bisel exterior de la corona graduada con 96 muescas y glifos
    float crownTilt = (f.music.flow - 0.5f) * 0.16f;
    float outerR = minDim * 0.455f;
    float innerR = minDim * 0.415f;

    c.save();
    c.translate(center.x, center.y);
    c.rotate(crownTilt);

    // Aros del bisel
    Paint bezel;
    // Golpes: el bisel se enciende con cada golpe.
    bezel.color = {0.85f, 0.72f, 0.48f, std::clamp(0.48f * boost + 0.62f * punch, 0.0f, 1.0f)};
    bezel.strokeWidth = 1.8f;
    if (punch > 0.0f) bezel.strokeWidth *= 1.0f + 1.3f * punch;
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
    tickPaint.color = {0.85f, 0.72f, 0.48f, std::clamp(0.55f * boost + 0.52f * punch, 0.0f, 1.0f)};
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

    // Agudos: los glifos centellean uno a uno.
    if (glint > 0.0f) {
      const uint32_t tick = uint32_t(std::floor(f.time * 10.0));
      Path sparkGlyphs;
      for (int s = 0; s < 12; s++) {
        if (hashU(uint32_t(s) * 2654435761u + tick * 40503u) >= glint * 0.95f) continue;
        float ang = (float(s) / 12.0f) * 6.2831853f + 0.130899f;
        sparkGlyphs.circle({std::cos(ang) * midRingR, std::sin(ang) * midRingR}, glyphR * 2.0f);
      }
      // Y destellos que corren por las 96 muescas.
      std::vector<Vec2> tickSparks;
      for (int i = 0; i < 96; i++) {
        if (hashU(uint32_t(i) * 747796405u + tick * 2891336453u) >= glint * 0.5f) continue;
        const float ang = (float(i) / 96.0f) * 6.2831853f;
        tickSparks.push_back({std::cos(ang) * outerR, std::sin(ang) * outerR});
      }
      if (!tickSparks.empty()) {
        Paint tickSpark; tickSpark.blend = Blend::plus;
        tickSpark.color = {1.0f, 0.95f, 0.8f, std::clamp(glint, 0.0f, 1.0f)};
        c.points(tickSparks, 2.4f, tickSpark);
      }
      Paint glyphSpark; glyphSpark.blend = Blend::plus;
      glyphSpark.color = {1.0f, 0.9f, 0.6f, std::clamp(0.8f * glint, 0.0f, 1.0f)};
      c.path(sparkGlyphs, glyphSpark);
    }

    c.restore();

    // 3. Órbitas elípticas de latón grabadas con tren de engranajes
    for (size_t i = 0; i < planets.size(); i++) {
      const auto& p = planets[i];
      float orbitR = minDim * p.radiusRatio;

      // Inclinación y Precesión (1 y 0 = las órbitas originales).
      const float incl = p.inclination * tiltK;
      c.save();
      c.translate(center.x, center.y);
      c.rotate(tiltOf(i, p.tiltAngle, prec));

      Paint orbitPaint;
      orbitPaint.color = {0.75f, 0.65f, 0.45f, std::clamp(0.25f * boost, 0.0f, 1.0f)};
      orbitPaint.strokeWidth = 1.0f;
      // Graves: las órbitas se encienden de latón y engordan despacio.
      // Golpes: las órbitas destellan.
      if (swell > 0.0f || punch > 0.0f) {
        const float lit = std::min(1.0f, swell + punch);
        orbitPaint.color = {0.75f + 0.2f * lit, 0.65f + 0.15f * lit, 0.45f + 0.05f * lit,
                            std::clamp(0.25f * boost + 0.5f * swell + 0.5f * punch, 0.0f, 1.0f)};
        orbitPaint.strokeWidth *= 1.0f + 1.6f * swell + 1.0f * punch;
      }

      Path orbitPath;
      float bAxis = orbitR * (1.0f - incl * 0.32f);
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

    // Graves: la corona crece despacio; Golpes: el sol late con cada golpe.
    const float coronaR = sunR * 2.8f * (1.0f + 0.25f * swell + 0.2f * punch);
    const float bodyR = sunR * (1.0f + 0.13f * swell + 0.2f * punch);
    Paint sunCorona = Paint::radial(center, coronaR,
      {{1.0f, 0.88f, 0.59f, std::clamp(0.85f * bassGlow * boost, 0.0f, 1.0f)},
       {0.85f, 0.55f, 0.29f, std::clamp(0.28f * bassGlow * boost, 0.0f, 1.0f)},
       {0, 0, 0, 0}}, {0.0f, 0.45f, 1.0f});
    sunCorona.blend = Blend::plus;
    c.circle(center, coronaR, sunCorona);

    Paint sunBody = Paint::radial({center.x - bodyR * 0.3f, center.y - bodyR * 0.3f}, bodyR,
      {Color::argb(0xfffff4d2), Color::argb(0xffd99b4a), Color::argb(0xff6b4820)},
      {0.0f, 0.6f, 1.0f});
    c.circle(center, bodyR, sunBody);

    // Golpes: un anillo de latón sale del sol hasta el bisel.
    const float ringFade = ringPower * float(std::exp(-ringAge * 2.5)) * g.pulso.weight(0);
    if (ringFade > 0.01f) {
      Paint ring; ring.blend = Blend::plus;
      ring.color = {1.0f, 0.82f, 0.45f, std::clamp(0.95f * ringFade * amp, 0.0f, 1.0f)};
      ring.strokeWidth = 2.0f + 5.0f * ringFade;
      c.circle(center, sunR * 1.4f + float(ringAge) * minDim * 0.7f, ring);
    }

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
    for (size_t pi = 0; pi < planets.size(); pi++) {
      const auto& p = planets[pi];
      float orbitR = minDim * p.radiusRatio;
      const float tilt = tiltOf(pi, p.tiltAngle, prec);
      const float incl = p.inclination * tiltK;
      float cosTilt = std::cos(tilt);
      float sinTilt = std::sin(tilt);
      float squash = 1.0f - incl * 0.32f;

      float lx = std::cos(p.angle) * orbitR;
      float ly = std::sin(p.angle) * orbitR * squash;
      float px = center.x + lx * cosTilt - ly * sinTilt;
      float py = center.y + lx * sinTilt + ly * cosTilt;

      float depthScale = 1.0f + std::sin(p.angle) * incl * 0.22f;
      float pr = p.size * (minDim / 420.0f) * depthScale;
      // Golpes: los planetas dan un salto; Graves: respiran.
      if (punch > 0.0f || swell > 0.0f) pr *= 1.0f + 0.2f * punch + 0.12f * swell;

      // Halo atmosférico del planeta (Halo: 0 lo apaga, 1 = el original)
      float haloR = pr * (2.6f + smoothSpark * 1.8f);
      haloR *= g.halo;
      // Golpes y Graves: el halo de cada planeta crece y se aviva.
      if (punch > 0.0f || swell > 0.0f) haloR *= 1.0f + 0.8f * punch + 0.8f * swell;
      if (g.halo > 0.001f) {
        Paint halo = Paint::radial({px, py}, haloR,
          {{p.color.r, p.color.g, p.color.b, std::clamp(0.55f * boost * std::min(g.halo, 1.4f) + 0.35f * punch + 0.25f * swell, 0.0f, 1.0f)},
           {p.color.r, p.color.g, p.color.b, 0.0f}}, {0.0f, 1.0f});
        halo.blend = Blend::plus;
        c.circle({px, py}, haloR, halo);
      }

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
