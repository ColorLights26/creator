// Monolitos Cromados — bloques de cromo flotando en un vacío con neones.
// Cinco monolitos altos giran en círculo sobre un suelo negro con una
// cuadrícula de luz roja; su superficie de cromo refleja franjas de neón rojo
// y blanco y un foco que gira, y sus aristas brillan como tubos de neón. La
// cámara rodea la escena despacio. Cada golpe separa los monolitos y los
// hace girar con un muelle, los graves encienden las aristas y la energía
// acelera la cámara.
const nativeSource = r'''
class Visual final : public Scene {
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double orbit = 0, spin = 0, clock = 0;
  float spread = 0, spreadVel = 0, twirl = 0, twirlVel = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    orbit = rng.unit() * 6.2831853;
    spin = rng.unit() * 6.2831853;
    clock = rng.unit() * 50.0;
    spread = spreadVel = twirl = twirlVel = 0;
  }

  void update(const Frame& f) override {
    float dt = float(f.delta);
    const Music& m = f.music;
    bass = follow(bass, m.bass, 22.0f, 4.5f, dt);
    body = follow(body, m.body, 12.0f, 3.0f, dt);
    spark = follow(spark, m.spark, 30.0f, 7.0f, dt);
    energy = follow(energy, m.energy, 6.0f, 1.8f, dt);
    drive = follow(drive, m.active ? std::pow(std::clamp(m.energy, 0.0f, 1.0f), 0.8f) : 0.0f, 3.0f, 0.7f, dt);

    float hit = 0, fl = 0;
    for (const auto& e : m.events[0]) hit = std::max(hit, e.strength);
    for (const auto& e : m.events[2]) hit = std::max(hit, e.strength * 0.85f);
    for (const auto& e : m.events[3]) fl = std::max(fl, e.strength);
    float onset = std::clamp((m.bass - slowBass - 0.15f) * 2.5f, 0.0f, 1.0f);
    slowBass = follow(slowBass, m.bass, 3.0f, 3.0f, dt);
    hit = std::min(std::max(hit, onset), 1.0f);
    if (hit > kick + 0.2f) {
      spreadVel += 2.2f * hit;
      twirlVel += 2.5f * hit;
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    spreadVel += (-spread * 14.0f - spreadVel * 4.0f) * dt;
    spread += spreadVel * dt;
    twirlVel += (-twirl * 8.0f - twirlVel * 3.0f) * dt;
    twirl += twirlVel * dt;
    orbit += f.delta * f.speed * (0.10 + 0.25 * drive);
    spin += f.delta * f.speed * (0.15 + 0.2 * drive);
    clock += f.delta * f.speed;
  }

  void render(const Frame& f, Canvas& c) const override {
    float amp = f.intensity;
    std::vector<float> u;
    u.reserve(44);
    u.insert(u.end(), {float(std::fmod(orbit, 6.2831853)), bass * amp, kick * amp, energy});
    u.insert(u.end(), {f.glow, spark * amp, flash * amp, float(std::fmod(clock, 1000.0))});
    // Monolitos: posición en el suelo (x, z), altura de flote y giro propio.
    float radius = 2.1f + 0.9f * std::max(-0.3f, spread);
    for (int i = 0; i < 5; i++) {
      float a = float(std::fmod(spin, 6.2831853)) + 1.2566371f * float(i);
      float bob = 0.15f * float(std::sin(clock * 0.7 + i * 1.3));
      u.insert(u.end(), {std::cos(a) * radius, std::sin(a) * radius, bob, -a + 0.4f * twirl * (i % 2 ? 1.0f : -1.0f)});
    }
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("chrome_monoliths", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'chrome_monoliths': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // órbita de cámara, graves, golpe, energía
uniform vec4 uB;   // glow, agudos, destello, reloj
uniform vec4 uM0;  // monolitos: x, z, flote, giro
uniform vec4 uM1;
uniform vec4 uM2;
uniform vec4 uM3;
uniform vec4 uM4;
uniform vec3 uC0;
uniform vec3 uC1;
uniform vec3 uC2;
uniform vec3 uC3;
out vec4 fragColor;

const vec3 HALF = vec3(0.42, 1.55, 0.14);

float hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

// Giro de cada monolito, calculado una sola vez por píxel.
vec2 rot0;
vec2 rot1;
vec2 rot2;
vec2 rot3;
vec2 rot4;

// Punto en el espacio local del monolito m con giro cs (coseno, seno).
vec3 toLocal(vec3 p, vec4 m, vec2 cs) {
  vec3 q = p - vec3(m.x, HALF.y + 0.35 + m.z, m.y);
  return vec3(cs.x * q.x - cs.y * q.z, q.y, cs.y * q.x + cs.x * q.z);
}

// Intersección exacta rayo-caja en el espacio local del monolito: devuelve
// la distancia del impacto (o -1) y el punto local tocado.
float boxHit(vec3 ro, vec3 rd, vec4 m, vec2 cs, out vec3 lp) {
  vec3 lo = toLocal(ro, m, cs);
  vec3 ld = vec3(cs.x * rd.x - cs.y * rd.z, rd.y, cs.y * rd.x + cs.x * rd.z);
  ld = sign(ld) * max(abs(ld), vec3(1e-5));
  vec3 inv = 1.0 / ld;
  vec3 t0 = (-HALF - lo) * inv;
  vec3 t1 = (HALF - lo) * inv;
  vec3 tmin = min(t0, t1);
  vec3 tmax = max(t0, t1);
  float tn = max(max(tmin.x, tmin.y), tmin.z);
  float tf = min(min(tmax.x, tmax.y), tmax.z);
  lp = lo + ld * tn;
  return (tn > tf || tn < 0.0) ? -1.0 : tn;
}

// Halo: cercanía del rayo al eje del monolito.
float boxHalo(vec3 ro, vec3 rd, vec4 m) {
  vec3 c = vec3(m.x, HALF.y + 0.35 + m.z, m.y) - ro;
  float along = max(dot(c, rd), 0.0);
  vec3 off = c - rd * along;
  off.y = max(abs(off.y) - HALF.y, 0.0);
  float d = max(length(off) - 0.35, 0.0);
  return exp(-d * 6.0);
}

vec4 monolith(float id) {
  return id < 0.5 ? uM0 : (id < 1.5 ? uM1 : (id < 2.5 ? uM2 : (id < 3.5 ? uM3 : uM4)));
}

vec2 monolithRot(float id) {
  return id < 0.5 ? rot0 : (id < 1.5 ? rot1 : (id < 2.5 ? rot2 : (id < 3.5 ? rot3 : rot4)));
}

// Entorno que refleja el cromo: vacío negro con franjas de neón y un foco.
vec3 environment(vec3 r) {
  float t = uB.w;
  vec3 col = uC0 + uC3 * (0.06 + 0.3 * smoothstep(-0.05, 0.7, r.y));
  // Barras verticales de luz alrededor: el cromo las refleja como rayas.
  float bars = pow(max(cos(atan(r.z, r.x) * 5.0 + t * 0.3), 0.0), 24.0) * smoothstep(-0.15, 0.1, r.y);
  col += uC2 * bars * 0.8;
  float strip1 = exp(-(r.y - 0.18) * (r.y - 0.18) * 260.0);
  float strip2 = exp(-(r.y - 0.55) * (r.y - 0.55) * 500.0);
  col += uC1 * strip1 * (1.1 + 0.8 * uA.y + 1.2 * uA.z);
  col += uC2 * strip2 * (0.7 + 0.5 * uA.z);
  float ang = atan(r.z, r.x) - t * 0.6;
  float spot = pow(max(cos(ang), 0.0), 40.0) * smoothstep(0.0, 0.4, r.y);
  col += uC2 * spot * 0.9;
  col += uC1 * smoothstep(-0.05, -0.4, r.y) * 0.12;
  return col;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  p.y = -p.y;
  rot0 = vec2(cos(uM0.w), sin(uM0.w));
  rot1 = vec2(cos(uM1.w), sin(uM1.w));
  rot2 = vec2(cos(uM2.w), sin(uM2.w));
  rot3 = vec2(cos(uM3.w), sin(uM3.w));
  rot4 = vec2(cos(uM4.w), sin(uM4.w));
  float a = uA.x;
  vec3 ro = vec3(sin(a) * 7.0, 2.3, cos(a) * 7.0);
  vec3 target = vec3(0.0, 1.6, 0.0);
  vec3 fw = normalize(target - ro);
  vec3 rt = normalize(cross(fw, vec3(0.0, 1.0, 0.0)));
  vec3 up = cross(rt, fw);
  vec3 rd = normalize(fw * 1.6 + rt * p.x + up * p.y);

  // Suelo: plano analítico y = 0 con una cuadrícula de neón rojo.
  float tFloor = rd.y < -0.001 ? -ro.y / rd.y : 1e5;
  vec3 col = environment(rd) * 0.12;
  // Impacto más cercano entre los cinco monolitos.
  float t = 1e5;
  float hitId = -1.0;
  vec3 q = vec3(0.0);
  vec3 lp;
  float th = boxHit(ro, rd, uM0, rot0, lp);
  if (th > 0.0 && th < t) { t = th; hitId = 0.0; q = lp; }
  th = boxHit(ro, rd, uM1, rot1, lp);
  if (th > 0.0 && th < t) { t = th; hitId = 1.0; q = lp; }
  th = boxHit(ro, rd, uM2, rot2, lp);
  if (th > 0.0 && th < t) { t = th; hitId = 2.0; q = lp; }
  th = boxHit(ro, rd, uM3, rot3, lp);
  if (th > 0.0 && th < t) { t = th; hitId = 3.0; q = lp; }
  th = boxHit(ro, rd, uM4, rot4, lp);
  if (th > 0.0 && th < t) { t = th; hitId = 4.0; q = lp; }
  if (t > tFloor) hitId = -1.0;
  float glowAcc = (boxHalo(ro, rd, uM0) + boxHalo(ro, rd, uM1) + boxHalo(ro, rd, uM2) + boxHalo(ro, rd, uM3) +
                   boxHalo(ro, rd, uM4)) * 0.12;
  float edgeGlow = 0.6 + 1.6 * uA.y + 1.8 * uA.z;
  if (hitId >= 0.0) {
    vec2 mr = monolithRot(hitId);
    // Normal de la caja en el espacio local, devuelta al mundo.
    vec3 aq = abs(q) / HALF;
    vec3 nl = aq.x > aq.y && aq.x > aq.z ? vec3(sign(q.x), 0.0, 0.0)
            : (aq.y > aq.z ? vec3(0.0, sign(q.y), 0.0) : vec3(0.0, 0.0, sign(q.z)));
    vec3 n = vec3(mr.x * nl.x + mr.y * nl.z, nl.y, -mr.y * nl.x + mr.x * nl.z);
    vec3 r = reflect(rd, n);
    float fres = 0.55 + 0.45 * pow(1.0 - max(dot(-rd, n), 0.0), 3.0);
    col = environment(r) * fres * mix(vec3(1.0), uC3, 0.35) * 1.2;
    // Aristas de neón: cerca de dos caras a la vez.
    vec3 e = HALF - abs(q);
    float e1 = min(e.x, min(e.y, e.z));
    float e2 = e.x + e.y + e.z - e1 - max(e.x, max(e.y, e.z));
    float edge = exp(-e2 * 45.0);
    col += uC1 * edge * edgeGlow * uB.x;
    col += uC2 * edge * smoothstep(0.85, 1.0, hash12(vec2(hitId, floor(uB.w * 8.0)))) * uB.y;
  } else if (tFloor < 1e4) {
    vec3 hp = ro + rd * tFloor;
    vec2 g = abs(fract(hp.xz * 0.75) - 0.5);
    float line = exp(-min(g.x, g.y) * 40.0);
    float fade = exp(-length(hp.xz) * 0.12);
    col = uC0 + uC1 * line * fade * (0.35 + 0.4 * uA.y + 0.6 * uA.z);
    // Reflejo tenue del entorno en el suelo pulido.
    col += environment(reflect(rd, vec3(0.0, 1.0, 0.0))) * 0.12 * fade;
  }
  // Halo rojo alrededor de los monolitos.
  col += uC1 * glowAcc * (0.5 + 1.0 * uA.y + 1.2 * uA.z) * uB.x;
  col += uC2 * uB.z * 0.05;
  col *= 1.0 - 0.35 * smoothstep(0.6, 1.4, length(p * vec2(0.9, 0.65)));
  float peak = max(col.r, max(col.g, col.b));
  if (peak > 0.85) {
    float k = (peak - 0.85) / 0.15;
    col *= (0.85 + 0.15 * k / (1.0 + k)) / peak;
  }
  col += (hash12(frag) - 0.5) / 255.0;
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
