// Hipercubo 4D Tesseract Transparente — Versión Overlay / Capa transparente.
// Proyección ortográfica y de doble perspectiva de un tesseract de 16 vértices
// y 32 aristas rotando simultáneamente en los planos XW e YZ sobre fondo transparente.
// Música: la energía y los graves aceleran el giro y la hiper-geometría
// respira con los graves. Pulso elige qué marca el ritmo: Golpes acerca de
// golpe la cuarta dimensión (el hipercubo se hincha y vuelve) y hace saltar
// los vértices en cada golpe; Graves agranda el núcleo y engruesa las aristas
// con los graves; Agudos hace centellear vértices y aristas con los agudos.
// En cada golpe (y al ritmo de los graves) un resplandor local enciende el sujeto.
// Sin música, el hipercubo gira sereno exactamente como siempre.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // FORMA: perspectiva 4D: cubo interior diminuto (hondo) o dos cubos parecidos (plano).
  CreatorModifier.slider('perspectiva', 'Perspectiva 4D', min: 1.9, max: 5, value: 2.4),
  // MÚSICA
  CreatorModifier.choice(
    'pulso',
    'Pulso',
    options: ['Golpes', 'Graves', 'Agudos'],
  ),
  // ATMÓSFERA: copias fantasma que dejan ver el giro como una estela.
  CreatorModifier.slider('estela', 'Estela', min: 0, max: 1, value: 0),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Hipercubo Plano', {
    'perspectiva': 4.6,
    'estela': .8,
    'pulso': 'Graves',
  }),
  CreatorVariation('Abismo 4D', {
    'perspectiva': 1.9,
    'estela': .45,
    'pulso': 'Golpes',
    'speed': 1.4,
  }),
];

