// Lluvia sobre Cristal Transparente — Versión Overlay / Capa transparente.
// Gotas de lluvia realistas con física de adherencia y deslizamiento, estelas con microgotas,
// sombras de menisco, anillos cáusticos y brillos especulares sobre cristal transparente.
const nativeSource = r'''
class Visual final : public Scene {
  float rainTime = 0.0f;
  float smoothEnergy = 0.0f;
  float smoothBass = 0.0f;
  float smoothSpark = 0.0f;

 public:
  void reset(uint32_t seed) override {
    (void)seed;
    rainTime = 0.0f;
    smoothEnergy = 0.0f;
    smoothBass = 0.0f;
    smoothSpark = 0.0f;
  }

  void update(const Frame& f) override {
    float dt = float(f.delta);
    float targetEnergy = f.music.active ? f.music.energy : 0.0f;
    float targetBass = f.music.active ? f.music.bass : 0.0f;
    float targetSpark = f.music.active ? f.music.spark : 0.0f;

    smoothEnergy += (targetEnergy - smoothEnergy) * float(1.0 - std::exp(-dt * 5.0));
    smoothBass += (targetBass - smoothBass) * float(1.0 - std::exp(-dt * 6.0));
    smoothSpark += (targetSpark - smoothSpark) * float(1.0 - std::exp(-dt * 15.0));

    // En silencio reposa en un lloviznar suave y sereno (~0.12f).
    // Con música la lluvia cobra ímpetu al compás de los ritmos y bombos.
    float audioDrive = 0.12f + smoothEnergy * 0.72f + smoothBass * 0.35f;
    float speedMult = (f.reducedMotion ? 0.35f : 1.0f) * f.speed * audioDrive;
    rainTime += dt * speedMult;
  }

  void render(const Frame& f, Canvas& c) const override {
    float w = f.width, h = f.height;

    // Renderiza la simulación transparente de lluvia sobre cristal
    c.material("rain_glass_overlay", {0.0f, 0.0f, w, h}, {
      rainTime,
      smoothEnergy,
      smoothSpark * f.intensity,
      smoothBass
    });
  }
};
''';

