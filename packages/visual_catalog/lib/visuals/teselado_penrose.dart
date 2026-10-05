// Teselado de Penrose — un mosaico que nunca se repite.
// Se parte de una rueda de diez triángulos de Robinson y cada píxel baja por
// sus subdivisiones (cada triángulo se parte en dos o tres más pequeños según
// la proporción áurea) hasta dar con su pieza: así aparece el teselado de
// rombos gruesos (ámbar) y finos (rojos) de Penrose, con su simetría de cinco
// puntas, sin que el dibujo se repita nunca. En Piezas, otros cortes dan el
// otro mosaico de Penrose: cometas (ámbar) y dardos (rojos). Detalle decide
// cuántas veces se subdivide. Cada pieza tiene un tono propio y juntas casi
// brillan. Cada golpe lanza desde el centro una onda con forma de pentágono
// que enciende las piezas enteras a su paso; los graves avivan los bordes y
// el mosaico gira despacio.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.choice('piezas', 'Piezas', options: ['Rombos', 'Cometas y dardos']),
  CreatorModifier.slider('giro', 'Giro', min: 0, max: 2, value: 1),
  CreatorModifier.toggle('ondas', 'Ondas de luz', value: true),
  CreatorModifier.toggle('bordes', 'Bordes brillantes', value: true),
];

