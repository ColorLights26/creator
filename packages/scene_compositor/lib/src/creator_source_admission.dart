/// Remove Dart comments without altering strings. The admitted source is one
/// const declaration, with no extra imports or executable top-level statements.
String stripComments(String input) {
  final out = StringBuffer();
  var i = 0;
  while (i < input.length) {
    if (input.startsWith('//', i)) {
      final end = input.indexOf('\n', i);
      if (end < 0) break;
      i = end;
      continue;
    }
    if (input.startsWith('/*', i)) {
      var depth = 1;
      i += 2;
      while (i < input.length && depth > 0) {
        if (input.startsWith('/*', i)) {
          depth++;
          i += 2;
        } else if (input.startsWith('*/', i)) {
          depth--;
          i += 2;
        } else {
          i++;
        }
      }
      if (depth != 0) throw const FormatException('Comentario incompleto.');
      out.write(' ');
      continue;
    }
    if (input[i] == "'" || input[i] == '"') {
      final quote = input[i];
      final delimiter = input.startsWith(quote * 3, i) ? quote * 3 : quote;
      final raw = i > 0 && input[i - 1] == 'r';
      out.write(delimiter);
      i += delimiter.length;
      var closed = false;
      while (i < input.length) {
        if (input.startsWith(delimiter, i)) {
          out.write(delimiter);
          i += delimiter.length;
          closed = true;
          break;
        }
        if (!raw && input[i] == '\\') {
          if (i + 1 >= input.length) break;
          out.write(input.substring(i, i + 2));
          i += 2;
        } else {
          out.write(input[i++]);
        }
      }
      if (!closed) throw const FormatException('String incompleto.');
      continue;
    }
    out.write(input[i++]);
  }
  return out.toString().trim();
}

void validateSourcePair(String source, String metadata) {
  validateCreatorVisualSource(source);
  validateCreatorMetadataSource(metadata);
}

/// Validate the pasted Dart envelope before importing it. GPU compilation and
/// runtime review still validate the drawing itself.
void validateCreatorVisualSource(String source) {
  if (source.trimLeft().startsWith('```')) {
    throw const FormatException(
      'Pegaste las marcas del bloque de la IA. Copia sólo el código que está dentro.',
    );
  }
  parseCreatorVisualSource(source);
}

class CreatorSourceEnvelope {
  const CreatorSourceEnvelope(
    this.source, {
    this.native = false,
    this.materials = const {},
    this.line = 1,
    this.modifiers = false,
    this.variations = false,
  });
  final String source;
  final bool native;
  final Map<String, String> materials;
  final int line;

  /// The file declares `const modifiers = [...]` before nativeSource.
  final bool modifiers;

  /// The file declares `const variations = [...]` before nativeSource.
  final bool variations;
}

const _authoringImport = "import 'package:scene_compositor/authoring.dart';";

/// The literal lists a code file may declare before nativeSource, with the
/// only words each may contain outside its strings. Anything else (calls,
/// variables, other declarations) is rejected before Dart sees it.
const _literalLists = {
  'modifiers': (
    type: 'CreatorModifier',
    words: {
      'const',
      'CreatorModifier',
      'slider',
      'steps',
      'toggle',
      'choice',
      'min',
      'max',
      'value',
      'options',
      'true',
      'false',
    },
    hint:
        'CreatorModifier.slider/steps/toggle/choice con textos, números, '
        'true o false',
  ),
  'variations': (
    type: 'CreatorVariation',
    words: {'const', 'CreatorVariation', 'true', 'false'},
    hint:
        "CreatorVariation('Nombre', {'id': valor, ...}) con textos, "
        'números, true o false',
  ),
};

// Numbers first, so 1e-3, 0x10 or 1_000 are not read as words.
final _numbers = RegExp(
  r'(?<![A-Za-z0-9_])(?:0[xX][0-9a-fA-F_]+|(?:\d[\d_]*)?\.?\d[\d_]*(?:[eE][+-]?\d[\d_]*)?)',
);

