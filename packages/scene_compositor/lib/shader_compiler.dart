import 'authoring.dart';

/// A deliberately small common GLSL/Metal authoring surface, not a transpiler.
/// Native Metal provides vector aliases; Android uses the GLSL source directly.
/// Namespacing author functions prevents collisions between catalogue entries.
String compilePortableShader(List<CreatorVisualDefinition> visuals) {
  final sources = <String>[];
  for (var i = 0; i < visuals.length; i++) {
    final visual = visuals[i];
    if (visual.isNative) {
      sources.add(
        'vec4 creator_${i}_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }',
      );
      continue;
    }
    var source = visual.shaderSource
        .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
        .replaceAll(RegExp(r'//[^\n]*'), '');
    if (RegExp(
          r'\b(uint|bool|struct|uniform|sampler\w*|texture\w*|dFdx|dFdy|fwidth|discard|inout|constant|thread|device)\b',
        ).hasMatch(source) ||
        source.contains('#') ||
        source.contains('&') ||
        source.contains('[[')) {
      throw FormatException(
        '${visual.id}: usa solo el subconjunto GLSL portable descrito en la plantilla.',
      );
    }
    final functions =
        RegExp(
          r'\b(?:float|int|vec[234]|mat[234]|void)\s+(\w+)\s*\(',
        ).allMatches(source).map((m) => m[1]!).toSet();
    if (!functions.contains('paintVisual') || functions.contains('main')) {
      throw FormatException('${visual.id}: define paintVisual, no main.');
    }
    for (final name in functions) {
      source = source.replaceAll(
        RegExp('\\b${RegExp.escape(name)}\\b'),
        'creator_${i}_$name',
      );
    }
    sources.add(source);
  }
  return '''// Generated from packages/visual_catalog/lib/visuals/*.dart. Do not edit.
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform float uTime;
uniform float uSeedLow;
uniform float uSeedHigh;
uniform float uEnergy;
uniform float uBass;
uniform float uBody;
uniform float uSpark;
uniform float uFlow;
uniform float uPulse;
uniform float uPhase;
uniform float uBpm;
uniform float uIntensity;
uniform float uSpeed;
uniform float uDetail;
uniform float uGlow;
uniform vec4 uColor0;
uniform vec4 uColor1;
uniform vec4 uColor2;
uniform vec4 uColor3;
uniform float uVisualIndex;
out vec4 fragColor;
struct CreatorFrame {
  vec2 size; float time; float seedLow; float seedHigh;
  float energy; float bass; float body; float spark;
  float flow; float pulse; float phase; float bpm;
  float intensity; float speed; float detail; float glow;
  vec4 color0; vec4 color1; vec4 color2; vec4 color3;
};
${sources.join('\n')}
void main() {
  CreatorFrame f;
  f.size=uSize; f.time=uTime; f.seedLow=uSeedLow; f.seedHigh=uSeedHigh;
  f.energy=uEnergy; f.bass=uBass; f.body=uBody; f.spark=uSpark;
  f.flow=uFlow; f.pulse=uPulse; f.phase=uPhase; f.bpm=uBpm;
  f.intensity=uIntensity; f.speed=uSpeed; f.detail=uDetail; f.glow=uGlow;
  f.color0=uColor0; f.color1=uColor1; f.color2=uColor2; f.color3=uColor3;
  vec2 uv=FlutterFragCoord().xy / max(f.size,vec2(1.0));
  vec4 color=vec4(0.0);
${[for (var i = 0; i < visuals.length; i++) '  ${i == 0 ? 'if' : 'else if'} (abs(uVisualIndex - $i.0) < 0.5) color=creator_${i}_paintVisual(uv,f);'].join('\n')}
  if (any(isnan(color)) || any(isinf(color))) color=vec4(0.0);
  color=clamp(color,0.0,1.0);
  fragColor=vec4(color.rgb*color.a,color.a);
}
''';
}
