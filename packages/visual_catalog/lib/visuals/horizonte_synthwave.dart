// Horizonte Synthwave — port de la galería immersive a escena nativa.
// Sol retro con rejilla infinita y montañas de neón estilo años 80.
// Música: la energía y los graves aceleran la rejilla y los golpes encienden
// el resplandor del horizonte. Pulso elige el resto: Golpes hace latir el sol,
// enciende la rejilla y lanza una línea de luz que barre el suelo en cada
// golpe; Graves levanta las montañas, engrosa su neón y ensancha el
// horizonte despacio; Agudos hace centellear estrellas en el cielo.
// Además, cada opción de Pulso enciende un resplandor local sobre
// el sol y el horizonte, que late con la música (nunca un velo a pantalla completa).
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // FORMA: horizonte llano o cordillera alta.
  CreatorModifier.slider('montanas', 'Montañas', min: 0, max: 2, value: 1),
  // MOVIMIENTO: suelo plano o rejilla que ondula como el mar.
  CreatorModifier.slider('oleaje', 'Oleaje', min: 0, max: 1, value: 0),
  // MÚSICA
  CreatorModifier.choice(
    'pulso',
    'Pulso',
    options: ['Golpes', 'Graves', 'Agudos'],
  ),
  // ATMÓSFERA: la franja de luz del horizonte.
  CreatorModifier.slider('bruma', 'Bruma del horizonte', min: 0, max: 2.5, value: 1),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Mar de Neón', {
    'oleaje': .8,
    'montanas': .4,
    'bruma': 1.8,
    'pulso': 'Graves',
  }),
  CreatorVariation('Cordillera', {
    'montanas': 1.7,
    'bruma': .5,
    'pulso': 'Agudos',
    'speed': 1.3,
  }),
];

