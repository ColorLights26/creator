// Matriz Oceánica 3D — Puerto fiel de Visuales Inmersivas v03.
// Perspectiva retrowave con oleaje multi-armónico, sol synthwave con persianas
// y líneas de malla que transicionan de cian a magenta neón.
// Música: la energía y los graves aceleran el tren de olas y lo levantan.
// Pulso elige qué marca el ritmo: Golpes hace saltar el sol y lanza una
// cresta brillante que corre desde el horizonte hasta el espectador en cada
// golpe; Graves hincha el oleaje, engruesa la malla y agranda el sol con los
// graves; Agudos hace centellear las crestas y salpica el mar de destellos.
// En cada golpe (y al ritmo de los graves) un resplandor local enciende el sujeto.
// Sin música, el mar nocturno se mece exactamente como siempre.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // FORMA: altura de las olas, de un mar en calma a un oleaje alto.
  CreatorModifier.slider('oleaje', 'Altura de ola', min: .3, max: 2.2, value: 1),
  // MOVIMIENTO: olas ordenadas o un mar cruzado y picado.
  CreatorModifier.slider('cruce', 'Mar cruzado', min: 0, max: 1, value: 0),
  // MÚSICA
  CreatorModifier.choice(
    'pulso',
    'Pulso',
    options: ['Golpes', 'Graves', 'Agudos'],
  ),
  // MODO: la malla se refleja en el cielo como un túnel retro.
  CreatorModifier.toggle('espejo', 'Cielo espejo', value: false),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Túnel Retro', {
    'espejo': true,
    'oleaje': .6,
    'pulso': 'Golpes',
  }),
  CreatorVariation('Mar de Fondo', {
    'oleaje': 1.5,
    'cruce': .6,
    'pulso': 'Graves',
    'speed': 1.3,
  }),
];

