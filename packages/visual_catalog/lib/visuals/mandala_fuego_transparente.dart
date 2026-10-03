// Mandala de Fuego Transparente — mandala de líneas incandescentes sobre negro puro.
// Versión overlay: mismo movimiento y reacción a la música sin fondo opaco.
// Un rosetón central de polígonos superpuestos, un anillo negro que lo separa y,
// fuera, cientos de rayos finos y estrellas en zigzag que nacen junto al anillo
// y viajan hacia fuera sin fin. Cada golpe expande el anillo como una onda de
// choque, empuja las estrellas y suelta una ráfaga de brasas; los graves avivan
// las líneas, los medios aceleran el giro y los agudos sueltan chispas.
const nativeSource = r'''
class Visual final : public Scene {
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0, mids = 0;
  float travel = 0, travelVel = 0, rotOuter = 0, rotInner = 0, embers = 0;
  float voidPush = 0, voidVel = 0, burst = 0, ringR = 3.0f, ringAmp = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = mids = 0;
    travel = rng.unit() * 10.0f;
    travelVel = 0;
    rotOuter = rng.unit() * 6.2831853f;
    rotInner = rng.unit() * 6.2831853f;
    embers = rng.unit() * 10.0f;
    voidPush = voidVel = burst = 0;
    ringR = 3.0f;
    ringAmp = 0;
  }

  void update(const Frame& f) override {
    float dt = float(f.delta);
    const Music& m = f.music;
    bass = follow(bass, m.bass, 22.0f, 4.5f, dt);
    body = follow(body, m.body, 12.0f, 3.0f, dt);
    spark = follow(spark, m.spark, 30.0f, 7.0f, dt);
    energy = follow(energy, m.energy, 6.0f, 1.8f, dt);
    drive = follow(drive, m.active ? std::pow(std::clamp(m.energy, 0.0f, 1.0f), 0.8f) : 0.0f, 3.0f, 0.7f, dt);
    float mi = 0;
    for (int i = 9; i < 21; i++) mi = std::max(mi, m.smoothSpectrum[i]);
    mids = follow(mids, mi, 12.0f, 3.0f, dt);

    float hit = 0, fl = 0;
    for (const auto& e : m.events[0]) hit = std::max(hit, e.strength);
    for (const auto& e : m.events[2]) hit = std::max(hit, e.strength * 0.85f);
    for (const auto& e : m.events[3]) fl = std::max(fl, e.strength);
    float onset = std::clamp((m.bass - slowBass - 0.15f) * 2.5f, 0.0f, 1.0f);
    slowBass = follow(slowBass, m.bass, 3.0f, 3.0f, dt);
    hit = std::min(std::max(hit, onset), 1.0f);
    if (hit > kick + 0.2f) {
      voidVel += 1.4f * hit;
      travelVel += 0.9f * hit;
      burst = std::max(burst, hit);
      ringR = 0.0f;
      ringAmp = hit;
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));

    // El anillo negro se expande con el golpe y vuelve con un muelle amortiguado.
    voidVel += (-voidPush * 30.0f - voidVel * 6.0f) * dt;
    voidPush += voidVel * dt;
    travelVel *= std::exp(-dt * 3.0f);
    travel += dt * f.speed * (0.10f + 0.55f * drive) + dt * travelVel;
    rotOuter += dt * f.speed * (0.03f + 0.18f * mids + 0.05f * drive);
    rotInner -= dt * f.speed * (0.05f + 0.30f * mids + 0.08f * drive);
    embers += dt * f.speed * (0.25f + 0.9f * drive + 0.8f * burst);
    burst *= std::exp(-dt * 2.5f);
    ringR += dt * (0.7f + 0.4f * drive);
    ringAmp *= std::exp(-dt * 2.4f);
  }

  void render(const Frame& f, Canvas& c) const override {
    float amp = f.intensity;
    float vin = 0.16f + 0.015f * bass * amp;
    float vout = 0.30f + 0.10f * voidPush * amp;
    std::vector<float> u;
    u.reserve(28);
    u.insert(u.end(), {travel, bass * amp, kick * amp, energy});
    u.insert(u.end(), {rotOuter, rotInner, spark * amp, f.glow});
    u.insert(u.end(), {vin, std::max(vout, vin + 0.06f), kick * amp, flash});
    u.insert(u.end(), {embers, burst * amp, ringR, ringAmp * amp});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("fire_mandala", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'fire_mandala': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // viaje, graves, golpe, energía
uniform vec4 uB;   // giro exterior, giro interior, agudos, glow
uniform vec4 uV;   // radio interior y exterior del anillo negro, fogonazo, destello
uniform vec4 uE;   // reloj de brasas, ráfaga, radio y fuerza del anillo del golpe
uniform vec3 uC0;
uniform vec3 uC1;
uniform vec3 uC2;
uniform vec3 uC3;
out vec4 fragColor;

const float TAU = 6.2831853;

float hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

// Distancia al contorno de un polígono regular de n lados (apotema ap).
float polygon(float r, float a, float n, float ap, float rot) {
  float sector = TAU / n;
  float th = mod(a + rot + 0.5 * sector, sector) - 0.5 * sector;
  return abs(r * cos(th) - ap);
}

// Distancia en arco al rayo radial más cercano de m rayos.
float rays(float r, float a, float m, float rot) {
  float s = fract((a + rot) * m / TAU) - 0.5;
  return abs(s) * (TAU / m) * r;
}

// Línea de neón con halo ceñido: el negro entre líneas queda limpio.
// Rampa de fuego: halos de brasa roja, líneas naranjas, oro y blanco sólo
// donde la luz es más intensa.
vec3 fireRamp(float I) {
  vec3 c = mix(uC1, uC2, smoothstep(0.05, 0.7, I));
  c = mix(c, uC3, smoothstep(1.6, 3.0, I));
  c = mix(c, vec3(1.0, 0.95, 0.85), smoothstep(3.0, 4.2, I));
  return c * min(I, 2.2) * 0.62;
}

float lineGlow(float d, float w) {
  float g = w * w / (d * d + w * w);
  return g * g;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  float r = max(length(p), 0.0005);
  float a = atan(p.y, p.x);
  float kick = uA.z;
  float bass = uA.y;
  float vin = uV.x;
  float vout = uV.y;
  float width = 0.0032 + 0.002 * bass;

  float energyLines = 0.0;

  // Exterior: rayos finos que titilan como fuego y estrellas que viajan hacia fuera.
  if (r > vout * 0.9) {
    float flick = 0.65 + 0.35 * hash12(vec2(floor((a + uB.x) * 64.0 / TAU), floor(uA.x * 8.0)));
    float ray = lineGlow(rays(r, a, 64.0, uB.x), width * 0.8) * smoothstep(vout, vout + 0.1, r);
    ray *= (0.45 + 0.35 * flick + 0.6 * uB.z * flick) * exp(-(r - vout) * 0.6);
    float bigRays = lineGlow(rays(r, a, 16.0, -uB.x * 0.5), width * 1.4) * smoothstep(vout, vout + 0.05, r);
    energyLines += ray + bigRays * 0.8;
    for (int k = 0; k < 3; k++) {
      float fk = float(k);
      float ph = fract(uA.x * 0.35 + fk / 3.0);
      float ap = vout + 0.02 + ph * 1.1;
      float fade = sin(3.14159 * ph);
      float rot = (mod(fk, 2.0) < 1.0 ? uB.x : -uB.x) * 1.5;
      float d = min(polygon(r, a, 8.0, ap, rot), polygon(r, a, 8.0, ap, rot + TAU / 16.0));
      energyLines += lineGlow(d, width * 1.5) * fade * 1.4;
    }
  }

  // Centro: rosetón de polígonos superpuestos que gira al revés.
  if (r < vin * 1.1) {
    float rot = uB.y;
    float d = min(polygon(r, a, 12.0, vin * 0.82, rot), polygon(r, a, 12.0, vin * 0.82, rot + TAU / 24.0));
    d = min(d, polygon(r, a, 8.0, vin * 0.58, -rot * 1.4));
    d = min(d, polygon(r, a, 8.0, vin * 0.58, -rot * 1.4 + TAU / 16.0));
    d = min(d, abs(r - vin * 0.28));
    d = min(d, abs(r - vin * 0.95));
    d = min(d, rays(r, a, 24.0, rot * 0.7) + max(0.0, vin * 0.3 - r));
    float bloom = 1.0 + 0.8 * kick + 0.5 * bass;
    energyLines += lineGlow(d, width * 0.9) * smoothstep(vin * 1.02, vin * 0.9, r) * bloom;
  }

  // Bordes del anillo negro: brillan y estallan con el golpe.
  float rimOut = exp(-(r - vout) * (r - vout) * 7000.0);
  float rimIn = exp(-(r - vin) * (r - vin) * 9000.0);
  energyLines += (rimOut * (0.5 + 2.2 * uV.z) + rimIn * (0.4 + 1.2 * uV.z));

  // Anillo de choque que sale del anillo negro con cada golpe.
  float ringR = vout + uE.z;
  energyLines += uE.w * exp(-(r - ringR) * (r - ringR) * 900.0) * 1.3;

  // Rampa de fuego: brasa, naranja, oro y blanco incandescente.
  float I = energyLines * uB.w * (0.8 + 0.4 * uA.w);
  vec3 col = uC0 + fireRamp(I);

  // Brasas que suben por los rayos hacia fuera.
  if (r > vout) {
    float lanesA = (a + uB.x) * 64.0 / TAU;
    float lane = log(r) * 16.0 - uE.x * 3.0;
    vec2 cell = vec2(floor(lanesA), floor(lane));
    float h = hash12(cell);
    float density = 0.04 + 0.16 * uB.z + 0.3 * uE.y;
    if (h > 1.0 - density) {
      float fy = fract(lane) - 0.5;
      float fx = fract(lanesA) - 0.5;
      float e = exp(-(fx * fx * 160.0 + fy * fy * 40.0)) * (0.6 + 0.4 * hash12(cell + 7.0));
      col += mix(uC2, uC3, 0.5) * e * (0.7 + 1.4 * uE.y + 0.6 * uB.z);
    }
  }

  // Núcleo incandescente y destello del flash.
  col += uC2 * (0.0005 + 0.003 * kick + 0.001 * bass) / (r * r + 0.0012);
  col += uC1 * uV.w * 0.06;

  col *= 1.0 - 0.35 * smoothstep(0.6, 1.4, length(p * vec2(0.9, 0.65)));
  // Mapeo de tonos que conserva el tono: comprime el brillo sin desplazar el
  // naranja hacia amarillo cuando una línea es muy intensa.
  float peak = max(col.r, max(col.g, col.b));
  float mapped = clamp((peak * (2.51 * peak + 0.03)) / (peak * (2.43 * peak + 0.59) + 0.14), 0.0, 1.0);
  col *= mapped / max(peak, 0.0001);
  col = pow(max(col, 0.0), vec3(0.4545));
  // Fondo transparente: el color va premultiplicado y la opacidad sale del
  // brillo, así la luz se compone sobre lo que haya debajo.
  col = clamp(col, 0.0, 1.0);
  float alpha = clamp(max(col.r, max(col.g, col.b)) * 1.25, 0.0, 1.0);
  fragColor = vec4(col, alpha);
}
""",
};
