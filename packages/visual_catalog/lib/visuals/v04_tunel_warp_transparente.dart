// Túnel Hiperdimensional Transparente — versión overlay sin fondo opaco.
// Música: la energía y los graves aceleran el viaje y la torsión. Pulso elige
// qué marca el ritmo: Golpes lanza un anillo de choque blanco que viene desde
// el fondo hacia el espectador, hace destellar los anillos y salta la
// singularidad en cada golpe; Graves ensancha el túnel, engruesa los anillos y
// enciende el núcleo con los graves; Agudos hace centellear los vértices.
// En cada golpe (y al ritmo de los graves) un resplandor local enciende el sujeto.
// Sin música, el túnel avanza tranquilo exactamente como siempre.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // FORMA: lados de cada anillo, de triángulo a casi un círculo.
  CreatorModifier.steps('lados', 'Lados', min: 3, max: 12, value: 8),
  // MOVIMIENTO: túnel recto o un vórtice que se retuerce hacia el fondo.
  CreatorModifier.slider('torsion', 'Torsión', min: 0, max: 2.5, value: 1),
  // MÚSICA
  CreatorModifier.choice(
    'pulso',
    'Pulso',
    options: ['Golpes', 'Graves', 'Agudos'],
  ),
  // MODO: malla completa (todas las vigas) en lugar de vigas alternas.
  CreatorModifier.toggle('malla', 'Malla completa', value: false),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Vórtice', {
    'torsion': 2.5,
    'lados': 5,
    'pulso': 'Graves',
  }),
  CreatorVariation('Hiperespacio', {
    'lados': 12,
    'malla': true,
    'torsion': 0,
    'pulso': 'Golpes',
    'speed': 1.5,
  }),
];

