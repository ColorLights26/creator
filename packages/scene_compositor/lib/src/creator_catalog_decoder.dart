import 'dart:convert';

import 'creator_visual_definition.dart';

/// Reads the two generated assets together. Editorial metadata never enters the
/// native runtime manifest, and a mismatch fails instead of joining by position.
List<CreatorVisualDefinition> decodeCreatorCatalog({
  required String runtimeJson,
  required String metadataJson,
}) {
  if (utf8.encode(runtimeJson).length > 4 * 1024 * 1024 ||
      utf8.encode(metadataJson).length > 1024 * 1024) {
    throw const FormatException('El catálogo supera su tamaño permitido.');
  }
  final runtime = _object(jsonDecode(runtimeJson), 'runtime');
  final metadata = _object(jsonDecode(metadataJson), 'metadata');
  if (runtime['schemaVersion'] != 1 || metadata['schemaVersion'] != 1) {
    throw const FormatException('Versión de catálogo no compatible.');
  }
  final programs = _list(runtime['visuals'], 'runtime.visuals');
  final descriptions = _list(metadata['visuals'], 'metadata.visuals');
  if (programs.isEmpty ||
      programs.length > 64 ||
      programs.length != descriptions.length) {
    throw const FormatException(
      'Los catálogos no contienen los mismos visuales.',
    );
  }
  final metadataById = <String, Map<String, dynamic>>{};
  for (final value in descriptions) {
    final item = _object(value, 'metadata visual');
    final id = _string(item['id'], 'metadata.id');
    if (metadataById.containsKey(id)) {
      throw FormatException('Metadata duplicada: $id.');
    }
    metadataById[id] = item;
  }
  final visuals = <CreatorVisualDefinition>[];
  for (final value in programs) {
    final item = _object(value, 'runtime visual');
    final id = _string(item['id'], 'runtime.id');
    final info = metadataById.remove(id);
    if (info == null) throw FormatException('Falta metadata de $id.');
    for (final field in ['name', 'role', 'reactivity']) {
      if (info[field] != item[field]) {
        throw FormatException('$id: $field difiere entre programa y metadata.');
      }
    }
    final controls = _object(item['controls'], '$id.controls');
    final credits = _object(info['credits'], '$id.credits');
    final thumbnail = _object(info['thumbnail'], '$id.thumbnail');
    final visual = CreatorVisualDefinition(
      id: id,
      name: _string(item['name'], '$id.name'),
      shaderSource: _string(item['shaderSource'], '$id.shaderSource'),
      role: _enum(CreatorRole.values, item['role'], '$id.role'),
      reactivity: _enum(
        CreatorReactivity.values,
        item['reactivity'],
        '$id.reactivity',
      ),
      framesPerSecond: _integer(item['framesPerSecond'], '$id.framesPerSecond'),
      seed: _integer(item['seed'], '$id.seed'),
      colors: List<int>.unmodifiable([
        for (final color in _list(item['colors'], '$id.colors'))
          _integer(color, '$id.color'),
      ]),
      controls: CreatorControls(
        intensity: _number(controls['intensity'], '$id.intensity'),
        speed: _number(controls['speed'], '$id.speed'),
        detail: _number(controls['detail'], '$id.detail'),
        glow: _number(controls['glow'], '$id.glow'),
      ),
      description: _string(info['description'], '$id.description'),
      purposes: _tags(info['purposes'], '$id.purposes'),
      moods: _tags(info['moods'], '$id.moods'),
      concepts: _tags(info['concepts'], '$id.concepts'),
      publication: _enum(
        CreatorPublication.values,
        info['publication'],
        '$id.publication',
      ),
      credits: CreatorCredits(
        author: _string(credits['author'], '$id.author'),
        license: _string(credits['license'], '$id.license'),
        source: _string(credits['source'], '$id.source'),
      ),
      thumbnail: CreatorThumbnailSpec(
        timeSeconds: _number(
          thumbnail['timeSeconds'],
          '$id.thumbnail.timeSeconds',
        ),
        assetPath: _optionalString(
          thumbnail['assetPath'],
          '$id.thumbnail.assetPath',
        ),
        assetPackage: _optionalString(
          thumbnail['assetPackage'],
          '$id.thumbnail.assetPackage',
        ),
      ),
    );
    if (item['programId'] != visual.programId) {
      throw FormatException('$id: el programId no corresponde al visual.');
    }
    visuals.add(visual);
  }
  return validateCreatorCatalog(visuals);
}

Map<String, dynamic> _object(Object? value, String field) {
  if (value is! Map<String, dynamic>)
    throw FormatException('$field debe ser un objeto.');
  return value;
}

List<dynamic> _list(Object? value, String field) {
  if (value is! List) throw FormatException('$field debe ser una lista.');
  return value;
}

String _string(Object? value, String field) {
  if (value is! String) throw FormatException('$field debe ser texto.');
  return value;
}

String? _optionalString(Object? value, String field) =>
    value == null ? null : _string(value, field);

int _integer(Object? value, String field) {
  if (value is! int) throw FormatException('$field debe ser un entero.');
  return value;
}

double _number(Object? value, String field) {
  if (value is! num || !value.isFinite)
    throw FormatException('$field debe ser un número finito.');
  return value.toDouble();
}

List<String> _tags(Object? value, String field) => List<String>.unmodifiable([
  for (final item in _list(value, field)) _string(item, field),
]);

T _enum<T extends Enum>(List<T> values, Object? value, String field) {
  final name = _string(value, field);
  for (final option in values) {
    if (option.name == name) return option;
  }
  throw FormatException('$field no admite $name.');
}
