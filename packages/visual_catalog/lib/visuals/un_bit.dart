// 1-Bit — una escena 3D dibujada sólo con tramas de puntos.
// Un cubo gira en el centro y cuatro esferas orbitan a su alrededor sobre un
// suelo de damero que se pierde en la niebla. Todo se calcula con
// intersecciones exactas (sin pasos de rayo), con luz y sombras de verdad,
// pero en lugar de grises se usa una trama de Bayer: cada píxel sólo puede
// ser papel negro o tinta blanca (y rojo para las esferas), como en el juego
// Return of the Obra Dinn. Las aristas del cubo se dibujan como líneas de
// tinta. Los graves agrandan el cubo, cada golpe aleja las esferas y las
// hace destellar, y la energía acelera el giro.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.steps('pixel', 'Tamaño de píxel', min: 1, max: 4, value: 2),
  CreatorModifier.slider('giro', 'Velocidad de giro', min: .2, max: 2.5, value: 1),
  CreatorModifier.toggle('rojo', 'Esferas rojas', value: true),
  CreatorModifier.toggle('suelo', 'Suelo', value: true),
];

const nativeSource = r'''
class Visual final : public Scene {
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double yaw = 0, pitch = 0, orbit = 0, clock = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    yaw = rng.unit() * 6.28;
    pitch = rng.unit() * 6.28;
    orbit = rng.unit() * 6.28;
    clock = 0;
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
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    double spin = f.delta * f.speed * m.giro * (1.0 + 1.4 * drive + 1.0 * kick);
    yaw += spin * 0.55;
    pitch += spin * 0.37;
    orbit += spin * 0.8;
    clock += f.delta * f.speed;
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    float amp = f.intensity;
    // Matriz del cubo (de mundo a local): giro en dos ejes.
    float cy = float(std::cos(yaw)), sy = float(std::sin(yaw)), cp = float(std::cos(pitch)), sp = float(std::sin(pitch));
    // Filas de R = Rx(pitch) · Ry(yaw); como es ortonormal, sus filas son
    // los ejes locales del cubo vistos en el mundo.
    std::array<float, 9> R = {cy, 0.0f, -sy, sp * sy, cp, sp * cy, cp * sy, -sp, cp * cy};
    std::vector<float> u;
    u.reserve(52);
    u.insert(u.end(), {float(std::fmod(clock, 1000.0)), bass * amp, kick * amp, energy});
    u.insert(u.end(), {float(std::clamp(m.pixel, 1, 4)), m.rojo ? 1.0f : 0.0f, m.suelo ? 1.0f : 0.0f, flash * amp});
    u.insert(u.end(), {R[0], R[1], R[2]});
    u.insert(u.end(), {R[3], R[4], R[5]});
    u.insert(u.end(), {R[6], R[7], R[8]});
    for (int i = 0; i < 4; i++) {
      double a = orbit * (i % 2 == 0 ? 1.0 : -0.8) + double(i) * 1.5707963;
      float radius = 1.85f + 0.35f * kick * amp + 0.15f * float(i % 2);
      float h = 0.55f * float(std::sin(orbit * 0.9 + double(i) * 2.1));
      u.insert(u.end(), {radius * float(std::cos(a)), h, radius * float(std::sin(a)), 0.32f + 0.05f * float(i % 3)});
    }
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("one_bit", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'one_bit': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // reloj, graves, golpe, energía
uniform vec4 uB;   // tamaño de píxel, esferas rojas, suelo, destello
uniform vec3 uR0;  // filas de la matriz del cubo
uniform vec3 uR1;
uniform vec3 uR2;
uniform vec4 uS0;  // esferas: centro y radio
uniform vec4 uS1;
uniform vec4 uS2;
uniform vec4 uS3;
uniform vec3 uC0;
uniform vec3 uC1;
uniform vec3 uC2;
uniform vec3 uC3;
out vec4 fragColor;

// Matriz de Bayer 8×8 calculada sin tablas.
float bayer2(vec2 a) {
  a = floor(a);
  return fract(dot(a, vec2(0.5, a.y * 0.75)));
}
float bayer4(vec2 a) { return bayer2(0.5 * a) * 0.25 + bayer2(a); }
float bayer8(vec2 a) { return bayer4(0.5 * a) * 0.25 + bayer2(a); }

float sphereHit(vec3 ro, vec3 rd, vec4 s) {
  vec3 oc = ro - s.xyz;
  float b = dot(oc, rd);
  float c = dot(oc, oc) - s.w * s.w;
  float h = b * b - c;
  if (h < 0.0) return -1.0;
  return -b - sqrt(h);
}

// Caja centrada en el origen en espacio local (método de las losas).
float boxHit(vec3 ro, vec3 rd, vec3 hs, out vec3 nL) {
  vec3 m = 1.0 / (rd + vec3(1e-6));
  vec3 n = m * ro;
  vec3 k = abs(m) * hs;
  vec3 t1 = -n - k;
  vec3 t2 = -n + k;
  float tn = max(max(t1.x, t1.y), t1.z);
  float tf = min(min(t2.x, t2.y), t2.z);
  nL = -sign(rd) * step(t1.yzx, t1.xyz) * step(t1.zxy, t1.xyz);
  if (tn > tf || tf < 0.0) return -1.0;
  return tn;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float ps = uB.x;
  vec2 cell = floor(frag / ps);
  vec2 fc = (cell + 0.5) * ps;
  float scale = min(uSize.x, uSize.y);
  vec2 uv = (fc - 0.5 * uSize) / scale;
  uv.y = -uv.y;
  vec3 ro = vec3(0.0, 0.9, -5.6);
  vec3 rd = normalize(vec3(uv.x, uv.y - 0.12, 1.55));
  vec3 L = normalize(vec3(-0.5, 0.85, -0.35));
  float hs = 0.82 * (1.0 + 0.12 * uA.y);
  float t = 1e9;
  vec3 n = vec3(0.0);
  float kind = 0.0;  // 0 cielo, 1 cubo, 2 esfera, 3 suelo
  float edge = 0.0;
  // Cubo en espacio local.
  vec3 roL = vec3(dot(uR0, ro), dot(uR1, ro), dot(uR2, ro));
  vec3 rdL = vec3(dot(uR0, rd), dot(uR1, rd), dot(uR2, rd));
  vec3 nL;
  float tb = boxHit(roL, rdL, vec3(hs), nL);
  if (tb > 0.0) {
    t = tb;
    n = nL.x * uR0 + nL.y * uR1 + nL.z * uR2;
    kind = 1.0;
    vec3 a = abs(roL + rdL * tb) / hs;
    float mx = max(a.x, max(a.y, a.z));
    float mn = min(a.x, min(a.y, a.z));
    float mid = a.x + a.y + a.z - mx - mn;
    edge = smoothstep(0.93, 0.97, mid);
  }
  float ts = sphereHit(ro, rd, uS0);
  if (ts > 0.0 && ts < t) { t = ts; n = normalize(ro + rd * ts - uS0.xyz); kind = 2.0; edge = 0.0; }
  ts = sphereHit(ro, rd, uS1);
  if (ts > 0.0 && ts < t) { t = ts; n = normalize(ro + rd * ts - uS1.xyz); kind = 2.0; edge = 0.0; }
  ts = sphereHit(ro, rd, uS2);
  if (ts > 0.0 && ts < t) { t = ts; n = normalize(ro + rd * ts - uS2.xyz); kind = 2.0; edge = 0.0; }
  ts = sphereHit(ro, rd, uS3);
  if (ts > 0.0 && ts < t) { t = ts; n = normalize(ro + rd * ts - uS3.xyz); kind = 2.0; edge = 0.0; }
  float floorY = -1.7;
  if (uB.z > 0.5 && rd.y < 0.0) {
    float tf = (floorY - ro.y) / rd.y;
    if (tf > 0.0 && tf < t) { t = tf; n = vec3(0.0, 1.0, 0.0); kind = 3.0; edge = 0.0; }
  }
  float lum = 0.06 + 0.1 * clamp(uv.y + 0.6, 0.0, 1.0);
  if (kind > 0.5) {
    vec3 p = ro + rd * t;
    float diff = clamp(dot(n, L), 0.0, 1.0);
    // Sombras exactas contra las esferas y el cubo.
    vec3 so = p + n * 0.003;
    float shadow = 1.0;
    if (sphereHit(so, L, uS0) > 0.0 || sphereHit(so, L, uS1) > 0.0 || sphereHit(so, L, uS2) > 0.0 || sphereHit(so, L, uS3) > 0.0) shadow = 0.25;
    vec3 soL = vec3(dot(uR0, so), dot(uR1, so), dot(uR2, so));
    vec3 lL = vec3(dot(uR0, L), dot(uR1, L), dot(uR2, L));
    vec3 tmp;
    if (kind > 1.5 && boxHit(soL, lL, vec3(hs), tmp) > 0.0) shadow = 0.25;
    float albedo = 0.95;
    if (kind > 2.5) {
      vec2 chk = floor(p.xz * 0.9);
      albedo = mod(chk.x + chk.y, 2.0) < 0.5 ? 0.55 : 0.25;
    }
    float spec = pow(clamp(dot(reflect(rd, n), L), 0.0, 1.0), 24.0);
    lum = albedo * (0.12 + 0.88 * diff * shadow) + spec * 0.6 * shadow;
    if (kind > 1.5 && kind < 2.5) lum = lum * (1.0 + 0.6 * uA.z);
    // Niebla del fondo.
    if (kind > 2.5) lum = mix(lum, 0.08, smoothstep(5.0, 18.0, t));
  }
  float threshold = bayer8(cell);
  float ink = step(threshold, lum);
  vec3 paper = uC0;
  vec3 inkCol = (kind > 1.5 && kind < 2.5 && uB.y > 0.5) ? uC2 : uC1;
  vec3 col = mix(paper, inkCol, ink);
  // Aristas del cubo en tinta.
  col = mix(col, uC1, edge);
  col = mix(col, uC1, uB.w * 0.08);
  fragColor = vec4(col, 1.0);
}
""",
};
