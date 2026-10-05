// Horizonte de Sucesos — puerto de la galería FLUX/10 al motor nativo.
// Disco de acreción en cuatro bandas de calor y dos pasadas (detrás / delante)
// para resolver el orden sin z-buffer, anillo fotónico, arco de Einstein y
// deflexión gravitatoria del campo de estrellas.
// Música: la energía y los graves aceleran el disco y lo hacen brillar. Pulso
// elige el resto: Golpes hace destellar y saltar el anillo fotónico y suelta
// una onda gravitatoria en cada golpe; Graves hincha el disco despacio y
// alarga sus estelas; Agudos hace centellear las estrellas y chispear el disco.
// Además, cada opción de Pulso enciende un resplandor local sobre
// el agujero negro, que late con la música (nunca un velo a pantalla completa).
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // FORMA: el disco visto de canto o casi de frente.
  CreatorModifier.slider('inclinacion', 'Inclinación del disco', min: .15, max: 2.5, value: 1),
  // MOVIMIENTO: órbitas limpias o materia que cae en espiral.
  CreatorModifier.slider('caida', 'Caída en espiral', min: 0, max: 1, value: 0),
  // MÚSICA
  CreatorModifier.choice(
    'pulso',
    'Pulso',
    options: ['Golpes', 'Graves', 'Agudos'],
  ),
  // ATMÓSFERA: la bruma de luz que rodea el agujero.
  CreatorModifier.slider('bruma', 'Bruma de luz', min: 0, max: 2.5, value: 1),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Filo del Disco', {
    'inclinacion': .3,
    'bruma': 1.8,
    'pulso': 'Graves',
  }),
  CreatorVariation('Remolino Cósmico', {
    'caida': 1,
    'inclinacion': 2.2,
    'pulso': 'Agudos',
    'speed': 1.4,
  }),
];

