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
  final code = stripComments(source);
  final envelope = RegExp(
    r"^const\s+shaderSource\s*=\s*r'''([\s\S]*?)'''\s*;$",
  ).firstMatch(code);
  if (envelope == null || envelope[1]!.contains("'''")) {
    throw const FormatException(
      'La respuesta no tiene el formato de la plantilla. Necesitas el archivo completo '
      'con const shaderSource = r\'\'\'...\'\'\';, sin widgets, imports ni metadata.',
    );
  }
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
