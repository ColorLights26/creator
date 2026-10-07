#include "creator_scene.hpp"
#include "creator_abi.h"
#include <cassert>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <iostream>
#include <limits>
#include <random>
#include <string>
#if __has_include("creator_probe_cases.inc")
#include "creator_probe_cases.inc"
#define CREATOR_PROBE_CASES 1
#endif

namespace {

constexpr uint32_t frameBytes = 520;
const std::array<float, 16> colors = {.02f,.03f,.08f,1,.2f,.6f,1,1,1,.2f,.6f,1,1,.8f,.5f,1};

struct Failure : std::runtime_error { using std::runtime_error::runtime_error; };

/// Synthetic music shared with the Dart tests (signals.bin, 520-byte frames),
/// made loud for the sweep: it starts where the music is active, every hit
/// has full strength and each beat also flashes, so a modifier that only
/// changes how hits look is exercised.
struct Music {
  std::vector<uint8_t> bytes;
  size_t start = 0;
  size_t frames() const { return bytes.size() / frameBytes; }
  const uint8_t* frame(size_t i) const { return bytes.data() + ((start + i) % frames()) * frameBytes; }

  void makeLoud() {
    for (size_t f = 0; f < frames(); f++) {
      uint8_t* b = bytes.data() + f * frameBytes;
      uint16_t flags; std::memcpy(&flags, b + 6, 2);
      if (start == 0 && f > 0 && (flags & 5) == 5) start = f;
      constexpr size_t events = 424, size = 24, beat = 2, flash = 3;
      if (b[events + beat * size + 21] == 1 && b[events + flash * size + 21] == 0)
        std::memcpy(b + events + flash * size, b + events + beat * size, size);
      for (size_t e = 0; e < 4; e++) {
        if (b[events + e * size + 21] != 1) continue;
        const float strength = 1;
        std::memcpy(b + events + e * size + 16, &strength, 4);
      }
    }
  }
};

/// The drawing of every frame, so a change that only shows on a hit counts.
struct Clip {
  std::vector<float> last;
  std::vector<uint64_t> frames;
  bool operator!=(const Clip& other) const { return frames != other.frames; }
};

uint64_t digest(const std::vector<float>& commands) {
  uint64_t hash = 1469598103934665603ull;
  for (float value : commands) {
    uint32_t bits; std::memcpy(&bits, &value, 4);
    hash = (hash ^ bits) * 1099511628211ull;
  }
  return hash;
}

std::vector<float> options(const std::array<float, 4>& basics, const std::vector<float>& modifiers) {
  std::vector<float> result(basics.begin(), basics.end());
  result.insert(result.end(), colors.begin(), colors.end());
  result.insert(result.end(), modifiers.begin(), modifiers.end());
  return result;
}

struct Instance {
  CPInstance* handle;
  explicit Instance(const creator::Program& program, uint32_t seed = 42) : handle(cp_create(program.id, program.hash, seed)) {
    if (!handle) throw Failure(cp_error(nullptr));
  }
  ~Instance() { cp_destroy(handle); }
  void check(int32_t result) const { if (result != 1) throw Failure(cp_error(handle)); }
  void configure(const std::vector<float>& values, double host, bool reactive = true) const {
    check(cp_configure(handle, values.data(), uint32_t(values.size()), reactive ? 1 : 0, 1, host));
  }
  std::vector<float> commands() const {
    const auto data = cp_commands(handle);
    return {data, data + cp_command_length(handle)};
  }
};

std::vector<float> replay(const creator::Program& program, int fps, bool interleaved=false, const std::vector<float>* modifiers=nullptr) {
  Instance p(program);
  std::unique_ptr<Instance> other = interleaved ? std::make_unique<Instance>(program) : nullptr;
  const auto values = options({1, 1, 1, 1}, modifiers ? *modifiers : std::vector<float>{});
  // 20 floats alone mean "the initial modifiers".
  const auto base = modifiers ? values : std::vector<float>(values.begin(), values.begin() + 20);
  p.configure(base, 0);
  if (other) other->configure(base, 0);
  for (int i = 0; i <= fps * 4; i++) {
    p.check(cp_update(p.handle, 320, 568, double(i) / fps, 0)); p.check(cp_draw(p.handle));
    if (other) { other->check(cp_update(other->handle, 320, 568, double(i) / fps, 0)); other->check(cp_draw(other->handle)); }
  }
  return p.commands();
}

std::string visualName(const creator::Program& program) {
  std::string id = program.id;
  return id.rfind("creator_", 0) == 0 ? id.substr(8) : id;
}

void checkProgram(const creator::Program& program) {
  auto a = replay(program, 30), b = replay(program, 30), c = replay(program, 60);
  if (a.empty() || a != b || c.empty())
    throw Failure("no dibuja nada o no repite el mismo dibujo con la misma semilla "
                  "(usa Random(seed) sólo en reset; nada de relojes ni estado global).");
  if (a != replay(program, 30, true))
    throw Failure("dos reproducciones comparten estado: no uses variables globales ni static mutables.");
  if (a.size() != c.size())
    throw Failure("sin música, la cantidad de figuras cambia entre 30 y 60 FPS. Calcula cada "
                  "partícula con una fórmula del tiempo (edad = f.time - nacimiento) y un grupo "
                  "fijo reservado en reset; no crees ni sortees partículas por cuadro.");
  // Four seconds without events: positions and angles should advance by
  // elapsed time, not by callback count. Allow floating point integration.
  for (size_t i = 0; i < a.size(); ++i)
    if (std::abs(a[i] - c[i]) > .1f)
      throw Failure("sin música, el movimiento difiere entre 30 y 60 FPS. Acumula fases con "
                    "f.delta (fase += f.delta * velocidad) o usa fórmulas cerradas del tiempo; no "
                    "integres en posiciones valores suavizados por cuadro ni uses Random en update.");
  // Declared modifiers: 20 floats mean their initial values; any other
  // count, or a value that is not a finite number, is refused.
  const auto& defaults = program.modifiers;
  if (!defaults.empty() && a != replay(program, 30, false, &defaults))
    throw Failure("enviar los valores iniciales de los modificadores cambia el dibujo.");
  std::vector<float> wrong(21 + defaults.size(), 1);
  Instance probe(program);
  const bool extra = cp_configure(probe.handle, wrong.data(), uint32_t(wrong.size()), 1, 1, 0) == 1;
  bool invalid = false;
  if (!defaults.empty()) {
    wrong.resize(20 + defaults.size()); wrong[20] = std::nanf("");
    invalid = cp_configure(probe.handle, wrong.data(), uint32_t(wrong.size()), 1, 1, 0) == 1;
  }
  if (extra || invalid) throw Failure("aceptó valores de modificadores fuera de lo declarado.");
  std::cout << "PASS authored CPU " << program.id << ": independent instances, repeatable state, 30/60 FPS, "
            << a.size() * 4 << " command bytes\n";
}

#ifdef CREATOR_PROBE_CASES
struct Loud;
void warnPasses(const creator::Program& program, const std::string& with, const std::array<float, 4>& basics,
                const std::vector<float>& modifiers, const Loud& music);

/// Three seconds at 30 FPS with loud music (none when [reactive] is false,
/// as the app plays it). [switches] change the modifiers live at a frame,
/// which exercises the engine's transitions.
Clip play(const creator::Program& program, bool reactive, const std::array<float, 4>& basics,
          const std::vector<float>& modifiers, const Music& music, int fps = 30, int seconds = 3,
          const std::vector<std::pair<int, std::vector<float>>>& switches = {}) {
  Instance p(program);
  p.configure(options(basics, modifiers), 0, reactive);
  Clip clip;
  for (int i = 0; i <= fps * seconds; i++) {
    for (const auto& [frame, next] : switches)
      if (frame == i) p.configure(options(basics, next), double(i) / fps, reactive);
    if (!music.bytes.empty()) p.check(cp_consume(p.handle, music.frame(i * 30 / fps), frameBytes));
    p.check(cp_update(p.handle, 320, 568, double(i) / fps, 0));
    p.check(cp_draw(p.handle));
    clip.last = p.commands();
    clip.frames.push_back(digest(clip.last));
  }
  return clip;
}

/// Every extreme, option and variation with loud music. Returns the
/// modifiers that never change the drawing. Every setting at its maximum
/// and each variation also count their passes on the iPad, with the gate's
/// music [gate].
std::vector<std::string> sweep(const creator::Program& program, const CreatorProbeCase& probe, const Music& music,
                               const Loud& gate) {
  const std::array<float, 4> loud = {2, 1, 2, 2};  // intensity, speed, detail, glow
  const bool reactive = probe.reactive;
  std::vector<float> initial;
  for (const auto& modifier : probe.modifiers) initial.push_back(modifier.value);
  const auto base = play(program, reactive, loud, initial, music);
  if (base != play(program, reactive, loud, initial, music)) throw Failure("con música, no repite el mismo dibujo.");
  std::vector<std::string> dead;
  for (size_t i = 0; i < probe.modifiers.size(); i++) {
    const auto& modifier = probe.modifiers[i];
    std::vector<float> tries;
    if (modifier.kind == 2) tries = {1 - modifier.value};  // toggle
    else if (modifier.kind == 3) { for (float o = 0; o <= modifier.upper; o++) if (o != modifier.value) tries.push_back(o); }
    else tries = {modifier.lower, modifier.upper};
    bool changes = false;
    for (float value : tries) {
      auto values = initial; values[i] = value;
      try { changes |= play(program, reactive, loud, values, music) != base; }
      catch (const Failure& e) {
        throw Failure(std::string(modifier.id) + " = " + std::to_string(value) + ": " + e.what());
      }
    }
    if (!changes) dead.push_back(modifier.id);
  }
  auto all = [&](bool high) {
    std::vector<float> values;
    for (const auto& modifier : probe.modifiers) values.push_back(high ? modifier.upper : modifier.lower);
    return values;
  };
  const auto low = all(false), high = all(true);
  try { play(program, reactive, loud, low, music); } catch (const Failure& e) { throw Failure(std::string("todos al mínimo: ") + e.what()); }
  try { play(program, reactive, loud, high, music); } catch (const Failure& e) { throw Failure(std::string("todos al máximo: ") + e.what()); }
  warnPasses(program, "todos los ajustes al máximo", loud, high, gate);
  std::mt19937 random(7);
  for (int combo = 0; combo < 8; combo++) {
    std::vector<float> values;
    for (const auto& modifier : probe.modifiers) {
      std::uniform_real_distribution<float> any(modifier.lower, modifier.upper);
      const float value = any(random);
      values.push_back(modifier.kind == 0 ? value : std::round(value));
    }
    try { play(program, reactive, loud, values, music); }
    catch (const Failure& e) { throw Failure("combinación al azar " + std::to_string(combo) + ": " + e.what()); }
  }
  for (const auto& variation : probe.variations) {
    const auto& values = variation.modifiers.empty() ? initial : variation.modifiers;
    try { play(program, reactive, variation.controls, values, music); }
    catch (const Failure& e) { throw Failure(std::string("variación ") + variation.name + ": " + e.what()); }
    warnPasses(program, std::string("la variación ") + variation.name, variation.controls, values, gate);
  }
  if (!probe.modifiers.empty()) {
    try { play(program, reactive, loud, initial, music, 30, 3, {{30, high}, {45, low}}); }
    catch (const Failure& e) { throw Failure(std::string("cambio en vivo: ") + e.what()); }
  }
  // Non-initial values follow the same frame-rate rule, without music.
  const Music silence;
  const auto at30 = play(program, reactive, {1, 1, 1, 1}, high, silence, 30, 4).last;
  const auto at60 = play(program, reactive, {1, 1, 1, 1}, high, silence, 60, 4).last;
  bool same = at30.size() == at60.size();
  for (size_t i = 0; same && i < at30.size(); i++) same = std::abs(at30[i] - at60[i]) <= .1f;
  if (!same) throw Failure("con los modificadores al máximo, el movimiento difiere entre 30 y 60 FPS.");
  return dead;
}

/// Passes per frame of the iOS renderer (SceneCreatorCommandRenderer.render
/// in scene_compositor/ios/Classes/Runtime/SceneCatalogCreatorScene.swift),
/// replayed on the validated commands without a GPU. Every pass is a
/// w*h*4-byte texture that Core Image keeps until the frame ends; past 192
/// passes or 128 MiB the renderer drops the frame and the image freezes.
/// Paths are the only drawing that shares a pass, while their blend repeats.
struct Passes {
  int passes = 0;
  uint64_t bytes = 0;
  // Where they come from, for the message.
  int batches = 0, blendBreaks = 0, stateBreaks = 0, points = 0, materials = 0, clipped = 0;
};

/// CGAffineTransform in double, like CGFloat: (x, y) -> (a x + c y + tx, b x + d y + ty).
struct Affine {
  double a = 1, b = 0, c = 0, d = 1, tx = 0, ty = 0;
  /// `first.concatenating(then)`: first applied, then [then].
  static Affine concat(const Affine& m, const Affine& n) {
    return {m.a * n.a + m.b * n.c, m.a * n.b + m.b * n.d, m.c * n.a + m.d * n.c,
            m.c * n.b + m.d * n.d, m.tx * n.a + m.ty * n.c + n.tx, m.tx * n.b + m.ty * n.d + n.ty};
  }
};
struct Box { double x, y, width, height; };

/// CGRect.applying: the box around the four transformed corners.
Box applying(const Box& r, const Affine& t) {
  const double xs[2] = {std::min(r.x, r.x + r.width), std::max(r.x, r.x + r.width)};
  const double ys[2] = {std::min(r.y, r.y + r.height), std::max(r.y, r.y + r.height)};
  const double inf = std::numeric_limits<double>::infinity();
  double minX = inf, minY = inf, maxX = -inf, maxY = -inf;
  for (double x : xs) for (double y : ys) {
    const double px = t.a * x + t.c * y + t.tx, py = t.b * x + t.d * y + t.ty;
    minX = std::min(minX, px); maxX = std::max(maxX, px);
    minY = std::min(minY, py); maxY = std::max(maxY, py);
  }
  return {minX, minY, maxX - minX, maxY - minY};
}

int texels(double extent, int limit) {
  const double size = std::ceil(std::abs(extent));
  return size >= limit ? limit : size >= 1 ? int(size) : 1;
}

Passes countPasses(const float* c, size_t length, double viewWidth, double viewHeight, int width, int height) {
  Passes s;
  const Affine scale{double(width) / viewWidth, 0, 0, double(height) / viewHeight, 0, 0};
  Affine transform;
  int clips = 0, batchBlend = 0;
  bool pending = false;
  std::vector<std::pair<Affine, int>> stack;
  auto account = [&](int w, int h) { s.passes++; s.bytes += uint64_t(w) * uint64_t(h) * 4; };
  auto clipped = [&] { for (int i = 0; i < clips; i++) { account(width, height); s.clipped++; } };
  auto flush = [&](int* reason) {
    if (!pending) return;
    account(width, height); clipped(); pending = false; s.batches++;
    if (reason) (*reason)++;
  };
  size_t pos = 0;
  // Paint: color 4, blend, stroke width, cap, join, gradient, geometry 4, stops, 5 per stop.
  auto blendOf = [&](size_t paint) { return int(c[paint + 4]); };
  auto paintLength = [&](size_t paint) { return size_t(14 + 5 * int(c[paint + 13])); };
  while (pos + 2 <= length) {
    const int op = int(c[pos]);
    const size_t count = size_t(c[pos + 1]), body = pos + 2, end = body + count;
    switch (op) {
      case 1: case 3: flush(&s.stateBreaks); stack.push_back({transform, clips}); break;
      case 2:
        flush(&s.stateBreaks);
        if (!stack.empty()) { transform = stack.back().first; clips = stack.back().second; stack.pop_back(); }
        break;
      case 4: {
        flush(&s.stateBreaks);
        const Affine local{c[body], c[body + 1], c[body + 2], c[body + 3], c[body + 4], c[body + 5]};
        transform = Affine::concat(local, transform);
        break;
      }
      case 5: flush(&s.stateBreaks); clips++; break;
      case 6: {
        const int blend = blendOf(body);
        if (blend != batchBlend) { flush(&s.blendBreaks); batchBlend = blend; }
        pending = true;
        break;
      }
      case 7: {
        flush(nullptr);
        const size_t after = body + paintLength(body);
        const float radius = c[after];
        const int points = int(c[after + 1]);
        if (points > 0 && radius > 0) { account(width, height); clipped(); s.points++; }
        break;
      }
      case 8: flush(nullptr); clipped(); break;
      case 9: {
        flush(nullptr);
        const Box rect{c[body + 1], c[body + 2], c[body + 3], c[body + 4]};
        const Box physical = applying(applying(rect, transform), scale);
        account(texels(physical.width, width), texels(physical.height, height));
        clipped(); s.materials++;
        break;
      }
      default: break;
    }
    pos = end;
  }
  flush(nullptr);
  return s;
}

/// The renderer's guard: past 192 passes or 128 MiB it drops the frame.
constexpr int rendererPasses = 192;
constexpr uint64_t byteLimit = 128ull * 1024 * 1024;

/// Bytes of one full-screen pass on a [width] x [height] surface.
constexpr uint64_t fullScreen(int width, int height) { return uint64_t(width) * uint64_t(height) * 4; }

/// The most full-screen passes that fit in the guard on that surface.
constexpr int passLimitFor(int width, int height) {
  return int(std::min<uint64_t>(rendererPasses, byteLimit / fullScreen(width, height)));
}

/// The two surfaces of the app: the iPhone (664x1440 px, 852 logical points
/// high) and the iPad (900x1296 px, 1180 high). The viewport keeps the
/// logical height and takes the width from the pixel aspect, as iOS does.
/// Each one fails past the full-screen passes that fit in 128 MiB.
struct Surface { const char* name; int width, height; double logicalHeight; int passLimit; };
constexpr Surface surfaces[] = {{"iPhone", 664, 1440, 852, passLimitFor(664, 1440)},
                                {"iPad", 900, 1296, 1180, passLimitFor(900, 1296)}};
// The template, README.md and MAINTAINER.md quote these two numbers.
static_assert(surfaces[0].passLimit == 35 && surfaces[1].passLimit == 28, "update the template and the docs");
constexpr const Surface& iPad = surfaces[1];

/// The harness music: the loud synthetic signals (makeLoud) with the levels
/// x1.35, played from where the music starts; the silence that follows ends
/// the run. Frames are indexed as the energy harness does.
struct Loud {
  std::vector<uint8_t> bytes;
  size_t loudStart = 0, silenceStart = 0, silenceEnd = 0;
  bool empty() const { return bytes.empty(); }
  static bool active(const uint8_t* frame) { uint16_t flags; std::memcpy(&flags, frame + 6, 2); return (flags & 5) == 5; }
  explicit Loud(const Music& music) : bytes(music.bytes), loudStart(music.start) {
    const size_t frames = bytes.size() / frameBytes;
    for (size_t f = 0; f < frames; f++) {
      uint8_t* b = bytes.data() + f * frameBytes;
      if (!active(b)) continue;
      // dynamics[0..4], then channels, spectrum summary, instant and smoothed spectrum.
      for (size_t o = 40; o < 356; o += 4) {
        if (o == 60) continue;
        float v; std::memcpy(&v, b + o, 4);
        v = std::min(1.f, std::max(0.f, v * 1.35f));
        std::memcpy(b + o, &v, 4);
      }
    }
    silenceStart = loudStart;
    while (silenceStart < frames && active(bytes.data() + silenceStart * frameBytes)) silenceStart++;
    silenceEnd = silenceStart;
    while (silenceEnd < frames && !active(bytes.data() + silenceEnd * frameBytes)) silenceEnd++;
  }
  /// Signal frame for app frame [i] of [frames], the last [silent] of them silent.
  const uint8_t* frame(int i, int frames, int silent, int fps) const {
    const int loud = frames - silent;
    const size_t index = i < loud
      ? loudStart + size_t(double(i) * 30 / double(fps)) % std::max<size_t>(1, silenceStart - loudStart)
      : std::min(silenceEnd - 1, silenceStart + size_t(double(i - loud) * 30 / double(fps)));
    return bytes.data() + index * frameBytes;
  }
};

struct SurfacePasses { Passes most; uint64_t bytes = 0; double at = 0; };

/// Plays [program] like the app (its fps, seed, controls, colors and
/// reactivity) and keeps its most expensive frame. [basics] and [modifiers]
/// replace its initial controls and modifiers.
SurfacePasses playPasses(const creator::Program& program, const CreatorPassCase& visual, const Surface& surface,
                         const Loud& music, int frames, int silent, const std::array<float, 4>* basics = nullptr,
                         const std::vector<float>* modifiers = nullptr) {
  Instance p(program, visual.seed);
  std::vector<float> values;
  if (basics) values.assign(basics->begin(), basics->end());
  else for (double control : visual.controls) values.push_back(float(control));
  for (uint32_t argb : visual.colors) {
    const auto color = creator::Color::argb(argb);
    values.insert(values.end(), {color.r, color.g, color.b, color.a});
  }
  if (modifiers) values.insert(values.end(), modifiers->begin(), modifiers->end());
  p.configure(values, 0, visual.reactive);
  const double viewHeight = surface.logicalHeight;
  const double viewWidth = surface.logicalHeight * surface.width / surface.height;
  SurfacePasses result;
  for (int i = 0; i < frames; i++) {
    if (!music.empty()) p.check(cp_consume(p.handle, music.frame(i, frames, silent, visual.fps), frameBytes));
    p.check(cp_update(p.handle, viewWidth, viewHeight, double(i) / visual.fps, 0));
    p.check(cp_draw(p.handle));
    const auto counted = countPasses(cp_commands(p.handle), cp_command_length(p.handle),
                                     viewWidth, viewHeight, surface.width, surface.height);
    if (counted.passes > result.most.passes) { result.most = counted; result.at = double(i) / visual.fps; }
    result.bytes = std::max(result.bytes, counted.bytes);
  }
  return result;
}

const CreatorPassCase& passCase(const creator::Program& program) {
  for (const auto& visual : creatorPassCases())
    if (std::strcmp(visual.program, program.id) == 0) return visual;
  throw Failure("falta su caso de pasadas: vuelve a generar el catálogo.");
}

/// The gate plays the initial settings; the sweep asks for its other ones
/// here (every setting at its maximum, each variation): the same 14 s on
/// the iPad, a warning and never a failure.
void warnPasses(const creator::Program& program, const std::string& with, const std::array<float, 4>& basics,
                const std::vector<float>& modifiers, const Loud& music) {
  try {
    const auto& visual = passCase(program);
    const auto run = playPasses(program, visual, iPad, music, 14 * visual.fps, 2 * visual.fps, &basics, &modifiers);
    if (run.most.passes > iPad.passLimit)
      std::cout << "WARN passes " << program.id << ": " << run.most.passes << " pasadas con " << with << " (máx "
                << iPad.passLimit << " en iPad)\n";
  } catch (const Failure& e) {
    std::cout << "WARN passes " << program.id << ": no se pudieron contar con " << with << ": " << e.what() << "\n";
  }
}

std::string decimal(double value, const char* format = "%.1f") {
  char text[32]; std::snprintf(text, sizeof text, format, value);
  std::string result = text;
  for (auto& ch : result) if (ch == '.') ch = ',';
  return result;
}

/// --pass-report harness: the energy harness schedule (240 frames at the
/// visual's fps, the last 60 silent), max passes and bytes on each surface.
void reportPasses(const creator::Program& program, const Loud& music) {
  const auto& visual = passCase(program);
  std::cout << "PASSES " << program.id << " fps " << visual.fps;
  for (const auto& surface : surfaces) {
    const auto run = playPasses(program, visual, surface, music, 240, 60);
    std::cout << " " << surface.name << " " << run.most.passes << " " << run.bytes;
  }
  std::cout << "\n";
}

/// The gate: 12 s of loud music and 2 s of silence at the visual's fps.
/// A frame over its surface's limit (35 passes on the iPhone, 28 on the
/// iPad) or over 128 MiB fails; the message says what each surface exceeded.
void checkPasses(const creator::Program& program, const Loud& music) {
  const auto& visual = passCase(program);
  if (music.empty() && visual.reactive) throw Failure("faltan las señales de música para contar sus pasadas.");
  SurfacePasses runs[2];
  bool overPasses[2], overBytes[2];
  for (int k = 0; k < 2; k++) {
    try { runs[k] = playPasses(program, visual, surfaces[k], music, 14 * visual.fps, 2 * visual.fps); }
    catch (const Failure& e) { throw Failure(std::string("al contar sus pasadas: ") + e.what()); }
    overPasses[k] = runs[k].most.passes > surfaces[k].passLimit;
    overBytes[k] = runs[k].bytes > byteLimit;
  }
  auto counted = [&](int k) {
    return std::to_string(runs[k].most.passes) + " (máx " + std::to_string(surfaces[k].passLimit) + ")";
  };
  if (!overPasses[0] && !overBytes[0] && !overPasses[1] && !overBytes[1]) {
    std::cout << "PASS passes " << program.id << ": iPhone " << counted(0) << ", iPad " << counted(1) << "\n";
    return;
  }
  auto mib = [](uint64_t bytes, const char* format) { return decimal(double(bytes) / 1048576, format) + " MiB"; };
  // Only what was exceeded, per surface, and where each limit comes from.
  std::string exceeded, limits, fine;
  int k = -1;  // the failing surface whose most expensive frame is broken down
  for (int s = 0; s < 2; s++) {
    const auto& surface = surfaces[s];
    const std::string passes = std::to_string(runs[s].most.passes), limit = std::to_string(surface.passLimit);
    if (!overPasses[s] && !overBytes[s]) {
      fine = std::string(" El ") + surface.name + " cumple: " + passes + " de " + limit + ".";
      continue;
    }
    if (k < 0 || runs[s].most.passes > runs[k].most.passes) k = s;
    if (!exceeded.empty()) exceeded += "; ";
    exceeded += passes + " pasadas por cuadro en el " + surface.name;
    if (overPasses[s]) exceeded += " (máx " + limit + ")";
    if (overBytes[s]) exceeded += " y " + mib(runs[s].bytes, "%.1f") + " (máx 128)";
    if (overPasses[s])
      limits += std::string(" En el ") + surface.name + " cada pasada de pantalla completa ocupa " +
                mib(fullScreen(surface.width, surface.height), "%.2f") + ": " + limit + " ya llenan " +
                mib(surface.passLimit * fullScreen(surface.width, surface.height), "%.1f") + ".";
  }
  const auto& at = runs[k].most;
  throw Failure(exceeded + ". La app no publica un cuadro de más de 128 MiB: la imagen se queda congelada." +
    limits + fine + " En el cuadro más caro (" + surfaces[k].name + ", " + decimal(runs[k].at) +
    " s): lotes de figuras " + std::to_string(at.batches) + " (" + std::to_string(at.stateBreaks) +
    " cortados por save/restore/transform/clip, " + std::to_string(at.blendBreaks) +
    " por cambiar de mezcla), points() " + std::to_string(at.points) + ", materiales " +
    std::to_string(at.materials) + ", recortes activos " + std::to_string(at.clipped) +
    ". Cada lote de figuras, points() y recorte activo es una pasada de pantalla completa; cada material, "
    "una pasada del tamaño de su rectángulo. Bájalas así: "
    "agrupa por mezcla (dibuja seguidas todas las figuras con la misma Blend), un lote de puntos (todas las "
    "partículas de un color en un solo points()), transforma en C++ (calcula tú las coordenadas en vez de "
    "save/translate/rotate/restore por figura) y sin recorte por celda (nada de clip dentro de un bucle).");
}
#endif

}  // namespace

