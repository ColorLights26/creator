// Tipografía Cinética — palabras gigantes que entran a golpes con el ritmo.
// Como en los vídeos de tipografía animada: palabras enormes que llenan la
// pantalla y entran con cada golpe de la música, de golpe, cayendo o
// girando letra a letra, mientras la anterior sale disparada. Las letras son
// de una fuente geométrica propia, gruesa y de esquinas cortadas, y detrás
// pasan filas de palabras en contorno. Los graves hinchan las letras y los
// agudos las hacen temblar con un desdoble de color.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // FORMA: cómo se ordenan las palabras en la pantalla.
  CreatorModifier.choice(
    'composicion',
    'Composición',
    options: ['Gigante', 'Columna', 'Mosaico'],
  ),
  // MOVIMIENTO: cómo entra cada palabra.
  CreatorModifier.choice(
    'entrada',
    'Entrada',
    options: ['Golpe', 'Caída', 'Giro'],
  ),
  // MÚSICA
  CreatorModifier.choice(
    'pulso',
    'Pulso',
    options: ['Golpes', 'Graves', 'Agudos'],
  ),
  // Las palabras que aparecen.
  CreatorModifier.choice(
    'idioma',
    'Palabras',
    options: ['Español', 'Inglés'],
  ),
  // MODO: letras macizas o sólo su contorno.
  CreatorModifier.toggle('contorno', 'Contorno', value: false),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Cartel', {
    'composicion': 'Columna',
    'contorno': false,
    'entrada': 'Caída',
  }),
  CreatorVariation('Club', {
    'composicion': 'Mosaico',
    'contorno': true,
    'pulso': 'Graves',
    'idioma': 'Inglés',
  }),
];

