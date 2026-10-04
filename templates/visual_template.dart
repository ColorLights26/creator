// PARA FRANCO: copia TODO este archivo a tu IA y describe el visual que quieres.
// Pega su respuesta completa en tu archivo .dart. Metadata en el archivo compañero.
// Guarda y usa Stop → Run. No necesitas registrar nada ni tocar el motor.
// Sus modificadores y variaciones aparecen en Studio, en Ajustes, para probarlos.
//
// PARA LA IA: entrega únicamente este archivo Dart completo, sin Markdown.
// Conserva las instrucciones y la referencia; reemplaza modifiers, variations y
// nativeSource por los de tu escena. Conserva el import: lo necesitan.
// nativeSource es C++17: define class Visual final : public Scene.
// Puedes crear algoritmos, structs, vectores, estado persistente, partículas,
// curvas y funciones auxiliares. La instancia es independiente por reproducción.
// No pongas includes dentro del string: el motor ya incluye algorithm, array,
// cmath, cstdint, initializer_list, memory, stdexcept, string y vector.
// reset(seed) inicializa toda la memoria; update(frame) mueve la simulación;
// render(frame,canvas) const sólo dibuja. No uses globals mutables, relojes del sistema,
// timers, sensores, red, archivos, hilos ni servicios de la app.
// Frame.time/delta son segundos activos, con pausa y delta acotado por el motor.
// Usa delta para velocidades; Random(seed) sólo en reset.
//
// 30 Y 60 FPS (Creator lo comprueba): sin música, el dibujo debe ser el mismo a
// 30 y a 60 FPS. Lleva un reloj propio en update (reloj += f.delta * f.speed) y
// acumula fases exactas con él. Para partículas, reserva un grupo fijo en reset
// y calcula cada una con una fórmula de ese reloj (edad = fmod(reloj + desfase,
// vida); posición = inicio + vel * edad): renacen por ciclo, sin Random en update
// y sin crear ni borrar por cuadro. Para ráfagas con cada golpe, guarda en update
// un anillo fijo de ranuras {inicio = reloj, fuerza} y dibuja cada chispa en
// render con (reloj - inicio). No integres en posiciones valores suavizados por
// cuadro (x += suave * delta). Evita pow, sqrt o log de valores que puedan ser
// negativos o cero.
//
// MÚSICA QUE SE VE: la energía (f.music.energy, bass) respira lento; los eventos
// (f.music.events) dan golpes cortos que se apagan. Un golpe fuerte debe verse a
// simple vista: un destello, una ráfaga, un cambio de forma o de movimiento. Lo
// que se limita es el tamaño y el brillo: con intensity 2 y música fuerte,
// crece como mucho un 25%, deja ~30% de oscuridad y no apiles capas aditivas ni
// rampas de color hasta el blanco. Sin música, el visual vive con su propio
// movimiento.
// Music.events ya está deduplicado. Si music.active=false, sus señales son cero.
// Apagar música no borra partículas existentes. No inventes golpes desde bpm.
// width/height son píxeles lógicos, origen arriba izquierda, y hacia abajo.
// Color usa RGBA recto. Un fondo debe cubrir el lienzo; un overlay conserva alpha.
// Agrupa partículas con Canvas.points. saveLayer aplica opacidad al grupo completo.
// Balancea save/saveLayer con restore. clip intersecta recortes anidados.
// Path.fillRule=FillRule::evenOdd permite huecos. Blend: sourceOver, plus, screen.
// El motor posee cadencia/calidad/recursos: 30 FPS por defecto; pedir 60 no lo fuerza.
// Acota memoria y trabajo según tu escena. No existe un máximo artificial de 8 bucles.
// El código nativo se valida antes de aprobarse; esa validación NO es un sandbox.
//
// AJUSTES BÁSICOS: todo visual los tiene y Studio los muestra. Úsalos siempre.
// f.intensity: cuánto reacciona a la música; multiplica la respuesta al audio.
// f.speed: ritmo del movimiento. Acumúlalo con delta (fase += f.delta*f.speed);
//   nunca uses f.time*f.speed: al mover el ajuste, el dibujo saltaría.
// f.detail (0.25 a 2): densidad. Reserva el máximo en reset y dibuja una parte.
// f.glow: halo, niebla o resplandor.
// f.colors: paleta de la metadata. colors[0] es el fondo; colors[1..3], los
//   acentos. No escribas colores fijos en el código: así la paleta se cambia.
//
// MODIFICADORES (SIEMPRE): declara de 3 a 5, cada uno de una familia distinta:
//   FORMA: cantidad, simetría, figura, estructura.
//   MOVIMIENTO: el carácter (fluido, nervioso, orbital), nunca la velocidad; que
//     se note también en una imagen fija (la forma del camino, la estela).
//   MÚSICA (obligatorio si reactivity no es none; con none no lo declares,
//     no cambiaría nada): qué parte del visual reacciona. En un choice como
//     'Pulso': Graves / Golpes / Brillos, cada opción mueve algo distinto (los
//     graves inflan la forma, los golpes lanzan ráfagas, los brillos centellean);
//     no la misma reacción con otra fuente.
//   ATMÓSFERA: estela, bruma, profundidad, textura.
//   MODO: un interruptor que cambia la estructura (Espejo, Contorno).
// Cada uno debe cambiar el visual a simple vista: su mínimo y su máximo deben
// parecer dos visuales distintos y los dos bonitos, también con detail 2,
// intensity 2 y música fuerte. Si sólo cambia un detalle pequeño, quítalo.
// No repitas los básicos (intensidad, velocidad, detalle, brillo) ni la paleta:
// Creator rechaza el visual. Un interruptor sólo para un modo que cambia la
// estructura (Espejo, Contorno), nunca para encender un adorno.
// Van en const modifiers, antes de nativeSource. El valor inicial de un choice
// es su primera opción (o value: con el índice). Tipos:
//   CreatorModifier.slider('id', 'Nombre', min: .5, max: 2, value: 1)    decimal
//   CreatorModifier.steps('id', 'Nombre', min: 3, max: 12, value: 6)     entero
//   CreatorModifier.toggle('id', 'Nombre', value: true)                  sí / no
//   CreatorModifier.choice('id', 'Nombre', options: ['A', 'B', 'C'])     opción
// En C++: auto m = modifiers(f); para decidir (float, int, bool o el índice).
//   auto g = glide(f); para transformarse: el motor ya suaviza cada cambio.
//   g.<slider> y g.<steps> son decimales que se deslizan (5.4 brazos: mezcla 5
//   y 6); g.<toggle> va de 0 a 1 (úsalo como opacidad); g.<choice>.weight(i) es
//   el peso de la opción i y los pesos suman 1: mezcla las opciones con ellos.
//   No escribas tu propio suavizado de los ajustes.
// Calcula el aspecto en render (así se ve en pausa); update sólo acumula
// movimiento. Reserva el máximo en reset; nunca reserves memoria ni reinicies
// al cambiar un ajuste. Para materiales, pasa los valores y pesos como floats.
// Al fundir dos opciones, reparte los elementos entre ambas en vez de dibujar
// dos pasadas completas. Límites por cuadro: 32768 puntos por lote y 1 MiB de
// comandos; colores y opacidades entre 0 y 1 (usa std::clamp).
// id: letras a-z sin acentos ni ñ, números y _; empieza por letra; hasta 24.
//   Es el nombre en C++: no uses intensity, speed, detail, glow, colors,
//   palette, music, time, delta, width, height, seed, modifiers, glide ni
//   palabras de C++ (double, float, auto, static, default, new, union...).
//   No leas f.modifiers[...] ni declares nada llamado modifiers, glide o Creator*.
// Nombre visible en español, hasta 24 caracteres; opciones hasta 20; máximo 8.
// Rangos dentro de ±100000; steps admite hasta 1000 pasos entre min y max.
//
// VARIACIONES (SIEMPRE): 2 o 3 en const variations, después de modifiers:
//   CreatorVariation('Tormenta', {'brazos': 8, 'pulso': 'Golpes', 'speed': 1.4})
// Cada una debe parecer otro visual. Claves: los ids de tus modificadores o
// intensity, speed, detail y glow. Un choice va con el texto de su opción y un
// toggle con true o false. Nombre de hasta 20 caracteres, distinto de 'Original'.
//
// Creator prueba cada mínimo, máximo, opción y variación con música: un ajuste
// que no cambia nada o que falla impide la aprobación.
// ANTES DE ENTREGAR, comprueba: 3 a 5 ajustes de familias distintas y uno
// musical (si reacciona); cada id se lee en el C++; ninguno repite un básico; extremos seguros
// con detail 2; 2 o 3 variaciones; el movimiento es igual a 30 y 60 FPS.
//
// MATERIALES OPCIONALES: añade, después de nativeSource,
// const shaderSources = <String, String>{
//   'material': r"""#version 460 core
// #include <flutter/runtime_effect.glsl>
// uniform vec2 uSize;
// uniform float uTime;
// out vec4 fragColor;
// void main() {
//   vec2 uv=FlutterFragCoord().xy/uSize;
//   fragColor=vec4(uv,0.5+0.5*sin(uTime),1.0);
// }
// """, };
// Dibuja con canvas.material("material", {0,0,f.width,f.height}, {float(f.time)}).
// uSize siempre primero; después float/vec2/vec3/vec4 y sampler2D, sin arrays.
// Material produce RGBA premultiplicado. Sus coordenadas son locales al rectángulo.
// Para aplicarlo a una forma: save(), clip(path), material(...), restore().
// Texturas se nombran en metadata.images: {'foto':'assets/images/foto.png'}.
// canvas.image("foto", rect) dibuja la imagen ya preparada. Los samplers del
// material reciben esas claves en orden: material("x", rect, floats, {"foto"}).
// No hay acceso al fotograma anterior, shaders de cómputo ni motor 3D.
//
// REFERENCIA REAL DEL SDK (generada; no redeclarar estas clases):
// namespace creator {
// constexpr double pi = 3.14159265358979323846;
// struct Vec2 { float x = 0, y = 0; };
// struct Rect { float x = 0, y = 0, width = 0, height = 0; };
// struct Color {
//   float r = 0, g = 0, b = 0, a = 1; // straight RGBA, 0..1
//   static Color argb(uint32_t value);
//   Color opacity(float value) const;
// };
// enum class Blend { sourceOver, plus, screen };
// enum class FillRule { nonZero, evenOdd };
// struct Event {
//   int64_t serial = 0, timestampMicros = 0;
//   float strength = 0;
//   int band = 0;
// };
// struct Music {
//   bool active = false;
//   float energy = 0, bass = 0, body = 0, spark = 0, flow = 0, bpm = 0, phase = 0;
//   std::array<float, 6> dynamics{};
//   std::array<float, 31> spectrum{}, smoothSpectrum{};
//   std::array<std::vector<Event>, 4> events; // impact, accent, beat, flash; new events only
// };
// struct Frame {
//   double time = 0, delta = 0;
//   float width = 1, height = 1; // logical pixels; y grows downward
//   uint32_t seed = 42;
//   bool reducedMotion = false;
//   float intensity = 1, speed = 1, detail = 1, glow = 1;
//   std::array<Color, 4> colors;
//   std::array<float, 8> modifiers{}; // raw values; read them typed: modifiers(f).<id>
//   Music music; // already authorized; zero when disabled/unavailable
// };
// class Random {
//  public:
//   explicit Random(uint32_t seed = 42) : state_(seed ? seed : 1) {}
//   uint32_t next();
//   float unit(); // deterministic [0,1), call only during reset (30/60 FPS rule)
//  private: uint32_t state_;
// };
// class Path {
//  public:
//   FillRule fillRule = FillRule::nonZero;
//   Path& moveTo(float x, float y);
//   Path& lineTo(float x, float y);
//   Path& quadraticTo(float cx, float cy, float x, float y);
//   Path& cubicTo(float ax, float ay, float bx, float by, float x, float y);
//   Path& close();
//   Path& rect(Rect rect);
//   Path& circle(Vec2 center, float radius);
//   const std::vector<float>& data() const { return data_; }
//  private: std::vector<float> data_;
// };
// struct Paint {
//   Color color{1,1,1,1};
//   Blend blend = Blend::sourceOver;
//   float strokeWidth = 0; // 0 = fill, otherwise stroke
//   int strokeCap = 0, strokeJoin = 0; // butt/miter=0, round=1, square/bevel=2
//   // Gradient positions are logical pixels in the current transform.
//   static Paint linear(Vec2 start, Vec2 end, std::vector<Color> colors,
//                       std::vector<float> stops = {});
//   static Paint radial(Vec2 center, float radius, std::vector<Color> colors,
//                       std::vector<float> stops = {});
//   int gradient = 0;
//   std::array<float, 4> geometry{};
//   std::vector<Color> colors;
//   std::vector<float> stops;
// };
// class Canvas {
//  public:
//   Canvas(std::vector<float>& buffer, const std::vector<std::string>& materials,
//          const std::vector<std::string>& images);
//   void save();
//   void restore(); // matches save or saveLayer; unbalanced stacks are errors
//   void saveLayer(float opacity, Blend blend = Blend::sourceOver);
//   void transform(float a, float b, float c, float d, float tx, float ty);
//   void translate(float x, float y);
//   void scale(float x, float y);
//   void rotate(float radians);
//   void clip(const Path& path); // intersects with the current clip
//   void path(const Path& path, const Paint& paint);
//   void rect(Rect rect, const Paint& paint);
//   void circle(Vec2 center, float radius, const Paint& paint);
//   void points(const std::vector<Vec2>& points, float radius, const Paint& paint);
//   void image(const std::string& name, Rect destination, float opacity = 1,
//              Blend blend = Blend::sourceOver);
//   // GLSL uniforms in declaration order. First uniform must be vec2 uSize,
//   // supplied automatically as destination width/height. Other floats are yours.
//   // Samplers in declaration order refer to metadata.images keys.
//   // GLSL output is premultiplied RGBA; use FlutterFragCoord() for local pixels.
//   void material(const std::string& name, Rect destination,
//                 const std::vector<float>& uniforms = {},
//                 const std::vector<std::string>& images = {},
//                 Blend blend = Blend::sourceOver);
//   void finish() const;
//  private:
//   std::vector<float>& buffer_;
//   const std::vector<std::string>& materials_;
//   const std::vector<std::string>& images_;
//   int depth_ = 0;
//   void emit(int opcode, const std::vector<float>& payload);
// };
// class Scene {
//  public:
//   virtual ~Scene() = default;
//   virtual void reset(uint32_t seed) = 0;
//   virtual void update(const Frame& frame) = 0;
//   virtual void render(const Frame& frame, Canvas& canvas) const = 0;
// };
// // Author defines: class Visual final : public creator::Scene { ... };
// // Keep mutable state on Visual, not in globals. No clocks, IO, sensors or threads.
// } // namespace creator

