// Marmoleado — arte ebru: tinta sobre agua peinada en plumas.
// Sigue el modelo matemático del marmoleado: cada gota de tinta empuja
// hacia fuera todo lo que ya flota (los anillos anteriores se estiran sin
// mezclarse) y cada pasada de peine arrastra la tinta a lo largo de sus púas
// formando plumas. Para pintar cada píxel se deshacen las operaciones de la
// más nueva a la más vieja hasta dar con la gota que lo tiñe. Las gotas caen
// en cinco puntos y forman dianas hasta cubrir el baño; luego llegan peines
// rectos, cruzados y ondulados y un remolino. Cada gota y cada peine se
// calculan una vez por frame y el shader sólo los deshace en orden. Con
// música, según el pulso, cada golpe deja caer la siguiente gota o pasa el
// peine, los graves inflan la última gota y empujan la tinta alrededor, o
// los agudos hacen correr la luz por los bordes de la tinta mojada; los
// graves dan brillo. En modo remolino el baño gira como un vórtice desde la
// primera gota. Al completar el dibujo, el papel se levanta con una cortina
// y empieza otro baño.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.slider('gotas', 'Tamaño de gotas', min: .6, max: 1.6, value: 1),
  CreatorModifier.slider('peine', 'Púas del peine', min: .5, max: 2, value: 1),
  // MÚSICA: qué parte del baño responde al ritmo.
  CreatorModifier.choice(
    'ritmo',
    'Pulso',
    options: ['Graves', 'Golpes', 'Brillos'],
    value: 1,
  ),
  // MODO: tinta en dianas y plumas o un baño que gira como un vórtice.
  CreatorModifier.toggle('remolino', 'Remolino'),
];

