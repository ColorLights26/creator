#include "creator_scene.hpp"
#include "creator_abi.h"
#include <cassert>
#include <cstring>
#include <fstream>
#include <iostream>
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
  explicit Instance(const creator::Program& program) : handle(cp_create(program.id, program.hash, 42)) {
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
/// modifiers that never change the drawing.
std::vector<std::string> sweep(const creator::Program& program, const CreatorProbeCase& probe, const Music& music) {
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
    try { play(program, reactive, variation.controls, variation.modifiers.empty() ? initial : variation.modifiers, music); }
    catch (const Failure& e) { throw Failure(std::string("variación ") + variation.name + ": " + e.what()); }
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
#endif

}  // namespace

int main(int argc, char** argv) {
  Music music;
  bool strict = false;
  for (int i = 1; i < argc; i++) {
    const std::string arg = argv[i];
    if (arg == "--strict-modifiers") { strict = true; continue; }
    std::ifstream file(arg, std::ios::binary);
    music.bytes.assign(std::istreambuf_iterator<char>(file), {});
    if (music.bytes.empty() || music.bytes.size() % frameBytes) {
      std::cerr << "Señales inválidas: " << arg << "\n";
      return 1;
    }
    music.makeLoud();
  }
  int failures = 0;
  // Every visual is checked even when one fails, so one fix never hides the next.
  for (const auto& program : creator::installedPrograms()) {
    try {
      checkProgram(program);
#ifdef CREATOR_PROBE_CASES
      for (const auto& probe : creatorProbeCases()) {
        if (std::strcmp(probe.program, program.id) != 0) continue;
        if (music.bytes.empty()) throw Failure("faltan las señales de música para probar sus modificadores.");
        const auto dead = sweep(program, probe, music);
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
  }
  if (failures) {
    std::cerr << failures << " problema(s). Copia cada línea FAIL, la plantilla y el archivo del visual a la IA.\n";
    return 1;
  }
}
