// Nubes Volumétricas — Puerto fiel de Visuales Inmersivas v13.
// Raymarching 3D volumétrico acelerado por GPU con ruido fractal 3D,
// absorción de Beer-Lambert y deformación de dominio reactiva al audio.
const nativeSource = r'''
class Visual final : public Scene {
  float cloudTime = 0.0f;
  float warpOffset = 0.0f;
  float smoothBass = 0.0f;
  float smoothEnergy = 0.0f;
  float smoothSpark = 0.0f;

 public:
  void reset(uint32_t seed) override {
    (void)seed;
    cloudTime = 0.0f;
    warpOffset = 0.0f;
    smoothBass = 0.0f;
    smoothEnergy = 0.0f;
    smoothSpark = 0.0f;
  }

  void update(const Frame& f) override {
    float dt = float(f.delta);
    float speedMult = (f.reducedMotion ? 0.25f : 1.0f) * f.speed;
    cloudTime += dt * speedMult;

    smoothBass += (f.music.bass - smoothBass) * float(1.0 - std::exp(-dt * 5.0));
    smoothEnergy += (f.music.energy - smoothEnergy) * float(1.0 - std::exp(-dt * 5.0));
    smoothSpark += (f.music.spark - smoothSpark) * float(1.0 - std::exp(-dt * 15.0));

    // Desplazamiento orgánico del dominio de ruido con los graves
    warpOffset += dt * (0.08f + smoothBass * 0.65f) * speedMult;
  }

  void render(const Frame& f, Canvas& c) const override {
    float w = f.width, h = f.height;
    std::vector<float> u;
    u.reserve(6);
    u.push_back(cloudTime);
    u.push_back(warpOffset);
    u.push_back(smoothEnergy * 0.12f);
    u.push_back(smoothSpark * f.intensity);
    u.push_back(f.reducedMotion ? 1.0f : 0.0f);

    c.material("nubes", {0.0f, 0.0f, w, h}, u);
  }
};
''';

const shaderSources = <String, String>{
  'nubes': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uTime;
uniform float uWarpShift;
uniform float uDensityAdd;
uniform float uSparkExp;
uniform float uReduced;

out vec4 fragColor;

float hash31(vec3 p) {
  p = fract(p * vec3(443.897, 441.423, 437.195));
  p += dot(p, p.yzx + 19.19);
  return fract((p.x + p.y) * p.z);
}

float valueNoise3D(vec3 x) {
  vec3 i = floor(x);
  vec3 f = fract(x);
  f = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(mix(hash31(i + vec3(0,0,0)), hash31(i + vec3(1,0,0)), f.x),
        mix(hash31(i + vec3(0,1,0)), hash31(i + vec3(1,1,0)), f.x), f.y),
    mix(mix(hash31(i + vec3(0,0,1)), hash31(i + vec3(1,0,1)), f.x),
        mix(hash31(i + vec3(0,1,1)), hash31(i + vec3(1,1,1)), f.x), f.y),
    f.z
  );
}

float cloudDensity(vec3 p) {
  vec3 q = p + vec3(uTime * 0.18 + uWarpShift, 0.0, -uTime * 0.12);
  float f = 0.0;
  float amp = 0.52;
  for (int i = 0; i < 4; i++) {
    f += amp * valueNoise3D(q);
    q = q * 2.03 + vec3(2.1, -1.7, 3.3);
    amp *= 0.5;
  }
  float d = f - (0.42 - uDensityAdd) - (abs(p.y) / 1.45) * 0.42;
  return clamp(d * 2.4, 0.0, 1.0);
}

void main() {
  vec2 px = FlutterFragCoord().xy;
  vec2 uv = px / uSize;
  vec2 p = (uv * 2.0 - 1.0) * vec2(uSize.x / uSize.y, -1.0);

  vec3 skyCol = mix(vec3(0.020, 0.024, 0.051), vec3(0.051, 0.063, 0.141), 1.0 - uv.y);
  vec3 colLight  = vec3(1.000, 0.945, 0.863);
  vec3 colMid    = vec3(0.788, 0.718, 0.839);
  vec3 colShadow = vec3(0.141, 0.102, 0.208);

  vec3 ro = vec3(0.0, -0.15, -3.2);
  vec3 rd = normalize(vec3(p * 0.85, 1.4));
  vec3 lightDir = normalize(vec3(-0.65, 0.72, -0.25));

  float maxSteps = uReduced > 0.5 ? 12.0 : 24.0;
  float stepSize = 4.3 / maxSteps;
  float jitter = fract(sin(dot(px, vec2(12.9898, 78.233))) * 43758.5453);
  float t = 1.1 + jitter * stepSize;

  vec3 accumCol = vec3(0.0);
  float accumDens = 0.0;

  for (int i = 0; i < 24; i++) {
    if (float(i) >= maxSteps || accumDens > 0.99) break;
    vec3 pos = ro + rd * t;
    float dens = cloudDensity(pos);
    if (dens > 0.01) {
      float sh = cloudDensity(pos + lightDir * 0.18) +
                 cloudDensity(pos + lightDir * 0.42) +
                 cloudDensity(pos + lightDir * 0.78);
      float trans = exp(-sh * 0.85 * 0.45 * 3.2);
      vec3 sCol = mix(mix(colShadow, colMid, smoothstep(0.0, 0.55, trans)),
                      colLight, smoothstep(0.45, 1.0, trans));
      float a = min(dens * 0.38 * (24.0 / maxSteps), 1.0 - accumDens);
      accumCol += sCol * a;
      accumDens += a;
    }
    t += stepSize;
  }

  vec3 col = mix(skyCol, accumCol / max(accumDens, 0.0001), accumDens);
  col *= (1.0 + uSparkExp * 0.58);
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
