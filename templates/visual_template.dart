// PARA FRANCO: copia TODO este archivo a tu IA y describe el visual que quieres.
// Pega su respuesta completa en tu archivo .dart. Metadata en el archivo compañero.
// Guarda y usa Stop → Run. No necesitas registrar nada ni tocar el motor.
//
// PARA LA IA: entrega únicamente este archivo Dart completo, sin Markdown.
// Conserva las instrucciones y la referencia, reemplaza nativeSource por tu escena.
// nativeSource es C++17: define class Visual final : public Scene.
// Puedes crear algoritmos, structs, vectores, estado persistente, partículas,
// curvas y funciones auxiliares. La instancia es independiente por reproducción.
// No pongas includes dentro del string: el motor ya incluye algorithm, array,
// cmath, cstdint, initializer_list, memory, stdexcept, string y vector.
// reset(seed) inicializa toda la memoria; update(frame) mueve la simulación;
// render(frame,canvas) const sólo dibuja. No uses globals mutables, relojes,
// timers, sensores, red, archivos, hilos ni servicios de la app.
// Frame.time/delta son segundos activos, con pausa y delta acotado por el motor.
// Usa delta para velocidades; Random(seed) para inicialización reproducible.
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
// MATERIALES OPCIONALES: añade const shaderSources = <String, String>{
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
//   Music music; // already authorized; zero when disabled/unavailable
// };
// class Random {
//  public:
//   explicit Random(uint32_t seed = 42) : state_(seed ? seed : 1) {}
//   uint32_t next();
//   float unit(); // deterministic [0,1), call during reset/update, never render
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

const nativeSource = r"""
class Visual final : public Scene {
  struct Star { float radius, angle, lift, drift; int group; };
  std::vector<Star> stars;
  float turn = 0, breath = 0;
 public:
  void reset(uint32_t seed) override {
    Random rng(seed); stars.clear(); stars.reserve(1500); turn=0; breath=0;
    for(int i=0;i<1500;i++) {
      float r=std::sqrt(rng.unit()); int arm=i%4;
      stars.push_back({r, float(arm*pi/2)+r*5.8f+(rng.unit()-.5f)*(.25f+r*.8f),
        (rng.unit()-.5f)*(.018f+r*.035f), .7f+rng.unit()*.6f, i%9});
    }
  }
  void update(const Frame& f) override {
    turn += float(f.delta)*f.speed*.06f;
    float target=f.music.energy;
    breath += (target-breath)*float(1-std::exp(-f.delta*3));
  }
  void render(const Frame& f, Canvas& c) const override {
    Paint sky=Paint::radial({f.width*.5f,f.height*.47f},f.height*.75f,
      {Color::argb(0xff151031),Color::argb(0xff03040d)});
    c.rect({0,0,f.width,f.height},sky);
    c.save(); c.translate(f.width*.5f,f.height*.48f); c.rotate(-.38f);
    float scale=std::min(f.width*.62f,f.height*.42f)*(1+breath*.045f);
    Paint haze=Paint::radial({0,0},scale*.8f,{Color{.24f,.1f,.5f,.2f},Color{.08f,.02f,.3f,0}});
    haze.blend=Blend::plus; c.rect({-scale,-scale,scale*2,scale*2},haze);
    for(int group=0;group<9;group++) {
      std::vector<Vec2> batch;batch.reserve(170);
      for(const auto& s:stars) if(s.group==group) {
        float a=s.angle+turn*s.drift;
        batch.push_back({std::cos(a)*s.radius*scale,
          std::sin(a)*s.radius*scale*.49f+s.lift*scale});
      }
      Paint p;p.blend=Blend::plus;
      p.color=group%3==0?Color{.58f,.69f,1,.65f}:group%3==1?Color{1,.67f,.48f,.6f}:Color{.9f,.72f,1,.72f};
      c.points(batch,.55f+(group/3)*.5f,p);
    }
    Paint core=Paint::radial({0,0},scale*.28f,{Color{1,.87f,.68f,.92f},Color{.65f,.34f,.75f,.22f},Color{.2f,.1f,.6f,0}},{0,.22f,1});
    core.blend=Blend::screen;c.circle({0,0},scale*.28f,core);c.restore();
  }
};
""";
