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
      if (!RegExp('\\.${modifier.id}\\b').hasMatch(code))
        '$file: ${modifier.label} (${modifier.id}) no se usa en el código: '
            'léelo con modifiers(f).${modifier.id} o glide(f).${modifier.id}, '
            'o quítalo.',
      if (_basicNames.contains(_plain(modifier.label)))
        '$file: «${modifier.label}» ya es un ajuste básico: elige un '
            'modificador que cambie otra cosa.',
    ],
  ];
}

/// [source] without C++ comments, string or character literals, so a name
/// mentioned only in a comment or a text does not count as used.
String stripCppCommentsAndStrings(String source) {
  final out = StringBuffer();
  var i = 0;
  while (i < source.length) {
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

String _plain(String label) {
  const accents = {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u'};
  return label
      .trim()
      .toLowerCase()
      .split('')
      .map((c) => accents[c] ?? c)
      .join();
}