const nativeSource = r'''
class Visual final : public Scene {
  std::vector<float> ridge;
  float synthTime = 0.0f;
  float smoothBass = 0.0f;
  float smoothEnergy = 0.0f;
  float pulse = 0;
  // Envolventes de la música para Pulso (cero en silencio) y el último golpe.
  float bass = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0;
  double sweepAge = 100.0;
  float sweepPower = 0.0f;
  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }
  static float vhash(int x, int y) {
    uint32_t h = uint32_t(x) * 374761393u + uint32_t(y) * 668265263u;
    h = (h ^ (h >> 13)) * 1274126177u; h ^= h >> 16;
    return float(h & 0xffffu) / 65535.0f;
  }
  static float vnoise(float x, float y) {
    int xi = int(std::floor(x)), yi = int(std::floor(y));
    float xf = x - float(xi), yf = y - float(yi);
    float u = xf * xf * (3.0f - 2.0f * xf), v = yf * yf * (3.0f - 2.0f * yf);
    float a = vhash(xi, yi), b = vhash(xi + 1, yi);
    float c = vhash(xi, yi + 1), d = vhash(xi + 1, yi + 1);
    return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v;
  }
 public:
  Visual() {
    reset(0);
  }
  void reset(uint32_t seed) override {
    (void)seed;
    synthTime = 0.0f;
    smoothBass = 0.0f;
    smoothEnergy = 0.0f;
    pulse = 0;
    bass = spark = energy = slowBass = kick = flash = 0.0f;
    sweepAge = 100.0; sweepPower = 0.0f;
    ridge.resize(30);
    for (int i = 0; i < 30; i++)
      ridge[i] = (vnoise(float(i) * 0.4f, 1.0f) * 0.5f + vnoise(float(i) * 0.9f, 7.0f) * 0.5f);
  }
  void update(const Frame& f) override {
    float dt = float(f.delta);
    float targetEnergy = f.music.active ? f.music.energy : 0.0f;
    float targetBass = f.music.active ? f.music.bass : 0.0f;
    smoothEnergy += (targetEnergy - smoothEnergy) * float(1.0 - std::exp(-dt * 5.0));
    smoothBass += (targetBass - smoothBass) * float(1.0 - std::exp(-dt * 6.0));

    // En silencio reposa en un rodaje synthwave suave y relajante (~0.10f).
    // Con música acelera la perspectiva de la rejilla y los destellos del sol.
    float audioDrive = 0.10f + smoothEnergy * 0.78f + smoothBass * 0.35f;
    synthTime += dt * f.speed * audioDrive;

    if (ridge.size() != 30) {
      reset(0);
    }
    if (f.music.active) {
      for (const auto& band : f.music.events)
        for (const auto& e : band) pulse += e.strength;
    }
    pulse *= float(std::exp(-dt * 4.0));

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
    sweepAge += f.delta;
    if (fresh) { sweepAge = 0.0; sweepPower = hit; }
  }
  void render(const Frame& f, Canvas& c) const override {
    float w = f.width, h = f.height;
    float t = synthTime;
    float hz = h * 0.56f;
    float glowBoost = std::clamp((0.7f + 0.6f * smoothBass + 0.8f * pulse) * f.intensity, 0.0f, 1.0f);
    auto g = glide(f);
    const float amp = f.intensity;
    // Pulso: sus pesos reparten la reacción; todo vale cero sin música.
    const float punch = std::min(kick * amp, 1.0f) * g.pulso.weight(0);
    const float swell = std::min(bass * amp, 1.0f) * g.pulso.weight(1);
    const float glint = std::min(spark * amp, 1.0f) * g.pulso.weight(2);
    Paint sky = Paint::linear({0, 0}, {0, hz},
      {Color::argb(0xff160034), Color::argb(0xff4a0a6b), Color::argb(0xffff4d78)}, {0, 0.55f, 1.0f});
    c.rect({0, 0, w, hz}, sky);
    // Agudos: estrellas que centellean en el cielo.
    if (glint > 0.0f) {
      const int tick = int(std::fmod(f.time * 9.0, 100000.0));
      std::vector<Vec2> stars;
      for (int i = 0; i < 120; i++) {
        if (vhash(i, tick) > glint * 0.9f) continue;
        stars.push_back({vhash(i, 911) * w, vhash(i, 577) * hz * 0.85f});
      }
      if (!stars.empty()) {
        Paint st; st.blend = Blend::plus;
        st.color = {1.0f, 0.92f, 0.98f, std::clamp(0.95f * glint, 0.0f, 1.0f)};
        c.points(stars, 1.8f, st);
      }
    }
    // Golpes: el sol late con cada golpe.
    float sr = std::min(w, h) * 0.22f * (1.0f + 0.18f * punch + 0.12f * swell);
    float sunCx = w * 0.5f, sunCy = hz - sr * 0.15f;
    // Resplandor local de la música alrededor del sol (nunca a pantalla
    // completa; las montañas lo tapan por abajo): dorado y rosa en cada golpe
    // y con los graves, cian que parpadea con los agudos.
    if (punch > 0.0f || swell > 0.0f || glint > 0.0f) {
      const float auraR = sr * 2.6f;
      const float flicker = 0.55f + 0.45f * std::sin(float(f.time) * 45.0f);
      const float warm = (0.42f * punch + 0.34f * swell) * f.glow;
      const float cool = 0.28f * glint * flicker * f.glow;
      if (warm > 0.0f) {
        Paint aura = Paint::radial({sunCx, sunCy}, auraR,
          {{1.0f, 0.95f, 0.42f, std::clamp(warm, 0.0f, 1.0f)},
           {1.0f, 0.18f, 0.6f, std::clamp(warm * 0.55f, 0.0f, 1.0f)},
           {1.0f, 0.18f, 0.6f, 0.0f}}, {0.0f, 0.5f, 1.0f});
        aura.blend = Blend::plus;
        c.circle({sunCx, sunCy}, auraR, aura);
      }
      if (cool > 0.0f) {
        Paint shimmer = Paint::radial({sunCx, sunCy}, auraR,
          {{0.0f, 1.0f, 0.965f, std::clamp(cool, 0.0f, 1.0f)}, {0.0f, 1.0f, 0.965f, 0.0f}}, {0.0f, 1.0f});
        shimmer.blend = Blend::plus;
        c.circle({sunCx, sunCy}, auraR, shimmer);
      }
    }
    c.save();
    Path sunClip; sunClip.circle({sunCx, sunCy}, sr);
    c.clip(sunClip);
    Paint sun = Paint::linear({0, hz - sr * 1.3f}, {0, hz + 4.0f},
      {Color::argb(0xfffff36b), Color::argb(0xffff8a3d), Color::argb(0xffff2e9a)}, {0, 0.45f, 1.0f});
    c.rect({sunCx - sr, hz - sr * 1.3f, sr * 2.0f, sr * 2.0f}, sun);
    Paint bar; bar.color = Color::argb(0xff160034);
    float lane = sr * 0.14f;
    float off = std::fmod(t * 14.0f, lane);
    for (int i = 0; i < 9; i++) {
      float y = hz - sr * 0.9f + float(i) * lane + off;
      c.rect({sunCx - sr, y, sr * 2.0f, float(i) * 0.55f + 1.5f}, bar);
    }
    c.restore();
    // Montañas (1 = la cordillera original); Graves las levanta despacio.
    const float rise = g.montanas * (1.0f + 0.25f * swell);
    Path mtn; mtn.moveTo(0, hz);
    if (ridge.size() == 30) {
      for (int i = 0; i < 30; i++)
        mtn.lineTo(float(i) / 29.0f * w, rise == 1.0f ? hz - ridge[i] * h * 0.16f : hz - ridge[i] * h * 0.16f * rise);
    }
    mtn.lineTo(w, hz); mtn.close();
    Paint mfill; mfill.color = Color::argb(0xff0d0020);
    c.path(mtn, mfill);
    Paint mstroke; mstroke.color = {1, 0.435f, 0.847f, std::min(1.0f, 0.9f * f.intensity)};
    mstroke.strokeWidth = 1.0f;
    // Graves: el neón de las montañas se engrosa.
    if (swell > 0.0f || punch > 0.0f) mstroke.strokeWidth *= 1.0f + 1.5f * swell + 1.2f * punch;
    c.path(mtn, mstroke);
    Paint floor = Paint::linear({0, hz}, {0, h},
      {Color::argb(0xff12002b), Color::argb(0xff2a004d)});
    c.rect({0, hz, w, h - hz}, floor);
    Path grid;
    const float wave = g.oleaje;
    if (wave <= 0.0f) {
      for (int i = -9; i <= 9; i++) {
        grid.moveTo(w * 0.5f, hz);
        grid.lineTo(w * 0.5f + float(i) * w * 0.34f, h);
      }
      float speed = std::fmod(t * 0.55f, 1.0f);
      for (int i = 0; i < 16; i++) {
        float k = (float(i) + speed) / 16.0f;
        float y = hz + (h - hz) * k * k * 1.02f;
        if (y > h) continue;
        grid.moveTo(0, y); grid.lineTo(w, y);
      }
    } else {
      // Oleaje: el suelo ondula como el mar; las dos familias de líneas
      // siguen la misma ola, plana en el horizonte y alta cerca.
      const float floorH = h - hz;
      auto lift = [&](float x, float y) {
        const float depth = (y - hz) / floorH;
        return y - wave * floorH * 0.12f * depth * std::sin(x / w * 9.4f + t * 2.2f - depth * 5.0f);
      };
      for (int i = -9; i <= 9; i++) {
        const float x1 = w * 0.5f + float(i) * w * 0.34f;
        for (int s = 0; s <= 16; s++) {
          const float q = float(s) / 16.0f;
          const float x = w * 0.5f + (x1 - w * 0.5f) * q, y = hz + floorH * q;
          if (s == 0) grid.moveTo(x, lift(x, y)); else grid.lineTo(x, lift(x, y));
        }
      }
      float speed = std::fmod(t * 0.55f, 1.0f);
      for (int i = 0; i < 16; i++) {
        float k = (float(i) + speed) / 16.0f;
        float y = hz + (h - hz) * k * k * 1.02f;
        if (y > h) continue;
        for (int s = 0; s <= 24; s++) {
          const float x = w * float(s) / 24.0f;
          if (s == 0) grid.moveTo(x, lift(x, y)); else grid.lineTo(x, lift(x, y));
        }
      }
    }
    // Golpes: la rejilla se enciende con cada golpe.
    Paint gp; gp.color = {0, 1, 0.965f, std::min(1.0f, 0.75f * f.intensity + 0.5f * punch)};
    gp.strokeWidth = 1.1f;
    if (punch > 0.0f) gp.strokeWidth *= 1.0f + 1.2f * punch;
    c.path(grid, gp);
    // Golpes y Graves: el horizonte se enciende de rosa sobre el suelo.
    if (punch > 0.0f || swell > 0.0f) {
      const float glowW = w * 0.55f;
      Paint horizonGlow = Paint::radial({0.0f, 0.0f}, glowW,
        {{1.0f, 0.18f, 0.6f, std::clamp((0.38f * punch + 0.28f * swell) * f.glow, 0.0f, 1.0f)},
         {1.0f, 0.18f, 0.6f, std::clamp((0.12f * punch + 0.09f * swell) * f.glow, 0.0f, 1.0f)},
         {1.0f, 0.18f, 0.6f, 0.0f}}, {0.0f, 0.5f, 1.0f});
      horizonGlow.blend = Blend::plus;
      c.save();
      c.translate(w * 0.5f, hz);
      c.scale(1.0f, std::min(0.6f, (h - hz) / glowW));
      c.circle({0.0f, 0.0f}, glowW, horizonGlow);
      c.restore();
    }
    // Golpes: una línea de luz barre el suelo hacia el espectador.
    const float sweepFade = sweepPower * float(std::exp(-sweepAge * 2.0)) * g.pulso.weight(0);
    if (sweepFade > 0.01f) {
      const float q = std::min(1.0f, float(sweepAge) * 1.6f);
      const float y = hz + (h - hz) * q * q;
      Path line; line.moveTo(0, y); line.lineTo(w, y);
      Paint sweepGlow; sweepGlow.blend = Blend::plus;
      sweepGlow.color = {1.0f, 0.3f, 0.7f, std::clamp(0.35f * sweepFade * amp, 0.0f, 1.0f)};
      sweepGlow.strokeWidth = 4.0f + 10.0f * sweepFade;
      c.path(line, sweepGlow);
      Paint sweep; sweep.blend = Blend::plus;
      sweep.color = {1.0f, 0.85f, 0.97f, std::clamp(0.95f * sweepFade * amp, 0.0f, 1.0f)};
      sweep.strokeWidth = 2.0f + 3.0f * sweepFade;
      c.path(line, sweep);
    }
    // Bruma del horizonte (1 = la franja original); Graves la ensancha.
    const float band = 26.0f * g.bruma * (1.0f + 0.6f * swell + 0.8f * punch);
    if (band > 0.01f) {
      Paint hg = Paint::linear({0, hz - band}, {0, hz + band},
        {{1, 0.18f, 0.604f, 0}, {1, 0.47f, 0.784f, std::min(1.0f, 0.35f * glowBoost * std::min(g.bruma, 1.6f) + (0.35f * punch + 0.2f * swell) * std::min(g.bruma, 1.6f))}, {0, 1, 0.965f, 0}}, {0, 0.5f, 1.0f});
      hg.blend = Blend::plus;
      c.rect({0, hz - band, w, band * 2.0f}, hg);
    }
  }
};
''';
