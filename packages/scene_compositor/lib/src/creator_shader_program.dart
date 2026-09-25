import 'dart:ui' as ui;

final _programs = <String, Future<ui.FragmentProgram>>{};

/// A single compiled Flutter program is shared by previews and frozen posters.
Future<ui.FragmentProgram> loadCreatorShaderProgram(String asset) {
  return _programs.putIfAbsent(asset, () async {
    try {
      return await ui.FragmentProgram.fromAsset(
        asset,
      ).timeout(const Duration(seconds: 15));
    } on Object {
      _programs.remove(asset);
      rethrow;
    }
  });
}
