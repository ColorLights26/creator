import 'dart:async';

import 'package:audiovisual_creator/readiness/creator_readiness.dart';
import 'package:audiovisual_creator/studio/creator_studio.dart';
import 'package:audiovisual_creator/studio/studio_view.dart';
import 'package:audiovisual_creator/team_review/accepted_visuals.dart';
import 'package:audiovisual_creator/team_review/revision_links.dart';
import 'package:audiovisual_creator/team_review/team_rating_panel.dart';
import 'package:audiovisual_creator/team_review/team_ranking_screen.dart';
import 'package:audiovisual_creator/team_review/team_review_client.dart';
import 'package:audiovisual_creator/team_review/team_review_controller.dart';
import 'package:audiovisual_creator/team_review/team_voting_summary.dart';
import 'package:audiovisual_creator/team_review/visual_revision.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_compositor/scene_compositor.dart';

const _overlay = CreatorVisualDefinition(
  id: 'aura_transparente',
  name: 'Aura transparente',
  role: CreatorRole.overlay,
  shaderSource: 'vec4 paintVisual() { return vec4(0.25); }',
);
const _background = CreatorVisualDefinition(
  id: 'aura',
  name: 'Aura fondo',
  shaderSource: 'vec4 paintVisual() { return vec4(1.0); }',
);
const _new = CreatorVisualDefinition(
  id: 'aura_2',
  name: 'Aura 2',
  shaderSource: 'vec4 paintVisual() { return vec4(0.5); }',
);
const _changed = CreatorVisualDefinition(
  id: 'aura_transparente',
  name: 'Aura transparente mejorada',
  role: CreatorRole.overlay,
  shaderSource: 'vec4 paintVisual() { return vec4(0.75); }',
);

Map<String, dynamic> _register() => {
  'schemaVersion': 1,
  'entries': [
    {
      'id': _overlay.id,
      'revision': visualRevision(_overlay),
      'integratedId': _overlay.id,
      'integratedRevision': visualRevision(_overlay),
      'relation': 'integrated',
      'family': 'aura',
    },
    {
      'id': _background.id,
      'revision': visualRevision(_background),
      'integratedId': _overlay.id,
      'integratedRevision': visualRevision(_overlay),
      'relation': 'equivalent',
      'family': 'aura',
    },
  ],
};

class _Controller extends SceneCompositorController {
  final shown = <String>[];
  @override
  int? get textureId => shown.isEmpty ? null : 7;
  @override
  String? get error => null;
  @override
  Future<void> setVisual(
    CreatorVisualDefinition visual, {
    required Size size,
    required double pixelRatio,
  }) async {
    shown.add(visual.id);
    notifyListeners();
  }

  @override
  Future<void> resize(Size size, double pixelRatio) async {}
  @override
  Future<void> setPlaying(bool value) async {}
  @override
  Future<void> setReactive(bool value) async {}
  @override
  Future<void> setControls(CreatorControls value) async {}
  @override
  Future<void> setModifiers(Map<String, double> value) async {}
  @override
  Future<void> setPalette(List<int>? value) async {}
  @override
  Future<void> reset({int? qaSessionSeed}) async {}
  @override
  Future<void> sendSignal(SceneRenderSignalFrameV2 frame) async {}
  @override
  Future<void> close() async {}
}

class _Store implements ReviewerKeyStore {
  @override
  Future<String?> read() async => 'test';
  @override
  Future<void> write(String? key) async {}
}

class _Client implements TeamReviewClient {
  static const reviewer = TeamReviewer(id: 'f', name: 'Franco');
  final sent = <String>[];
  final votes = <TeamRating>[
    TeamRating(
      visualId: _overlay.id,
      revision: visualRevision(_overlay),
      reviewerId: 'f',
      reviewerName: 'Franco',
      score: 9,
    ),
  ];
  @override
  Future<TeamReviewer> me(String key) async => reviewer;
  @override
  Future<TeamRatingsSnapshot?> ratings(String key, {String? since}) async =>
      TeamRatingsSnapshot(
        reviewer: reviewer,
        ratings: votes,
        hiddenCounts: const {},
      );
  @override
  Future<TeamRating> rate(
    String key, {
    required String visualId,
    required String visualName,
    required String revision,
    required int score,
    String? comment,
    bool change = false,
  }) async {
    sent.add(visualId);
    final rating = TeamRating(
      visualId: visualId,
      revision: revision,
      reviewerId: 'f',
      reviewerName: 'Franco',
      score: score,
    );
    votes.add(rating);
    return rating;
  }
}