const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kCols = 26;
  static constexpr int kRows = 24;
  float waveTime = 0.0f;
  float smoothEnergy = 0.0f;
  float smoothBass = 0.0f;
  // Música: envolventes estándar y golpe (todo vale 0 sin música).
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Cresta del último golpe: segundos desde que nació y su fuerza.
  float waveAge = 10.0f, wavePower = 0.0f;
  // Reloj del centelleo de los agudos (sólo se ve con música).
  double glint = 0.0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }
 public:
  void reset(uint32_t seed) override {
    (void)seed;
    waveTime = 0.0f;
    smoothEnergy = 0.0f;
    smoothBass = 0.0f;
    bass = body = spark = energy = slowBass = kick = flash = drive = 0.0f;
    waveAge = 10.0f;
    wavePower = 0.0f;
    glint = 0.0;
  }
  void update(const Frame& f) override {
    float dt = float(f.delta);
    float targetEnergy = f.music.active ? f.music.energy : 0.0f;
    float targetBass = f.music.active ? f.music.bass : 0.0f;
    smoothEnergy += (targetEnergy - smoothEnergy) * float(1.0 - std::exp(-dt * 5.0));
    smoothBass += (targetBass - smoothBass) * float(1.0 - std::exp(-dt * 6.0));

    // En silencio reposa en un suave oleaje de marea nocturna (~0.10f).
    // Con música acelera el tren de olas synthwave al compás del beat.
    float audioDrive = 0.10f + smoothEnergy * 0.78f + smoothBass * 0.35f;
    waveTime += dt * f.speed * audioDrive;

    // Bloque de música estándar: graves, medios, agudos, energía y golpe.
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
    // Cada golpe nuevo lanza una cresta desde el horizonte.
    waveAge = std::min(waveAge + dt, 100.0f);
    if (fresh) {
      waveAge = 0.0f;
      wavePower = hit;
    }
    glint += f.delta * f.speed;
  }
  void render(const Frame& f, Canvas& c) const override {
    auto g = glide(f);
    const float amp = f.intensity;
    // Pulso: cada opción mueve algo distinto y sus pesos funden el cambio.
    // Todo se multiplica por señales de música: sin música vale 0.
    const float golpe = g.pulso.weight(0) * std::min(kick * amp, 1.0f);
    const float onda = g.pulso.weight(0) * std::min(wavePower * amp, 1.0f) * std::exp(-waveAge * 1.2f);
    const float grave = g.pulso.weight(1) * std::min((bass * 0.8f + body * 0.3f + drive * 0.1f) * amp, 1.2f);
    const float agudo = g.pulso.weight(2) * std::min((spark + flash * 0.4f + energy * 0.1f) * amp, 1.2f);
    const float gt = float(std::fmod(glint, 1000.0));
    float w = f.width, h = f.height;
    float t = waveTime;
    float horizonY = h * 0.40f;
    float centerX = w * 0.5f;

    // 1. Cielo cyberpunk con degradado lineal
    Paint sky = Paint::linear({centerX, 0.0f}, {centerX, h},
      {Color::argb(0xff070014), Color::argb(0xff1b0336), Color::argb(0xff03010a)},
      {0.0f, 0.5f, 1.0f});
    c.rect({0, 0, w, h}, sky);

    // 2. Sol distante Synthwave: salta con cada golpe y crece con los graves.
    Vec2 sunCenter{centerX, horizonY - 15.0f};
    float sunRadius = std::min(w, h) * 0.22f;
    sunRadius *= 1.0f + golpe * 0.18f + grave * 0.12f;
    Paint sun = Paint::radial(sunCenter, sunRadius,
      {{1.0f, 0.0f, 0.5f, std::clamp(0.95f * f.intensity, 0.0f, 1.0f)},
       {1.0f, 0.47f, 0.0f, std::clamp(0.85f * f.intensity, 0.0f, 1.0f)},
       {0.0f, 0.0f, 0.0f, 0.0f}},
      {0.0f, 0.55f, 1.0f});
    sun.blend = Blend::plus;
    c.circle(sunCenter, sunRadius, sun);

    // Persianas horizontales cortando el sol (estilo neón retro)
    Paint blind; blind.color = Color::argb(0xff070014);
    blind.strokeWidth = 2.4f;
    float blindTop = sunCenter.y - sunRadius * 0.35f;
    float blindBottom = sunCenter.y + sunRadius * 0.90f;
    for (float by = blindTop; by < blindBottom; by += 8.0f) {
      Path bp; bp.moveTo(sunCenter.x - sunRadius, by); bp.lineTo(sunCenter.x + sunRadius, by);
      c.path(bp, blind);
    }

    // Resplandor local del sol y del horizonte: Golpes lo enciende, Graves lo hace respirar.
    const float bloom = std::min(0.55f, (golpe * 0.38f + grave * 0.22f) * f.glow);
    if (bloom > 0.003f) {
      Paint sg = Paint::radial(sunCenter, sunRadius * 2.3f,
        {Color{1.0f, 0.35f, 0.55f, bloom}, Color{1.0f, 0.2f, 0.6f, bloom * 0.45f}, Color{0.5f, 0.0f, 0.5f, 0.0f}},
        {0.0f, 0.4f, 1.0f});
      sg.blend = Blend::plus;
      c.circle(sunCenter, sunRadius * 2.3f, sg);
      Paint hg = Paint::radial({centerX, horizonY + 10.0f}, w * 0.7f,
        {Color{1.0f, 0.2f, 0.7f, bloom * 0.5f}, Color{0.6f, 0.1f, 0.8f, 0.0f}}, {0.0f, 1.0f});
      hg.blend = Blend::plus;
      c.circle({centerX, horizonY + 10.0f}, w * 0.7f, hg);
    }

    // 3. Proyección 3D de la malla oceánica
    const float fov = 260.0f;
    const float gridSpacingX = 40.0f;
    const float gridSpacingZ = 34.0f;
    const float nearZ = 60.0f;
    float camHeight = 150.0f + std::sin(t * 0.5f) * 15.0f;
    float waveBass = (1.0f + f.music.bass * 0.75f);
    // Altura de ola (1 = la de siempre); Graves la hincha con los graves.
    const float swell = g.oleaje * (1.0f + grave * 0.2f);

    // Golpes: la cresta corre del horizonte (fila del fondo) al espectador.
    float rowFlash[kRows];
    const float crest = float(kRows - 1) - waveAge * 26.0f;
    for (int r = 0; r < kRows; r++) {
      const float off = float(r) - crest;
      rowFlash[r] = onda > 0.003f ? onda * std::exp(-off * off / 3.0f) : 0.0f;
    }

    Vec2 proj[kRows][kCols];
    // Con los ajustes iniciales y sin golpe, el mar se calcula como siempre.
    const bool plainSea = swell == 1.0f && g.cruce <= 0.0f && onda <= 0.003f;

    if (plainSea) {
      for (int r = 0; r < kRows; r++) {
        float z = nearZ + float(r) * gridSpacingZ;
        float depthFactor = fov / (z + 120.0f);

        for (int col = 0; col < kCols; col++) {
          float worldX = (float(col) - float(kCols) * 0.5f) * gridSpacingX;

          // Armónicos de olas
          float wave1 = std::sin(worldX * 0.015f + t * 1.5f) * 24.0f * waveBass;
          float wave2 = std::cos(z * 0.020f - t * 1.8f) * 20.0f * waveBass;
          float wave3 = std::sin((worldX + z) * 0.010f + t * 1.1f) * 16.0f * waveBass;
          float worldY = camHeight + wave1 + wave2 + wave3;

          float px = centerX + worldX * depthFactor;
          float py = horizonY + worldY * depthFactor;
          proj[r][col] = Vec2{px, py};
        }
      }
    } else for (int r = 0; r < kRows; r++) {
      float z = nearZ + float(r) * gridSpacingZ;
      float depthFactor = fov / (z + 120.0f);

      for (int col = 0; col < kCols; col++) {
        float worldX = (float(col) - float(kCols) * 0.5f) * gridSpacingX;

        // Armónicos de olas (Altura de ola y Graves los escalan)
        float wave1 = std::sin(worldX * 0.015f + t * 1.5f) * 24.0f * waveBass * swell;
        float wave2 = std::cos(z * 0.020f - t * 1.8f) * 20.0f * waveBass * swell;
        float wave3 = std::sin((worldX + z) * 0.010f + t * 1.1f) * 16.0f * waveBass * swell;
        float worldY = camHeight + wave1 + wave2 + wave3;
        // Mar cruzado: dos trenes de olas cortas en diagonal que se cruzan.
        if (g.cruce > 0.0f) {
          worldY += g.cruce * waveBass * swell *
            (std::sin(worldX * 0.05f - z * 0.035f + t * 3.1f) * 13.0f +
             std::sin(-worldX * 0.031f - z * 0.052f - t * 2.4f) * 9.0f);
        }
        // La cresta del golpe levanta la fila por la que pasa.
        if (rowFlash[r] > 0.0f) worldY -= 26.0f * rowFlash[r];

        float px = centerX + worldX * depthFactor;
        float py = horizonY + worldY * depthFactor;
        proj[r][col] = Vec2{px, py};
      }
    }

    // Cielo espejo: la malla reflejada sobre el horizonte, algo más tenue.
    const float mirror = g.espejo;

    // 4. Renderizar líneas de fila (olas horizontales) con niebla de profundidad
    for (int r = 0; r < kRows; r++) {
      float depth = float(r) / float(kRows - 1);
      float alpha = std::clamp((1.0f - depth * 0.75f) * f.intensity, 0.05f, 1.0f);
      if (rowFlash[r] > 0.0f) alpha = std::min(1.0f, alpha + rowFlash[r] * 0.6f);
      // Golpes: toda la malla se enciende en el golpe.
      if (golpe > 0.003f) alpha = std::min(1.0f, alpha * (1.0f + golpe * 0.9f));

      // Desplazamiento cromático: cian brillante adelante -> magenta vivo en el horizonte
      Color rowCol{
        0.0f * (1.0f - depth) + 1.0f * depth,
        1.0f * (1.0f - depth) + 0.0f * depth,
        0.95f * (1.0f - depth) + 0.47f * depth,
        alpha
      };
      Paint rp; rp.blend = Blend::plus; rp.color = rowCol;
      rp.strokeWidth = std::max(0.6f, 2.2f * (1.0f - depth * 0.7f)) * (1.0f + grave * 0.6f + rowFlash[r] * 1.2f + golpe * 1.0f);

      Path rowPath;
      rowPath.moveTo(proj[r][0].x, proj[r][0].y);
      for (int col = 1; col < kCols; col++) {
        rowPath.lineTo(proj[r][col].x, proj[r][col].y);
      }
      c.path(rowPath, rp);
      if (mirror > 0.0f) {
        Path up;
        up.moveTo(proj[r][0].x, 2.0f * horizonY - proj[r][0].y);
        for (int col = 1; col < kCols; col++) {
          up.lineTo(proj[r][col].x, 2.0f * horizonY - proj[r][col].y);
        }
        rp.color = rowCol.opacity(alpha * 0.7f * mirror);
        c.path(up, rp);
      }
    }

    // Renderizar líneas de columna (longitudinales hacia el horizonte)
    Paint colPaint; colPaint.blend = Blend::plus;
    colPaint.color = {0.0f, 1.0f, 0.84f, std::clamp(0.35f * f.intensity + grave * 0.2f + golpe * 0.4f, 0.0f, 1.0f)};
    colPaint.strokeWidth = 0.9f * (1.0f + golpe * 1.0f + grave * 0.6f);
    for (int col = 0; col < kCols; col += 2) {
      Path colPath;
      colPath.moveTo(proj[0][col].x, proj[0][col].y);
      for (int r = 1; r < kRows; r++) {
        colPath.lineTo(proj[r][col].x, proj[r][col].y);
      }
      c.path(colPath, colPaint);
    }
    if (mirror > 0.0f) {
      Paint upCol = colPaint;
      upCol.color = colPaint.color.opacity(colPaint.color.a * 0.7f * mirror);
      for (int col = 0; col < kCols; col += 2) {
        Path colPath;
        colPath.moveTo(proj[0][col].x, 2.0f * horizonY - proj[0][col].y);
        for (int r = 1; r < kRows; r++) {
          colPath.lineTo(proj[r][col].x, 2.0f * horizonY - proj[r][col].y);
        }
        c.path(colPath, upCol);
      }
    }

    // Crestas iluminadas (destellos blancos en picos de olas)
    std::vector<Vec2> crests;
    crests.reserve(24);
    for (int r = 0; r < 6; r++) {
      for (int col = 2; col < kCols - 2; col += 3) {
        crests.push_back(proj[r][col]);
      }
    }
    Paint crestPaint; crestPaint.blend = Blend::plus;
    crestPaint.color = {1.0f, 1.0f, 1.0f, std::clamp(0.85f * f.intensity, 0.0f, 1.0f)};
    c.points(crests, 1.8f * (1.0f + golpe * 0.8f), crestPaint);

    // Agudos: destellos que saltan de cresta en cresta por todo el mar cercano.
    if (agudo > 0.003f) {
      std::vector<Vec2> glints;
      glints.reserve(kRows * kCols);
      for (int r = 0; r < 18; r++) {
        for (int col = 1; col < kCols - 1; col++) {
          if (std::sin(gt * 13.0f + float(r) * 1.7f + float(col) * 2.3f) > 0.1f) glints.push_back(proj[r][col]);
        }
      }
      Paint gp; gp.blend = Blend::plus;
      gp.color = {1.0f, 0.92f, 0.98f, std::clamp(agudo * 0.9f, 0.0f, 1.0f)};
      c.points(glints, 2.6f, gp);
    }
  }
};
''';
