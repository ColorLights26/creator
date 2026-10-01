import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:visual_catalog/visual_catalog.dart';

import 'studio/creator_studio.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  String? failure;
  try {
    await initializeCreatorCatalog();
  } on Object catch (error, stack) {
    developer.log(
      'Creator catalog initialization failed',
      name: 'creator',
      error: error,
      stackTrace: stack,
    );
    failure = error.toString();
  }

  Map<String, VisualCurationStatus>? initialCuration;
  try {
    final assetString =
        await rootBundle.loadString('assets/creator_curation_review.json');
    final decoded = jsonDecode(assetString);
    if (decoded is Map) {
      initialCuration = {};
      for (final entry in decoded.entries) {
        final status = VisualCurationStatus.values.firstWhere(
          (s) => s.name == entry.value,
          orElse: () => VisualCurationStatus.pending,
        );
        initialCuration[entry.key as String] = status;
      }
    }
  } catch (_) {
    // Bundled asset may not exist in mock environments
  }

  runApp(VisualStudioApp(
    initializationError: failure,
    initialCuration: initialCuration,
  ));
}

class VisualStudioApp extends StatelessWidget {
  const VisualStudioApp({
    super.key,
    this.initializationError,
    this.initialCuration,
  });

  final String? initializationError;
  final Map<String, VisualCurationStatus>? initialCuration;

  @override
  Widget build(BuildContext context) {
    final colors = ColorScheme.fromSeed(
      seedColor: const Color(0xFF8AF7D5),
      brightness: Brightness.dark,
      surface: const Color(0xFF111314),
    );
    return MaterialApp(
      title: 'Visual Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colors,
        scaffoldBackgroundColor: colors.surface,
        appBarTheme: AppBarTheme(
          backgroundColor: colors.surface,
          foregroundColor: colors.onSurface,
          elevation: 0,
          centerTitle: false,
        ),
      ),
      home:
          initializationError == null
              ? CreatorStudio(initialCuration: initialCuration)
              : Scaffold(
                appBar: AppBar(title: const Text('Revisa el catálogo')),
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: SelectableText(
                      'No se pudo abrir el catálogo. Revisa el error, corrige el '
                      'archivo y vuelve a ejecutar el proyecto.\n\n$initializationError',
                    ),
                  ),
                ),
              ),
    );
  }
}