Future<void> _flush(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

Future<void> _pickFilter(WidgetTester tester, String name) async {
  await tester.tap(find.byKey(const ValueKey('role-filter-button')));
  await _flush(tester);
  final option = find.byKey(ValueKey('vote-filter-$name'));
  await tester.ensureVisible(option);
  await tester.tap(option);
  await _flush(tester);
}

Future<void> _mount(
  WidgetTester tester,
  _Controller controller, {
  TeamReviewController? review,
  List<CreatorVisualDefinition> Function()? catalog,
  Future<AcceptedVisuals> Function()? loader,
}) async {
  tester.view.physicalSize = const Size(1024, 1366);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: CreatorStudio(
        catalogBuilder: catalog ?? () => [_overlay, _background, _new],
        controllerFactory: () => controller,
        recordingsLoader: () async => [],
        readinessLoader: () async => const CreatorReadiness.none(),
        buildHashLoader: () async => null,
        revisionLinksLoader: () async => const RevisionLinks.none(),
        acceptedVisualsLoader:
            loader ?? () async => AcceptedVisuals.fromJson(_register()),
        thumbnailBuilder: (_, _) => const SizedBox(),
        backdropBuilder: (_, _) => const SizedBox(),
        teamReview: review,
      ),
    ),
  );
  await _flush(tester);
}

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await _flush(tester);
}

