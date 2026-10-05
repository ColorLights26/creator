// Confeti — capa transparente de fiesta para poner encima de otro visual.
// Dos cañones en las esquinas de abajo disparan ráfagas de papelitos que
// suben, se frenan con el aire y caen girando. Cada papelito es un
// rectángulo, una tira o una lentejuela que da vueltas en 3D: se estrecha al
// ponerse de canto y muestra su cara trasera más oscura. Con cada golpe
// dispara un cañón (alternando), en los golpes fuertes disparan los dos y
// estalla otro puñado en el centro, y la energía hace llover confeti desde
// arriba. Sin música hay una ráfaga cada pocos segundos. El fondo es
// transparente: sólo se ve el confeti. El vuelo cambia cómo cae: aleteando,
// atrapado en un remolino en el centro o barrido por ráfagas de viento. Los
// seis colores salen de la paleta: sus tres acentos y los tonos intermedios.
// Pulso elige qué más hace la música: en Golpes cada golpe dispara una
// ráfaga mucho más grande con un estallido extra en el centro, un fogonazo
// de luz sale de cada cañón y de cada estallido, y los papelitos dan un
// salto de tamaño y brillo; en Graves los graves soplan desde abajo con un
// resplandor, el confeti flota y se hincha con ellos; en Agudos muchos
// papelitos destellan como lentejuelas con los agudos.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.slider('cantidad', 'Cantidad', min: .3, max: 2, value: 1),
  CreatorModifier.slider('tamano', 'Tamaño', min: .5, max: 2, value: 1),
  // MOVIMIENTO: el carácter de la caída.
  CreatorModifier.choice('vuelo', 'Vuelo', options: ['Aleteo', 'Remolino', 'Viento']),
  CreatorModifier.toggle('lluvia', 'Lluvia desde arriba', value: true),
  // MÚSICA: qué parte de la fiesta reacciona.
  CreatorModifier.choice('pulso', 'Pulso', options: ['Golpes', 'Graves', 'Agudos']),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Gran Fiesta', {
    'cantidad': 1.7,
    'tamano': 1.2,
    'vuelo': 'Viento',
    'pulso': 'Golpes',
  }),
  CreatorVariation('Lentejuelas', {
    'tamano': .7,
    'vuelo': 'Remolino',
    'lluvia': false,
    'pulso': 'Agudos',
  }),
];