const nativeSource = r'''
class Visual final : public Scene {
  struct Part { float r, a0, spd, w; };
  struct Star { float x, y, m; };
  std::vector<Part> parts;
  std::vector<Star> stars;
  float horizonTime = 0.0f;
  float smoothEnergy = 0.0f;
  float smoothBass = 0.0f;
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
 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    parts.clear(); stars.clear();
    horizonTime = 0.0f; smoothEnergy = 0.0f; smoothBass = 0.0f;
    bass = spark = energy = slowBass = kick = flash = 0.0f;
    ringAge = 100.0; ringPower = 0.0f;
    int np = 620;
    parts.reserve(np);
    for (int i = 0; i < np; i++) {
      Part p;
      float u = rng.unit();
      p.r = 1.55f + std::pow(u, 0.62f) * 3.6f;
      p.a0 = rng.unit() * 6.2831853f;
      // Kepler: la velocidad angular cae con r^1.5 => rotación diferencial real.
      p.spd = 1.0f / (p.r * std::sqrt(p.r));
      p.w = 0.5f + rng.unit() * 2.2f;
      parts.push_back(p);
    }
    stars.reserve(320);
    for (int i = 0; i < 320; i++) {
      Star s; s.x = rng.unit(); s.y = rng.unit(); s.m = rng.unit();
      stars.push_back(s);
    }
  }
  void update(const Frame& f) override {
    float dt = float(f.delta);
    float targetEnergy = f.music.active ? f.music.energy : 0.0f;
    float targetBass = f.music.active ? f.music.bass : 0.0f;
    smoothEnergy += (targetEnergy - smoothEnergy) * float(1.0 - std::exp(-dt * 5.0));
    smoothBass += (targetBass - smoothBass) * float(1.0 - std::exp(-dt * 6.0));

    // En silencio reposa en una rotación gravitatoria lenta (~0.10f).
    // Con música acelera la rotación del disco y la deflexión relativista.
    float audioDrive = 0.10f + smoothEnergy * 0.75f + smoothBass * 0.35f;
    horizonTime += dt * f.speed * audioDrive;

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
    float t = horizonTime;
    float cx = w * 0.5f, cy = h * 0.5f;
    float rs = std::min(w, h) * 0.13f;
    float yaw = std::sin(t * 0.09f) * 0.22f * (1.0f + smoothEnergy * 0.3f);
    float squash = 0.24f + std::cos(t * 0.07f) * 0.14f;
    float boost = std::clamp((0.85f + 0.35f * smoothEnergy + 0.30f * smoothBass) * f.intensity, 0.0f, 1.0f);
    float spin = t * 0.06f * (f.reducedMotion ? 0.3f : 1.0f);
    auto g = glide(f);
    const float amp = f.intensity;
    // Pulso: sus pesos reparten la reacción; todo vale cero sin música.
    const float punch = std::min(kick * amp, 1.0f) * g.pulso.weight(0);
    const float swell = std::min(bass * amp, 1.0f) * g.pulso.weight(1);
    const float glint = std::min(spark * amp, 1.0f) * g.pulso.weight(2);
    const float fall = g.caida;
    const float haze = g.bruma;
    const uint32_t tick = uint32_t(std::floor(f.time * 12.0));
    // Inclinación del disco: de canto (menos) o casi de frente (más).
    squash *= g.inclinacion;
    Paint bg; bg.color = Color::argb(0xff030308);
    c.rect({0, 0, w, h}, bg);

    // ── Estrellas con deflexión gravitatoria ──
    std::vector<Vec2> field, twinkle;
    field.reserve(stars.size());
    for (const auto& s : stars) {
      float bx = s.x * w, by = s.y * h;
      float dx = bx - cx, dy = by - cy;
      float d = std::sqrt(dx * dx + dy * dy) + 1.0f;
      if (d < rs * 1.25f) continue; // devoradas por la sombra
      float k = 1.0f + (rs * rs * 5.2f) / (d * d);
      field.push_back({cx + dx * k, cy + dy * k});
      // Agudos: algunas estrellas centellean.
      if (glint > 0.0f && hashU(uint32_t(field.size()) * 2654435761u + tick * 40503u) < glint * 0.8f) {
        twinkle.push_back(field.back());
      }
    }
    Paint sp; sp.blend = Blend::plus;
    sp.color = {0.863f, 0.910f, 1, 0.69f * boost};
    c.points(field, 1.1f, sp);
    if (!twinkle.empty()) {
      Paint tw; tw.blend = Blend::plus;
      tw.color = {0.92f, 0.95f, 1.0f, std::clamp(0.9f * glint, 0.0f, 1.0f)};
      c.points(twinkle, 2.5f, tw);
    }

    // Resplandor local de la música alrededor del agujero (nunca a pantalla
    // completa; la sombra lo tapa por dentro): cálido en cada golpe y con los
    // graves, blanco azulado que parpadea con los agudos.
    if (punch > 0.0f || swell > 0.0f || glint > 0.0f) {
      const float auraR = rs * 4.2f * (1.0f + 0.12f * punch + 0.15f * swell);
      const float flicker = 0.55f + 0.45f * std::sin(float(f.time) * 45.0f);
      const float warm = (0.42f * punch + 0.34f * swell) * f.glow;
      const float cool = 0.28f * glint * flicker * f.glow;
      if (warm > 0.0f) {
        Paint aura = Paint::radial({cx, cy}, auraR,
          {{1.0f, 0.82f, 0.4f, std::clamp(warm, 0.0f, 1.0f)},
           {1.0f, 0.56f, 0.29f, std::clamp(warm * 0.6f, 0.0f, 1.0f)},
           {1.0f, 0.56f, 0.29f, 0.0f}}, {0.0f, 0.55f, 1.0f});
        aura.blend = Blend::plus;
        c.circle({cx, cy}, auraR, aura);
      }
      if (cool > 0.0f) {
        Paint shimmer = Paint::radial({cx, cy}, auraR,
          {{0.86f, 0.91f, 1.0f, std::clamp(cool, 0.0f, 1.0f)}, {0.86f, 0.91f, 1.0f, 0.0f}}, {0.0f, 1.0f});
        shimmer.blend = Blend::plus;
        c.circle({cx, cy}, auraR, shimmer);
      }
    }

    const uint32_t ramp[4] = {0xffc9432a, 0xffff8f4a, 0xffffd166, 0xfffff3d0};
    std::vector<Vec2> diskSparks;

    // Disco: cuatro bandas de calor, dos pasadas para el orden.
    for (int pass = 0; pass < 2; pass++) {
      for (int b = 0; b < 4; b++) {
        Path disk;
        for (size_t pi = 0; pi < parts.size(); pi++) {
          const auto& p = parts[pi];
          float heat = 1.0f - (p.r - 1.55f) / 3.6f;
          if (heat < 0.0f) heat = 0.0f; if (heat > 1.0f) heat = 1.0f;
          if (int(heat * 3.999f) != b) continue;
          float rad = p.r * rs;
          // Graves: el disco se hincha despacio.
          if (swell > 0.0f || punch > 0.0f) rad *= 1.0f + 0.14f * swell + 0.12f * punch;
          float a = p.a0 + spin * p.spd + yaw;
          float sa = std::sin(a);
          if ((sa < 0.0f ? 0 : 1) != pass) continue;
          float x = cx + std::cos(a) * rad;
          float y = cy + sa * rad * squash;
          float len = p.w * (2.2f + heat * 6.0f);
          if (swell > 0.0f || punch > 0.0f) len *= 1.0f + 0.6f * swell + 0.8f * punch;
          if (fall > 0.0f) {
            // Caída en espiral: la estela se abre hacia fuera como un brazo.
            const float l2 = len * (1.0f + 0.8f * fall);
            disk.moveTo(x + (std::sin(a) + fall * std::cos(a)) * l2,
                        y + (fall * std::sin(a) - std::cos(a)) * squash * l2);
          } else {
            disk.moveTo(x + std::sin(a) * len, y - std::cos(a) * squash * len);
          }
          disk.lineTo(x, y);
          // Agudos: chispas calientes en el disco.
          if (glint > 0.0f && hashU(uint32_t(pi) * 747796405u + tick * 2891336453u) < glint * 0.35f) {
            diskSparks.push_back({x, y});
          }
        }
        Color cc = Color::argb(ramp[b]);
        Paint dp; dp.blend = Blend::plus;
        // Graves: el disco brilla más con los graves.
        dp.color = {cc.r, cc.g, cc.b, std::min(1.0f, (0.10f + float(b) * 0.14f) * boost + 0.25f * swell + 0.3f * punch)};
        dp.strokeWidth = 0.7f + float(b) * 0.5f;
        dp.strokeCap = 1; dp.strokeJoin = 1;
        c.path(disk, dp);
      }
      if (pass == 0) {
        // ── Anillo fotónico ──
        float ringR = rs * 1.34f;
        Paint rp; rp.blend = Blend::plus;
        for (int i = 3; i >= 1; i--) {
          // Bruma de luz: el halo del anillo (1 = el original).
          rp.color = {1, 0.819f, 0.400f, std::min(1.0f, 0.051f * boost * haze)};
          rp.strokeWidth = rs * 0.16f * float(i);
          c.circle({cx, cy}, ringR * (1.0f + float(i) * 0.07f), rp);
        }
        Paint crisp; crisp.blend = Blend::plus;
        crisp.color = {1, 0.941f, 0.824f, 0.949f * boost};
        crisp.strokeWidth = std::max(1.0f, rs * 0.045f);
        // Golpes: el anillo fotónico destella y da un salto.
        if (punch > 0.0f) crisp.strokeWidth *= 1.0f + 2.0f * punch;
        c.circle({cx, cy}, ringR * (1.0f + 0.15f * punch), crisp);
        // ── Sombra del horizonte ──
        Paint shadow; shadow.color = {0, 0, 0, 1};
        c.circle({cx, cy}, rs, shadow);
      }
    }

    if (!diskSparks.empty()) {
      Paint ds; ds.blend = Blend::plus;
      ds.color = {1.0f, 0.95f, 0.85f, std::clamp(0.85f * glint, 0.0f, 1.0f)};
      c.points(diskSparks, 2.0f, ds);
    }

    // Golpes: una onda gravitatoria sale del anillo con cada golpe.
    const float waveFade = ringPower * float(std::exp(-ringAge * 2.6)) * g.pulso.weight(0);
    if (waveFade > 0.01f) {
      Paint wave; wave.blend = Blend::plus;
      wave.color = {1.0f, 0.78f, 0.45f, std::clamp(0.85f * waveFade * amp, 0.0f, 1.0f)};
      wave.strokeWidth = rs * (0.05f + 0.1f * waveFade);
      c.circle({cx, cy}, rs * 1.34f + float(ringAge) * std::min(w, h) * 0.6f, wave);
    }

    // ── Arco de Einstein: imagen lensada del disco sobre el horizonte ──
    Path arc;
    const int steps = 48;
    for (int i = 0; i <= steps; i++) {
      float a = 3.14159265f * 1.06f + float(i) / float(steps) * 3.14159265f * 0.88f;
      float x = cx + std::cos(a) * rs * 1.16f;
      float y = cy + std::sin(a) * rs * 1.16f;
      if (i == 0) arc.moveTo(x, y); else arc.lineTo(x, y);
    }
    Paint ap; ap.blend = Blend::plus;
    ap.color = {1, 0.722f, 0.361f, std::min(1.0f, 0.502f * boost + 0.45f * punch)};
    ap.strokeWidth = rs * 0.2f; ap.strokeCap = 1; ap.strokeJoin = 1;
    c.path(arc, ap);

    // Resplandor global (Bruma de luz: 0 lo apaga, 1 = el original).
    if (haze > 0.001f) {
      Paint glow = Paint::radial({cx, cy}, rs * 6.5f,
        {{1, 0.667f, 0.314f, std::min(1.0f, 0.141f * boost * haze + (0.14f * punch + 0.1f * swell) * haze)}, {0.627f, 0.314f, 1, std::min(1.0f, 0.051f * boost * haze)}, {0, 0, 0, 0}},
        {0.0f, 0.4f, 1.0f});
      glow.blend = Blend::plus;
      c.rect({0, 0, w, h}, glow);
    }
  }
};
''';