const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kWaves = 3;
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double spin = 0, clock = 0, sinceIdle = 0;
  std::array<double, kWaves> waveAge{};
  std::array<float, kWaves> wavePower{};
  int nextWave = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  void launch(float power, double age) {
    waveAge[size_t(nextWave)] = age;
    wavePower[size_t(nextWave)] = power;
    nextWave = (nextWave + 1) % kWaves;
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    spin = rng.unit() * 6.2831853;
    clock = 0;
    sinceIdle = 0;
    waveAge.fill(100.0);
    wavePower.fill(0.0f);
    nextWave = 0;
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
    for (auto& a : waveAge) a += f.delta * f.speed;
    sinceIdle += f.delta;
    if (hit > kick + 0.2f && m.ondas) {
      launch(0.6f + 0.6f * hit, 0.0);
      sinceIdle = 0;
    }
    if (!mu.active && m.ondas && sinceIdle > 2.5) {
      sinceIdle -= 2.5;
      launch(0.75f, sinceIdle);
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    spin += f.delta * f.speed * m.giro * (0.025 + 0.05 * drive);
    clock += f.delta * f.speed;
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    auto g = glide(f);
    float amp = f.intensity;
    // Detalle (0,25 a 2) da de 4 a 8 subdivisiones: 6 con el valor normal.
    int levels = std::clamp(int(std::lround(4.0f + (f.detail - 0.25f) / 1.75f * 4.0f)), 4, 8);
    std::vector<float> u;
    u.reserve(33);
    u.insert(u.end(), {float(std::fmod(spin, 6.2831853)), bass * amp, kick * amp, energy});
    u.insert(u.end(), {float(levels), m.bordes ? 1.0f : 0.0f, f.glow, flash * amp});
    std::array<float, 4> radius{9, 9, 9, 9}, power{0, 0, 0, 0};
    for (int i = 0; i < kWaves; i++) {
      if (waveAge[size_t(i)] < 4.0) {
        radius[size_t(i)] = float(waveAge[size_t(i)]) * 0.55f;
        power[size_t(i)] = wavePower[size_t(i)] * float(1.0 - waveAge[size_t(i)] / 4.0) * amp;
      }
    }
    u.insert(u.end(), {radius[0], radius[1], radius[2], float(std::fmod(clock, 1000.0))});
    u.insert(u.end(), {power[0], power[1], power[2], spark * amp});
    // Piezas: peso de cometas y dardos; al cambiar, un mosaico se funde en el otro.
    u.push_back(std::clamp(g.piezas.weight(1), 0.0f, 1.0f));
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("penrose", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'penrose': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // giro, graves, golpe, energía
uniform vec4 uB;   // niveles, bordes, glow, destello
uniform vec4 uW;   // radios de las ondas, reloj
uniform vec4 uP;   // fuerza de las ondas, agudos
uniform float uK;  // peso de cometas y dardos (0 = rombos)
uniform vec3 uC0;
uniform vec3 uC1;
uniform vec3 uC2;
uniform vec3 uC3;
out vec4 fragColor;

const float PI = 3.14159265;
const float PHI = 1.6180340;

float hash11(float n) {
  n = fract(n * 0.1031);
  n *= n + 33.33;
  n *= n + n;
  return fract(n);
}

float hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

float cross2(vec2 a, vec2 b) { return a.x * b.y - a.y * b.x; }

// ¿Están p y r al mismo lado de la recta a→b?
bool sameSide(vec2 p, vec2 r, vec2 a, vec2 b) {
  return cross2(b - a, p - a) * cross2(b - a, r - a) >= 0.0;
}

float segDist(vec2 p, vec2 a, vec2 b) {
  vec2 pa = p - a;
  vec2 ba = b - a;
  float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
  return length(pa - ba * h);
}

// Distancia "pentagonal": así las ondas tienen cinco puntas.
float pentaDist(vec2 p) {
  float d = dot(p, vec2(0.0, 1.0));
  d = max(d, dot(p, vec2(-0.9510565, 0.3090170)));
  d = max(d, dot(p, vec2(-0.5877853, -0.8090170)));
  d = max(d, dot(p, vec2(0.5877853, -0.8090170)));
  return max(d, dot(p, vec2(0.9510565, 0.3090170)));
}

// Color de la pieza bajo q en uno de los dos mosaicos de Penrose: rombos
// (P3) o cometas y dardos (P2). Ambos parten de una rueda de diez triángulos
// de Robinson y bajan por sus subdivisiones; cada pieza son dos triángulos
// unidos por BC, así que sus bordes son AB y AC.
vec3 tile(vec2 q, bool kites) {
  float R0 = 1.5;
  float ang = atan(q.y, q.x);
  float i = mod(floor((ang + PI / 10.0) / (PI / 5.0)), 10.0);
  vec2 A = vec2(0.0);
  vec2 B = R0 * vec2(cos((2.0 * i - 1.0) * PI / 10.0), sin((2.0 * i - 1.0) * PI / 10.0));
  vec2 C = R0 * vec2(cos((2.0 * i + 1.0) * PI / 10.0), sin((2.0 * i + 1.0) * PI / 10.0));
  if (mod(i, 2.0) < 0.5) {
    vec2 tmp = B;
    B = C;
    C = tmp;
  }
  if (kites) {
    // En cometas y dardos el vértice del ángulo agudo va en medio (B).
    vec2 tmp = A;
    A = B;
    B = tmp;
  }
  float kind = 0.0;
  for (int level = 0; level < 8; level++) {
    if (float(level) >= uB.x) break;
    if (kites) {
      if (kind < 0.5) {
        // Media cometa: se parte en dos medias cometas y un medio dardo.
        vec2 Q = A + (B - A) / PHI;
        vec2 Rr = B + (C - B) / PHI;
        if (sameSide(q, B, Q, Rr)) {
          vec2 nA = Rr; vec2 nB = Q; vec2 nC = B; A = nA; B = nB; C = nC;
          kind = 1.0;
        } else if (sameSide(q, C, A, Rr)) {
          vec2 nA = C; vec2 nB = A; vec2 nC = Rr; A = nA; B = nB; C = nC;
        } else {
          vec2 nA = Q; vec2 nB = A; vec2 nC = Rr; A = nA; B = nB; C = nC;
        }
      } else {
        // Medio dardo: se parte en un medio dardo y una media cometa.
        vec2 P = C + (A - C) / PHI;
        if (sameSide(q, A, B, P)) {
          vec2 nA = B; vec2 nB = P; vec2 nC = A; A = nA; B = nB; C = nC;
          kind = 1.0;
        } else {
          vec2 nA = P; vec2 nB = C; vec2 nC = B; A = nA; B = nB; C = nC;
          kind = 0.0;
        }
      }
    } else if (kind < 0.5) {
      // Triángulo fino: se parte en dos.
      vec2 P = A + (B - A) / PHI;
      if (sameSide(q, B, C, P)) {
        A = C; vec2 nB = P; vec2 nC = B; B = nB; C = nC;
        kind = 0.0;
      } else {
        vec2 nA = P; vec2 nB = C; vec2 nC = A; A = nA; B = nB; C = nC;
        kind = 1.0;
      }
    } else {
      // Triángulo grueso: se parte en tres.
      vec2 Q = B + (A - B) / PHI;
      vec2 Rr = B + (C - B) / PHI;
      if (sameSide(q, C, Rr, A)) {
        vec2 nA = Rr; vec2 nB = C; vec2 nC = A; A = nA; B = nB; C = nC;
        kind = 1.0;
      } else if (sameSide(q, B, Q, Rr)) {
        vec2 nA = Q; vec2 nB = Rr; vec2 nC = B; A = nA; B = nB; C = nC;
        kind = 1.0;
      } else {
        vec2 nA = Rr; vec2 nB = Q; vec2 nC = A; A = nA; B = nB; C = nC;
        kind = 0.0;
      }
    }
  }
  // La pieza son dos triángulos unidos por BC; su centro es el de BC.
  vec2 center = (B + C) * 0.5;
  float tileHash = hash11(floor(center.x * 97.0) + floor(center.y * 61.0) * 13.0);
  // Ámbar para rombos gruesos y cometas; rojo para rombos finos y dardos.
  bool amber = kites ? kind < 0.5 : kind > 0.5;
  vec3 col = amber ? uC1 : uC2;
  col *= 0.62 + 0.38 * tileHash;
  col *= 0.85 + 0.25 * uA.y;
  // Ondas pentagonales que encienden piezas enteras.
  float dc = pentaDist(center);
  float light = 0.0;
  light += uP.x * smoothstep(0.09, 0.0, abs(dc - uW.x));
  light += uP.y * smoothstep(0.09, 0.0, abs(dc - uW.y));
  light += uP.z * smoothstep(0.09, 0.0, abs(dc - uW.z));
  col = mix(col, uC3, clamp(light, 0.0, 1.0) * 0.85);
  // Bordes de las piezas (AB y AC; BC es la línea interior).
  float scale = min(uSize.x, uSize.y);
  float e = min(segDist(q, A, B), segDist(q, A, C));
  float px = 1.0 / scale;
  float edge = 1.0 - smoothstep(px * 0.8, px * 2.2, e);
  vec3 edgeCol = uB.y > 0.5 ? mix(uC0, uC3, 0.35 + 0.4 * uA.y + 0.5 * light) : uC0;
  col = mix(col, edgeCol, edge);
  // Brillos en los vértices con los agudos.
  if (uP.w > 0.02) {
    vec2 da = q - A;
    vec2 db = q - B;
    vec2 dcv = q - C;
    float vtx2 = min(dot(da, da), min(dot(db, db), dot(dcv, dcv)));
    col += uC3 * (1.0 - smoothstep(px * px, 9.0 * px * px, vtx2)) * uP.w * 0.8;
  }
  return col;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  float cs = cos(uA.x);
  float sn = sin(uA.x);
  vec2 q = vec2(cs * p.x - sn * p.y, sn * p.x + cs * p.y);
  // Piezas: un mosaico o el otro; sólo al cambiar se calculan los dos.
  vec3 col = vec3(0.0);
  if (uK < 0.999) col = tile(q, false);
  if (uK > 0.001) col = mix(col, tile(q, true), uK);
  col *= mix(1.0, uB.z, 0.4);
  col += uC1 * uB.w * 0.05;
  col *= 1.0 - 0.3 * smoothstep(0.7, 1.5, length(p * vec2(0.9, 0.65)));
  float peak = max(col.r, max(col.g, col.b));
  if (peak > 0.85) {
    float ee = (peak - 0.85) / 0.15;
    col *= (0.85 + 0.15 * ee / (1.0 + ee)) / peak;
  }
  col += (hash12(frag) - 0.5) / 255.0;
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
