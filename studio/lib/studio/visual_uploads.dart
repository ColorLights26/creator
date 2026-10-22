import 'dart:convert';

/// Stable authoring IDs distinguish copies without changing their revision.
enum StudioReactiveFamily {
  improved('Reactivas mejoradas', 'reactiva_mejorada_'),
  original('Reactivas', 'reactiva_');

  const StudioReactiveFamily(this.label, this.idPrefix);
  final String label;
  final String idPrefix;
}

/// Delivery provenance is editorial data, separate from visual revisions.
class StudioVisualUpload {
  const StudioVisualUpload({required this.visualId, this.author, this.date});

  final String visualId;
  final String? author;
  final String? date;

  StudioReactiveFamily? get reactiveFamily {
    for (final family in StudioReactiveFamily.values) {
      if (visualId.startsWith(family.idPrefix)) return family;
    }
    return null;
  }

  Map<String, String> toJson() => {
    'id': visualId,
    if (author != null) 'author': author!,
    if (date != null) 'date': date!,
  };
}

List<StudioVisualUpload> decodeStudioVisualUploads(String source) {
  final data = jsonDecode(source);
  if (data is! Map || data['schemaVersion'] != 1 || data['visuals'] is! List) {
    throw const FormatException('El registro de entregas no es válido.');
  }
  final ids = <String>{};
  final uploads = <StudioVisualUpload>[];
  for (final row in data['visuals'] as List) {
    if (row is! Map ||
        row['id'] is! String ||
        !RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(row['id'] as String) ||
        !ids.add(row['id'] as String)) {
      throw const FormatException(
        'ID ausente, inválido o repetido en entregas.',
      );
    }
    final author = row['author'];
    final date = row['date'];
    if ((author != null || date != null) &&
        (author is! String ||
            author.trim().isEmpty ||
            date is! String ||
            !isStudioUploadDate(date))) {
      throw const FormatException('Autor o fecha de entrega inválidos.');
    }
    uploads.add(
      StudioVisualUpload(
        visualId: row['id'] as String,
        author: author as String?,
        date: date as String?,
      ),
    );
  }
  return List.unmodifiable(uploads);
}

bool isStudioUploadDate(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return false;
  final date = DateTime.tryParse(value);
  return date != null && date.toIso8601String().startsWith(value);
}

String encodeStudioVisualUploads(Iterable<StudioVisualUpload> uploads) =>
    '${const JsonEncoder.withIndent('  ').convert({
      'schemaVersion': 1,
      'visuals': [for (final upload in uploads) upload.toJson()],
    })}\n';
