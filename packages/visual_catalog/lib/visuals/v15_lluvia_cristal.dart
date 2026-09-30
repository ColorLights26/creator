// Lluvia sobre Cristal — Puerto de alta fidelidad con refracción óptica real y bokeh bokeh cinematográfico.
// Gotas de lluvia realistas con física de stutter-slide (adherencia y deslizamiento), estelas con microgotas,
// condensación empañada en cristal, sombras de menisco, anillos cáusticos y refracción invertida de ciudad nocturna.
const nativeSource = r'''
class Visual final : public Scene {
  float rainTime = 0.0f;
  float smoothEnergy = 0.0f;
  float smoothBass = 0.0f;
  float smoothSpark = 0.0f;

 public:
  void reset(uint32_t seed) override {
    rainTime = 0.0f;
    smoothEnergy = 0.0f;
    smoothBass = 0.0f;
    smoothSpark = 0.0f;
  }

  void update(const Frame& f) override {
    float dt = float(f.delta);
    float speedMult = (f.reducedMotion ? 0.35f : 1.0f) * f.speed * (1.0f + smoothBass * 0.45f);
    rainTime += dt * speedMult;

    smoothEnergy += (f.music.energy - smoothEnergy) * float(1.0 - std::exp(-dt * 5.0));
    smoothBass += (f.music.bass - smoothBass) * float(1.0 - std::exp(-dt * 6.0));
    smoothSpark += (f.music.spark - smoothSpark) * float(1.0 - std::exp(-dt * 15.0));
  }

  void render(const Frame& f, Canvas& c) const override {
    float w = f.width, h = f.height;

    // Renderiza la simulación completa de lluvia sobre cristal con refracción óptica
    // y bokeh nocturno multicapa libre de cortes de cuadrícula.
    c.material("city_bokeh", {0.0f, 0.0f, w, h}, {
      rainTime,
      smoothEnergy,
      smoothSpark * f.intensity,
      smoothBass
    });
  }
};
''';

