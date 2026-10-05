// Matriz Oceánica 3D — un mar de malla de neón bajo un sol synthwave.
// Cielo nocturno con degradado de índigo a rosa, estrellas que titilan,
// dos cordilleras con el filo de neón y un gran sol amarillo, naranja y
// magenta cortado por franjas que bajan despacio (las franjas son huecos
// del disco: por ellos se ve el cielo). Debajo, un mar de malla cian y
// magenta en perspectiva que avanza hacia el espectador sobre un oleaje de
// varias ondas, con el reflejo del sol temblando en el agua y la bruma rosa
// del horizonte.
// Música: la energía y los graves aceleran el oleaje y el avance de la
// malla. Pulso elige qué marca el ritmo: Golpes hace saltar el sol, enciende
// el horizonte y lanza una cresta brillante que corre desde el horizonte
// hasta el espectador; Graves hincha el oleaje, engruesa la malla, agranda
// el sol y aviva su reflejo; Agudos hace titilar las estrellas y salpica el
// mar de destellos. Sin música, el mar nocturno se mece y avanza despacio.
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
  // ATMÓSFERA: de una noche limpia a una bruma rosa sobre el horizonte.
  CreatorModifier.slider('bruma', 'Bruma', min: 0, max: 1, value: .3),
  // MODO: la malla se refleja en el cielo como un túnel retro.
  CreatorModifier.toggle('espejo', 'Cielo espejo', value: false),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Túnel Retro', {
    'espejo': true,
    'oleaje': .6,
    'bruma': .1,
    'pulso': 'Golpes',
  }),
  CreatorVariation('Mar de Fondo', {
    'oleaje': 1.6,
    'cruce': .6,
    'bruma': .75,
    'pulso': 'Graves',
    'speed': 1.3,
  }),
];

