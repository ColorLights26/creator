// Agujero Negro & Acreción — Puerto fiel de Visuales Inmersivas v01.
// Disco de acreción relativista con corrimiento Doppler, chorros polares bipolares,
// anillo fotónico ISCO y curvatura gravitacional de Einstein.
// Música: la energía y los graves aceleran el disco y desatan los chorros. Pulso
// elige qué marca el ritmo: Golpes lanza una onda de choque por el disco desde
// el horizonte, hace saltar el disco y destella el anillo de fotones en cada
// golpe; Graves hincha los halos de la lente y engorda el disco con los graves;
// Agudos hace centellear las estrellas y salpica el disco de destellos finos.
// En cada golpe (y al ritmo de los graves) un resplandor local enciende el sujeto.
// Sin música, el agujero negro gira tranquilo exactamente como siempre.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // FORMA: el disco visto casi de frente (el de siempre) o de canto (rasante).
  CreatorModifier.slider('inclinacion', 'Inclinación', min: .5, max: 1.4, value: .5),
  // MOVIMIENTO: órbitas limpias o un disco turbulento con brazos en espiral.
  CreatorModifier.slider('turbulencia', 'Turbulencia', min: 0, max: 1, value: 0),
  // MÚSICA
  CreatorModifier.choice(
    'pulso',
    'Pulso',
    options: ['Golpes', 'Graves', 'Agudos'],
  ),
  // ATMÓSFERA: sin chorros, los de siempre o chorros largos y encendidos.
  CreatorModifier.slider('chorros', 'Chorros polares', min: 0, max: 2, value: 1),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Perfil Rasante', {
    'inclinacion': 1.3,
    'chorros': .4,
    'pulso': 'Graves',
  }),
  CreatorVariation('Cuásar Furioso', {
    'inclinacion': .8,
    'turbulencia': .8,
    'chorros': 2,
    'pulso': 'Golpes',
    'speed': 1.3,
  }),
];