const shaderSources = <String, String>{
  'city_bokeh': r"""
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

// Bokeh cinematográfico de ciudad nocturna en coordenadas isotrópicas.
// CERO bolas cortadas: los radios y las celdas se calculan en espacio isotrópico
// garantizando que cada círculo decae a 0 antes del borde del vecindario 3x3.
vec3 sampleCityBokeh(vec2 p, vec2 uv) {
  // 1. Cielo nocturno profundo y gradiente de horizonte urbano
  vec3 colSkyZenith  = vec3(0.015, 0.020, 0.040); // Azul noche profundo
  vec3 colSkyHorizon = vec3(0.075, 0.050, 0.090); // Bruma púrpura/ámbar de contaminación lumínica
  vec3 colGround     = vec3(0.012, 0.014, 0.022); // Asfalto oscuro mojado

  // Gradiente vertical basado en UV (0 = superior, 1 = inferior)
  vec3 col = mix(colSkyZenith, colSkyHorizon, smoothstep(0.0, 0.65, uv.y));
  col = mix(col, colGround, smoothstep(0.65, 1.0, uv.y));

  // 2. Grandes cúpulas de luz difusa en la distancia (farolas y letreros lejanos)
  vec2 lamp1 = vec2(-0.45, -0.05);
  vec2 lamp2 = vec2( 0.40,  0.08);
  vec2 lamp3 = vec2(-0.05,  0.15);
  vec2 lamp4 = vec2( 0.18, -0.15);
  col += vec3(1.00, 0.68, 0.30) * 0.22 * exp(-length(p - lamp1) * 3.2);
  col += vec3(0.35, 0.80, 1.00) * 0.20 * exp(-length(p - lamp2) * 3.5);
  col += vec3(1.00, 0.40, 0.18) * 0.24 * exp(-length(p - lamp3) * 3.0);
  col += vec3(0.85, 0.22, 0.65) * 0.16 * exp(-length(p - lamp4) * 3.8);

  // 3. Capa 1: Discos de apertura fotográfica bokeh (lejanos, desenfoque f/1.4)
  // Cuadrícula isotrópica perfecta (sin deformación por aspect ratio)
  float scale1 = 4.2;
  vec2 gp1 = p * scale1;
  vec2 cell1 = floor(gp1);
  vec2 f1 = fract(gp1);

  for (int dy = -1; dy <= 1; dy++) {
    for (int dx = -1; dx <= 1; dx++) {
      vec2 neighbor = vec2(float(dx), float(dy));
      vec2 cId = cell1 + neighbor;
      vec3 rnd = hash33(vec3(cId, 17.3));

      // Solo en la franja media/baja (ciudad/horizonte)
      float cellY = (cId.y + 0.5) / scale1;
      if (rnd.x < 0.60 && cellY > -0.60) {
        // Centro strictly centrado dentro de [0.25, 0.75]
        vec2 center = neighbor + 0.25 + 0.50 * rnd.yz;
        float dist = length(f1 - center);

        // Radio estrictamente <= 0.38 para garantizar que nunca toque celdas +-2
        float radius = 0.18 + 0.18 * rnd.x;

        if (dist < radius) {
          float normDist = dist / radius;
          // Perfil de lente bokeh con anillo cáustico exterior y núcleo translúcido
          float rim = smoothstep(0.70, 0.98, normDist) * (1.0 - smoothstep(0.98, 1.0, normDist));
          float core = (1.0 - normDist * normDist) * 0.45;
          float bokeh = rim * 1.35 + core;

          vec3 lCol;
          float cSel = rnd.z;
          if (cSel < 0.36) {
            lCol = vec3(1.00, 0.72, 0.36); // Ámbar farola
          } else if (cSel < 0.62) {
            lCol = vec3(0.40, 0.85, 1.00); // Cian xenón
          } else if (cSel < 0.82) {
            lCol = vec3(1.00, 0.22, 0.26); // Rojo freno
          } else {
            lCol = vec3(0.28, 0.95, 0.65); // Verde semáforo
          }

          col += lCol * bokeh * (0.35 + uEnergy * 0.18);
        }
      }
    }
  }

  // 4. Capa 2: Tráfico en movimiento (faros cálidos y luces traseras rojas en carriles)
  float scale2 = 7.0;
  float trafficTime = uTime * 0.12;
  vec2 pT = p;
  if (p.y > -0.20 && p.y < 0.60) {
    float laneY = floor(p.y * 7.0);
    float dir = (mod(laneY, 2.0) == 0.0) ? 1.0 : -1.0;
    pT.x += trafficTime * dir * (0.7 + 0.3 * fract(laneY * 0.41));

    vec2 gp2 = pT * scale2;
    vec2 cell2 = floor(gp2);
    vec2 f2 = fract(gp2);

    for (int dy = -1; dy <= 1; dy++) {
      for (int dx = -1; dx <= 1; dx++) {
        vec2 neighbor = vec2(float(dx), float(dy));
        vec2 cId = cell2 + neighbor;
        vec3 rnd = hash33(vec3(cId, 43.1));

        if (rnd.x < 0.52) {
          vec2 center = neighbor + 0.28 + 0.44 * rnd.yz;
          float dist = length(f2 - center);
          float radius = 0.13 + 0.14 * rnd.y;

          if (dist < radius) {
            float normDist = dist / radius;
            float bokeh = smoothstep(1.0, 0.45, normDist) * (1.0 - normDist * 0.35);
            vec3 lCol = (dir > 0.0)
              ? vec3(1.00, 0.88, 0.65) // Faros delanteros dorados
              : vec3(1.00, 0.16, 0.20); // Luces de freno rojas
            col += lCol * bokeh * 0.40;
          }
        }
      }
    }
  }

  return col;
}

// Capas de lluvia física sobre cristal: gotas deslizantes con stutter-slide,
// estelas con microgotas, gotas estáticas y condensación.
vec4 getRain(vec2 uv, float t, vec2 aspect) {
  vec2 totalNormal = vec2(0.0);
  float dropMask = 0.0;
  float rimMask = 0.0;
  float trailMask = 0.0;

  // -----------------------------------------------------------------
  // 1. Gotas Principales Deslizantes (Stutter-Slide con estela de agua)
  // -----------------------------------------------------------------
  vec2 gridA = uv * vec2(4.0 * aspect.x, 3.2);
  vec2 idA = floor(gridA);
  vec2 fA = fract(gridA) - 0.5;

  for (int dy = -1; dy <= 1; dy++) {
    for (int dx = -1; dx <= 1; dx++) {
      vec2 n = vec2(float(dx), float(dy));
      vec2 cId = idA + n;
      vec3 rnd = hash33(vec3(cId, 103.1));

      // Movimiento característico de stutter-slide (adherencia y deslizamiento rápido)
      float dropPhase = t * (0.32 + 0.18 * rnd.x) + rnd.y * 6.28318;
      float slip = dropPhase + sin(dropPhase) * 0.42 + sin(dropPhase * 2.0) * 0.12;
      float dropY = fract(slip * 0.25);

      vec2 dropPos = n + vec2((rnd.z - 0.5) * 0.52, dropY - 0.5);
      vec2 dVec = fA - dropPos;
      dVec.x *= aspect.x;

      float dropR = 0.046 + 0.024 * rnd.y;

      // Estela mojada y microgotas dejadas en el recorrido vertical
      if (dVec.y < 0.0 && dVec.y > -0.52) {
        float trailProg = -dVec.y / 0.52;
        float trailWidth = dropR * 0.35 * (1.0 - trailProg * 0.65);

        // Gotas perladas a lo largo de la estela
        float beadSpacing = 0.065;
        float beadY = mod(-dVec.y, beadSpacing) - beadSpacing * 0.5;
        float beadDist = length(vec2(dVec.x, beadY));
        float beadR = trailWidth * 0.85;

        if (beadDist < beadR) {
          float beadNorm = beadDist / beadR;
          float beadSoft = smoothstep(1.0, 0.68, beadNorm);
          vec2 beadN = (vec2(dVec.x, beadY) / max(beadR, 0.001)) * beadSoft;
          totalNormal += beadN * 0.70;
          dropMask = max(dropMask, beadSoft * 0.82);
          rimMask = max(rimMask, smoothstep(0.60, 0.95, beadNorm) * beadSoft);
        }

        // Pista de agua limpia sobre el cristal
        if (abs(dVec.x) < trailWidth) {
          float wMask = (1.0 - abs(dVec.x) / trailWidth) * (1.0 - trailProg);
          totalNormal.x += (dVec.x / max(trailWidth, 0.001)) * wMask * 0.22;
          trailMask = max(trailMask, wMask * 0.50);
        }
      }

      // Forma convexa de la gota principal
      float distDrop = length(dVec * vec2(1.0, 0.86 + 0.14 * smoothstep(0.0, dropR, -dVec.y)));
      if (distDrop < dropR) {
        float normDist = distDrop / dropR;
        float edgeSoft = smoothstep(1.0, 0.80, normDist);
        float rim = smoothstep(0.70, 0.98, normDist) * edgeSoft;

        vec2 norm2D = (dVec / dropR) * edgeSoft;
        totalNormal += norm2D * 1.55;
        dropMask = max(dropMask, edgeSoft);
        rimMask = max(rimMask, rim);
      }
    }
  }

  // -----------------------------------------------------------------
  // 2. Gotas Estáticas Medianas Adheridas al Cristal
  // -----------------------------------------------------------------
  vec2 gridB = uv * vec2(8.5 * aspect.x, 8.5);
  vec2 idB = floor(gridB);
  vec2 fB = fract(gridB) - 0.5;

  for (int dy = -1; dy <= 1; dy++) {
    for (int dx = -1; dx <= 1; dx++) {
      vec2 n = vec2(float(dx), float(dy));
      vec2 cId = idB + n;
      vec3 rnd = hash33(vec3(cId, 239.5));

      if (rnd.x < 0.62) {
        vec2 dropPos = n + (rnd.yz - 0.5) * 0.58;
        vec2 dVec = fB - dropPos;
        dVec.x *= aspect.x;
        float dropR = 0.024 + 0.016 * rnd.x;
        float distDrop = length(dVec);

        if (distDrop < dropR) {
          float normDist = distDrop / dropR;
          float edgeSoft = smoothstep(1.0, 0.76, normDist);
          float rim = smoothstep(0.68, 0.96, normDist) * edgeSoft;

          vec2 norm2D = (dVec / dropR) * edgeSoft;
          totalNormal += norm2D * 1.25;
          dropMask = max(dropMask, edgeSoft);
          rimMask = max(rimMask, rim);
        }
      }
    }
  }

  // -----------------------------------------------------------------
  // 3. Micro-condensación de Niebla en Cristal (gotitas microscópicas)
  // -----------------------------------------------------------------
  vec2 gridC = uv * vec2(20.0 * aspect.x, 20.0);
  vec2 idC = floor(gridC);
  vec2 fC = fract(gridC) - 0.5;
  vec3 rndC = hash33(vec3(idC, 511.9));

  if (rndC.x < 0.68) {
    vec2 dropPos = (rndC.yz - 0.5) * 0.65;
    vec2 dVec = fC - dropPos;
    float dropR = 0.055 + 0.075 * rndC.x;
    float distM = length(dVec);
    if (distM < dropR) {
      float normDist = distM / dropR;
      float edgeSoft = smoothstep(1.0, 0.62, normDist);
      vec2 norm2D = (dVec / dropR) * edgeSoft * 0.42;
      totalNormal += norm2D;
      dropMask = max(dropMask, edgeSoft * 0.65);
      rimMask = max(rimMask, smoothstep(0.60, 0.95, normDist) * edgeSoft * 0.40);
    }
  }

  return vec4(totalNormal, max(dropMask, trailMask), rimMask);
}

void main() {
  vec2 px = FlutterFragCoord().xy;
  vec2 uv = px / uSize;
  vec2 aspect = vec2(uSize.x / max(uSize.y, 1.0), 1.0);
  float minDim = min(uSize.x, uSize.y);

  // Simulación física de capas de lluvia
  vec4 rain = getRain(uv, uTime, aspect);
  vec2 normal = rain.xy;
  float dropMask = rain.z;
  float rimMask = rain.w;

  // Reactividad a graves: ondas capilares de tensión superficial
  if (uBass > 0.03) {
    normal += vec2(sin(uv.y * 70.0 + uTime * 10.0), cos(uv.x * 70.0 + uTime * 10.0)) * (uBass * 0.016);
  }

  // Desplazamiento por refracción óptica real (Ley de Snell en gota convexa):
  // La gota invierte y amplifica la escena del fondo.
  float refrPower = 0.065 * (1.0 + uEnergy * 0.25);
  vec2 refractedUV = uv - normal * refrPower;

  // Aberración cromática: dispersión de longitudes de onda en el borde de agua
  vec2 caOffset = normal * 0.007 * (1.0 + rimMask * 2.2);
  vec2 uvR = clamp(refractedUV + caOffset, 0.0, 1.0);
  vec2 uvG = clamp(refractedUV, 0.0, 1.0);
  vec2 uvB = clamp(refractedUV - caOffset, 0.0, 1.0);

  // Muestreo del bokeh cinematográfico a través del lente refractivo
  vec2 pR = (uvR - 0.5) * vec2(uSize.x / minDim, uSize.y / minDim);
  vec2 pG = (uvG - 0.5) * vec2(uSize.x / minDim, uSize.y / minDim);
  vec2 pB = (uvB - 0.5) * vec2(uSize.x / minDim, uSize.y / minDim);

  float rCh = sampleCityBokeh(pR, uvR).r;
  float gCh = sampleCityBokeh(pG, uvG).g;
  float bCh = sampleCityBokeh(pB, uvB).b;
  vec3 col = vec3(rCh, gCh, bCh);

  // Niebla de condensación suave en cristal fuera de las gotas y pistas de agua
  float mist = (1.0 - dropMask) * 0.18;
  col += vec3(0.08, 0.11, 0.16) * mist;

  // Sombra de menisco oscuro (reflexión interna total en el borde de la gota)
  col *= (1.0 - rimMask * 0.52);

  // Anillo cáustico luminoso brillante en el borde
  vec3 causticCol = vec3(0.85, 0.94, 1.00) * (0.42 + uSpark * 0.58);
  col += causticCol * rimMask;

  // Brillo especular superior del cielo/farolas (reflejo en la cúpula de agua)
  vec2 specDir = normalize(vec2(-0.55, -0.80));
  float specDot = max(0.0, dot(normalize(vec3(normal, 0.45)), vec3(specDir, 0.75)));
  float spec = pow(specDot, 22.0) * dropMask;
  col += vec3(1.0, 1.0, 1.0) * spec * (0.75 + uSpark * 0.50);

  // Relámpago distante en chispas de audio
  if (uSpark > 0.05) {
    col += vec3(0.72, 0.85, 1.00) * (uSpark * 0.35);
  }

  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