const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kCols = 61;
  static constexpr int kRows = 62;
  // Malla en unidades del mundo: la cámara está a altura 1 sobre el agua.
  static constexpr float kNear = 0.3f;
  static constexpr float kDz = 0.2f;
  static constexpr float kDx = 0.25f;
  // Reloj del oleaje en doble precisión: igual a 30 y 60 FPS.
  double waveTime = 0.0;
  float smoothEnergy = 0.0f;
  float smoothBass = 0.0f;
  // Música: envolventes estándar y golpe (todo vale 0 sin música).
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Cresta del último golpe: segundos desde que nació y su fuerza.
  float waveAge = 10.0f, wavePower = 0.0f;
  // Relojes en doble precisión: avance de la malla, franjas del sol y brillo.
  double travel = 0.0, stripes = 0.0, glint = 0.0;
  // Memoria de trabajo de la malla (se rellena al dibujar).
  mutable std::vector<Vec2> proj;
  mutable std::vector<float> lift;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }
 public:
  void reset(uint32_t seed) override {
    (void)seed;
    waveTime = 0.0;
    smoothEnergy = 0.0f;
    smoothBass = 0.0f;
    bass = body = spark = energy = slowBass = kick = flash = drive = 0.0f;
    waveAge = 10.0f;
    wavePower = 0.0f;
    travel = stripes = glint = 0.0;
    proj.assign(size_t((kRows + 1) * kCols), Vec2{});
    lift.assign(size_t((kRows + 1) * kCols), 0.0f);
  }
  void update(const Frame& f) override {
    float dt = float(f.delta);
    float targetEnergy = f.music.active ? f.music.energy : 0.0f;
    float targetBass = f.music.active ? f.music.bass : 0.0f;
    smoothEnergy += (targetEnergy - smoothEnergy) * float(1.0 - std::exp(-dt * 5.0));
    smoothBass += (targetBass - smoothBass) * float(1.0 - std::exp(-dt * 6.0));

    // En silencio reposa en un suave oleaje de marea nocturna (0.10).
    // Con música acelera el tren de olas y el avance de la malla.
    float audioDrive = 0.10f + smoothEnergy * 0.78f + smoothBass * 0.35f;
    waveTime += f.delta * f.speed * double(audioDrive);
    travel += f.delta * f.speed * double(0.22f + 1.1f * (audioDrive - 0.10f));
    stripes += f.delta * f.speed * double(0.16f + 0.5f * (audioDrive - 0.10f));
    glint += f.delta * f.speed;

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
    const float w = f.width, h = f.height;
    const float cx = w * 0.5f;
    const float hz = h * 0.42f;
    // Escala de la escena: igual en un teléfono vertical que en horizontal.
    const float unit = std::min(w, h * 0.62f);
    const float sc = std::max(0.6f, unit / 390.0f);
    const float bruma = std::clamp(g.bruma, 0.0f, 1.0f);

    // 1. Cielo, estrellas, sol con franjas, montañas, bruma y reflejo (material).
    // El sol salta con cada golpe y crece con los graves (como mucho un 25 %).
    const float R = unit * 0.3f * (1.0f + golpe * 0.16f + grave * 0.09f);
    const float sunY = hz - unit * 0.3f * 0.6f;
    std::vector<float> u;
    u.reserve(24);
    u.insert(u.end(), {float(std::fmod(glint, 1000.0)), hz, R, float(std::fmod(stripes, 1000.0))});
    u.insert(u.end(), {1.0f + golpe * 0.9f + grave * 0.6f, std::clamp(f.glow, 0.0f, 2.0f), agudo,
                       1.0f + grave * 0.9f + golpe * 0.4f});
    u.insert(u.end(), {sunY, std::clamp(0.16f + 0.14f * f.detail, 0.0f, 0.5f), 1.0f + golpe * 1.1f + agudo * 0.3f, bruma});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[size_t(i)].r, f.colors[size_t(i)].g, f.colors[size_t(i)].b});
    c.material("synth_sky", {0, 0, w, h}, u);

    // 2. Proyección del mar de malla: la malla avanza hacia el espectador.
    const float F = unit * 0.95f;
    // Todas las ondas repiten cada 20π: el reloj se pliega sin saltos.
    const float wt = float(std::fmod(waveTime, 62.83185307179586));
    const float camH = 1.0f + 0.05f * std::sin(wt * 2.0f);
    const float waveBass = 1.0f + std::min(bass * amp, 1.0f) * 0.3f;
    // Altura de ola (1 = la de siempre); Graves la hincha con los graves.
    const float swell = g.oleaje * (1.0f + grave * 0.3f) * waveBass;
    const float cruce = g.cruce;
    const double steps = travel / double(kDz);
    const float rowShift = float(steps - std::floor(steps));
    const float tz = float(std::fmod(travel, 6283.185307179586));
    const float zFar = kNear + float(kRows) * kDz;
    // Golpes: la cresta corre del horizonte al espectador.
    const float crestZ = zFar - waveAge * 10.0f;
    const float limit = 0.55f * camH;
    float rowFlash[kRows + 1];
    float rowZ[kRows + 1];
    for (int r = 0; r <= kRows; r++) {
      // La fila kRows es el borde lejano fijo, donde nacen las filas nuevas.
      const float z = r == kRows ? zFar : kNear + (float(r) + 1.0f - rowShift) * kDz;
      rowZ[r] = z;
      const float off = (z - crestZ) / 0.7f;
      rowFlash[r] = onda > 0.003f ? onda * std::exp(-off * off) : 0.0f;
      const float zw = z + tz;
      const float depth = F / z;
      for (int col = 0; col < kCols; col++) {
        const float x = (float(col) - float(kCols - 1) * 0.5f) * kDx;
        // Armónicos de olas.
        float y = (0.10f * std::sin(x * 0.9f + wt * 4.0f) + 0.08f * std::cos(zw * 1.2f - wt * 4.6f) +
                   0.06f * std::sin((x + zw) * 0.6f + wt * 3.0f)) * swell;
        // Mar cruzado: dos trenes de olas cortas en diagonal que se cruzan.
        if (cruce > 0.0f) {
          y += cruce * swell * (0.05f * std::sin(x * 2.2f - zw * 1.6f + wt * 7.0f) +
                                0.035f * std::sin(-x * 1.4f - zw * 2.3f - wt * 5.5f));
        }
        // La cresta del golpe levanta la fila por la que pasa.
        y += 0.12f * rowFlash[r];
        // Las olas nunca alcanzan la cámara.
        y = limit * std::tanh(y / limit);
        const size_t k = size_t(r * kCols + col);
        lift[k] = y;
        proj[k] = Vec2{cx + x * depth, hz + (camH - y) * depth};
      }
    }
    const float logSpan = std::log(zFar / kNear);
    auto depthOf = [&](float z) { return std::clamp(std::log(z / kNear) / logSpan, 0.0f, 1.0f); };
    // Las filas nacen transparentes en el fondo; la bruma apaga las lejanas.
    auto fadeOf = [&](float z) {
      const float k = depthOf(z);
      return (1.0f - std::clamp((z - (zFar - 3.0f * kDz)) / (3.0f * kDz), 0.0f, 1.0f)) *
             (1.0f - bruma * 0.65f * std::clamp((k - 0.3f) / 0.7f, 0.0f, 1.0f));
    };
    const Color cNear = f.colors[1], cFar = f.colors[2];
    auto rowColor = [&](float k) {
      const float m = std::clamp((k - 0.15f) / 0.7f, 0.0f, 1.0f);
      return Color{cNear.r + (cFar.r - cNear.r) * m, cNear.g + (cFar.g - cNear.g) * m,
                   cNear.b + (cFar.b - cNear.b) * m, 1.0f};
    };
    const float glowK = std::clamp(f.glow, 0.0f, 2.0f);

    // Cielo espejo: la malla reflejada sobre el horizonte, más tenue.
    const float mirror = g.espejo;
    auto drawRows = [&](bool up, float strength) {
      for (int r = 0; r < kRows; r++) {
        const float z = rowZ[r];
        const float k = depthOf(z);
        const float fade = fadeOf(z);
        if (fade <= 0.002f) continue;
        Path rowPath;
        for (int col = 0; col < kCols; col++) {
          const Vec2 p = proj[size_t(r * kCols + col)];
          const float y = up ? 2.0f * hz - p.y : p.y;
          if (col == 0) rowPath.moveTo(p.x, y); else rowPath.lineTo(p.x, y);
        }
        // Golpes: toda la malla se enciende en el golpe y la cresta brilla.
        const float alpha = std::clamp(((0.95f - 0.62f * k) * (1.0f + golpe * 0.6f) + rowFlash[r] * 0.8f) * fade * strength, 0.0f, 1.0f);
        const float width = sc * (2.3f - 1.6f * k) * (1.0f + grave * 0.6f + golpe * 0.7f + rowFlash[r] * 1.2f);
        Paint glowPaint; glowPaint.blend = Blend::plus;
        glowPaint.color = rowColor(k).opacity(std::clamp(alpha * 0.2f * glowK, 0.0f, 1.0f));
        glowPaint.strokeWidth = width * (3.6f - 2.6f * k);
        glowPaint.strokeJoin = 1;
        c.path(rowPath, glowPaint);
        Paint rp; rp.blend = Blend::plus;
        rp.color = rowColor(k).opacity(alpha);
        rp.strokeWidth = width;
        rp.strokeJoin = 1;
        c.path(rowPath, rp);
      }
    };
    auto drawCols = [&](bool up, float strength) {
      // Las columnas pasan del magenta del horizonte al cian cercano.
      const float a = std::clamp((0.75f + golpe * 0.25f + grave * 0.15f) * strength, 0.0f, 1.0f);
      const float y0 = hz, y1 = up ? 2.0f * hz - h : h;
      const float farFade = 1.0f - bruma * 0.6f;
      auto ramp = [&](float k) {
        return Paint::linear({0, y0}, {0, y1},
          {cFar.opacity(0.0f), cFar.opacity(std::clamp(a * 0.35f * farFade * k, 0.0f, 1.0f)),
           rowColor(0.45f).opacity(std::clamp(a * 0.75f * k, 0.0f, 1.0f)), cNear.opacity(std::clamp(a * k, 0.0f, 1.0f))},
          {0.0f, 0.08f, 0.32f, 1.0f});
      };
      Paint glowPaint = ramp(std::clamp(0.2f * glowK, 0.0f, 1.0f));
      glowPaint.blend = Blend::plus;
      glowPaint.strokeWidth = sc * 1.3f * 3.2f * (1.0f + golpe * 0.8f + grave * 0.5f);
      Paint cp = ramp(1.0f);
      cp.blend = Blend::plus;
      cp.strokeWidth = sc * 1.3f * (1.0f + golpe * 0.8f + grave * 0.5f);
      cp.strokeJoin = 1;
      for (int col = 0; col < kCols; col++) {
        Path colPath;
        for (int r = kRows; r >= 0; r--) {
          const Vec2 p = proj[size_t(r * kCols + col)];
          const float y = up ? 2.0f * hz - p.y : p.y;
          if (r == kRows) colPath.moveTo(p.x, y); else colPath.lineTo(p.x, y);
        }
        c.path(colPath, glowPaint);
        c.path(colPath, cp);
      }
    };
    if (mirror > 0.001f) {
      drawRows(true, 0.5f * mirror);
      drawCols(true, 0.5f * mirror);
    }
    drawRows(false, 1.0f);
    drawCols(false, 1.0f);

    // Crestas iluminadas: destellos blancos donde la ola está más alta.
    std::vector<Vec2> crests;
    crests.reserve(size_t(kRows * kCols));
    const float crestLevel = limit * std::tanh(0.19f * swell / limit);
    for (int r = 0; r < kRows / 2; r++) {
      for (int col = 1; col < kCols - 1; col++) {
        const size_t k = size_t(r * kCols + col);
        const Vec2 p = proj[k];
        if (lift[k] > crestLevel && p.x > -8.0f && p.x < w + 8.0f && p.y < h + 8.0f) crests.push_back(p);
      }
    }
    Paint crestPaint; crestPaint.blend = Blend::plus;
    crestPaint.color = {1.0f, 1.0f, 1.0f, std::clamp(0.8f + golpe * 0.2f, 0.0f, 1.0f)};
    c.points(crests, sc * 1.3f * (1.0f + golpe * 0.7f), crestPaint);

    // Agudos: destellos que saltan de cresta en cresta por todo el mar cercano.
    if (agudo > 0.003f) {
      const float gt = float(std::fmod(glint, 1000.0));
      std::vector<Vec2> glints;
      glints.reserve(size_t(kRows * kCols));
      for (int r = 0; r < kRows * 2 / 3; r++) {
        for (int col = 1; col < kCols - 1; col++) {
          const Vec2 p = proj[size_t(r * kCols + col)];
          if (p.x < -8.0f || p.x > w + 8.0f || p.y > h + 8.0f) continue;
          if (std::sin(gt * 13.0f + float(r) * 1.7f + float(col) * 2.3f) > 0.35f) glints.push_back(p);
        }
      }
      Paint gp; gp.blend = Blend::plus;
      gp.color = {1.0f, 0.92f, 0.98f, std::clamp(agudo * 0.9f, 0.0f, 1.0f)};
      c.points(glints, sc * 2.4f, gp);
    }
  }
};
''';

const shaderSources = <String, String>{
  'synth_sky': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // reloj, horizonte (px), radio del sol (px), franjas
uniform vec4 uB;   // halo del sol, glow, centelleo de estrellas, reflejo
uniform vec4 uM;   // centro del sol (px), estrellas, brillo del horizonte, bruma
uniform vec3 uC0;
uniform vec3 uC1;
uniform vec3 uC2;
uniform vec3 uC3;
out vec4 fragColor;

float hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

float noise1(float x) {
  float i = floor(x);
  float f = fract(x);
  float u = f * f * (3.0 - 2.0 * f);
  return mix(hash12(vec2(i, 3.7)), hash12(vec2(i + 1.0, 3.7)), u);
}

// Perfil de una cordillera: picos agudos.
float ridge(float x) {
  float a = 1.0 - abs(noise1(x) * 2.0 - 1.0);
  float b = 1.0 - abs(noise1(x * 2.3 + 5.1) * 2.0 - 1.0);
  return a * 0.7 + b * b * 0.3;
}

void main() {
  vec2 px = FlutterFragCoord().xy;
  float W = uSize.x;
  float H = uSize.y;
  float t = uA.x;
  float hz = uA.y;
  float R = uA.z;
  float fog = uM.w;
  vec2 sunC = vec2(0.5 * W, uM.x);
  // Rosa anaranjado del horizonte.
  vec3 hot = mix(uC2, uC3, 0.35);
  vec3 col;
  if (px.y < hz) {
    // Cielo: índigo arriba, violeta y rosa encendido junto al horizonte.
    float ty = px.y / hz;
    vec3 mid = mix(uC2, uC1, 0.22) * 0.3 + uC0 * 0.5;
    col = mix(uC0, mid, smoothstep(0.0, 0.7, ty));
    float low = smoothstep(0.45, 1.0, ty);
    col = mix(col, hot * 0.75, low * low);
    // Estrellas que titilan; con Agudos centellean.
    float cs = W * 0.055;
    vec2 cell = floor(px / cs);
    float hs = hash12(cell);
    if (hs > 1.0 - uM.y) {
      vec2 sp = (cell + 0.2 + 0.6 * vec2(hash12(cell + 1.3), hash12(cell + 7.1))) * cs;
      vec2 sd = px - sp;
      float tw = 0.65 + 0.35 * sin(t * (1.3 + 2.0 * hs) + hs * 60.0);
      tw *= 1.0 + uB.z * 1.6 * max(sin(t * 9.0 + hs * 80.0), 0.0);
      float star = exp(-dot(sd, sd) / (0.7 + 1.6 * fract(hs * 13.0))) * tw;
      col += mix(vec3(1.0), uC1, 0.25) * star * (1.0 - smoothstep(0.35, 0.8, ty));
    }
    // Sol: amarillo arriba, naranja y magenta abajo.
    vec2 d = px - sunC;
    float r = length(d);
    float v = clamp((px.y - (sunC.y - R)) / (2.0 * R), 0.0, 1.0);
    vec3 sunCol = mix(mix(uC3, vec3(1.0, 0.95, 0.45), 0.6), uC3, smoothstep(0.05, 0.5, v));
    sunCol = mix(sunCol, uC2, smoothstep(0.45, 0.95, v));
    float disc = 1.0 - smoothstep(R - 1.0, R + 1.0, r);
    // Franjas: huecos dentro del disco, cada vez más anchos hacia abajo.
    float sv = (px.y - (sunC.y - 0.3 * R)) / R;
    float mask = 1.0;
    if (sv > 0.0) {
      float period = 0.13;
      float f = fract(sv / period + uA.w);
      float gap = clamp(0.06 + 0.5 * sv, 0.0, 0.85);
      float aa = 1.2 / (R * period);
      float cut = smoothstep(gap - aa, gap + aa, f) * (1.0 - smoothstep(1.0 - aa, 1.0, f));
      mask = mix(1.0, cut, smoothstep(0.0, 0.1, sv));
    }
    float sunA = disc * mask;
    // Halo del sol (también se ve por los huecos de las franjas).
    float outer = max(r - R, 0.0);
    col += mix(uC2, uC3, 0.45) * uB.x * (0.5 + 0.5 * uB.y) * (0.45 * exp(-outer / (0.2 * R)) + 0.2 * exp(-r / (1.3 * R)));
    col = mix(col, sunCol, sunA);
    // Montañas: dos cordilleras con el filo de neón, bajas en el centro.
    float xn = (px.x - 0.5 * W) / W;
    float ax = abs(xn);
    float farY = hz - W * (0.035 + 0.11 * ridge(xn * 4.0 + 2.0)) * (0.25 + 0.75 * smoothstep(0.05, 0.45, ax));
    float nearY = hz - W * (0.02 + 0.08 * ridge(xn * 6.5 + 9.0)) * (0.1 + 0.9 * smoothstep(0.18, 0.5, ax));
    vec3 farCol = mix(uC0, hot, 0.2 + 0.3 * fog) * (0.55 + 0.45 * smoothstep(farY, hz, px.y));
    col = mix(col, farCol, smoothstep(farY - 0.8, farY + 0.8, px.y));
    col += uC2 * exp(-abs(px.y - farY) / 1.4) * 0.5 * (1.0 - 0.5 * fog);
    vec3 nearCol = mix(uC0, hot, 0.05 + 0.15 * fog);
    col = mix(col, nearCol, smoothstep(nearY - 0.8, nearY + 0.8, px.y));
    col += uC1 * exp(-abs(px.y - nearY) / 1.2) * 0.55 * (1.0 - 0.5 * fog);
  } else {
    // Mar: violeta junto al horizonte y casi negro cerca.
    float dy = px.y - hz;
    float depthT = dy / max(H - hz, 1.0);
    col = mix(mix(uC0, uC2, 0.2), uC0 * 0.5, smoothstep(0.0, 0.45, depthT));
    // Reflejo del sol: barras que tiemblan bajo el sol.
    float band = sqrt(dy) * 1.6 - t * 0.6;
    float fb = fract(band);
    float bar = smoothstep(0.0, 0.18, fb) * (1.0 - smoothstep(0.45, 0.7, fb));
    float jitter = (noise1(floor(band) * 3.7 + t * 0.7) - 0.5) * R * 0.35;
    float halfW = R * mix(0.9, 0.3, smoothstep(0.0, 0.7, depthT));
    float xr = abs(px.x - 0.5 * W - jitter) / halfW;
    float refl = bar * (1.0 - smoothstep(0.55, 1.0, xr)) * exp(-depthT * 3.0) * uB.w;
    col += mix(uC3, uC2, smoothstep(0.0, 0.35, depthT)) * refl * 0.75;
  }
  // Línea y resplandor del horizonte; la bruma lo envuelve.
  float hy = abs(px.y - hz);
  col += hot * (exp(-hy / 1.6) * 0.8 + exp(-hy / (0.02 * H)) * 0.3) * uM.z;
  float fogD = (0.015 + 0.09 * fog) * H;
  col = mix(col, hot * 0.55, clamp(exp(-hy / fogD) * (0.2 + 0.6 * fog), 0.0, 1.0));
  col += (hash12(px) - 0.5) / 255.0;
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
