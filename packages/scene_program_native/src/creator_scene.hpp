#pragma once
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <initializer_list>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>

// BEGIN AUTHOR API -- this section is embedded verbatim in the AI template.
namespace creator {
constexpr double pi = 3.14159265358979323846;
struct Vec2 { float x = 0, y = 0; };
struct Rect { float x = 0, y = 0, width = 0, height = 0; };
struct Color {
  float r = 0, g = 0, b = 0, a = 1; // straight RGBA, 0..1
  static Color argb(uint32_t value);
  Color opacity(float value) const;
};
enum class Blend { sourceOver, plus, screen };
enum class FillRule { nonZero, evenOdd };
struct Event {
  int64_t serial = 0, timestampMicros = 0;
  float strength = 0;
  int band = 0;
};
struct Music {
  bool active = false;
  float energy = 0, bass = 0, body = 0, spark = 0, flow = 0, bpm = 0, phase = 0;
  std::array<float, 6> dynamics{};
  std::array<float, 31> spectrum{}, smoothSpectrum{};
  std::array<std::vector<Event>, 4> events; // impact, accent, beat, flash; new events only
};
struct Frame {
  double time = 0, delta = 0;
  float width = 1, height = 1; // logical pixels; y grows downward
  uint32_t seed = 42;
  bool reducedMotion = false;
  float intensity = 1, speed = 1, detail = 1, glow = 1;
  std::array<Color, 4> colors;
  Music music; // already authorized; zero when disabled/unavailable
};
class Random {
 public:
  explicit Random(uint32_t seed = 42) : state_(seed ? seed : 1) {}
  uint32_t next();
  float unit(); // deterministic [0,1), call during reset/update, never render
 private: uint32_t state_;
};
class Path {
 public:
  FillRule fillRule = FillRule::nonZero;
  Path& moveTo(float x, float y);
  Path& lineTo(float x, float y);
  Path& quadraticTo(float cx, float cy, float x, float y);
  Path& cubicTo(float ax, float ay, float bx, float by, float x, float y);
  Path& close();
  Path& rect(Rect rect);
  Path& circle(Vec2 center, float radius);
  const std::vector<float>& data() const { return data_; }
 private: std::vector<float> data_;
};
struct Paint {
  Color color{1,1,1,1};
  Blend blend = Blend::sourceOver;
  float strokeWidth = 0; // 0 = fill, otherwise stroke
  int strokeCap = 0, strokeJoin = 0; // butt/miter=0, round=1, square/bevel=2
  // Gradient positions are logical pixels in the current transform.
  static Paint linear(Vec2 start, Vec2 end, std::vector<Color> colors,
                      std::vector<float> stops = {});
  static Paint radial(Vec2 center, float radius, std::vector<Color> colors,
                      std::vector<float> stops = {});
  int gradient = 0;
  std::array<float, 4> geometry{};
  std::vector<Color> colors;
  std::vector<float> stops;
};
class Canvas {
 public:
  Canvas(std::vector<float>& buffer, const std::vector<std::string>& materials,
         const std::vector<std::string>& images);
  void save();
  void restore(); // matches save or saveLayer; unbalanced stacks are errors
  void saveLayer(float opacity, Blend blend = Blend::sourceOver);
  void transform(float a, float b, float c, float d, float tx, float ty);
  void translate(float x, float y);
  void scale(float x, float y);
  void rotate(float radians);
  void clip(const Path& path); // intersects with the current clip
  void path(const Path& path, const Paint& paint);
  void rect(Rect rect, const Paint& paint);
  void circle(Vec2 center, float radius, const Paint& paint);
  void points(const std::vector<Vec2>& points, float radius, const Paint& paint);
  void image(const std::string& name, Rect destination, float opacity = 1,
             Blend blend = Blend::sourceOver);
  // GLSL uniforms in declaration order. First uniform must be vec2 uSize,
  // supplied automatically as destination width/height. Other floats are yours.
  // Samplers in declaration order refer to metadata.images keys.
  // GLSL output is premultiplied RGBA; use FlutterFragCoord() for local pixels.
  void material(const std::string& name, Rect destination,
                const std::vector<float>& uniforms = {},
                const std::vector<std::string>& images = {},
                Blend blend = Blend::sourceOver);
  void finish() const;
 private:
  std::vector<float>& buffer_;
  const std::vector<std::string>& materials_;
  const std::vector<std::string>& images_;
  int depth_ = 0;
  void emit(int opcode, const std::vector<float>& payload);
};
class Scene {
 public:
  virtual ~Scene() = default;
  virtual void reset(uint32_t seed) = 0;
  virtual void update(const Frame& frame) = 0;
  virtual void render(const Frame& frame, Canvas& canvas) const = 0;
};
// Author defines: class Visual final : public creator::Scene { ... };
// Keep mutable state on Visual, not in globals. No clocks, IO, sensors or threads.
} // namespace creator
// END AUTHOR API

namespace creator {
struct Program {
  const char* id;
  const char* hash;
  std::unique_ptr<Scene> (*create)();
  std::vector<std::string> materials;
  std::vector<std::string> images;
};
const std::vector<Program>& installedPrograms();
void validateCommands(const std::vector<float>& buffer, const Program& program);
}
