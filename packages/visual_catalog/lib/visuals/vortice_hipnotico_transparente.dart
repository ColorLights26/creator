// Vórtice Hipnótico Transparente — versión overlay sin fondo opaco.
// La música ya aceleraba el giro y avivaba los anillos con los graves;
// Pulso decide qué más se ve: con Golpes los anillos saltan hacia fuera, se
// engrosan y se encienden sobre un resplandor violeta en cada golpe; con
// Graves crecen, se ondulan como pétalos y el centro respira con su halo; con
// Agudos los bordes tiemblan y parpadean con los agudos. Sin música se ve
// igual que siempre.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // FORMA: lados de cada anillo, de triángulos a casi círculos.
  CreatorModifier.steps('lados', 'Lados', min: 3, max: 12, value: 6),
  // MOVIMIENTO: túnel recto o espiral muy retorcida.
  CreatorModifier.slider('torsion', 'Torsión', min: 0, max: 3, value: 1),
  // MÚSICA
  CreatorModifier.choice(
    'pulso',
    'Pulso',
    options: ['Golpes', 'Graves', 'Agudos'],
  ),
  // ATMÓSFERA: un halo de neón alrededor de cada anillo.
  CreatorModifier.slider('halo', 'Halo', min: 0, max: 1, value: 0),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Mandala', {
    'lados': 12,
    'torsion': 0,
    'halo': .6,
    'pulso': 'Graves',
  }),
  CreatorVariation('Espiral Triangular', {
    'lados': 3,
    'torsion': 2.5,
    'pulso': 'Golpes',
    'speed': 1.3,
  }),
];