int main(int argc, char** argv) {
  Music music;
  bool strict = false;
  std::string report;
  for (int i = 1; i < argc; i++) {
    const std::string arg = argv[i];
    if (arg == "--strict-modifiers") { strict = true; continue; }
    if (arg == "--pass-report") {
      if (i + 1 >= argc || std::string(argv[i + 1]) != "harness") { std::cerr << "--pass-report sólo admite harness.\n"; return 1; }
      report = argv[++i];
      continue;
    }
    std::ifstream file(arg, std::ios::binary);
    music.bytes.assign(std::istreambuf_iterator<char>(file), {});
    if (music.bytes.empty() || music.bytes.size() % frameBytes) {
      std::cerr << "Señales inválidas: " << arg << "\n";
      return 1;
    }
    music.makeLoud();
  }
  int failures = 0;
#ifdef CREATOR_PROBE_CASES
  const Loud loud(music);
  if (!report.empty()) {
    if (loud.empty()) { std::cerr << "Faltan las señales de música.\n"; return 1; }
    for (const auto& program : creator::installedPrograms()) {
      try { reportPasses(program, loud); }
      catch (const std::exception& e) { std::cerr << "FAIL " << visualName(program) << ": " << e.what() << "\n"; failures++; }
    }
    return failures ? 1 : 0;
  }
#else
  if (!report.empty()) { std::cerr << "Faltan los casos generados (creator_probe_cases.inc).\n"; return 1; }
#endif
  // Every visual is checked even when one fails, so one fix never hides the next.
  for (const auto& program : creator::installedPrograms()) {
    bool runs = false;
    try {
      checkProgram(program);
      runs = true;
#ifdef CREATOR_PROBE_CASES
      for (const auto& probe : creatorProbeCases()) {
        if (std::strcmp(probe.program, program.id) != 0) continue;
        if (music.bytes.empty()) throw Failure("faltan las señales de música para probar sus modificadores.");
        const auto dead = sweep(program, probe, music, loud);
        for (const auto& id : dead) {
          std::cout << (strict ? "FAIL " : "WARN ") << visualName(program) << ": el modificador " << id
                    << " no cambia nada, ni en sus extremos ni con música.\n";
          if (strict) failures++;
        }
        std::cout << "PASS modifiers " << program.id << ": extremes, options, variations, live change, 30/60 FPS\n";
      }
#endif
    } catch (const std::exception& e) {
      std::cerr << "FAIL " << visualName(program) << ": " << e.what() << "\n";
      failures++;
    }
#ifdef CREATOR_PROBE_CASES
    // Energy: its own check, so a modifier failure never hides it.
    if (runs) {
      try { checkPasses(program, loud); }
      catch (const std::exception& e) {
        std::cerr << "FAIL " << visualName(program) << ": " << e.what() << "\n";
        failures++;
      }
    }
#else
    (void)runs;
#endif
  }
  if (failures) {
    std::cerr << failures << " problema(s). Copia cada línea FAIL, la plantilla y el archivo del visual a la IA.\n";
    return 1;
  }
}
