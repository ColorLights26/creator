import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_compositor/scene_compositor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.chic.colorlights/scene_surface_renderer');
  const visual = CreatorVisualDefinition(
    id: 'test_visual',
    name: 'Test visual',
    shaderSource:
        'vec4 paintVisual(vec2 uv, CreatorFrame f) { return f.color0; }',
  );

  test(
    'iOS still owns native textures while ordinary signal/control changes do not rebuild UI',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final asset = Uint8List.fromList(
        utf8.encode(encodeCreatorCatalog([visual])),
      );
      messenger.setMockMessageHandler('flutter/assets', (data) async {
        if (utf8.decode(
              data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
            ) !=
            'assets/creator_catalog.json')
          return null;
        return ByteData.sublistView(asset);
      });
      addTearDown(
        () => messenger.setMockMessageHandler('flutter/assets', null),
      );
      final calls = <MethodCall>[];
      var nextTexture = 10;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'isSupported') return true;
        if (call.method == 'attach') return {'textureId': nextTexture++};
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final controller = SceneCompositorController();
      var notifications = 0;
      controller.addListener(() => notifications++);
      await controller.setVisual(
        visual,
        size: const Size(390, 844),
        pixelRatio: 3,
      );
      expect(controller.textureId, 10);
      expect(controller.preview, isNull);
      expect(notifications, 1);
      await controller.setPlaying(false);
      await controller.resize(const Size(400, 800), 3);
      await controller.sendSignal(
        createSyntheticSceneSignalRecording().samples[31].frame,
      );
      expect(notifications, 1);
      expect(calls.any((call) => call.method == 'updateSignalFrame'), isTrue);
      await controller.setControls(const CreatorControls(speed: .3, intensity: .8));
      await controller.setReactive(false);
      expect(calls.where((call) => call.method == 'attach'), hasLength(1));
      expect(controller.textureId, 10);
      final update = calls.lastWhere((call) => call.method == 'updateDocument').arguments as Map;
      final updatedLayer = (update['sceneDocument']['layers'] as List).single as Map;
      final updatedNode = (updatedLayer['proceduralParameters']['document']['layers'] as List).single['node'] as Map;
      expect(updatedNode['parameters']['options']['speed'], .3);
      expect(updatedNode['parameters']['audioReactive'], false);
      await controller.reset(qaSessionSeed: 0xffffffff);
      expect(controller.textureId, 11);
      expect(notifications, 2);
      final attach =
          calls.lastWhere((call) => call.method == 'attach').arguments as Map;
      final outer = (attach['sceneDocument']['layers'] as List).single as Map;
      final inner = outer['proceduralParameters']['document'] as Map;
      final node = (inner['layers'] as List).single['node'] as Map;
      expect(node['parameters']['seed'], 0xffffffff);
      expect(node['parameters']['options']['speed'], .3);
      await controller.close();
      expect(controller.textureId, isNull);
      expect(controller.preview, isNull);
      expect(notifications, 3);
      controller.dispose();
    },
  );
}