const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kMax = 900;
  static constexpr double kStep = 1.0 / 60.0;
  struct Piece { float x, y, px, py, vx, vy, angle, spin, flip, flipSpeed, w, h; uint8_t color, shape; };
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double sim = 0, nextIdle = 0.3, rainAcc = 0;
  int64_t steps = 0;
  int idleCount = 0, side = 0;
  int pendingLeft = 0, pendingRight = 0, pendingCenter = 0;
  // Fogonazos de Golpes: edad del último disparo de cada cañón y del último
  // estallido, su fuerza y dónde estalló.
  double leftAge = 100, rightAge = 100, popAge = 100;
  float burstPow = 0, popX = 0, popY = 0;
  float width = 1, height = 1;
  Random rng{1};
  std::vector<Piece> pieces;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }
  static float hashU(uint32_t x) {
    x ^= x >> 16; x *= 0x7feb352dU; x ^= x >> 15; x *= 0x846ca68bU; x ^= x >> 16;
    return float(x & 0xffffffu) / 16777216.0f;
  }

  // El tono intermedio de dos colores por el arco corto del círculo de tonos,
  // con la saturación media y el valor del más luminoso: rojo y amarillo dan
  // naranja, amarillo y azul dan verde.
  static Color between(const Color& a, const Color& b) {
    auto hsv = [](const Color& c, float& h, float& s, float& v) {
      float hi = std::max({c.r, c.g, c.b}), lo = std::min({c.r, c.g, c.b}), d = hi - lo;
      v = hi;
      s = hi > 1e-5f ? d / hi : 0.0f;
      h = 0.0f;
      if (d > 1e-5f) {
        if (hi == c.r) h = (c.g - c.b) / d;
        else if (hi == c.g) h = 2.0f + (c.b - c.r) / d;
        else h = 4.0f + (c.r - c.g) / d;
        h /= 6.0f;
        if (h < 0.0f) h += 1.0f;
      }
    };
    float ha, sa, va, hb, sb, vb;
    hsv(a, ha, sa, va);
    hsv(b, hb, sb, vb);
    if (sa < 0.05f) ha = hb;
    if (sb < 0.05f) hb = ha;
    float dh = hb - ha;
    if (dh > 0.5f) dh -= 1.0f;
    if (dh < -0.5f) dh += 1.0f;
    float h = ha + dh * 0.5f;
    h -= std::floor(h);
    float s = 0.5f * (sa + sb), v = std::max(va, vb);
    auto ch = [&](float n) {
      float k = std::fmod(n + h * 6.0f, 6.0f);
      return std::clamp(v - v * s * std::clamp(std::min(k, 4.0f - k), 0.0f, 1.0f), 0.0f, 1.0f);
    };
    return Color{ch(5.0f), ch(3.0f), ch(1.0f), 1.0f};
  }

  void spawn(float x, float y, float vx, float vy, float sizeMul) {
    if (int(pieces.size()) >= kMax) return;
    float s = std::min(width, height);
    Piece p;
    p.x = p.px = x;
    p.y = p.py = y;
    p.vx = vx;
    p.vy = vy;
    p.angle = rng.unit() * 6.2831853f;
    p.spin = (rng.unit() - 0.5f) * 9.0f;
    p.flip = rng.unit() * 6.2831853f;
    p.flipSpeed = 4.0f + 9.0f * rng.unit();
    p.shape = uint8_t(std::min(int(rng.unit() * 3.0f), 2));
    float base = s * 0.012f * sizeMul * (0.7f + 0.6f * rng.unit());
    p.w = p.shape == 1 ? base * 0.45f : base;
    p.h = p.shape == 1 ? base * 2.6f : (p.shape == 2 ? base : base * 1.5f);
    p.color = uint8_t(std::min(int(rng.unit() * 6.0f), 5));
    pieces.push_back(p);
  }

  void cannon(bool left, int count, float sizeMul) {
    float s = std::min(width, height);
    for (int i = 0; i < count; i++) {
      float a = (left ? -1.05f : -2.09f) + (rng.unit() - 0.5f) * 0.55f;
      float speed = s * (1.9f + 1.4f * rng.unit());
      spawn(left ? 0.0f : width, height * 1.01f, std::cos(a) * speed, std::sin(a) * speed, sizeMul);
    }
  }

  void pop(int count, float sizeMul) {
    float s = std::min(width, height);
    float cx = width * (0.3f + 0.4f * rng.unit()), cy = height * (0.3f + 0.25f * rng.unit());
    popX = cx;
    popY = cy;
    for (int i = 0; i < count; i++) {
      float a = rng.unit() * 6.2831853f;
      float speed = s * (0.4f + 1.3f * rng.unit());
      spawn(cx, cy, std::cos(a) * speed, std::sin(a) * speed - s * 0.5f, sizeMul);
    }
  }

  // [flutter], [swirl] y [wind] son los pesos de Vuelo (suman 1); [lift], el
  // soplo de los graves (cero sin música).
  void step(float rainRate, float amount, float sizeMul, bool rain, float flutter, float swirl, float wind, float lift) {
    float s = std::min(width, height);
    float dt = float(kStep);
    double t = double(steps) * kStep;
    // Sin música: ráfagas a su hora exacta, alternando cañones y estallidos.
    if (t >= nextIdle) {
      int kind = idleCount % 4;
      int n = int(55.0f * amount);
      if (kind == 0) cannon(true, n, sizeMul);
      if (kind == 1) cannon(false, n, sizeMul);
      if (kind == 2) { cannon(true, n / 2, sizeMul); cannon(false, n / 2, sizeMul); }
      if (kind == 3) pop(n, sizeMul);
      idleCount++;
      nextIdle += 3.2;
    }
    if (pendingLeft > 0) { cannon(true, pendingLeft, sizeMul); pendingLeft = 0; }
    if (pendingRight > 0) { cannon(false, pendingRight, sizeMul); pendingRight = 0; }
    if (pendingCenter > 0) { pop(pendingCenter, sizeMul); pendingCenter = 0; }
    if (rain) {
      rainAcc += double(rainRate) * kStep;
      while (rainAcc >= 1.0) {
        rainAcc -= 1.0;
        spawn(rng.unit() * width, -s * 0.03f, (rng.unit() - 0.5f) * s * 0.2f, s * 0.15f, sizeMul);
      }
    }
    // En el remolino flotan: la gravedad pesa menos.
    const float g = s * 1.35f * (1.0f - 0.55f * swirl);
    const float drag = 2.4f;
    float k = std::exp(-drag * dt);
    const float cx = width * 0.5f, cy = height * 0.45f;
    // Viento: ráfagas que cambian de lado despacio y ondulan con la altura.
    const float gust = float(std::sin(t * 0.45));
    for (auto& p : pieces) {
      p.px = p.x;
      p.py = p.y;
      // Los papelitos planean: más freno cuanto más de cara caen.
      float face = std::fabs(std::cos(p.flip));
      p.vy += g * dt;
      // Graves: un soplo desde abajo hace flotar el confeti.
      if (lift > 0.0f) p.vy -= lift * dt;
      float kk = k * (1.0f - 0.02f * face);
      p.vx *= kk;
      p.vy *= kk;
      // Aleteo: cada papelito se mece de lado según cómo gira.
      p.vx += std::sin(p.flip * 0.5f + p.angle) * s * 0.35f * dt * (flutter + 0.3f * wind);
      if (swirl > 0.0f) {
        // Remolino: empuje tangencial alrededor del centro (máximo a 0,35 del
        // lado) y un tirón hacia dentro que los mantiene girando.
        float dx = p.x - cx, dy = p.y - cy;
        float r = std::sqrt(dx * dx + dy * dy + 1.0f);
        float q = r / (0.35f * s);
        float push = s * 3.4f * q / (1.0f + q * q) * swirl;
        float pull = s * 0.9f * std::min(q, 1.5f) * swirl;
        p.vx += (-dy / r * push - dx / r * pull) * dt;
        p.vy += (dx / r * push - dy / r * pull) * dt;
      }
      if (wind > 0.0f) {
        float blow = s * (1.25f * gust + 0.7f * std::sin(float(t) * 1.7f + p.y / s * 3.0f));
        p.vx += blow * wind * dt;
      }
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.angle += p.spin * dt * (1.0f + wind);
      p.flip += p.flipSpeed * dt * (1.0f + 0.8f * wind);
    }
    pieces.erase(std::remove_if(pieces.begin(), pieces.end(), [&](const Piece& p) {
      return p.y > height + s * 0.08f || p.x < -s * 0.3f || p.x > width + s * 0.3f;
    }), pieces.end());
  }

 public:
  void reset(uint32_t seed) override {
    rng = Random(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    sim = 0;
    steps = 0;
    nextIdle = 0.3;
    rainAcc = 0;
    idleCount = 0;
    side = 0;
    pendingLeft = pendingRight = pendingCenter = 0;
    leftAge = rightAge = popAge = 100;
    burstPow = popX = popY = 0;
    pieces.clear();
    pieces.reserve(kMax + 64);
  }

  void update(const Frame& f) override {
    auto m = modifiers(f);
    float dt = float(f.delta);
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
    float onset = std::clamp((mu.bass - slowBass - 0.15f) * 2.5f, 0.0f, 1.0f);
    slowBass = follow(slowBass, mu.bass, 3.0f, 3.0f, dt);
    hit = std::min(std::max(hit, onset), 1.0f);
    bool beat = hit > kick + 0.2f;
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    width = f.width;
    height = f.height;
    leftAge += f.delta;
    rightAge += f.delta;
    popAge += f.delta;
    if (beat) {
      int n = int((14.0f + 30.0f * hit) * m.cantidad);
      burstPow = hit;
      // Golpes: ráfagas mucho más grandes y un estallido extra en el centro.
      if (m.pulso == 0) {
        n = int(float(n) * (1.0f + 0.8f * std::min(f.intensity, 2.0f)));
        if (hit <= 0.75f) {
          pendingCenter += n / 2;
          popAge = 0.0;
        }
      }
      if (hit > 0.75f) {
        pendingLeft += n;
        pendingRight += n;
        pendingCenter += n;
        leftAge = rightAge = popAge = 0.0;
      } else if ((side++ & 1) == 0) {
        pendingLeft += n;
        leftAge = 0.0;
      } else {
        pendingRight += n;
        rightAge = 0.0;
      }
    }
    if (fl > 0.5f) pendingCenter += int(30.0f * m.cantidad);
    // Con música las ráfagas las marcan los golpes, no el reloj.
    if (mu.active) nextIdle = double(steps) * kStep + 3.2;
    sim += f.delta * f.speed;
    int64_t target = int64_t(std::floor(sim / kStep + 1e-6));
    if (target - steps > 30) steps = target - 30;
    float rainRate = (6.0f + 40.0f * energy) * m.cantidad;
    auto g = glide(f);
    const float flutter = g.vuelo.weight(0), swirl = g.vuelo.weight(1), wind = g.vuelo.weight(2);
    const float lift = std::min(bass * f.intensity, 1.0f) * g.pulso.weight(1) * std::min(width, height) * 1.5f;
    while (steps < target) {
      step(rainRate, m.cantidad, m.tamano, m.lluvia, flutter, swirl, wind, lift);
      steps++;
    }
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    auto gl = glide(f);
    float amp = f.intensity;
    // Pulso: cada opción mueve algo distinto; sin música todo vale cero.
    const float kickP = std::min(kick * amp, 1.0f) * gl.pulso.weight(0);
    const float bassP = std::min(bass * amp, 1.0f) * gl.pulso.weight(1);
    const float sparkP = std::min(spark * amp, 1.0f) * gl.pulso.weight(2);
    // Golpes: salto de tamaño; Graves: el confeti se hincha con los graves.
    const float grow = 1.0f + 0.2f * kickP + 0.15f * bassP;
    // Agudos: las caras que miran de frente, y muchos papelitos sueltos,
    // destellan como lentejuelas.
    std::vector<Vec2> glints;
    if (sparkP > 0.002f) glints.reserve(pieces.size());
    const uint32_t tick = uint32_t(std::fmod(sim, 100000.0) * 14.0);
    const float span = std::min(f.width, f.height);
    // Golpes: un fogonazo de luz en la boca de cada cañón y en cada estallido.
    const float burst = std::min(burstPow * amp, 1.0f) * gl.pulso.weight(0);
    auto bloom = [&](Vec2 at, double age, float radius) {
      if (age > 1.5) return;
      const float o = std::clamp(0.4f * burst * std::exp(-float(age) * 5.0f) * f.glow, 0.0f, 0.6f);
      if (o < 0.003f) return;
      Paint bp = Paint::radial(at, radius, {f.colors[3].opacity(o), f.colors[2].opacity(o * 0.5f), f.colors[1].opacity(0.0f)},
                               {0.0f, 0.4f, 1.0f});
      bp.blend = Blend::plus;
      c.circle(at, radius, bp);
    };
    if (burst > 0.002f) {
      bloom({0.0f, f.height}, leftAge, span * 0.45f);
      bloom({f.width, f.height}, rightAge, span * 0.45f);
      bloom({popX, popY}, popAge, span * 0.32f);
    }
    // Graves: el soplo de abajo se ve como un resplandor que late.
    const float updraft = std::clamp(0.28f * bassP * f.glow, 0.0f, 0.5f);
    if (updraft > 0.003f) {
      const Vec2 at{f.width * 0.5f, f.height * 1.05f};
      Paint up = Paint::radial(at, span * 0.7f, {f.colors[2].opacity(updraft), f.colors[1].opacity(0.0f)});
      up.blend = Blend::plus;
      c.circle(at, span * 0.7f, up);
    }
    // Entre el paso anterior y el último: movimiento suave a cualquier FPS.
    float a = float(std::clamp(sim / kStep - double(steps), 0.0, 1.0));
    // Arcoíris de la paleta: cada acento y, entre ellos, su tono intermedio.
    const Color& c1 = f.colors[1];
    const Color& c2 = f.colors[2];
    const Color& c3 = f.colors[3];
    const std::array<Color, 6> cols = {c1, between(c1, c2), c2, between(c2, c3), c3, between(c3, c1)};
    // Cara delantera y trasera de cada color.
    std::array<Path, 12> paths;
    for (const auto& p : pieces) {
      float x = p.px + (p.x - p.px) * a, y = p.py + (p.y - p.py) * a;
      float cf = std::cos(p.flip);
      float hw = 0.5f * p.w * std::max(0.08f, std::fabs(cf));
      float hh = 0.5f * p.h;
      hw *= grow;
      hh *= grow;
      if (sparkP > 0.002f &&
          (std::fabs(cf) > 0.9f || hashU(uint32_t(&p - pieces.data()) * 2654435761u + tick * 40503u) < 0.2f * sparkP))
        glints.push_back({x, y});
      float ca = std::cos(p.angle), sa = std::sin(p.angle);
      Path& path = paths[size_t(p.color * 2 + (cf < 0.0f ? 1 : 0))];
      path.moveTo(x + (-hw) * ca - (-hh) * sa, y + (-hw) * sa + (-hh) * ca)
          .lineTo(x + hw * ca - (-hh) * sa, y + hw * sa + (-hh) * ca)
          .lineTo(x + hw * ca - hh * sa, y + hw * sa + hh * ca)
          .lineTo(x + (-hw) * ca - hh * sa, y + (-hw) * sa + hh * ca)
          .close();
    }
    float lit = (0.9f + 0.2f * kick) * amp * (1.0f + 0.8f * kickP + 0.3f * bassP);
    for (int k = 0; k < 12; k++) {
      const Color& col = cols[size_t(k / 2)];
      float shade = (k % 2 == 0 ? 1.0f : 0.62f) * lit;
      Paint p;
      p.color = Color{std::min(1.0f, col.r * shade), std::min(1.0f, col.g * shade), std::min(1.0f, col.b * shade), 1.0f};
      c.path(paths[size_t(k)], p);
    }
    if (!glints.empty()) {
      const Color& c3 = f.colors[3];
      Paint gp;
      gp.blend = Blend::plus;
      gp.color = Color{std::min(1.0f, c3.r * 0.4f + 0.6f), std::min(1.0f, c3.g * 0.4f + 0.6f), std::min(1.0f, c3.b * 0.4f + 0.6f),
                       std::clamp(1.0f * sparkP, 0.0f, 0.95f)};
      c.points(glints, std::min(f.width, f.height) * 0.009f * m.tamano, gp);
    }
    (void)flash;
  }
};
''';
