/// Build-time only: how a visual's C++ uses what it declares. Studio's asset
/// build and the app approval run it; the phone's catalog decoding never
/// does, so it can read source code freely.
library;

import 'authoring.dart';

/// Labels that only rename a basic setting every visual already has.
const _basicNames = {
  'intensidad',
  'intensity',
  'velocidad',
  'speed',
  'detalle',
  'detail',
  'densidad',
  'brillo',
  'glow',
  'resplandor',
  'color',
  'colores',
  'paleta',
  'palette',
  'colors',
};

/// Problems that make a declared modifier useless or misleading, each one a
/// message the collaborator can hand to the AI. Empty when all is well.
/// [file] names the code file when [visual] was rebuilt from a catalog.
List<String> lintCreatorVisual(CreatorVisualDefinition visual, {String? file}) {
  if (visual.modifiers.isEmpty) return const [];
  final code = stripCppCommentsAndStrings(visual.nativeSource);
  file ??= visual.sourceFile;
  return [
    if (RegExp(r'\bmodifiers\s*\[').hasMatch(code))
      '$file: lee los ajustes con modifiers(f) o glide(f), no con '
          'f.modifiers[…].',
    for (final modifier in visual.modifiers) ...[
      // Any use of the name counts (m.id, a structured binding, a macro):
      // the native sweep is what proves the modifier changes the drawing.
      if (!RegExp(
        '(?<![A-Za-z0-9_])${modifier.id}(?![A-Za-z0-9_])',
      ).hasMatch(code))
        '$file: ${modifier.label} (${modifier.id}) no se usa en el código: '
            'léelo con modifiers(f).${modifier.id} o glide(f).${modifier.id}, '
            'o quítalo.',
      if (_basicNames.contains(_plain(modifier.label)))
        '$file: «${modifier.label}» ya es un ajuste básico: elige un '
            'modificador que cambie otra cosa.',
    ],
  ];
}

/// [source] without C++ comments, string or character literals (raw strings
/// included), so a name mentioned only in a comment or a text does not count
/// as used. A digit separator (10'000) is not a character literal.
String stripCppCommentsAndStrings(String source) {
  final out = StringBuffer();
  var i = 0;
  bool alnum(int at) =>
      at >= 0 &&
      at < source.length &&
      RegExp(r'[A-Za-z0-9_]').hasMatch(source[at]);
  while (i < source.length) {
    final raw = RegExp(r'R"([^()\\\s]{0,16})\(').matchAsPrefix(source, i);
    if (raw != null && !alnum(i - 1)) {
      final close = source.indexOf(')${raw[1]}"', raw.end);
      i = close < 0 ? source.length : close + raw[1]!.length + 2;
      out.write(' ');
      continue;
    }
    if (source[i] == "'" && _inNumber(source, i)) {
      i++;
      continue;
    }
    if (source.startsWith('//', i)) {
      final end = source.indexOf('\n', i);
      i = end < 0 ? source.length : end;
      continue;
    }
    if (source.startsWith('/*', i)) {
      final end = source.indexOf('*/', i + 2);
      i = end < 0 ? source.length : end + 2;
      out.write(' ');
      continue;
    }
    final char = source[i];
    if (char == '"' || char == "'") {
      i++;
      while (i < source.length && source[i] != char && source[i] != '\n') {
        i += source[i] == r'\' ? 2 : 1;
      }
      i++;
      out.write(' ');
      continue;
    }
    out.write(char);
    i++;
  }
  return out.toString();
}

/// Whether the apostrophe at [at] separates digits of a number (10'000,
/// 0xFF'FF), which happens when the word before it starts with a digit.
bool _inNumber(String source, int at) {
  var start = at;
  while (start > 0 && RegExp(r'[A-Za-z0-9_.]').hasMatch(source[start - 1])) {
    start--;
  }
  return start < at &&
      RegExp(r'[0-9]').hasMatch(source[start]) &&
      at + 1 < source.length &&
      RegExp(r'[0-9A-Fa-f]').hasMatch(source[at + 1]);
}

String _plain(String label) {
  const accents = {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u'};
  return label
      .trim()
      .toLowerCase()
      .split('')
      .map((c) => accents[c] ?? c)
      .join();
}
