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
  });
  final String source;
  final bool native;
  final Map<String, String> materials;
  final int line;
}

/// Parse literal constants only; never execute author expressions during discovery.
CreatorSourceEnvelope parseCreatorVisualSource(String source) {
  final code = stripComments(source);
  final head = RegExp(
    r'^const\s+(shaderSource|nativeSource)\s*=\s*r(\x27{3}|\x22{3})([\s\S]*?)\2\s*;',
  ).firstMatch(code);
  if (head == null) {
    throw const FormatException(
      'Conserva const nativeSource = r\'\'\'...\'\'\'; (o shaderSource para visuales anteriores), sin imports, widgets ni metadata.',
    );
  }
  var tail = code.substring(head.end).trim();
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