/// Splits one `const <name> = [...];` off the start of [code]. Returns null
/// when [code] does not start with a literal list.
({String name, String rest})? _takeLiteralList(String code) {
  final head = RegExp(
    r'^const\s+(modifiers|variations)\s*=\s*(?:<(\w+)>)?\s*\[',
  ).firstMatch(code);
  if (head == null) return null;
  final name = head[1]!;
  final list = _literalLists[name]!;
  if (head[2] != null && head[2] != list.type) {
    throw FormatException(
      '$name es una lista de ${list.type}: const $name = [ ... ];',
    );
  }
  var depth = 1;
  var i = head.end;
  final outside = StringBuffer();
  while (i < code.length && depth > 0) {
    final char = code[i];
    if (char == "'" || char == '"') {
      // Skip the whole string, including escaped quotes.
      var end = i + 1;
      while (end < code.length && code[end] != char) {
        end += code[end] == '\\' ? 2 : 1;
      }
      if (end >= code.length) break;
      if (code.substring(i, end).contains(r'$')) {
        throw FormatException(
          'Los textos de $name son literales: quita el \$.',
        );
      }
      i = end + 1;
      outside.write(' ');
      continue;
    }
    if ('[({'.contains(char)) depth++;
    if ('])}'.contains(char)) depth--;
    if (depth > 0) outside.write(char);
    i++;
  }
  final after = code.substring(i).trimLeft();
  if (depth != 0 || !after.startsWith(';')) {
    throw FormatException(
      '$name debe ser una lista constante: const $name = [ ... ];',
    );
  }
  if (code.substring(head.end, i - 1).trim().isEmpty) {
    throw FormatException(
      'const $name está vacía: bórrala o agrega al menos un elemento.',
    );
  }
  if (name == 'variations') _checkVariations(code.substring(head.end - 1, i));
  final words = RegExp(
    r'[A-Za-z_][A-Za-z0-9_]*',
  ).allMatches('$outside'.replaceAll(_numbers, ' '));
  final unknown = words
      .map((m) => m[0]!)
      .where((word) => !list.words.contains(word));
  if (outside.toString().contains(';') || unknown.isNotEmpty) {
    throw FormatException(
      '$name sólo admite ${list.hint}'
      '${unknown.isEmpty ? '' : ' (sobra: ${unknown.first})'}.',
    );
  }
  return (name: name, rest: after.substring(1).trim());
}

/// Variations are maps the registry imports as Dart: anything but
/// `CreatorVariation('Nombre', {'id': valor, ...})` with text keys, text,
/// number or true/false values and no repeated key would break the catalog
/// build for every visual, so the exact shape is checked here.
void _checkVariations(String literal) {
  final tokens = _variationToken.allMatches(literal).map((m) => m[1]!).toList();
  var at = 0;
  String? peek() => at < tokens.length ? tokens[at] : null;
  String take() => at < tokens.length ? tokens[at++] : '';
  bool isText(String? token) =>
      token != null && (token.startsWith("'") || token.startsWith('"'));
  Never bad(String why) =>
      throw FormatException(
        "variations: $why. Usa CreatorVariation('Nombre', {'id': valor, ...}).",
      );
  void expect(String token) {
    if (take() != token) bad('falta «$token»');
  }

  expect('[');
  while (peek() != ']') {
    if (peek() == 'const') take();
    if (take() != 'CreatorVariation') {
      bad('cada elemento es un CreatorVariation');
    }
    expect('(');
    if (!isText(take())) bad('el nombre va entre comillas');
    expect(',');
    if (peek() == 'const') take();
    expect('{');
    final keys = <String>{};
    while (peek() != '}') {
      final key = take();
      if (!isText(key)) bad('las claves son ids entre comillas');
      if (!keys.add(key.substring(1, key.length - 1))) {
        bad('la clave $key está repetida');
      }
      expect(':');
      final value = take();
      if (!isText(value) &&
          value != 'true' &&
          value != 'false' &&
          !RegExp(r'^[-+]?[0-9.]').hasMatch(value)) {
        bad('$key necesita un número, un texto, true o false');
      }
      if (peek() == ',') take();
    }
    expect('}');
    if (peek() == ',') take();
    expect(')');
    if (peek() == ',') take();
  }
  expect(']');
  if (at != tokens.length) bad('sobra algo después de la lista');
}

/// One token of a variations literal: a quoted text, a number, a word or a
/// punctuation mark.
final _variationToken = RegExp(
  r'''\s*('(?:\\.|[^'\\])*'|"(?:\\.|[^"\\])*"|[-+]?(?:0[xX][0-9a-fA-F_]+|(?:\d[\d_]*)?\.?\d[\d_]*(?:[eE][+-]?\d[\d_]*)?)|[A-Za-z_]\w*|[\[\](){}:,])''',
);

/// The Dart expression that joins a visual's code file (imported as [code])
/// with its metadata file (imported as [metadata]). Every generator uses it,
/// so a new declaration reaches the studio and the app approval alike.
String creatorVisualExpression(
  CreatorSourceEnvelope source, {
  required String code,
  required String metadata,
  required String file,
}) =>
    source.native
        ? '$metadata.metadata.withNative($code.nativeSource, '
            'shaderSources: ${source.materials.isEmpty ? 'const {}' : '$code.shaderSources'}, '
            '${source.modifiers ? 'modifiers: $code.modifiers, ' : ''}'
            '${source.variations ? 'variations: $code.variations, ' : ''}'
            "sourceFile: '$file', sourceLine: ${source.line})"
        : '$metadata.metadata.withShader($code.shaderSource)';