const shaderSources = <String, String>{
  'rain_glass_overlay': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uTime;
uniform float uEnergy;
uniform float uSpark;
uniform float uBass;

out vec4 fragColor;

vec3 hash33(vec3 p3) {
  p3 = fract(p3 * vec3(0.1031, 0.1030, 0.0973));
  p3 += dot(p3, p3.yxz + 33.33);
  return fract((p3.xxy + p3.yzz) * p3.zyx);
}

// Simulación física multicapa de gotas de lluvia
vec4 getRain(vec2 uv, float t, vec2 aspect) {
  vec2 totalNormal = vec2(0.0);
  float dropMask = 0.0;
  float trailMask = 0.0;
  float rimMask = 0.0;

  // CAPA 1: Gotas grandes deslizándose con física de stutter-slide (adherencia y caída brusca)
  vec2 uv1 = uv * vec2(3.5, 1.2) * aspect;
  vec2 id1 = floor(uv1);
  vec2 f1 = fract(uv1) - 0.5;

  for (int dy = -1; dy <= 1; dy++) {
    for (int dx = -1; dx <= 1; dx++) {
      vec2 neighbor = vec2(float(dx), float(dy));
      vec2 cId = id1 + neighbor;
      vec3 rnd = hash33(vec3(cId, 45.2));

      if (rnd.x < 0.42) {
        float speed = 0.35 + rnd.y * 0.45;
        float fallTime = t * speed + rnd.z * 100.0;

        // Física stutter-slide: escalonamiento por tensión superficial
        float stepPhase = fract(fallTime);
        float dropY = floor(fallTime) + smoothstep(0.70, 0.98, stepPhase);

        vec2 dropCenter = neighbor + vec2((rnd.y - 0.5) * 0.35, fract(dropY) - 0.5);
        vec2 dVec = f1 - dropCenter;

        // Estiramiento aerodinámico por gravedad
        dVec.y *= 0.85;
        float dist = length(dVec);
        float r = 0.12 + 0.08 * rnd.x;

        if (dist < r) {
          float normDist = dist / r;
          float edgeSoft = smoothstep(1.0, 0.70, normDist);
          vec2 norm2D = (dVec / r) * edgeSoft;
          totalNormal += norm2D * 0.75;
          dropMask = max(dropMask, edgeSoft);
          rimMask = max(rimMask, smoothstep(0.65, 0.96, normDist) * edgeSoft);
        }

        // Estela vertical dejada por la gota
        float trailX = dVec.x;
        float trailY = dVec.y;
        if (trailY > 0.0 && trailY < 0.95 && abs(trailX) < r * 0.38) {
          float trailFade = (1.0 - trailY / 0.95);
          float trailWidth = smoothstep(r * 0.38, 0.0, abs(trailX));
          trailMask = max(trailMask, trailWidth * trailFade * 0.45);
          totalNormal.x += trailX * trailWidth * 0.35;
        }
      }
    }
  }

  // CAPA 2: Gotas medianas estáticas y micro-perlas
  vec2 uv2 = uv * vec2(9.0, 6.0) * aspect;
  vec2 id2 = floor(uv2);
  vec2 f2 = fract(uv2) - 0.5;

  for (int dy = -1; dy <= 1; dy++) {
    for (int dx = -1; dx <= 1; dx++) {
      vec2 neighbor = vec2(float(dx), float(dy));
      vec2 cId = id2 + neighbor;
      vec3 rnd = hash33(vec3(cId, 88.9));

      if (rnd.x < 0.65) {
        vec2 dropCenter = neighbor + (rnd.yz - 0.5) * 0.60;
        vec2 dVec = f2 - dropCenter;
        float dist = length(dVec);
        float r = 0.075 + 0.065 * rnd.y;

        if (dist < r) {
          float normDist = dist / r;
          float edgeSoft = smoothstep(1.0, 0.65, normDist);
          vec2 norm2D = (dVec / r) * edgeSoft * 0.55;
          totalNormal += norm2D;
          dropMask = max(dropMask, edgeSoft * 0.85);
          rimMask = max(rimMask, smoothstep(0.60, 0.95, normDist) * edgeSoft * 0.70);
        }
      }
    }
  }

  return vec4(totalNormal, max(dropMask, trailMask), rimMask);
}

void main() {
  vec2 px = FlutterFragCoord().xy;
  vec2 uv = px / uSize;
  vec2 aspect = vec2(uSize.x / max(uSize.y, 1.0), 1.0);

  // Simulación física de capas de lluvia
  vec4 rain = getRain(uv, uTime, aspect);
  vec2 normal = rain.xy;
  float dropMask = rain.z;
  float rimMask = rain.w;

  // Reactividad a graves: ondas de tensión superficial
  if (uBass > 0.03) {
    normal += vec2(sin(uv.y * 70.0 + uTime * 10.0), cos(uv.x * 70.0 + uTime * 10.0)) * (uBass * 0.016);
  }

  // Iluminación cáustica de borde (refracción interna en cristal transparente)
  vec3 causticCol = vec3(0.82, 0.94, 1.00) * (0.65 + uSpark * 0.45);
  vec3 col = causticCol * rimMask;

  // Brillo especular superior del cielo/luz cenital
  vec2 specDir = normalize(vec2(-0.55, -0.80));
  float specDot = max(0.0, dot(normalize(vec3(normal, 0.45)), vec3(specDir, 0.75)));
  float spec = pow(specDot, 20.0) * dropMask;
  col += vec3(1.0, 1.0, 1.0) * spec * (0.85 + uSpark * 0.45);

  // Cuerpo de agua ligeramente cian translúcido en el interior de la gota
  col += vec3(0.35, 0.65, 0.88) * dropMask * 0.35;

  // Destello de relámpago con agudos altos
  if (uSpark > 0.08) {
    col += vec3(0.70, 0.85, 1.00) * (uSpark * 0.40) * dropMask;
  }

  // Alpha transparente: fondo completamente vacío, solo gotas y rastros visibles
  float alpha = clamp(dropMask * 0.28 + rimMask * 0.78 + spec * 0.95, 0.0, 1.0);

  fragColor = vec4(clamp(col, 0.0, 1.0) * alpha, alpha);
}
""",
};