const nativeSource = r'''
class Visual final : public Scene {
  using Stroke = std::vector<Vec2>;
  using Glyph = std::vector<Stroke>;
  float bass = 0, spark = 0, slowBass = 0;
  float kick = 0, flash = 0;
  // Relojes en doble precisión: sin música es idéntico a 30 y 60 FPS.
  double clock = 0, wordAge = 0, sinceWord = 10;
  uint32_t wordIndex = 0;
  std::array<Glyph, 26> glyphs{};

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }
  static float hashU(uint32_t x) {
    x ^= x >> 16; x *= 0x7feb352dU; x ^= x >> 15; x *= 0x846ca68bU; x ^= x >> 16;
    return float(x & 0xffffffu) / 16777216.0f;
  }
  static float easeOutBack(float x) {
    const float e = x - 1.0f;
    return 1.0f + 2.70158f * e * e * e + 1.70158f * e * e;
  }
  static float bounce(float x) {
    if (x < 0.5f) return 4.0f * x * x;
    const float e = x - 0.82f;
    return 1.0f - 0.9f * std::max(0.0f, 0.15f - 2.2f * e * e);
  }
  // Fuente de trazos: puntos en medias unidades (x 0..8, y 0..12), '|' separa trazos.
  static int hexValue(char ch) { return ch >= 'A' ? ch - 'A' + 10 : ch - '0'; }
  static Glyph parse(const char* code) {
    Glyph glyph;
    Stroke stroke;
    for (const char* p = code; *p; p++) {
      if (*p == '|') { glyph.push_back(stroke); stroke.clear(); continue; }
      if (*p == ' ') continue;
      const int x = hexValue(p[0]), y = hexValue(p[1]);
      stroke.push_back({float(x), float(y)});
      p++;
    }
    if (!stroke.empty()) glyph.push_back(stroke);
    return glyph;
  }
  static int length(const char* w) {
    int n = 0;
    while (w[n]) n++;
    return n;
  }
  static const char* word(int language, uint32_t index) {
    static const char* es[10] = {"FUEGO", "RITMO", "BAILA", "SUBE", "GOLPE", "LUZ", "VAMOS", "DALE", "OTRA", "ARRIBA"};
    static const char* en[10] = {"BASS", "DROP", "BEAT", "BOOM", "LOUD", "HYPE", "VIBE", "DANCE", "JUMP", "MORE"};
    return language == 1 ? en[index % 10u] : es[index % 10u];
  }
  void addGlyph(Path& path, char ch, float cx, float cy, float unit, float scale, float rot) const {
    if (ch < 'A' || ch > 'Z') return;
    const Glyph& g = glyphs[size_t(ch - 'A')];
    const float cs = std::cos(rot), sn = std::sin(rot);
    for (const Stroke& s : g) {
      bool first = true;
      for (const Vec2& pt : s) {
        const float x = (pt.x - 4.0f) * unit * scale, y = (pt.y - 6.0f) * unit * scale;
        const float X = cx + x * cs - y * sn, Y = cy + x * sn + y * cs;
        if (first) { path.moveTo(X, Y); first = false; } else path.lineTo(X, Y);
      }
    }
  }

 public:
  void reset(uint32_t seed) override {
    static const char* codes[26] = {
        "0C 03 30 50 83 8C|07 87", "0C 00 50 72 74 56 06|56 78 7A 5C 0C", "82 60 20 02 0A 2C 6C 8A",
        "00 50 83 89 5C 0C 00", "80 00 0C 8C|06 66", "80 00 0C|06 66", "82 60 20 02 0A 2C 6C 8A 87 47",
        "00 0C|80 8C|06 86", "40 4C|20 60|2C 6C", "80 8A 6C 2C 0A", "00 0C|80 17|35 8C", "00 0C 8C",
        "0C 00 46 80 8C", "0C 00 8C 80", "20 60 82 8A 6C 2C 0A 02 20", "0C 00 60 82 84 66 06",
        "20 60 82 8A 6C 2C 0A 02 20|59 8C", "0C 00 60 82 84 66 06|46 8C",
        "82 60 20 02 04 26 66 88 8A 6C 2C 0A", "00 80|40 4C", "00 0A 2C 6C 8A 80", "00 4C 80",
        "00 2C 45 6C 80", "00 8C|80 0C", "00 46 80|46 4C", "00 80 0C 8C"};
    for (int i = 0; i < 26; i++) glyphs[size_t(i)] = parse(codes[i]);
    bass = spark = slowBass = kick = flash = 0;
    clock = 0;
    wordAge = 1.0;
    sinceWord = 10;
    wordIndex = seed % 10u;
  }

  void update(const Frame& f) override {
    auto m = modifiers(f);
    const float dt = float(f.delta);
    const Music& mu = f.music;
    bass = follow(bass, mu.bass, 22.0f, 4.5f, dt);
    spark = follow(spark, mu.spark, 30.0f, 7.0f, dt);
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
    const double step = f.delta * f.speed;
    clock += step;
    wordAge += step;
    sinceWord += f.delta;
    // Golpes: cada golpe trae la palabra siguiente.
    const bool onBeats = mu.active && m.pulso == 0;
    if (onBeats && fresh && sinceWord > 0.16) {
      wordIndex++;
      wordAge = 0;
      sinceWord = 0;
    }
    // A su ritmo cambia de palabra cada 0,75 s.
    while (!onBeats && wordAge >= 0.75) {
      wordAge -= 0.75;
      wordIndex++;
    }
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    auto g = glide(f);
    const auto& pal = f.colors;
    const float amp = f.intensity;
    const float W = f.width, H = f.height;
    const float side = std::min(W, H);
    const float wGolpes = g.pulso.weight(0), wGraves = g.pulso.weight(1), wAgudos = g.pulso.weight(2);
    const float boom = std::min(kick * amp, 1.0f) * wGolpes;
    const float swell = 1.0f + 0.12f * std::min(bass * amp, 1.0f) * wGraves;
    const float jitter = std::min(spark * amp, 1.0f) * wAgudos;
    // Fondo: oscuro, con un fogonazo rojo en cada golpe.
    const Color& bg = pal[0];
    const float flashK = std::clamp(0.45f * boom + 0.08f * flash * amp, 0.0f, 0.55f);
    const Color back{bg.r + (pal[1].r - bg.r) * flashK, bg.g + (pal[1].g - bg.g) * flashK, bg.b + (pal[1].b - bg.b) * flashK, 1.0f};
    Paint backPaint;
    backPaint.color = back;
    c.rect({0, 0, W, H}, backPaint);
    const int lang = m.idioma;
    // Filas de palabras en contorno que pasan detrás (más con más detalle).
    {
      const int rows = std::clamp(int(std::lround(4.0f + 4.0f * f.detail)), 4, 12);
      const float unit = H / float(rows) / 16.0f;
      Path marquee;
      for (int r = 0; r < rows; r++) {
        const float y = H * (float(r) + 0.5f) / float(rows);
        const float dir = r % 2 == 0 ? 1.0f : -1.0f;
        float x = float(std::fmod(clock * double(W) * 0.05 * double(1 + r % 3), double(W))) * dir - W;
        uint32_t k = uint32_t(r * 3);
        while (x < W * 1.2f) {
          const char* w = word(lang, wordIndex + k++);
          for (const char* ch = w; *ch; ch++) {
            addGlyph(marquee, *ch, x + 4.0f * unit, y, unit, 1.0f, 0.0f);
            x += 11.0f * unit;
          }
          x += 14.0f * unit;
        }
      }
      Paint mp;
      mp.strokeWidth = unit * 1.2f;
      mp.color = pal[1].opacity(std::clamp(0.14f * f.glow, 0.0f, 1.0f));
      c.path(marquee, mp);
    }
    const char* current = word(lang, wordIndex);
    const char* previous = word(lang, wordIndex + 9u);
    const int n = length(current);
    const Color& ink = (wordIndex % 2u == 0) ? pal[3] : pal[2];
    const float hollow = std::clamp(g.contorno, 0.0f, 1.0f);
    const float wGolpe = g.entrada.weight(0), wCaida = g.entrada.weight(1), wGiro = g.entrada.weight(2);
    const float stagger = 0.04f * (wCaida + wGiro);
    const float age = float(wordAge);
    const uint32_t jitterSlot = uint32_t(std::floor(clock * 20.0));

    // Dibuja una palabra con su animación de entrada en un trazado.
    auto layoutWord = [&](Path& path, Path* split, const char* w, int count, float composition, float scaleAll, float alphaAge, bool exiting) {
      (void)alphaAge;
      float unit, step, x0, y0;
      bool column = composition > 0.5f;
      if (!column) {
        unit = std::min(W * 0.9f / (11.0f * float(count) - 3.0f), H * 0.4f / 12.0f);
        step = 11.0f * unit;
        x0 = W * 0.5f - (float(count) * step - 3.0f * unit) * 0.5f + 4.0f * unit;
        y0 = H * 0.5f;
      } else {
        unit = std::min(H * 0.86f / (float(count) * 14.5f - 2.5f), W * 0.8f / 8.0f);
        step = 14.5f * unit;
        x0 = W * 0.5f;
        y0 = H * 0.5f - (float(count) * step - 2.5f * unit) * 0.5f + 6.0f * unit;
      }
      unit *= scaleAll;
      for (int j = 0; j < count; j++) {
        float cx = column ? x0 : x0 + float(j) * step * scaleAll + (1.0f - scaleAll) * (W * 0.5f - x0);
        float cy = column ? y0 + float(j) * step * scaleAll + (1.0f - scaleAll) * (H * 0.5f - y0) : y0;
        float s = 1.0f, rot = 0.0f;
        if (!exiting) {
          const float a = age - float(j) * stagger;
          if (a < 0.0f) continue;
          const float kG = std::clamp(a / 0.22f, 0.0f, 1.0f);
          const float kC = std::clamp(a / 0.35f, 0.0f, 1.0f);
          const float kR = std::clamp(a / 0.3f, 0.0f, 1.0f);
          s = wGolpe * (1.8f - 0.8f * easeOutBack(kG)) + wCaida + wGiro * (0.4f + 0.6f * kR);
          cy -= wCaida * (1.0f - bounce(kC)) * H * 0.6f;
          rot = wGiro * (1.0f - easeOutBack(kR)) * 1.6f;
        }
        if (jitter > 0.01f) {
          cx += (hashU(uint32_t(j) * 2654435761u + jitterSlot) - 0.5f) * jitter * 0.04f * W;
          cy += (hashU(uint32_t(j) * 2246822519u + jitterSlot) - 0.5f) * jitter * 0.02f * W;
        }
        addGlyph(path, w[j], cx, cy, unit, s, rot);
        if (split) addGlyph(*split, w[j], cx + jitter * 6.0f * side / 400.0f, cy, unit, s, rot);
      }
      return unit;
    };

    auto drawComposition = [&](float compo, float weight) {
      if (weight < 0.01f) return;
      if (weight < 0.99f) c.saveLayer(weight);
      if (compo < 1.5f) {
        // Gigante o Columna: la palabra sola en el centro.
        Path main, split, gone;
        const float unit = layoutWord(main, jitter > 0.01f ? &split : nullptr, current, n, compo, swell, age, false);
        const float strokeW = unit * 2.2f * (1.0f + 0.3f * std::min(bass * amp, 1.0f) * wGraves);
        if (age < 0.15f) {
          // La palabra anterior sale disparada.
          layoutWord(gone, nullptr, previous, length(previous), compo, 1.0f + age * 3.0f, age, true);
          Paint gp;
          gp.strokeWidth = strokeW;
          gp.strokeCap = 2;
          gp.color = pal[1].opacity(std::clamp(1.0f - age / 0.15f, 0.0f, 1.0f));
          c.path(gone, gp);
        }
        if (jitter > 0.01f) {
          Paint sp;
          sp.blend = Blend::plus;
          sp.strokeWidth = strokeW;
          sp.strokeCap = 2;
          sp.color = pal[1].opacity(std::clamp(0.8f * jitter, 0.0f, 1.0f));
          c.path(split, sp);
        }
        Paint tp;
        tp.strokeWidth = strokeW;
        tp.strokeCap = 2;
        tp.color = ink;
        c.path(main, tp);
        if (hollow > 0.01f) {
          Paint hp;
          hp.strokeWidth = strokeW * 0.55f;
          hp.strokeCap = 2;
          hp.color = back.opacity(hollow);
          c.path(main, hp);
        }
      } else {
        // Mosaico: la palabra repetida en filas que corren en sentidos opuestos.
        const int rows = 7;
        const float unit = std::min(W * 0.62f / (11.0f * float(n) - 3.0f), H / float(rows) / 15.0f) * swell;
        const float wordW = (11.0f * float(n) + 11.0f) * unit;
        for (int r = 0; r < rows; r++) {
          Path rowPath;
          const float y = H * (float(r) + 0.5f) / float(rows);
          const float dir = r % 2 == 0 ? 1.0f : -1.0f;
          const float k = std::clamp(age / 0.25f, 0.0f, 1.0f);
          const float slide = (1.0f - easeOutBack(k)) * W * 0.5f * dir;
          float x = float(std::fmod(clock * double(wordW) * 0.35 * double(dir), double(wordW))) - wordW + slide;
          while (x < W + wordW) {
            for (int j = 0; j < n; j++) addGlyph(rowPath, current[j], x + float(j) * 11.0f * unit + 4.0f * unit, y, unit, 1.0f, 0.0f);
            x += wordW;
          }
          const float strokeW = unit * 2.2f * (1.0f + 0.3f * std::min(bass * amp, 1.0f) * wGraves);
          Paint rp;
          rp.strokeWidth = strokeW;
          rp.strokeCap = 2;
          rp.color = (r == rows / 2 ? ink : (r % 2 == 0 ? pal[2] : pal[3])).opacity(r == rows / 2 ? 1.0f : 0.75f);
          c.path(rowPath, rp);
          // Las filas alternas van en contorno; con Contorno, todas.
          const float rowHollow = std::max(hollow, r % 2 == 1 ? 1.0f : 0.0f);
          if (rowHollow > 0.01f) {
            Paint hp;
            hp.strokeWidth = strokeW * 0.55f;
            hp.strokeCap = 2;
            hp.color = back.opacity(rowHollow);
            c.path(rowPath, hp);
          }
        }
      }
      if (weight < 0.99f) c.restore();
    };
    drawComposition(0.0f, g.composicion.weight(0));
    drawComposition(1.0f, g.composicion.weight(1));
    drawComposition(2.0f, g.composicion.weight(2));
  }
};
''';