/// Parse literal constants only; never execute author expressions during discovery.
CreatorSourceEnvelope parseCreatorVisualSource(String source) {
  var code = stripComments(source);
  final imported = code.startsWith(_authoringImport);
  if (imported) code = code.substring(_authoringImport.length).trimLeft();
  final declared = <String>{};
  for (var list = _takeLiteralList(code); list != null;) {
    if (!declared.add(list.name)) {
      throw FormatException('const ${list.name} aparece dos veces.');
    }
    if (!imported) {
      throw FormatException(
        'Para declarar ${list.name}, empieza el archivo con '
        "import 'package:scene_compositor/authoring.dart';",
      );
    }
    code = list.rest;
    list = _takeLiteralList(code);
  }
  if (imported && declared.isEmpty) {
    throw FormatException(
      RegExp(r'\bconst\s+(modifiers|variations)\b').hasMatch(code)
          ? 'const modifiers y const variations van antes de nativeSource, '
              'justo después del import.'
          : 'El import sólo hace falta para declarar const modifiers = [...] '
              'o const variations = [...].',
    );
  }
  final head = RegExp(
    r'^const\s+(shaderSource|nativeSource)\s*=\s*r(\x27{3}|\x22{3})([\s\S]*?)\2\s*;',
  ).firstMatch(code);
  if (head == null) {
    throw const FormatException(
      'Conserva const nativeSource = r\'\'\'...\'\'\'; (o shaderSource para visuales anteriores), sin widgets ni metadata. Sólo puede ir antes el import de authoring.dart, const modifiers = [...] y const variations = [...].',
    );
  }
  var tail = code.substring(head.end).trim();
  if (RegExp(r'^const\s+(modifiers|variations)\b').firstMatch(tail)
      case final misplaced?) {
    throw FormatException(
      'const ${misplaced[1]} va antes de nativeSource, justo después del import.',
    );
  }
  final materials = <String, String>{};
  if (tail.isNotEmpty && head[1] == 'nativeSource') {
    final map = RegExp(
      r'^const\s+shaderSources\s*=\s*(?:<String,\s*String>)?\s*\{',
    ).firstMatch(tail);
    if (map == null || !tail.endsWith('};'))
      throw const FormatException(
        'shaderSources debe ser un mapa constante de nombres y strings GLSL raw.',
      );
    tail = tail.substring(map.end, tail.length - 2).trim();
    final entry = RegExp(
      r'^\x27([a-z][a-z0-9_]*)\x27\s*:\s*r(\x27{3}|\x22{3})([\s\S]*?)\2\s*(,|$)',
    );
    while (tail.isNotEmpty) {
      final match = entry.firstMatch(tail);
      if (match == null || materials.containsKey(match[1]))
        throw const FormatException(
          'Material inválido o repetido. Usa nombre: string raw, sin expresiones.',
        );
      materials[match[1]!] = match[3]!;
      tail = tail.substring(match.end).trim();
    }
  }
  if (tail.isNotEmpty)
    throw const FormatException(
      'El archivo creativo sólo contiene nativeSource y shaderSources opcional, o shaderSource anterior.',
    );
  if (declared.isNotEmpty && head[1] != 'nativeSource') {
    throw const FormatException(
      'Los modificadores y las variaciones sólo existen en visuales con nativeSource.',
    );
  }
  final literal = source.indexOf('r${head[2]}${head[3]}');
  final line =
      literal < 0
          ? 1
          : '\n'.allMatches(source.substring(0, literal + 4)).length + 1;
  return CreatorSourceEnvelope(
    head[3]!,
    native: head[1] == 'nativeSource',
    materials: materials,
    line: line,
    modifiers: declared.contains('modifiers'),
    variations: declared.contains('variations'),
  );
}

void validateCreatorMetadataSource(String metadata) {
  var data = stripComments(metadata);
  const allowedImport = "import 'package:scene_compositor/authoring.dart';";
  if (!data.startsWith(allowedImport)) {
    throw const FormatException(
      'Metadata: sólo se admite el import de authoring.dart.',
    );
  }
  data = data.substring(allowedImport.length).trim();
  const start = 'const metadata = CreatorVisualMetadata(';
  if (!data.startsWith(start) || !data.endsWith(');')) {
    throw const FormatException(
      'Metadata: conserva const metadata = CreatorVisualMetadata(...).',
    );
  }
  // Any semicolon outside a string other than the final one is a second Dart
  // statement. Const evaluation itself rejects executable expressions.
  final strings = RegExp(
    r"'(?:\\.|[^'\\])*'"
    '|'
    r'"(?:\\.|[^"\\])*"',
  );
  final withoutStrings = data.replaceAll(strings, '');
  if (';'.allMatches(withoutStrings).length != 1 ||
      RegExp(
        r'\b(import|export|part|class|extension|void|final|late)\b',
      ).hasMatch(withoutStrings)) {
    throw const FormatException(
      'La metadata sólo admite la declaración constante, sin código adicional.',
    );
  }
}