const nativeSource = r'''
class Visual final : public Scene {
  float vortexTime = 0.0f;
  float spin = 0.0f;
  float smoothBass = 0.0f;
  float smoothEnergy = 0.0f;
  float smoothSpark = 0.0f;
  // Música estándar: envolventes y golpe corto (valen 0 sin música).
  float bass = 0, body = 0, spark = 0, energy = 0, drive = 0, slowBass = 0, kick = 0, flash = 0;
  // Reloj propio para el temblor de los agudos.
  double clock = 0;
  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }
 public:
  void reset(uint32_t seed) override {
    (void)seed;
    vortexTime = 0.0f;
    spin = 0.0f;
    smoothBass = 0.0f;
    smoothEnergy = 0.0f;
    smoothSpark = 0.0f;
    bass = body = spark = energy = drive = slowBass = kick = flash = 0;
    clock = 0;
  }
  void update(const Frame& f) override {
    float dt = float(f.delta);
    float targetEnergy = f.music.active ? f.music.energy : 0.0f;
    float targetBass = f.music.active ? f.music.bass : 0.0f;
    float targetSpark = f.music.active ? f.music.spark : 0.0f;
    smoothBass += (targetBass - smoothBass) * float(1.0 - std::exp(-dt * 6.0));
    smoothEnergy += (targetEnergy - smoothEnergy) * float(1.0 - std::exp(-dt * 5.0));
    smoothSpark += (targetSpark - smoothSpark) * float(1.0 - std::exp(-dt * 15.0));

    // En silencio reposa en un giro hipnótico pausado (~0.10f).
    // Con música acelera la absorción vórtice y los cambios de tono.
    float audioDrive = 0.10f + smoothEnergy * 0.75f + smoothBass * 0.35f;
    vortexTime += dt * f.speed * audioDrive;
    spin += dt * f.speed * audioDrive * (f.reducedMotion ? 0.15f : 0.35f);

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
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    clock += f.delta;
  }
  void render(const Frame& f, Canvas& c) const override {
    auto gl = glide(f);
    const float level = f.intensity;
    // Pulso: cada opción mueve algo distinto y sus pesos mezclan las opciones.
    const float golpe = gl.pulso.weight(0) * std::min(kick * level, 1.0f);
    const float graves = gl.pulso.weight(1) * std::min(bass * level, 1.0f);
    const float agudos = gl.pulso.weight(2) * std::min(spark * level, 1.0f);
    const float tick = float(std::fmod(clock, 1000.0));
    float w = f.width, h = f.height;
    float t = vortexTime;
    float cx = w * 0.5f, cy = h * 0.5f;
    float maxR = std::max(w, h) * 0.62f;
    float boost = std::clamp((0.75f + 0.5f * smoothBass) * f.intensity, 0.0f, 1.0f);
    // Lados se desliza: con 6.4 lados el último tramo crece poco a poco.
    const float sides = gl.lados;
    const int verts = int(std::ceil(sides - 0.001f));
    // Torsión: 0 alinea los anillos en un túnel recto; 1 es el original.
    const float twist = gl.torsion;
    const float halo = std::clamp(gl.halo, 0.0f, 1.0f);
    for (int i = 0; i < 42; i++) {
      float z = std::fmod(float(i) / 42.0f + t * 0.16f, 1.0f);
      z = z * z;
      // Golpes: cada golpe empuja los anillos un 15% hacia fuera; Graves, un 12%.
      float rad = (z * maxR + 6.0f) * (1.0f + golpe * 0.15f + graves * 0.12f);
      float rot = z * 2.2f * twist + spin;
      // Graves: los anillos se ondulan como pétalos con los graves.
      float wob = std::sin(t * 0.8f + float(i) * 0.3f) * 0.12f * (1.0f + graves * 1.2f);
      float a = std::min(1.0f, z * 2.4f) * (1.0f - z * 0.75f) * 0.95f;
      float hue = std::fmod(float(i) * 6.0f + t * 44.0f, 360.0f) / 60.0f;
      int seg = int(hue) % 6;
      float fr = hue - std::floor(hue);
      const float v = 0.92f;
      float q = v * (1.0f - fr), u = v * fr;
      float r = 0, g = 0, b = 0;
      if (seg == 0) { r = v; g = u; }
      else if (seg == 1) { r = q; g = v; }
      else if (seg == 2) { g = v; b = u; }
      else if (seg == 3) { g = q; b = v; }
      else if (seg == 4) { b = v; r = u; }
      else { r = v; b = q; }
      Path hex;
      for (int s = 0; s <= verts; s++) {
        float ang = std::min(float(s) / sides, 1.0f) * 6.2831853f + rot;
        float rr = rad * (1.0f + std::sin(ang * 3.0f + t) * wob);
        // Agudos: el borde tiembla fino con los agudos.
        if (agudos > 0.001f) rr += std::sin(float(s) * 13.1f + tick * 47.0f + float(i)) * agudos * (2.0f + rad * 0.02f);
        float x = cx + std::cos(ang) * rr, y = cy + std::sin(ang) * rr;
        if (s == 0) hex.moveTo(x, y); else hex.lineTo(x, y);
      }
      hex.close();
      Paint p; p.blend = Blend::plus;
      // Agudos: cada anillo parpadea a su ritmo.
      const float flicker = 1.0f + agudos * 0.8f * std::sin(tick * 31.0f + float(i) * 2.7f) + golpe * 0.8f;
      p.color = {r, g, b, std::min(1.0f, a * boost * flicker)};
      // Golpes: el trazo se engrosa en cada golpe (×2,3); Graves, ×1,6.
      p.strokeWidth = (1.0f + z * 3.5f) * (1.0f + golpe * 1.3f + graves * 0.6f);
      if (halo > 0.001f) {
        // Halo: un trazo ancho y tenue detrás de cada anillo.
        Paint ring = p;
        ring.strokeWidth = p.strokeWidth * (3.0f + halo * 5.0f);
        ring.color.a = std::min(1.0f, a * boost * 0.16f * halo);
        c.path(hex, ring);
      }
      c.path(hex, p);
    }
    // Graves: el centro luminoso respira hasta un 20% más grande.
    Paint core = Paint::radial({cx, cy}, std::min(w, h) * 0.3f * (1.0f + graves * 0.2f),
      {{1, 1, 1, (0.85f + 0.15f * f.music.spark) * boost}, {0.667f, 0.353f, 1, 0.35f * boost},
       {0, 0, 0, 0}}, {0.0f, 0.25f, 1.0f});
    core.blend = Blend::plus;
    c.circle({cx, cy}, std::min(w, h) * 0.3f * (1.0f + graves * 0.2f), core);
    const float burst = std::min(1.0f, (0.42f * golpe + 0.25f * graves) * f.glow);
    if (burst > 0.001f) {
      // Golpes y Graves: un resplandor violeta local alrededor del centro.
      const float reach = std::min(w, h) * 0.65f;
      Paint light = Paint::radial({cx, cy}, reach,
        {{0.9f, 0.55f, 1, burst}, {0.6f, 0.35f, 1, burst * 0.4f}, {0.3f, 0.2f, 1, 0}}, {0, 0.4f, 1.0f});
      light.blend = Blend::plus;
      c.circle({cx, cy}, reach, light);
    }
  }
};
''';
