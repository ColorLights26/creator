// Espiral Áurea Sagrada — Puerto fiel de Visuales Inmersivas v09.
// Distribución de filotaxis áurea de 750 nodos con ángulo de divergencia de 137.5°,
// ciclo cromático HSV de Fibonacci y núcleo de singularidad.
// Música: la energía y los graves aceleran el giro y la espiral respira con
// los graves. Pulso elige qué marca el ritmo: Golpes lanza una ola de luz que
// recorre las semillas del centro hacia fuera y hace saltar la singularidad
// en cada golpe; Graves engorda las semillas y enciende el núcleo con los
// graves; Agudos hace centellear y blanquear semillas sueltas con los agudos.
// En cada golpe (y al ritmo de los graves) un resplandor local enciende el sujeto.
// Sin música, la espiral gira meditativa exactamente como siempre.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // FORMA: ángulo entre semillas; lejos del áureo aparecen brazos en espiral.
  CreatorModifier.slider('divergencia', 'Divergencia', min: 2.3, max: 2.5, value: 2.39996323),
  // MOVIMIENTO: giro rígido o un torbellino que retuerce la espiral.
  CreatorModifier.slider('torbellino', 'Torbellino', min: 0, max: 1, value: 0),
  // MÚSICA
  CreatorModifier.choice(
    'pulso',
    'Pulso',
    options: ['Golpes', 'Graves', 'Agudos'],
  ),
  // MODO: una segunda espiral en sentido contrario, como un girasol.
  CreatorModifier.toggle('espejo', 'Girasol doble', value: false),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Girasol', {
    'espejo': true,
    'torbellino': .3,
    'pulso': 'Graves',
  }),
  CreatorVariation('Galaxia Áurea', {
    'torbellino': 1,
    'divergencia': 2.43,
    'pulso': 'Golpes',
    'speed': 1.4,
  }),
];