const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kOps = 16;
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double opClock = 0, wipe = -1, bathClock = 0, shine = 0;
  int cycle = 0, opsDone = 0;
  bool pending = false;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  static float hash(int a, int b, int salt) {
    uint32_t x = uint32_t(a) * 73856093u ^ uint32_t(b) * 19349663u ^ uint32_t(salt) * 83492791u;
    x ^= x >> 16;
    x *= 0x7feb352du;
    x ^= x >> 15;
    x *= 0x846ca68bu;
    x ^= x >> 16;
    return float(x >> 8) / 16777216.0f;
  }

  // Tipo de operación: 0 gota, 1 peine, 2 peine ondulado, 3 remolino.
  // Primero muchas gotas cubren el baño; luego se alternan peines y gotas.
  // El orden es fijo: el shader llama a la función de cada tipo sin ramas.
  static int opType(int i) {
    if (i == 9 || i == 11) return 1;
    if (i == 14) return 2;
    if (i == 15) return 3;
    return 0;
  }

 public:
  void reset(uint32_t seed) override {
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    cycle = int(seed % 97u);
    opsDone = 0;
    opClock = 0;
    wipe = -1;
    bathClock = shine = 0;
    pending = false;
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
    // Pulso «Golpes»: cada golpe adelanta la siguiente gota o peine; con los
    // otros pulsos el baño sigue su propio ritmo.
    bool onBeats = m.ritmo == 1;
    if (onBeats && hit > kick + 0.2f) pending = true;
    if (!onBeats) pending = false;
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));

    // Reloj propio de la luz que corre por los bordes (Brillos).
    shine = std::fmod(shine + f.delta * f.speed * 4.0, 6.283185307179586);
    opClock += f.delta * f.speed;
    if (wipe >= 0.0) {
      wipe += f.delta * f.speed / 1.3;
      if (wipe >= 1.0) {
        wipe = -1;
        opClock = 0;
        bathClock = 0;
      }
      return;
    }
    // El vórtice del modo remolino se enrosca con el tiempo del baño.
    bathClock = std::min(bathClock + f.delta * f.speed, 40.0);
    // La siguiente operación llega con un golpe o, sin música, a su ritmo.
    double idle = 1.5;
    if (opClock > 0.75 && (pending || opClock > idle)) {
      // Sin música se conserva el sobrante: el ritmo no depende de los FPS.
      opClock = pending ? 0.0 : opClock - idle;
      pending = false;
      if (opsDone >= kOps - 1) {
        cycle++;
        opsDone = 0;
        wipe = 0;
      } else {
        opsDone++;
      }
    }
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    auto g = glide(f);
    float amp = f.intensity;
    // Pulso: Graves, Golpes y Brillos, mezclados por sus pesos mientras cambian.
    float graves = g.ritmo.weight(0), golpes = g.ritmo.weight(1), brillos = g.ritmo.weight(2);
    // Graves: inflan la gota más reciente hasta un 25% y empujan la tinta.
    float swell = 1.0f + 0.25f * graves * std::min(bass * amp, 1.0f);
    float side = std::min(f.width, f.height);
    float halfH = 0.5f * f.height / side;
    // Durante la cortina se describe el baño anterior completo.
    bool wiping = wipe >= 0.0;
    int bath = wiping ? cycle - 1 : cycle;
    int shown = wiping ? kOps : opsDone + 1;
    float progress = float(std::min(opClock / 0.75, 1.0));
    float ease = 1.0f - (1.0f - progress) * (1.0f - progress);
    std::vector<float> u;
    u.reserve(96);
    // Remolino: el giro del vórtice en el centro, que se enrosca con el baño.
    float vortex = g.remolino * (2.2f + 0.1f * float(bathClock));
    u.insert(u.end(), {float(((bath % 1000) + 1000) % 1000), wiping ? float(wipe) : -1.0f,
                       kick * amp * golpes, bass * amp});
    u.insert(u.end(), {0.11f / m.peine, f.glow, flash * amp, vortex});
    float glints = brillos * std::clamp((spark * 1.2f + flash) * amp, 0.0f, 1.0f);
    u.insert(u.end(), {glints, float(shine), 0.0f, 0.0f});
    int startAnchor = int(hash(bath, 0, 9) * 5.0f);
    int newestDrop = -1;
    for (int i = 0; i < std::min(shown, kOps); i++) {
      if (opType(i) == 0) newestDrop = i;
    }
    for (int i = 0; i < kOps; i++) {
      // Las operaciones que aún no llegan no mueven nada (radio o arrastre 0).
      float e = i >= shown ? 0.0f : ((!wiping && i == opsDone) ? ease : 1.0f);
      int type = opType(i);
      if (type == 0) {
        // Gota: cinco puntos repartidos; al repetir punto se forman dianas.
        int anchor = (i + startAnchor) % 5;
        float cx = (hash(bath, anchor, 2) - 0.5f) * 0.7f + (hash(bath, i, 3) - 0.5f) * 0.08f;
        float cy = ((float(anchor) + 0.5f) / 5.0f - 0.5f) * halfH * 1.7f + (hash(bath, i, 4) - 0.5f) * 0.08f;
        float r = (0.17f + 0.17f * hash(bath, i, 5)) * m.gotas * e * (i == newestDrop ? swell : 1.0f);
        u.insert(u.end(), {cx, cy, r, float(((bath + i + anchor) % 4 + 4) % 4)});
      } else if (type == 3) {
        u.insert(u.end(), {0.0f, 0.0f, 3.2f * e, 0.0f});
      } else {
        float a = i == 9 ? 1.5707963f : (i == 11 ? 0.0f : 0.785f);
        float sgn = hash(bath, i, 6) > 0.5f ? 1.0f : -1.0f;
        u.insert(u.end(), {std::cos(a) * sgn, std::sin(a) * sgn, 0.16f * e, 0.0f});
      }
    }
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("ebru", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'ebru': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // baño, cortina, golpe, graves
uniform vec4 uB;   // separación de púas, glow, destello, vórtice
uniform vec4 uE;   // brillos: cantidad, fase de la luz
uniform vec4 uO0;  // operaciones en orden fijo: gota (x, y, radio, tinta),
uniform vec4 uO1;  // peine (dirección x, y, arrastre) y remolino (-, -, giro)
uniform vec4 uO2;
uniform vec4 uO3;
uniform vec4 uO4;
uniform vec4 uO5;
uniform vec4 uO6;
uniform vec4 uO7;
uniform vec4 uO8;
uniform vec4 uO9;
uniform vec4 uO10;
uniform vec4 uO11;
uniform vec4 uO12;
uniform vec4 uO13;
uniform vec4 uO14;
uniform vec4 uO15;
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

vec3 ink(float k) {
  if (k < 1.0) return uC1;
  if (k < 2.0) return uC2;
  if (k < 3.0) return uC3;
  return vec3(0.96, 0.93, 0.86);
}

// Deshacer una gota: si el punto cae dentro, toma su tinta; si no, vuelve
// a donde estaba antes de que la gota lo empujara. rim junta su borde
// visible (para los Brillos).
void undoDrop(inout vec2 P, inout vec3 col, inout float w, inout float rim, vec4 O) {
  vec2 d = P - O.xy;
  float q = dot(d, d);
  float r2 = O.z * O.z;
  float edge = (sqrt(q) - O.z) * 220.0;
  rim += w * (exp(-edge * edge) + 0.3 * uB.y * exp(-abs(edge) * 0.35)) * step(1e-4, O.z);
  float f = clamp((r2 - q) / (O.z * 0.016 + 1e-5) + 0.5, 0.0, 1.0);
  col += w * f * ink(O.w);
  w *= 1.0 - f;
  P = O.xy + d * sqrt(max(1.0 - r2 / max(q, r2 + 1e-6), 0.0));
}

// Deshacer una pasada de peine: arrastre máximo junto a cada púa.
void undoComb(inout vec2 P, vec4 O, float wavy) {
  vec2 M = O.xy;
  float across = dot(P, vec2(-M.y, M.x)) + wavy * 0.05 * sin(dot(P, M) * 9.0 + uA.x);
  float spacing = uB.x;
  float tine = abs(fract(across / spacing) - 0.5) * spacing;
  float k = max(1.0 - tine / 0.07, 0.0);
  P -= M * O.z * k * k * k;
}

// Deshacer un giro: girar al revés, más cerca del centro.
void undoTwist(inout vec2 P, float amount, float reach) {
  float ang = -amount * exp(-length(P) / reach);
  float cs = cos(ang);
  float sn = sin(ang);
  P = vec2(cs * P.x - sn * P.y, sn * P.x + cs * P.y);
}

// Deshacer el remolino final.
void undoSwirl(inout vec2 P, vec4 O) {
  undoTwist(P, O.z, 0.32);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  float halfH = 0.5 * uSize.y / scale;
  // Cortina: el papel se levanta de arriba abajo y deja el agua limpia.
  float line = -halfH - 0.1 + uA.y * (2.0 * halfH + 0.2);
  vec3 col = uC0;
  float rim = 0.0;
  if (uA.y < 0.0 || p.y > line) {
    vec2 P = p;
    vec3 acc = vec3(0.0);
    float w = 1.0;
    // Vórtice del modo remolino: lo más nuevo, se deshace primero.
    undoTwist(P, uB.w, 0.3);
    undoSwirl(P, uO15);
    undoComb(P, uO14, 1.0);
    undoDrop(P, acc, w, rim, uO13);
    undoDrop(P, acc, w, rim, uO12);
    undoComb(P, uO11, 0.0);
    undoDrop(P, acc, w, rim, uO10);
    undoComb(P, uO9, 0.0);
    undoDrop(P, acc, w, rim, uO8);
    undoDrop(P, acc, w, rim, uO7);
    undoDrop(P, acc, w, rim, uO6);
    undoDrop(P, acc, w, rim, uO5);
    undoDrop(P, acc, w, rim, uO4);
    undoDrop(P, acc, w, rim, uO3);
    undoDrop(P, acc, w, rim, uO2);
    undoDrop(P, acc, w, rim, uO1);
    undoDrop(P, acc, w, rim, uO0);
    col = acc + w * uC0;
  }
  if (uA.y >= 0.0) col += vec3(1.0) * exp(-abs(p.y - line) * 120.0) * 0.5;
  // Brillo húmedo de la tinta y grano del agua.
  col *= 0.9 + 0.18 * uA.w + 0.12 * uA.z;
  col *= 0.97 + 0.03 * hash12(floor(frag * 0.5));
  col += uC1 * uB.z * 0.04;
  // Brillos: con los agudos, la luz corre por los bordes de la tinta.
  float shimmer = 0.5 + 0.5 * sin(dot(p, vec2(23.0, 14.0)) - uE.y);
  col += (vec3(1.0) - col) * clamp(rim, 0.0, 1.0) * (0.25 + 0.75 * shimmer * shimmer) * uE.x * 0.8;
  col *= 1.0 - 0.25 * smoothstep(0.7, 1.5, length(p * vec2(0.9, 0.6)));
  col += (hash12(frag) - 0.5) / 255.0;
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
