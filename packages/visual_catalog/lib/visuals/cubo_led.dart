// Cubo LED 3D — un cubo de luces como los que construyen los aficionados.
// Una rejilla de 8×8×8 LED (hasta 10×10×10) que gira despacio en 3D; los LED
// apagados se ven como puntitos tenues y los encendidos brillan con halo,
// del rojo de abajo al amarillo de arriba. Cinco animaciones: lluvia que cae
// por las columnas, una superficie de ondas, el espectro de la música como
// barras en volumen, explosiones esféricas con cada golpe y una espiral que
// sube. En Auto la animación cambia cada ocho golpes. Los graves aceleran el
// giro y cada golpe hace destellar todo el cubo.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.steps('tamano', 'LED por lado', min: 6, max: 10, value: 8),
  CreatorModifier.choice('animacion', 'Animación', options: ['Auto', 'Lluvia', 'Ondas', 'Espectro', 'Explosión', 'Espiral']),
  CreatorModifier.slider('giro', 'Velocidad de giro', min: 0, max: 2, value: 1),
  CreatorModifier.toggle('apagados', 'LED apagados visibles', value: true),
];

const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kMax = 10;
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  std::array<float, kMax> bands{};
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double clock = 0, yaw = 0, sinceAnim = 0, sinceHit = 100;
  float hitPower = 0;
  int beats = 0, autoAnim = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  static float hash(int a, int b) {
    uint32_t x = uint32_t(a) * 374761393u + uint32_t(b) * 668265263u;
    x = (x ^ (x >> 13)) * 1274126177u;
    return float(x ^ (x >> 16)) / 4294967296.0f;
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    bands.fill(0);
    clock = rng.unit() * 20.0;
    yaw = rng.unit() * 6.28;
    sinceAnim = 0;
    sinceHit = 100;
    hitPower = 0;
    beats = 0;
    autoAnim = 0;
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
    int n = std::clamp(m.tamano, 4, kMax);
    for (int i = 0; i < n; i++) {
      int b0 = i * 28 / n, b1 = std::max(b0 + 1, (i + 1) * 28 / n);
      float v = 0;
      for (int b = b0; b < b1; b++) v = std::max(v, mu.smoothSpectrum[size_t(b)]);
      bands[size_t(i)] = follow(bands[size_t(i)], v, 20.0f, 5.0f, dt);
    }

    float hit = 0, fl = 0;
    for (const auto& e : mu.events[0]) hit = std::max(hit, e.strength);
    for (const auto& e : mu.events[2]) hit = std::max(hit, e.strength * 0.85f);
    for (const auto& e : mu.events[3]) fl = std::max(fl, e.strength);
    float onset = std::clamp((mu.bass - slowBass - 0.15f) * 2.5f, 0.0f, 1.0f);
    slowBass = follow(slowBass, mu.bass, 3.0f, 3.0f, dt);
    hit = std::min(std::max(hit, onset), 1.0f);
    sinceAnim += f.delta;
    sinceHit += f.delta;
    if (hit > kick + 0.2f) {
      sinceHit = 0;
      hitPower = hit;
      if (++beats % 8 == 0) {
        autoAnim = (autoAnim + 1) % 5;
        sinceAnim = 0;
      }
    }
    if (!mu.active) {
      // Sin música: una explosión cada 1,6 s y otra animación cada 9 s.
      if (sinceHit > 1.6) {
        sinceHit -= 1.6;
        hitPower = 0.8f;
      }
      if (sinceAnim > 9.0) {
        sinceAnim -= 9.0;
        autoAnim = (autoAnim + 1) % 5;
      }
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    clock += f.delta * f.speed * (1.0 + 0.8 * drive);
    yaw += f.delta * f.speed * m.giro * (0.3 + 0.5 * drive + 0.6 * bass);
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    float amp = f.intensity;
    const Color& bg = f.colors[0];
    c.rect({0, 0, f.width, f.height}, Paint::radial({f.width * 0.5f, f.height * 0.5f}, std::max(f.width, f.height) * 0.7f,
                                                   {Color{std::min(1.0f, bg.r + 0.06f), std::min(1.0f, bg.g + 0.03f), std::min(1.0f, bg.b + 0.05f), 1.0f},
                                                    Color{bg.r, bg.g, bg.b, 1.0f}}));
    int n = std::clamp(m.tamano, 4, kMax);
    int mode = m.animacion == 0 ? autoAnim : m.animacion - 1;
    float t = float(std::fmod(clock, 1000.0));
    float side = std::min(f.width, f.height);
    float px = side / 400.0f;
    float cy = float(std::cos(yaw)), sy = float(std::sin(yaw));
    float tilt = 0.45f + 0.12f * float(std::sin(clock * 0.3));
    float cp = std::cos(tilt), sp = std::sin(tilt);
    float scale = side * 0.36f;
    float boom = sinceHit < 2.0 ? float(sinceHit) * 1.9f : 9.0f;
    float boomPower = sinceHit < 2.0 ? hitPower * float(1.0 - sinceHit / 2.0) : 0.0f;
    // Grupos por brillo (4 niveles) y color (5 tonos).
    std::array<std::vector<Vec2>, 20> lit;
    std::vector<Vec2> off;
    off.reserve(size_t(n * n * n));
    for (auto& g : lit) g.reserve(size_t(n * n * n / 4));
    for (int ix = 0; ix < n; ix++) {
      for (int iy = 0; iy < n; iy++) {
        for (int iz = 0; iz < n; iz++) {
          float x = float(ix) / float(n - 1) * 2.0f - 1.0f;
          float y = float(iy) / float(n - 1) * 2.0f - 1.0f;  // y = -1 abajo, 1 arriba
          float z = float(iz) / float(n - 1) * 2.0f - 1.0f;
          float v = 0;
          switch (mode) {
            case 0: {  // Lluvia: gotas que caen por cada columna.
              float h = hash(ix * 31 + iz, 7);
              float speed = 0.5f + 0.8f * hash(ix, iz * 17);
              float drop = 1.0f - 2.0f * float(std::fmod(double(t) * speed * (1.0 + 1.2 * double(drive)) + double(h) * 9.0, 1.4)) / 1.4f;
              float d = y - drop;
              v = d >= 0.0f ? std::exp(-d * 5.0f) : std::exp(d * 18.0f);
              v *= 0.6f + 0.4f * hash(ix + 3, iz + 5);
              break;
            }
            case 1: {  // Ondas: una superficie que se ondula desde el centro.
              float r = std::sqrt(x * x + z * z);
              float s = std::sin(r * 3.2f - t * 2.6f) * (0.45f + 0.35f * bass) + 0.3f * std::sin(x * 2.0f + t);
              v = std::exp(-std::fabs(y - s) * 5.5f);
              break;
            }
            case 2: {  // Espectro: barras en volumen, una banda por fila.
              float level = mu_level(ix, iz, n, t);
              float top = -1.0f + 2.0f * level;
              v = y <= top ? 0.55f + 0.45f * (y + 1.0f) / 2.0f : std::exp(-(y - top) * 9.0f) * 0.4f;
              break;
            }
            case 3: {  // Explosión: una cáscara esférica que crece.
              float r = std::sqrt(x * x + y * y + z * z);
              v = std::exp(-std::fabs(r - boom) * 5.0f) * (0.35f + boomPower) + std::exp(-r * 4.0f) * (0.3f + 0.6f * bass);
              break;
            }
            default: {  // Espiral: una hélice que sube girando.
              float ang = std::atan2(z, x);
              float r = std::sqrt(x * x + z * z);
              float ph = ang / 6.2831853f - y * 0.45f + t * 0.4f;
              float arm = std::fabs(ph * 2.0f - std::floor(ph * 2.0f + 0.5f));
              v = std::exp(-arm * 9.0f) * std::exp(-std::fabs(r - 0.75f) * 3.0f);
              break;
            }
          }
          v = std::clamp(v * (0.85f + 0.4f * kick), 0.0f, 1.0f);
          float rx = x * cy + z * sy, rz = -x * sy + z * cy;
          float ry = y * cp - rz * sp;
          float rzz = y * sp + rz * cp;
          float persp = 2.6f / (3.4f + rzz);
          Vec2 q{f.width * 0.5f + rx * persp * scale, f.height * 0.5f - ry * persp * scale};
          if (v < 0.12f) {
            off.push_back(q);
            continue;
          }
          int level = std::min(3, int(v * 4.0f));
          int col = std::clamp(int((y * 0.5f + 0.5f) * 4.99f), 0, 4);
          lit[size_t(level * 5 + col)].push_back(q);
        }
      }
    }
    float cell = scale * 2.0f / float(n - 1);
    if (m.apagados) {
      Paint dim;
      dim.color = Color{0.35f, 0.3f, 0.32f, 0.35f};
      c.points(off, std::max(0.8f, cell * 0.06f), dim);
    }
    std::array<Color, 5> tones = {f.colors[1],
                                  Color{(f.colors[1].r + f.colors[2].r) * 0.5f, (f.colors[1].g + f.colors[2].g) * 0.5f, (f.colors[1].b + f.colors[2].b) * 0.5f, 1.0f},
                                  f.colors[2],
                                  Color{(f.colors[2].r + f.colors[3].r) * 0.5f, (f.colors[2].g + f.colors[3].g) * 0.5f, (f.colors[2].b + f.colors[3].b) * 0.5f, 1.0f},
                                  f.colors[3]};
    for (int level = 0; level < 4; level++) {
      float b = (0.35f + 0.22f * float(level)) * amp;
      for (int k = 0; k < 5; k++) {
        const auto& pts = lit[size_t(level * 5 + k)];
        if (pts.empty()) continue;
        Paint halo;
        halo.blend = Blend::plus;
        halo.color = tones[size_t(k)].opacity(std::clamp(b * 0.28f * f.glow, 0.0f, 1.0f));
        c.points(pts, cell * (0.32f + 0.08f * float(level)), halo);
        Paint core;
        core.blend = Blend::plus;
        core.color = tones[size_t(k)].opacity(std::clamp(b * 1.1f, 0.0f, 1.0f));
        c.points(pts, std::max(1.2f * px, cell * (0.1f + 0.025f * float(level))), core);
      }
    }
    if (flash > 0.01f) {
      Paint fl;
      fl.blend = Blend::plus;
      fl.color = f.colors[2].opacity(std::clamp(flash * 0.05f * amp, 0.0f, 1.0f));
      c.rect({0, 0, f.width, f.height}, fl);
    }
  }

 private:
  // Nivel de la barra de espectro de una columna (con música) o una
  // ecualización de demostración (sin música).
  float mu_level(int ix, int iz, int n, float t) const {
    float band = bands[size_t(std::min(ix, n - 1))];
    float depth = 1.0f - 0.12f * float(std::abs(iz - n / 2));
    float idle = 0.35f + 0.25f * std::sin(t * 2.1f + float(ix) * 0.9f) * std::cos(t * 1.3f + float(iz) * 0.7f);
    float v = std::max(band * 1.3f, energy > 0.02f ? 0.0f : idle);
    return std::clamp(v * depth, 0.0f, 1.0f);
  }
};
''';