const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kRings = 28;
  static constexpr int kMaxSides = 12;
  static constexpr float kMaxDepth = 1400.0f;
  static constexpr float kMinDepth = 60.0f;
  float warpTravel = 0.0f;
  float twistTime = 0.0f;
  float smoothBass = 0.0f;
  float smoothEnergy = 0.0f;
  // Música: envolventes estándar y golpe (todo vale 0 sin música).
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Anillo de choque del último golpe: segundos desde que nació y su fuerza.
  float waveAge = 10.0f, wavePower = 0.0f;
  // Reloj del centelleo de los agudos (sólo se ve con música).
  double glint = 0.0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }
 public:
  void reset(uint32_t seed) override {
    (void)seed;
    warpTravel = 0.0f;
    twistTime = 0.0f;
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

    // En silencio reposa en un avance de túnel suave y contemplativo (~0.09f).
    // Con música acelera a velocidad hiperdimensional y torsión cuántica.
    float speedMult = 0.09f + smoothEnergy * 0.78f + smoothBass * 0.40f;
    warpTravel += dt * f.speed * speedMult;
    twistTime += dt * f.speed * (0.09f + smoothEnergy * 0.75f);

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
    // Cada golpe nuevo lanza un anillo de choque desde el fondo del túnel.
    waveAge = std::min(waveAge + dt, 100.0f);
    if (fresh) {
      waveAge = 0.0f;
      wavePower = hit;
    }
    glint += f.delta * f.speed;
  }
  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    auto g = glide(f);
    const float amp = f.intensity;
    // Pulso: cada opción mueve algo distinto y sus pesos funden el cambio.
    // Todo se multiplica por señales de música: sin música vale 0.
    const float golpe = g.pulso.weight(0) * std::min(kick * amp, 1.0f);
    const float onda = g.pulso.weight(0) * std::min(wavePower * amp, 1.0f) * std::exp(-waveAge * 1.5f);
    const float grave = g.pulso.weight(1) * std::min((bass * 0.8f + body * 0.3f + drive * 0.1f) * amp, 1.2f);
    const float agudo = g.pulso.weight(2) * std::min((spark + flash * 0.4f + energy * 0.1f) * amp, 1.2f);
    const float gt = float(std::fmod(glint, 1000.0));
    float w = f.width, h = f.height;
    Vec2 center{w * 0.5f, h * 0.5f};
    float minDim = std::min(w, h);

    // Resplandor del núcleo focal: Graves lo agranda y lo enciende.
    float coreKick = (1.0f + smoothBass * 0.5f);
    const float coreGrow = 1.0f + grave * 0.8f;
    Paint coreGlow = Paint::radial(center, 45.0f * coreKick * coreGrow,
      {{0.74f, 0.0f, 1.0f, std::clamp(0.48f * f.intensity * (1.0f + grave * 0.8f), 0.0f, 1.0f)}, {0, 0, 0, 0}},
      {0.0f, 1.0f});
    coreGlow.blend = Blend::plus;
    c.circle(center, 45.0f * coreKick * coreGrow, coreGlow);

    // Resplandor local del fondo del túnel: Golpes lo enciende, Graves lo hace respirar.
    const float bloom = std::min(0.55f, (golpe * 0.38f + grave * 0.2f) * f.glow);
    if (bloom > 0.003f) {
      const float R = minDim * 0.5f;
      Paint gl = Paint::radial(center, R,
        {Color{0.74f, 0.2f, 1.0f, bloom}, Color{0.2f, 0.7f, 1.0f, bloom * 0.45f}, Color{0.0f, 0.3f, 0.6f, 0.0f}},
        {0.0f, 0.45f, 1.0f});
      gl.blend = Blend::plus;
      c.circle(center, R, gl);
    }

    // Lados: 8 es el octógono de siempre.
    const int sides = std::clamp(m.lados, 3, kMaxSides);
    // Graves ensancha y engruesa el túnel; Golpes hace destellar los anillos.
    const float breathe = 1.0f + grave * 0.12f + golpe * 0.15f;
    const float thick = 1.0f + grave * 0.6f + golpe * 1.2f;
    const float flare = 1.0f + golpe * 1.0f;

    float stepZ = (kMaxDepth - kMinDepth) / float(kRings);
    float animOffset = std::fmod(warpTravel * 0.25f, 1.0f);
    if (animOffset < 0.0f) animOffset += 1.0f;
    animOffset *= stepZ;

    // Almacenar vértices para las vigas longitudinales
    std::vector<std::array<Vec2, kMaxSides>> ringVertices;
    ringVertices.reserve(kRings);
    // Agudos: vértices que centellean como estrellas.
    std::vector<Vec2> glints;
    if (agudo > 0.003f) glints.reserve(kRings * kMaxSides);

    // Dibujar anillos poligonales desde el fondo hacia el frente
    for (int i = kRings - 1; i >= 0; i--) {
      float z = kMinDepth + float(i) * stepZ - animOffset;
      if (z <= 12.0f) continue;

      float scale = 500.0f / z;
      float radius = 220.0f * scale * (minDim / 400.0f) * (1.0f + smoothBass * 0.12f) * breathe;
      float twist = (1.0f - z / kMaxDepth) * 2.8f + twistTime * 0.8f;
      // Torsión: 1 es la de siempre; 0 deja el túnel recto y 2,5 lo vuelve un vórtice.
      if (g.torsion != 1.0f) twist += (1.0f - z / kMaxDepth) * 2.8f * (g.torsion - 1.0f);

      float normDepth = std::clamp(z / kMaxDepth, 0.0f, 1.0f);
      float alpha = std::clamp((1.0f - normDepth) * 0.88f * f.intensity, 0.0f, 1.0f);
      alpha = std::min(1.0f, alpha * flare);

      // Ciclo cromático entre cian {0, 1, 0.8} y violeta/magenta {0.74, 0, 1}
      float colorPhase = std::fmod(normDepth + warpTravel * 0.15f, 1.0f);
      if (colorPhase < 0.0f) colorPhase += 1.0f;
      Color ringCol{
        std::clamp(0.0f * (1.0f - colorPhase) + 0.74f * colorPhase, 0.0f, 1.0f),
        std::clamp(1.0f * (1.0f - colorPhase) + 0.0f * colorPhase, 0.0f, 1.0f),
        std::clamp(0.8f * (1.0f - colorPhase) + 1.0f * colorPhase, 0.0f, 1.0f),
        alpha
      };
      Paint rp; rp.blend = Blend::plus; rp.color = ringCol;
      rp.strokeWidth = std::clamp(scale * 2.2f, 1.0f, 3.8f) * thick;

      Path ringPath;
      std::array<Vec2, kMaxSides> verts{};
      for (int s = 0; s < sides; s++) {
        // Fracción del giro en su propia instrucción: redondea igual que con 8 lados fijos.
        const float share = (float(s) / float(sides)) * 6.2831853f;
        float angle = share + twist;
        float vx = center.x + radius * std::cos(angle);
        float vy = center.y + radius * std::sin(angle);
        verts[s] = Vec2{vx, vy};
        if (s == 0) ringPath.moveTo(vx, vy);
        else ringPath.lineTo(vx, vy);
        if (agudo > 0.003f && std::sin(gt * 15.0f + float(i) * 1.9f + float(s) * 2.7f) > 0.0f) glints.push_back({vx, vy});
      }
      ringPath.close();
      c.path(ringPath, rp);

      ringVertices.push_back(verts);
    }

    // Golpes: un anillo de choque blanco viene del fondo hacia el espectador.
    if (onda > 0.003f) {
      const float zs = kMaxDepth - waveAge * 1800.0f;
      if (zs > 40.0f) {
        const float sc = 500.0f / zs;
        const float rr = 220.0f * sc * (minDim / 400.0f) * (1.0f + smoothBass * 0.12f) * breathe;
        const float tw = (1.0f - zs / kMaxDepth) * (2.8f * g.torsion) + twistTime * 0.8f;
        Path shock;
        for (int s = 0; s < sides; s++) {
          float angle = (float(s) / float(sides)) * 6.2831853f + tw;
          float vx = center.x + rr * std::cos(angle);
          float vy = center.y + rr * std::sin(angle);
          if (s == 0) shock.moveTo(vx, vy);
          else shock.lineTo(vx, vy);
        }
        shock.close();
        Paint sp; sp.blend = Blend::plus;
        sp.color = {0.85f, 0.95f, 1.0f, std::clamp(onda * 1.1f, 0.0f, 1.0f)};
        sp.strokeWidth = std::clamp(sc * 6.0f, 2.0f, 9.0f);
        sp.strokeJoin = 1;
        c.path(shock, sp);
      }
    }

    // 2. Vigas longitudinales de torsión conectando anillos adyacentes
    if (ringVertices.size() >= 2) {
      Paint beamPaint; beamPaint.blend = Blend::plus;
      beamPaint.strokeWidth = 1.0f;

      for (size_t r = 0; r + 1 < ringVertices.size(); r += 2) {
        const auto& cur = ringVertices[r];
        const auto& nxt = ringVertices[r + 1];
        float beamAlpha = std::clamp((0.2f + float(r) / float(ringVertices.size()) * 0.5f) * f.intensity, 0.0f, 0.65f);
        beamPaint.color = {0.0f, 0.9f, 1.0f, beamAlpha};

        Path beams;
        for (int s = 0; s < sides; s += 2) {
          beams.moveTo(cur[s].x, cur[s].y);
          beams.lineTo(nxt[s].x, nxt[s].y);
        }
        c.path(beams, beamPaint);
      }

      // Malla completa: se encienden también las vigas de anillos y lados alternos.
      if (g.malla > 0.0f) {
        Paint meshPaint; meshPaint.blend = Blend::plus;
        meshPaint.strokeWidth = 1.0f;
        for (size_t r = 0; r + 1 < ringVertices.size(); r++) {
          const auto& cur = ringVertices[r];
          const auto& nxt = ringVertices[r + 1];
          float beamAlpha = std::clamp((0.2f + float(r) / float(ringVertices.size()) * 0.5f) * f.intensity, 0.0f, 0.65f);
          meshPaint.color = {0.0f, 0.9f, 1.0f, beamAlpha * g.malla};
          Path beams;
          for (int s = 0; s < sides; s++) {
            if (r % 2 == 0 && s % 2 == 0) continue;
            beams.moveTo(cur[s].x, cur[s].y);
            beams.lineTo(nxt[s].x, nxt[s].y);
          }
          c.path(beams, meshPaint);
        }
      }
    }

    if (!glints.empty()) {
      Paint gp; gp.blend = Blend::plus;
      gp.color = {0.92f, 0.85f, 1.0f, std::clamp(agudo * 0.95f, 0.0f, 1.0f)};
      c.points(glints, 2.8f, gp);
    }

    // Singularidad central brillante: Golpes la hace saltar.
    Paint sing; sing.blend = Blend::plus;
    sing.color = {1.0f, 1.0f, 1.0f, std::clamp(0.95f * f.intensity, 0.0f, 1.0f)};
    c.circle(center, 3.6f * coreKick * (1.0f + golpe * 1.5f), sing);
  }
};
''';