const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kNodeCount = 750;
  static constexpr float kGoldenAngle = 2.39996323f; // ~137.507764 grados
  float spiralAngle = 0.0f;
  float colorTime = 0.0f;
  float smoothBass = 0.0f;
  float smoothEnergy = 0.0f;
  // Música: envolventes estándar y golpe (todo vale 0 sin música).
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Ola de luz del último golpe: segundos desde que nació y su fuerza.
  float waveAge = 10.0f, wavePower = 0.0f;
  // Reloj del centelleo de los agudos (sólo se ve con música).
  double glint = 0.0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  static Color hsvToRgb(float h, float s, float v, float a) {
    float c = v * s;
    float x = c * (1.0f - std::abs(std::fmod(h / 60.0f, 2.0f) - 1.0f));
    float m = v - c;
    float r = 0, g = 0, b = 0;
    if (h < 60.0f) { r = c; g = x; b = 0; }
    else if (h < 120.0f) { r = x; g = c; b = 0; }
    else if (h < 180.0f) { r = 0; g = c; b = x; }
    else if (h < 240.0f) { r = 0; g = x; b = c; }
    else if (h < 300.0f) { r = x; g = 0; b = c; }
    else { r = c; g = 0; b = x; }
    return Color{
      std::clamp(r + m, 0.0f, 1.0f),
      std::clamp(g + m, 0.0f, 1.0f),
      std::clamp(b + m, 0.0f, 1.0f),
      std::clamp(a, 0.0f, 1.0f)
    };
  }

 public:
  void reset(uint32_t seed) override {
    (void)seed;
    spiralAngle = 0.0f;
    colorTime = 0.0f;
    smoothBass = 0.0f;
    smoothEnergy = 0.0f;
    bass = body = spark = energy = slowBass = kick = flash = drive = 0.0f;
    waveAge = 10.0f;
    wavePower = 0.0f;
    glint = 0.0;
  }
  void update(const Frame& f) override {
    float dt = float(f.delta);
    float targetEnergy = f.music.active ? f.music.energy : 0.0f;
    float targetBass = f.music.active ? f.music.bass : 0.0f;
    smoothBass += (targetBass - smoothBass) * float(1.0 - std::exp(-dt * 6.0));
    smoothEnergy += (targetEnergy - smoothEnergy) * float(1.0 - std::exp(-dt * 5.0));

    // En silencio reposa en un giro áureo meditativo (~0.05f).
    // Con música la espiral acelera y desata ondas cromáticas al ritmo.
    float rate = 0.05f + smoothEnergy * 0.35f + smoothBass * 0.20f;
    spiralAngle += dt * f.speed * rate;
    colorTime += dt * f.speed * (0.08f + smoothEnergy * 0.72f);

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
    // Cada golpe nuevo lanza una ola de luz desde el centro.
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
    const float onda = g.pulso.weight(0) * std::min(wavePower * amp, 1.0f) * std::exp(-waveAge * 1.4f);
    const float grave = g.pulso.weight(1) * std::min((bass * 0.8f + body * 0.3f + drive * 0.1f) * amp, 1.2f);
    const float agudo = g.pulso.weight(2) * std::min((spark + flash * 0.4f + energy * 0.1f) * amp, 1.2f);
    const float gt = float(std::fmod(glint, 1000.0));
    float w = f.width, h = f.height;
    Vec2 center{w * 0.5f, h * 0.5f};
    float minDim = std::min(w, h);
    float maxDim = std::max(w, h);

    // 1. Fondo cósmico profundo
    Paint bg = Paint::radial(center, minDim * 0.85f,
      {Color::argb(0xff0f001a), Color::argb(0xff040008), Color::argb(0xff000000)},
      {0.0f, 0.5f, 1.0f});
    c.rect({0, 0, w, h}, bg);

    // Resplandor de la singularidad central: Graves lo enciende, Golpes lo hace saltar.
    float bassBreath = 1.0f + smoothBass * 0.32f;
    const float singGrow = 1.0f + grave * 0.8f + golpe * 0.5f;
    Paint singGlow = Paint::radial(center, 40.0f * bassBreath * singGrow,
      {{0.0f, 1.0f, 0.84f, std::clamp(0.40f * f.intensity * (1.0f + grave * 0.8f + golpe * 0.8f), 0.0f, 1.0f)}, {0, 0, 0, 0}},
      {0.0f, 1.0f});
    singGlow.blend = Blend::plus;
    c.circle(center, 40.0f * bassBreath * singGrow, singGlow);

    // Resplandor local de la espiral: Golpes lo enciende, Graves lo hace respirar.
    const float bloom = std::min(0.55f, (golpe * 0.48f + grave * 0.25f) * f.glow);
    if (bloom > 0.003f) {
      const float R = minDim * 0.6f;
      Paint gl = Paint::radial(center, R,
        {Color{0.0f, 1.0f, 0.84f, bloom}, Color{0.7f, 0.3f, 1.0f, bloom * 0.45f}, Color{0.4f, 0.0f, 0.6f, 0.0f}},
        {0.0f, 0.45f, 1.0f});
      gl.blend = Blend::plus;
      c.circle(center, R, gl);
    }

    // 2. Nodos de la filotaxis áurea
    float cConst = (minDim * 0.021f) * bassBreath;
    float maxRadius = maxDim * 0.72f;
    // Divergencia: el ángulo áureo de siempre; lejos de él aparecen brazos.
    const float divergence = g.divergencia;
    const float swirl = g.torbellino;
    const float mirror = g.espejo;
    // Golpes: frente de la ola de luz; Graves: semillas más gordas.
    const float front = waveAge * maxRadius * 1.6f;
    const float band = maxDim * 0.06f;
    const float seedGrow = 1.0f + grave * 0.5f;
    // Golpes: la espiral entera salta; Graves: respira con los graves.
    const float spread = 1.0f + golpe * 0.15f + grave * 0.12f;
    const float seedPop = 1.0f + golpe * 0.3f;

    for (int n = 1; n < kNodeCount; n++) {
      float fn = float(n);
      float theta = fn * divergence + spiralAngle;
      float r = cConst * std::sqrt(fn);
      if (r > maxRadius) break;
      // Torbellino: el centro gira más rápido que el borde y la espiral se retuerce.
      if (swirl > 0.0f) {
        const float rn = std::sqrt(fn / float(kNodeCount));
        theta += swirl * (rn * 2.6f + spiralAngle * 2.0f * (1.0f - rn));
      }
      float boost = 0.0f;
      if (onda > 0.003f) {
        const float off = (r - front) / band;
        boost = onda * std::exp(-off * off);
      }
      const float rr = r * (1.0f + boost * 0.05f) * spread;

      float px = center.x + rr * std::cos(theta);
      float py = center.y + rr * std::sin(theta);

      float hue = std::fmod(fn * 0.45f + colorTime * 25.0f, 360.0f);
      if (hue < 0.0f) hue += 360.0f;
      float alpha = std::clamp((0.40f + (fn / float(kNodeCount)) * 0.60f) * f.intensity, 0.0f, 1.0f);
      float sat = 0.85f;
      // Agudos: semillas que centellean y se blanquean un instante.
      float tw = 0.0f;
      if (agudo > 0.003f) {
        tw = agudo * std::max(0.0f, std::sin(gt * 16.0f + fn * 1.7f));
        alpha = std::min(1.0f, alpha + 0.9f * tw);
        sat -= 0.7f * tw;
      }
      if (boost > 0.0f) alpha = std::min(1.0f, alpha + boost * 0.8f);
      // Golpes: todas las semillas se encienden en el golpe.
      if (golpe > 0.003f) alpha = std::min(1.0f, alpha * (1.0f + golpe * 0.8f));

      Color nodeCol = hsvToRgb(hue, sat, 1.0f, alpha);
      Paint np; np.blend = Blend::plus; np.color = nodeCol;
      float nodeRad = (1.4f + std::sqrt(fn / float(kNodeCount)) * 2.6f) * (minDim / 400.0f);
      nodeRad *= seedGrow * (1.0f + boost * 1.2f) * seedPop * (1.0f + tw * 0.5f);

      c.circle({px, py}, std::max(0.6f, nodeRad), np);

      // Girasol doble: una semilla gemela en la espiral que gira al revés.
      if (mirror > 0.0f) {
        const float back = 0.6f - theta;
        float hue2 = hue + 120.0f;
        if (hue2 >= 360.0f) hue2 -= 360.0f;
        Paint mp; mp.blend = Blend::plus;
        mp.color = hsvToRgb(hue2, sat, 1.0f, alpha * 0.7f * mirror);
        c.circle({center.x + rr * std::cos(back), center.y + rr * std::sin(back)}, std::max(0.6f, nodeRad * 0.85f), mp);
      }
    }

    // 3. Singularidad blanca en el origen: Golpes la hace saltar.
    Paint singCenter; singCenter.blend = Blend::plus;
    singCenter.color = {1.0f, 1.0f, 1.0f, std::clamp(0.95f * f.intensity, 0.0f, 1.0f)};
    c.circle(center, 3.5f * (1.0f + golpe * 1.5f), singCenter);
  }
};
''';
