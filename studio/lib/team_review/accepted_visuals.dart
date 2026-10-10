import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

enum AcceptedVisualRelation { integrated, equivalent }

/// Editorial acceptance is separate from team scores and technical readiness.
/// Only the exact drawing revision named in the portable register is accepted.
class AcceptedVisualEntry {
  const AcceptedVisualEntry({
    required this.id,
    required this.revision,
    required this.integratedId,
    required this.integratedRevision,
    required this.relation,
    required this.family,
  });

  final String id;
  final String revision;
  final String integratedId;
  final String integratedRevision;
  final AcceptedVisualRelation relation;
  final String family;

  String get label => switch (relation) {
    AcceptedVisualRelation.integrated => 'En la app',
    AcceptedVisualRelation.equivalent => 'Variante equivalente',
  };
}

class AcceptedVisuals {
  const AcceptedVisuals.none() : _entries = const {};

  AcceptedVisuals.fromJson(Object? value) : _entries = _parse(value);

  final Map<String, AcceptedVisualEntry> _entries;

  AcceptedVisualEntry? entryFor(String id, String revision) {
    return _entries['$id@$revision'];
  }

  bool contains(String id, String revision) => entryFor(id, revision) != null;

  static Map<String, AcceptedVisualEntry> _parse(Object? value) {
    if (value is! Map<String, dynamic> ||
        value['schemaVersion'] != 1 ||
        value['entries'] is! List) {
      throw const FormatException('Registro de aceptados: esquema inválido.');
    }
    final result = <String, AcceptedVisualEntry>{};
    final revisionPattern = RegExp(r'^[a-f0-9]{16}$');
    for (final row in value['entries'] as List) {
      if (row is! Map<String, dynamic> ||
          ![
            'id',
            'revision',
            'integratedId',
            'integratedRevision',
            'family',
          ].every(
            (key) => row[key] is String && (row[key] as String).isNotEmpty,
          ) ||
          !revisionPattern.hasMatch(row['revision'] as String) ||
          !revisionPattern.hasMatch(row['integratedRevision'] as String) ||
          !['integrated', 'equivalent'].contains(row['relation'])) {
        throw const FormatException('Registro de aceptados: entrada inválida.');
      }
      final id = row['id'] as String;
      final key = '$id@${row['revision']}';
      if (result.containsKey(key)) {
        throw FormatException(
          'Registro de aceptados: revisión duplicada $key.',
        );
      }
      final relation = AcceptedVisualRelation.values.byName(
        row['relation'] as String,
      );
      if (relation == AcceptedVisualRelation.integrated &&
          (id != row['integratedId'] ||
              row['revision'] != row['integratedRevision'])) {
        throw FormatException(
          'Registro de aceptados: integración incoherente $id.',
        );
      }
      result[key] = AcceptedVisualEntry(
        id: id,
        revision: row['revision'] as String,
        integratedId: row['integratedId'] as String,
        integratedRevision: row['integratedRevision'] as String,
        relation: relation,
        family: row['family'] as String,
      );
    }
    for (final entry in result.values) {
      if (entry.relation != AcceptedVisualRelation.equivalent) continue;
      final integrated =
          result['${entry.integratedId}@${entry.integratedRevision}'];
      if (integrated == null ||
          integrated.relation != AcceptedVisualRelation.integrated ||
          integrated.revision != entry.integratedRevision ||
          integrated.family != entry.family) {
        throw FormatException(
          'Registro de aceptados: variante sin integración válida ${entry.id}.',
        );
      }
    }
    return Map.unmodifiable(result);
  }
}

/// Offline kits keep working if the register cannot be read. A missing or
/// malformed asset is reported and never turns candidates into accepted ones.
Future<AcceptedVisuals> loadAcceptedVisuals() async {
  try {
    return AcceptedVisuals.fromJson(
      jsonDecode(await rootBundle.loadString('assets/accepted_visuals.json')),
    );
  } on FormatException catch (error, stack) {
    return acceptedVisualsLoadFailure(error, stack);
  } on FlutterError catch (error, stack) {
    return acceptedVisualsLoadFailure(error, stack);
  }
}

AcceptedVisuals acceptedVisualsLoadFailure(Object error, StackTrace stack) {
  developer.log(
    'No se pudo cargar assets/accepted_visuals.json: $error',
    name: 'audiovisual_creator',
    error: error,
    stackTrace: stack,
  );
  return const AcceptedVisuals.none();
}