void main() {
  test('only exact revisions are accepted, family descendants stay active', () {
    final accepted = AcceptedVisuals.fromJson(_register());
    expect(
      accepted.entryFor(_overlay.id, visualRevision(_overlay))?.label,
      'En la app',
    );
    expect(
      accepted.entryFor(_background.id, visualRevision(_background))?.label,
      'Variante equivalente',
    );
    expect(accepted.contains(_changed.id, visualRevision(_changed)), isFalse);
    expect(accepted.contains(_new.id, visualRevision(_new)), isFalse);
  });

  test('invalid and inconsistent registers fail explicitly', () {
    for (final register in [
      {'schemaVersion': 2, 'entries': <Object?>[]},
      {
        'schemaVersion': 1,
        'entries': [
          {'id': 'invalid'},
        ],
      },
      {
        'schemaVersion': 1,
        'entries': [(_register()['entries'] as List).last],
      },
      {
        'schemaVersion': 1,
        'entries': [
          (_register()['entries'] as List).first,
          (_register()['entries'] as List).first,
        ],
      },
    ]) {
      expect(() => AcceptedVisuals.fromJson(register), throwsFormatException);
    }
  });

  test('historical integration and a current counterpart may share an ID', () {
    final register = _register();
    (register['entries'] as List).add({
      'id': _background.id,
      'revision': '0000000000000000',
      'integratedId': _background.id,
      'integratedRevision': '0000000000000000',
      'relation': 'integrated',
      'family': 'aura',
    });
    final accepted = AcceptedVisuals.fromJson(register);
    expect(
      accepted.entryFor(_background.id, '0000000000000000')?.label,
      'En la app',
    );
    expect(
      accepted.entryFor(_background.id, visualRevision(_background))?.label,
      'Variante equivalente',
    );
  });

  testWidgets(
    'accepted section works offline, plays both variants and keeps adjustments',
    (tester) async {
      final controller = _Controller();
      await _mount(tester, controller);
      expect(controller.shown.last, _new.id);
      expect(find.text('01 / 01'), findsOneWidget);
      await _pickFilter(tester, 'accepted');
      expect(controller.shown.last, _overlay.id);
      expect(find.text('01 / 02'), findsOneWidget);
      expect(find.text('En la app · Fuera de votación'), findsOneWidget);
      expect(find.byType(TeamRatingPanel), findsNothing);
      expect(
        find.byKey(const ValueKey('visual-adjustments-button')),
        findsOneWidget,
      );
      final view = tester.widget<StudioView>(find.byType(StudioView));
      view.onSelectVisual(_background.id);
      await _flush(tester);
      expect(controller.shown.last, _background.id);
      expect(
        find.text('Variante equivalente · Fuera de votación'),
        findsOneWidget,
      );
      await _pickFilter(tester, 'all');
      expect(controller.shown.last, _new.id);
      await _close(tester);
    },
  );

  testWidgets(
    'accepted entries leave queue, pending counts and round summary; historical votes remain',
    (tester) async {
      final client = _Client();
      final review = TeamReviewController(client: client, store: _Store());
      final controller = _Controller();
      await _mount(tester, controller, review: review);
      final panel = tester.widget<TeamRatingPanel>(
        find.byType(TeamRatingPanel),
      );
      expect(panel.queue.map((entry) => entry.id), [_new.id]);
      expect(review.myRating(_overlay.id, visualRevision(_overlay))?.score, 9);
      await tester.tap(find.byKey(const ValueKey('role-filter-button')));
      await _flush(tester);
      expect(find.text('Por votar (1)'), findsOneWidget);
      expect(find.text('Ya votados (0)'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('vote-filter-toVote')));
      await _flush(tester);
      panel.onFinished!();
      await _flush(tester);
      final summary = tester.widget<TeamVotingSummaryScreen>(
        find.byType(TeamVotingSummaryScreen),
      );
      expect(summary.entries.map((entry) => entry.id), [_new.id]);
      await tester.ensureVisible(
        find.byKey(const ValueKey('team-summary-all')),
      );
      await tester.tap(find.byKey(const ValueKey('team-summary-all')));
      await tester.pump();
      await _flush(tester);
      expect(find.byType(TeamVotingSummaryScreen), findsNothing);
      await _pickFilter(tester, 'accepted');
      expect(find.byType(TeamRatingPanel), findsNothing);
      expect(client.sent, isEmpty);
      expect(
        find.byKey(const ValueKey('accepted-historical-ranking')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('accepted-historical-ranking')),
      );
      await _flush(tester);
      final ranking = tester.widget<TeamRankingScreen>(
        find.byType(TeamRankingScreen),
      );
      expect(ranking.entries.map((entry) => entry.id), [
        _overlay.id,
        _background.id,
        _new.id,
      ]);
      ranking.onOpenVisual(_background.id);
      await tester.pump();
      await _flush(tester);
      expect(controller.shown.last, _background.id);
      expect(
        find.text('Variante equivalente · Fuera de votación'),
        findsOneWidget,
      );
      expect(find.byType(TeamRatingPanel), findsNothing);
      expect(client.sent, isEmpty);
      await _close(tester);
      review.dispose();
    },
  );

  testWidgets('new revision returns to voting after reload', (tester) async {
    final client = _Client();
    final review = TeamReviewController(client: client, store: _Store());
    final controller = _Controller();
    var catalog = [_overlay, _background, _new];
    await _mount(tester, controller, review: review, catalog: () => catalog);
    catalog = [_changed, _background, _new];
    tester.binding.buildOwner!.reassemble(tester.binding.rootElement!);
    await _flush(tester);
    final panel = tester.widget<TeamRatingPanel>(find.byType(TeamRatingPanel));
    expect(panel.queue.map((entry) => entry.id), [_changed.id, _new.id]);
    await _pickFilter(tester, 'accepted');
    final view = tester.widget<StudioView>(find.byType(StudioView));
    expect(view.visuals.map((visual) => visual.id), [_background.id]);
    await _close(tester);
    review.dispose();
  });

  testWidgets('voting stays unavailable until register loading finishes', (
    tester,
  ) async {
    final client = _Client();
    final review = TeamReviewController(client: client, store: _Store());
    final gate = Completer<AcceptedVisuals>();
    final controller = _Controller();
    await _mount(tester, controller, review: review, loader: () => gate.future);
    expect(find.byType(TeamRatingPanel), findsNothing);
    expect(controller.shown, isEmpty);
    gate.complete(AcceptedVisuals.fromJson(_register()));
    await _flush(tester);
    expect(controller.shown.last, _new.id);
    expect(find.byType(TeamRatingPanel), findsOneWidget);
    expect(client.sent, isEmpty);
    await _close(tester);
    review.dispose();
  });

  testWidgets(
    'accepted section remains reachable when the evaluation list is empty',
    (tester) async {
      final controller = _Controller();
      await _mount(tester, controller, catalog: () => [_overlay, _background]);
      expect(controller.shown, isEmpty);
      expect(find.text('No hay visuales en este filtro.'), findsOneWidget);
      await _pickFilter(tester, 'accepted');
      expect(controller.shown.last, _overlay.id);
      expect(find.text('01 / 02'), findsOneWidget);
      await _close(tester);
    },
  );

  testWidgets(
    'broken register loader preserves creation without inventing acceptance',
    (tester) async {
      final controller = _Controller();
      await _mount(
        tester,
        controller,
        loader: () async => throw const FormatException('bad register'),
      );
      expect(controller.shown.last, _overlay.id);
      expect(find.text('01 / 03'), findsOneWidget);
      await _pickFilter(tester, 'accepted');
      expect(
        tester.widget<StudioView>(find.byType(StudioView)).visuals,
        isEmpty,
      );
      await _close(tester);
    },
  );
}