import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual: Studio los muestra en Ajustes.
const modifiers = [
  // FORMA
  CreatorModifier.steps('brazos', 'Brazos', min: 2, max: 8, value: 4),
  // MÚSICA: cómo se ve el ritmo.
  CreatorModifier.choice(
    'pulso',
    'Pulso',
    options: ['Graves', 'Golpes', 'Brillos'],
  ),
  // ATMÓSFERA
  CreatorModifier.slider('estela', 'Estela', min: 0, max: 1, value: .35),
  // MODO: cambia la estructura.
  CreatorModifier.toggle('espejo', 'Espejo'),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Tormenta', {
    'brazos': 8,
    'pulso': 'Golpes',
    'estela': .9,
    'espejo': true,
    'speed': 1.4,
  }),
  CreatorVariation('Calma', {
    'brazos': 2,
    'pulso': 'Graves',
    'estela': .1,
    'speed': .5,
  }),
];

const nativeSource = r"""
class Visual final : public Scene {
  // Reserve the maximum (detail 2): changing a setting never reallocates.
  static constexpr int maxStars = 3000;
  struct Star { float radius, offset, lift, drift, arm; int group; };
  std::vector<Star> stars;
  float clock = 0, breath = 0, beat = 0;
 public:
  void reset(uint32_t seed) override {
    Random rng(seed); stars.clear(); stars.reserve(maxStars);
    clock = 0; breath = 0; beat = 0;
    for (int i = 0; i < maxStars; i++) {
      float r = std::sqrt(rng.unit());
      stars.push_back({r, r * 5.8f + (rng.unit() - .5f) * (.25f + r * .8f),
        (rng.unit() - .5f) * (.018f + r * .035f), .7f + rng.unit() * .6f,
        rng.unit(), i % 9});
    }
  }
  void update(const Frame& f) override {
    // Motion only: an own clock follows Velocidad and matches at 30 and 60 FPS.
    const float d = float(f.delta);
    clock += d * f.speed;
    // Music: the bass breathes slowly; each beat is a short accent that fades.
    breath += (f.music.bass * f.intensity - breath) * (1 - std::exp(-d * 4));
    if (!f.music.events[2].empty()) beat = std::min(1.f, f.intensity);
    beat *= std::exp(-d * 5);
  }
  void render(const Frame& f, Canvas& c) const override {
    // Look is computed here, so every setting shows even while paused.
    auto g = glide(f);  // transitions: gliding decimals, a 0..1 fade, weights
    const auto& pal = f.colors;
    // Pulso decides how the music shows; its weights blend the options.
    const float graves = g.pulso.weight(0) * breath;
    const float golpes = g.pulso.weight(1) * beat;
    const float brillos = g.pulso.weight(2) * f.music.spark * f.intensity;
    Color deep{pal[0].r * .25f, pal[0].g * .25f, pal[0].b * .25f, 1};
    c.rect({0, 0, f.width, f.height},
           Paint::radial({f.width * .5f, f.height * .47f}, f.height * .75f,
                         {pal[0].opacity(1), deep}));
    c.save(); c.translate(f.width * .5f, f.height * .48f); c.rotate(-.38f);
    // Music grows the galaxy 20% at most, even with intensity 2.
    const float scale = std::min(f.width * .62f, f.height * .42f) * (1 + std::min(graves, 1.f) * .2f);
    // Estela: from sharp stars (0) to a soft, glowing nebula (1).
    const float haze = g.estela;
    Paint mist = Paint::radial({0, 0}, scale * (.6f + haze * .5f),
      {pal[2].opacity((.05f + haze * .35f) * f.glow), pal[2].opacity(0)});
    mist.blend = Blend::plus;
    c.rect({-scale * 1.2f, -scale * 1.2f, scale * 2.4f, scale * 2.4f}, mist);
    // Brazos glides (5.4 arms): each star sits at its share of the circle, so
    // arms spread apart smoothly while the count changes.
    const int fewer = int(std::floor(g.brazos)), more = fewer + 1;
    const float between = g.brazos - float(fewer);
    auto armAngle = [](float share, int arms) {
      return std::floor(share * float(arms)) * float(2 * pi) / float(arms);
    };
    const int visible = std::min(maxStars, int(maxStars * .5f * f.detail));
    Paint core = Paint::radial({0, 0}, scale * .28f,
      {pal[3].opacity(.92f * std::min(1.f, f.glow)), pal[1].opacity(.22f), pal[1].opacity(0)},
      {0, .22f, 1});
    core.blend = Blend::screen;
    c.circle({0, 0}, scale * (.28f + golpes * .08f), core);
    for (int group = 0; group < 9; group++) {
      std::vector<Vec2> batch, mirror;
      batch.reserve(visible / 9 + 1); mirror.reserve(visible / 9 + 1);
      for (int i = 0; i < visible; i++) {
        const auto& s = stars[i];
        if (s.group != group) continue;
        const float from = armAngle(s.arm, fewer), to = armAngle(s.arm, more);
        const float a = from + (to - from) * between + s.offset + clock * .06f * s.drift;
        const Vec2 point{std::cos(a) * s.radius * scale,
                         std::sin(a) * s.radius * scale * .49f + s.lift * scale};
        batch.push_back(point);
        mirror.push_back({-point.x, point.y});
      }
      const float twinkle = .5f + .5f * std::sin(clock * 9 + group * 1.7f);
      Paint p; p.blend = Blend::plus;
      const float alpha = std::min(1.f, .55f + golpes * .45f + brillos * twinkle * .6f);
      const float size = (.55f + (group / 3) * .5f) * (1 + haze * 1.6f + golpes * .25f);
      p.color = pal[1 + group % 3].opacity(alpha);
      c.points(batch, size, p);
      // Espejo: a mirrored twin turns the spiral into a symmetric butterfly.
      if (g.espejo > 0) {
        p.color = pal[1 + (group + 1) % 3].opacity(alpha * g.espejo);
        c.points(mirror, size, p);
      }
    }
    c.restore();
  }
};
""";