const nativeSource = r'''
class Visual final : public Scene {
  static constexpr float kV4[16][4] = {
    {-1,-1,-1,-1}, {1,-1,-1,-1}, {1,1,-1,-1}, {-1,1,-1,-1},
    {-1,-1,1,-1},  {1,-1,1,-1},  {1,1,1,-1},  {-1,1,1,-1},
    {-1,-1,-1,1},  {1,-1,-1,1},  {1,1,-1,1},  {-1,1,-1,1},
    {-1,-1,1,1},   {1,-1,1,1},   {1,1,1,1},   {-1,1,1,1}
  };
  struct Edge { int i, j; };
  std::vector<Edge> edges;
  float angle4D = 0.0f;
  float rotTime = 0.0f;
  float smoothBass = 0.0f;
  float smoothEnergy = 0.0f;
  // Música: envolventes estándar y golpe (todo vale 0 sin música).
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Reloj del centelleo de los agudos (sólo se ve con música).
  double glint = 0.0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }
 public:
  void reset(uint32_t seed) override {
    (void)seed;
    edges.clear();
    angle4D = 0.0f;
    rotTime = 0.0f;
    smoothBass = 0.0f;
    smoothEnergy = 0.0f;
    bass = body = spark = energy = slowBass = kick = flash = drive = 0.0f;
    glint = 0.0;
    for (int i = 0; i < 16; i++) {
      for (int j = i + 1; j < 16; j++) {
        int diff = 0;
        for (int k = 0; k < 4; k++) {
          if (kV4[i][k] != kV4[j][k]) diff++;
        }
        if (diff == 1) edges.push_back({i, j});
      }
    }
  }
  void update(const Frame& f) override {
    float dt = float(f.delta);
    float targetEnergy = f.music.active ? f.music.energy : 0.0f;
    float targetBass = f.music.active ? f.music.bass : 0.0f;
    smoothBass += (targetBass - smoothBass) * float(1.0 - std::exp(-dt * 6.0));
    smoothEnergy += (targetEnergy - smoothEnergy) * float(1.0 - std::exp(-dt * 5.0));

    // En silencio reposa en una rotación 4D mística y serena (~0.08f).
    // Con música la hiper-geometría acelera sus proyecciones al ritmo.
    float audioDrive = 0.08f + smoothEnergy * 0.72f + smoothBass * 0.35f;
    angle4D += dt * f.speed * audioDrive * 0.75f;
    rotTime += dt * f.speed * audioDrive;

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
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    glint += f.delta * f.speed;
  }
  void render(const Frame& f, Canvas& c) const override {
    auto g = glide(f);
    const float amp = f.intensity;
    // Pulso: cada opción mueve algo distinto y sus pesos funden el cambio.
    // Todo se multiplica por señales de música: sin música vale 0.
    const float golpe = g.pulso.weight(0) * std::min(kick * amp, 1.0f);
    const float grave = g.pulso.weight(1) * std::min((bass * 0.8f + body * 0.3f + drive * 0.1f) * amp, 1.2f);
    const float agudo = g.pulso.weight(2) * std::min((spark + flash * 0.4f + energy * 0.1f) * amp, 1.2f);
    const float gt = float(std::fmod(glint, 1000.0));
    float w = f.width, h = f.height;
    float t = rotTime;
    Vec2 center{w * 0.5f, h * 0.5f};
    float minDim = std::min(w, h);

    // Sin fondo opaco: lienzo 100% transparente

    // 1. Núcleo sagrado resplandeciente aditivo: Graves lo agranda y lo enciende.
    float bassPulse = (1.0f + smoothBass * 0.35f);
    const float coreGrow = 1.0f + grave * 0.8f;
    Paint coreGlow = Paint::radial(center, minDim * 0.18f * bassPulse * coreGrow,
      {{0.62f, 0.31f, 0.87f, std::clamp(0.40f * f.intensity * (1.0f + grave * 0.8f + golpe * 1.0f), 0.0f, 1.0f)}, {0, 0, 0, 0}},
      {0.0f, 1.0f});
    coreGlow.blend = Blend::plus;
    c.circle(center, minDim * 0.18f * bassPulse * coreGrow, coreGlow);

    // Resplandor local alrededor del hipercubo: Golpes lo enciende, Graves lo hace respirar.
    // Agudos: el resplandor titila con los agudos.
    const float bloom = std::min(0.6f, (golpe * 0.6f + grave * 0.3f + agudo * 0.15f * (0.6f + 0.4f * std::sin(gt * 23.0f))) * f.glow);
    if (bloom > 0.003f) {
      const float R = minDim * 0.6f;
      Paint gl = Paint::radial(center, R,
        {Color{0.2f, 1.0f, 0.9f, bloom}, Color{0.62f, 0.31f, 0.87f, bloom * 0.7f}, Color{0.3f, 0.1f, 0.5f, 0.0f}},
        {0.0f, 0.45f, 1.0f});
      gl.blend = Blend::plus;
      c.circle(center, R, gl);
    }

    float cosA = std::cos(angle4D), sinA = std::sin(angle4D);
    float cosB = std::cos(angle4D * 0.7f), sinB = std::sin(angle4D * 0.7f);

    float rotX = 0.35f + std::sin(t * 0.25f) * 0.15f;
    float rotY = t * 0.30f;
    float cosX = std::cos(rotX), sinX = std::sin(rotX);
    float cosY = std::cos(rotY), sinY = std::sin(rotY);

    // Perspectiva 4D: 2,4 es la de siempre; el cubo exterior conserva su tamaño.
    const float distance4D = g.perspectiva;
    const float fit = (distance4D - 1.4142f) / (2.4f - 1.4142f);
    // Golpes: la cuarta dimensión se acerca de golpe y el hipercubo se hincha.
    const float near4D = distance4D - golpe * 0.15f * (distance4D - 1.4142f);
    const float distance3D = 3.6f;
    // Graves: el hipercubo respira con los graves.
    float scale = minDim * 0.42f * bassPulse * fit * (1.0f + grave * 0.12f);

    Vec2 projected[16];
    float depths[16];

    for (int i = 0; i < 16; i++) {
      float px = kV4[i][0], py = kV4[i][1], pz = kV4[i][2], pw = kV4[i][3];

      // Rotación 4D en planos XW e YZ
      float x1 = px * cosA - pw * sinA;
      float w1 = px * sinA + pw * cosA;

      float y1 = py * cosB - pz * sinB;
      float z1 = py * sinB + pz * cosB;

      // Proyección perspectiva 4D -> 3D
      float f4D = 1.0f / (near4D - w1);
      float x3 = x1 * f4D;
      float y3 = y1 * f4D;
      float z3 = z1 * f4D;

      // Rotación 3D (pitch & yaw continuos)
      float y3Rot = y3 * cosX - z3 * sinX;
      float z3Rot1 = y3 * sinX + z3 * cosX;

      float x3Rot = x3 * cosY + z3Rot1 * sinY;
      float z3Rot = -x3 * sinY + z3Rot1 * cosY;

      // Proyección perspectiva 3D -> 2D
      float f3D = 1.0f / (distance3D - z3Rot);
      float x2 = center.x + x3Rot * f3D * scale;
      float y2 = center.y + y3Rot * f3D * scale;

      projected[i] = Vec2{x2, y2};
      depths[i] = z3Rot;
    }

    // Estela: copias fantasma en posiciones anteriores del giro, cada vez más tenues.
    if (g.estela > 0.0f) {
      auto ghost = [&](float a4, float tt, Vec2* out) {
        const float ca = std::cos(a4), sa = std::sin(a4);
        const float cb = std::cos(a4 * 0.7f), sb = std::sin(a4 * 0.7f);
        const float rx = 0.35f + std::sin(tt * 0.25f) * 0.15f, ry = tt * 0.30f;
        const float cx = std::cos(rx), sx = std::sin(rx), cy = std::cos(ry), sy = std::sin(ry);
        for (int i = 0; i < 16; i++) {
          const float px = kV4[i][0], py = kV4[i][1], pz = kV4[i][2], pw = kV4[i][3];
          const float x1 = px * ca - pw * sa, w1 = px * sa + pw * ca;
          const float y1 = py * cb - pz * sb, z1 = py * sb + pz * cb;
          const float f4 = 1.0f / (near4D - w1);
          const float x3 = x1 * f4, y3 = y1 * f4, z3 = z1 * f4;
          const float yr = y3 * cx - z3 * sx, zr1 = y3 * sx + z3 * cx;
          const float xr = x3 * cy + zr1 * sy, zr = -x3 * sy + zr1 * cy;
          const float f3 = 1.0f / (distance3D - zr);
          out[i] = Vec2{center.x + xr * f3 * scale, center.y + yr * f3 * scale};
        }
      };
      const int ghosts = 6;
      for (int k = ghosts; k >= 1; k--) {
        const float lag = float(k) * 0.13f * (0.35f + 0.65f * g.estela);
        Vec2 gp[16];
        ghost(angle4D - lag * 0.75f, t - lag, gp);
        Path trail;
        for (const auto& e : edges) {
          trail.moveTo(gp[e.i].x, gp[e.i].y);
          trail.lineTo(gp[e.j].x, gp[e.j].y);
        }
        const float fade = 1.0f - float(k) / float(ghosts + 1);
        Paint tp; tp.blend = Blend::plus;
        // De cian (la copia más cercana) a violeta (la más lejana).
        tp.color = {0.62f * (1.0f - fade), 0.31f + 0.69f * fade, 0.87f + 0.01f * fade,
                    std::clamp(g.estela * 0.65f * fade * f.intensity, 0.0f, 1.0f)};
        tp.strokeWidth = 1.6f;
        c.path(trail, tp);
      }
    }

    // Golpes hace destellar las aristas; Graves las engruesa.
    const float edgeLift = 1.0f + golpe * 1.0f;
    const float edgeThick = 1.0f + grave * 0.6f + golpe * 1.3f;

    // 2. Renderizar 32 aristas del tesseract con iluminación por profundidad
    for (const auto& e : edges) {
      Vec2 p1 = projected[e.i];
      Vec2 p2 = projected[e.j];
      float avgZ = (depths[e.i] + depths[e.j]) * 0.5f;
      float depthNorm = std::clamp((avgZ + 1.2f) / 2.4f, 0.0f, 1.0f);

      // Color lerp: cian brillante {0, 1, 0.88} en primer plano -> magenta neón {1, 0, 0.5} al fondo
      Color col{
        0.0f * (1.0f - depthNorm) + 1.0f * depthNorm,
        1.0f * (1.0f - depthNorm) + 0.0f * depthNorm,
        0.88f * (1.0f - depthNorm) + 0.5f * depthNorm,
        std::clamp((0.35f + (1.0f - depthNorm) * 0.65f) * f.intensity * edgeLift, 0.0f, 1.0f)
      };

      Paint ep; ep.blend = Blend::plus; ep.color = col;
      ep.strokeWidth = std::clamp(1.2f + (1.0f - depthNorm) * 2.0f, 0.8f, 3.2f) * edgeThick;

      Path edgePath;
      edgePath.moveTo(p1.x, p1.y);
      edgePath.lineTo(p2.x, p2.y);
      c.path(edgePath, ep);
    }

    // Agudos: chispas que saltan por el centro de las aristas.
    if (agudo > 0.003f) {
      std::vector<Vec2> glints;
      glints.reserve(edges.size());
      for (size_t k = 0; k < edges.size(); k++) {
        if (std::sin(gt * 14.0f + float(k) * 2.3f) > -0.3f) {
          const Vec2 a = projected[edges[k].i], b = projected[edges[k].j];
          glints.push_back({(a.x + b.x) * 0.5f, (a.y + b.y) * 0.5f});
        }
      }
      Paint gp; gp.blend = Blend::plus;
      gp.color = {1.0f, 0.85f, 1.0f, std::clamp(agudo * 0.95f, 0.0f, 1.0f)};
      c.points(glints, 2.2f, gp);
    }

    // 3. Renderizar los 16 vértices cuatridimensionales
    for (int i = 0; i < 16; i++) {
      Vec2 pt = projected[i];
      float z = depths[i];
      float depthNorm = std::clamp((z + 1.2f) / 2.4f, 0.0f, 1.0f);
      float rad = std::clamp(2.0f + (1.0f - depthNorm) * 3.5f, 1.5f, 5.5f);
      // Golpes: los vértices saltan; Agudos: centellean cada uno a su ritmo.
      rad *= 1.0f + golpe * 0.5f;
      float twinkle = 0.0f;
      if (agudo > 0.003f) twinkle = agudo * std::max(0.0f, std::sin(gt * 16.0f + float(i) * 2.1f));

      // Halo del vértice
      Paint vHalo; vHalo.blend = Blend::plus;
      vHalo.color = {0.0f, 1.0f, 0.88f, std::clamp(0.40f * f.intensity + golpe * 0.5f + twinkle * 0.6f, 0.0f, 1.0f)};
      c.circle(pt, rad * 2.0f, vHalo);

      // Núcleo blanco del vértice
      Paint vCore; vCore.blend = Blend::plus;
      vCore.color = {1.0f, 1.0f, 1.0f, std::clamp(0.92f * f.intensity, 0.0f, 1.0f)};
      c.circle(pt, rad * (1.0f + twinkle * 0.8f), vCore);
    }
  }
};
''';