const nativeSource = r'''
class Visual final : public Scene {
  struct DiskParticle { float radius, angle, speed, size; };
  struct JetParticle { float z, speedZ, spread, size; };
  struct Star { float x, y, phase; };
  std::vector<DiskParticle> disk;
  std::vector<JetParticle> jets;
  std::vector<Star> stars;
  float jetTravel = 0.0f;
  float diskTime = 0.0f;
  float smoothEnergy = 0.0f;
  float smoothBass = 0.0f;
  // Música: envolventes estándar y golpe (todo vale 0 sin música).
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Onda de choque del último golpe: segundos desde que nació y su fuerza.
  float waveAge = 10.0f, wavePower = 0.0f;
  // Reloj del centelleo de los agudos (sólo se ve con música).
  double glint = 0.0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }
 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    jetTravel = 0.0f;
    diskTime = 0.0f;
    smoothEnergy = 0.0f;
    smoothBass = 0.0f;
    bass = body = spark = energy = slowBass = kick = flash = drive = 0.0f;
    waveAge = 10.0f;
    wavePower = 0.0f;
    glint = 0.0;
    disk.clear(); disk.reserve(650);
    for (int i = 0; i < 650; i++) {
      float r = 55.0f + rng.unit() * 160.0f;
      float a = rng.unit() * 6.2831853f;
      float spd = (1.2f / std::sqrt(r)) * 0.045f;
      float sz = 1.0f + rng.unit() * 2.2f;
      disk.push_back({r, a, spd, sz});
    }
    jets.clear(); jets.reserve(120);
    for (int i = 0; i < 120; i++) {
      float z = (rng.unit() - 0.5f) * 220.0f;
      float spd = (1.5f + rng.unit() * 3.0f) * (rng.unit() > 0.5f ? 1.0f : -1.0f);
      float sp = rng.unit() * 12.0f;
      float sz = 1.2f + rng.unit() * 2.0f;
      jets.push_back({z, spd, sp, sz});
    }
    stars.clear(); stars.reserve(60);
    for (int i = 0; i < 60; i++) {
      stars.push_back({rng.unit(), rng.unit(), rng.unit() * 6.2831853f});
    }
  }
  void update(const Frame& f) override {
    float dt = float(f.delta);
    float targetEnergy = f.music.active ? f.music.energy : 0.0f;
    float targetBass = f.music.active ? f.music.bass : 0.0f;
    smoothEnergy += (targetEnergy - smoothEnergy) * float(1.0 - std::exp(-dt * 6.0));
    smoothBass += (targetBass - smoothBass) * float(1.0 - std::exp(-dt * 6.0));

    // En silencio reposa en una órbita relativista pausada (~0.10f).
    // Con música acelera el disco de acreción y desata los chorros polares.
    float diskDrive = 0.10f + smoothEnergy * 0.75f + smoothBass * 0.35f;
    diskTime += dt * f.speed * diskDrive;

    float jetRate = 8.0f + smoothEnergy * 65.0f + smoothBass * 35.0f;
    jetTravel += dt * f.speed * jetRate;

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
    // Cada golpe nuevo lanza una onda de choque desde el horizonte.
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
    const float onda = g.pulso.weight(0) * std::min(wavePower * amp, 1.0f) * std::exp(-waveAge * 2.4f);
    const float grave = g.pulso.weight(1) * std::min((bass * 0.8f + body * 0.3f + drive * 0.1f) * amp, 1.2f);
    const float agudo = g.pulso.weight(2) * std::min((spark + flash * 0.4f + energy * 0.1f) * amp, 1.2f);
    const float gt = float(std::fmod(glint, 1000.0));
    float w = f.width, h = f.height;
    float t = diskTime;
    Vec2 center{w * 0.5f, h * 0.5f};
    float minDim = std::min(w, h);
    float holeRadius = minDim * 0.11f;

    // 1. Fondo cósmico profundo
    Paint bg = Paint::radial(center, minDim * 0.85f,
      {Color::argb(0xff0d061a), Color::argb(0xff040208), Color::argb(0xff000000)},
      {0.0f, 0.45f, 1.0f});
    c.rect({0, 0, w, h}, bg);

    // Estrellas de fondo con centelleo armónico
    std::vector<Vec2> starPoints;
    starPoints.reserve(stars.size());
    for (const auto& s : stars) {
      starPoints.push_back({s.x * w, s.y * h});
    }
    float starTwinkle = 0.35f + 0.35f * std::sin(t * 2.5f);
    Paint starPaint; starPaint.blend = Blend::plus;
    starPaint.color = {1.0f, 1.0f, 1.0f, std::clamp(starTwinkle * f.intensity, 0.0f, 1.0f)};
    c.points(starPoints, 1.1f, starPaint);

    // Agudos: las estrellas centellean una a una con los agudos.
    if (agudo > 0.003f) {
      std::vector<Vec2> glints;
      glints.reserve(stars.size());
      for (const auto& s : stars) {
        if (std::sin(gt * 14.0f + s.phase * 5.0f) > -0.2f) glints.push_back({s.x * w, s.y * h});
      }
      Paint gp; gp.blend = Blend::plus;
      gp.color = {1.0f, 0.95f, 0.85f, std::clamp(agudo * 0.9f, 0.0f, 1.0f)};
      c.points(glints, 2.6f, gp);
    }

    // 2. Halo de curvatura gravitacional exterior (anillo de Einstein)
    float bassBoost = (0.85f + 0.35f * smoothBass) * f.intensity;
    // Graves: los halos de la lente crecen y se encienden con los graves.
    const float haloGrow = 1.0f + grave * 0.3f;
    const float haloLift = 1.0f + grave * 0.8f + golpe * 0.8f;
    Paint halo1 = Paint::radial(center, holeRadius * 3.2f * haloGrow,
      {{0.29f, 0.08f, 0.55f, std::clamp(0.35f * bassBoost * haloLift, 0.0f, 1.0f)}, {0, 0, 0, 0}},
      {0.0f, 1.0f});
    halo1.blend = Blend::plus;
    c.circle(center, holeRadius * 3.2f * haloGrow, halo1);

    Paint halo2 = Paint::radial(center, holeRadius * 2.0f * haloGrow,
      {{1.0f, 0.43f, 0.0f, std::clamp(0.24f * bassBoost * haloLift, 0.0f, 1.0f)}, {0, 0, 0, 0}},
      {0.0f, 1.0f});
    halo2.blend = Blend::plus;
    c.circle(center, holeRadius * 2.0f * haloGrow, halo2);

    // Resplandor local del disco: Golpes lo enciende de golpe y Graves lo hace respirar.
    const float bloom = std::min(0.6f, (golpe * 0.6f + grave * 0.25f) * f.glow);
    if (bloom > 0.003f) {
      const float R = holeRadius * 5.6f;
      Paint gl = Paint::radial(center, R,
        {Color{1.0f, 0.55f, 0.2f, bloom}, Color{0.85f, 0.3f, 0.6f, bloom * 0.65f}, Color{0.5f, 0.1f, 0.6f, 0.0f}},
        {0.0f, 0.45f, 1.0f});
      gl.blend = Blend::plus;
      c.circle(center, R, gl);
    }

    // 3. Chorros relativistas polares bipolares
    // Chorros polares: 0 los apaga; por encima de 1 se alargan y se encienden.
    const float jetLen = std::max(1.0f, 0.5f + 0.5f * g.chorros);
    // Turbulencia: los chorros también se abren y serpentean más.
    const float jetSpread = 1.0f + g.turbulencia * 1.5f;
    for (const auto& j : jets) {
      float jz = std::fmod(j.z + j.speedZ * jetTravel + 24000.0f, 480.0f) - 240.0f;
      float prog = std::clamp(std::abs(jz) / 240.0f, 0.0f, 1.0f);
      float alpha = std::clamp((1.0f - prog) * 0.82f * f.intensity * g.chorros * (1.0f + golpe * 0.8f), 0.0f, 1.0f);
      float xOff = std::sin(jz * 0.05f + t * 2.0f) * j.spread * (1.0f + prog * 2.0f) * jetSpread;
      float jx = center.x + xOff * (minDim / 400.0f);
      float jy = center.y + jz * jetLen * (minDim / 400.0f);

      Color jcol{
        std::clamp(0.0f * (1.0f - prog) + 0.83f * prog, 0.0f, 1.0f),
        std::clamp(0.9f * (1.0f - prog) + 0.0f * prog, 0.0f, 1.0f),
        std::clamp(1.0f * (1.0f - prog) + 0.98f * prog, 0.0f, 1.0f),
        alpha
      };
      Paint jp; jp.blend = Blend::plus; jp.color = jcol;
      c.circle({jx, jy}, std::max(0.5f, j.size * (1.0f - prog * 0.5f)), jp);
    }

    // 4. Disco de acreción 3D con corrimiento Doppler
    // Inclinación: 0,5 es la vista de siempre; más, el disco se ve de canto.
    float pitch = g.inclinacion + std::sin(t * 0.18f) * 0.12f;
    float yaw = t * 0.35f;
    float cosPitch = std::cos(pitch);
    float sinPitch = std::sin(pitch);
    float diskScale = (minDim / 400.0f) * (1.0f + smoothBass * 0.15f);
    // Golpes: el disco salta hacia fuera en cada golpe y vuelve.
    // Graves: el disco respira con los graves y sus partículas engordan.
    diskScale *= 1.0f + golpe * 0.16f + grave * 0.12f;
    const float grain = 1.0f + grave * 0.6f;

    struct Proj { Vec2 pt; float size; Color col; };
    std::vector<Proj> backPts, frontPts;
    backPts.reserve(350); frontPts.reserve(350);

    for (const auto& p : disk) {
      float effAngle = p.angle + p.speed * t * 70.0f + yaw;
      // Turbulencia: el radio ondula en tres brazos espirales que giran con el disco.
      float rad = p.radius;
      if (g.turbulencia > 0.0f) {
        rad *= 1.0f + g.turbulencia * 0.22f * std::sin(effAngle * 3.0f - p.radius * 0.045f + t * 3.0f);
      }
      float rawX = rad * std::cos(effAngle) * diskScale;
      float rawY = rad * std::sin(effAngle) * diskScale;

      float rotX = rawX;
      float rotY = rawY * cosPitch;
      float rotZ = rawY * sinPitch;

      float doppler = (std::sin(effAngle) + 1.0f) * 0.5f;
      float dAlpha = std::clamp((0.4f + doppler * 0.6f) * f.intensity, 0.0f, 1.0f);
      float size = p.size * diskScale * grain;
      // Golpes: todo el disco se enciende en el golpe.
      if (golpe > 0.003f) dAlpha = std::min(1.0f, dAlpha * (1.0f + golpe * 0.9f));
      // Agudos: destellos finos que saltan de partícula en partícula.
      if (agudo > 0.003f && std::sin(gt * 17.0f + p.angle * 40.0f) > 0.0f) {
        dAlpha = std::min(1.0f, dAlpha + agudo * 0.8f);
        size *= 1.0f + agudo * 0.8f;
      }

      Color col{
        std::clamp(1.0f * (1.0f - doppler) + 0.0f * doppler, 0.0f, 1.0f),
        std::clamp(0.34f * (1.0f - doppler) + 0.9f * doppler, 0.0f, 1.0f),
        std::clamp(0.13f * (1.0f - doppler) + 1.0f * doppler, 0.0f, 1.0f),
        dAlpha
      };

      Proj pr{{center.x + rotX, center.y + rotY}, size, col};
      if (rotZ < 0.0f) backPts.push_back(pr);
      else frontPts.push_back(pr);
    }

    // Partículas detrás del horizonte
    for (const auto& pr : backPts) {
      Paint p; p.blend = Blend::plus; p.color = pr.col;
      c.circle(pr.pt, pr.size, p);
    }

    // 5. Arco de deflexión gravitacional de Einstein sobre el horizonte
    Path arc;
    const int arcSteps = 36;
    float arcR = holeRadius * 1.25f;
    for (int i = 0; i <= arcSteps; i++) {
      float a = -3.14159265f * 0.85f + (float(i) / float(arcSteps)) * 3.14159265f * 1.7f;
      float ax = center.x + std::cos(a) * arcR;
      float ay = center.y + std::sin(a) * arcR * cosPitch * 1.4f;
      if (i == 0) arc.moveTo(ax, ay); else arc.lineTo(ax, ay);
    }
    Paint arcPaint; arcPaint.blend = Blend::plus;
    arcPaint.color = {1.0f, 0.67f, 0.25f, std::clamp(0.65f * bassBoost + golpe * 0.6f, 0.0f, 1.0f)};
    arcPaint.strokeWidth = 3.0f * (1.0f + golpe * 1.2f + grave * 0.6f); arcPaint.strokeCap = 1; arcPaint.strokeJoin = 1;
    c.path(arc, arcPaint);

    // 6. Horizonte de Sucesos (Vacío Absoluto)
    Paint holePaint; holePaint.color = Color::argb(0xff030305);
    c.circle(center, holeRadius, holePaint);

    // 7. Esfera de fotones (Anillo ISCO): Golpes la hace destellar y engrosar.
    Paint iscoPaint; iscoPaint.blend = Blend::plus;
    iscoPaint.color = {1.0f, 0.85f, 0.35f, std::clamp(0.92f * bassBoost + golpe * 0.5f, 0.0f, 1.0f)};
    iscoPaint.strokeWidth = 2.4f * (1.0f + golpe * 1.5f + grave * 0.6f);
    c.circle(center, holeRadius + 1.2f, iscoPaint);

    // 8. Partículas delante del horizonte
    for (const auto& pr : frontPts) {
      Paint p; p.blend = Blend::plus; p.color = pr.col;
      c.circle(pr.pt, pr.size, p);
    }

    // Golpes: una onda de choque recorre el plano del disco desde el horizonte.
    if (onda > 0.003f) {
      const float R = holeRadius * (1.3f + waveAge * 7.0f);
      Path ring;
      for (int i = 0; i <= 48; i++) {
        float a = float(i) / 48.0f * 6.2831853f;
        float x = center.x + std::cos(a) * R;
        float y = center.y + std::sin(a) * R * cosPitch;
        if (i == 0) ring.moveTo(x, y); else ring.lineTo(x, y);
      }
      Paint wp; wp.blend = Blend::plus;
      wp.color = {1.0f, 0.78f, 0.45f, std::clamp(onda * 0.85f, 0.0f, 1.0f)};
      wp.strokeWidth = 2.0f + 4.0f * onda;
      wp.strokeJoin = 1;
      c.path(ring, wp);
    }
  }
};
''';
