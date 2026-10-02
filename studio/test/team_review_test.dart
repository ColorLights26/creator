import 'dart:async';

import 'package:audiovisual_creator/studio/creator_studio.dart';
import 'package:audiovisual_creator/team_review/team_ranking.dart';
import 'package:audiovisual_creator/team_review/team_ranking_screen.dart';
import 'package:audiovisual_creator/team_review/team_review_client.dart';
import 'package:audiovisual_creator/team_review/team_review_controller.dart';
import 'package:audiovisual_creator/team_review/visual_revision.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_compositor/scene_compositor.dart';

const _aurora = CreatorVisualDefinition(
  id: 'aurora',
  name: 'Aurora',
  shaderSource: 'float4 paintVisual() { return float4(0); }',
);
const _plasma = CreatorVisualDefinition(
  id: 'plasma',
  name: 'Plasma',
  shaderSource: 'float4 paintVisual() { return float4(1); }',
);
const _tides = CreatorVisualDefinition(
  id: 'mareas_test',
  name: 'Mareas',
  shaderSource: 'float4 paintVisual() { return float4(0.5); }',
);

class _MemoryStore implements ReviewerKeyStore {
  _MemoryStore([this.key]);

  String? key;

  @override
  Future<String?> read() async => key;

  @override
  Future<void> write(String? key) async => this.key = key;
}

/// Server double with the same blind rule as chic-ads.
class _FakeClient implements TeamReviewClient {
  final reviewers = <String, TeamReviewer>{
    'clr_franco': const TeamReviewer(id: 'f', name: 'Franco'),
    'clr_katy': const TeamReviewer(id: 'k', name: 'Katy'),
  };
  final stored = <TeamRating>[];
  final rateCalls = <({String visualId, String revision, int score})>[];

  TeamReviewer _auth(String key) =>
      reviewers[key] ??
      (throw const TeamReviewException('revoked', unauthorized: true));

  @override
  Future<TeamReviewer> me(String key) async => _auth(key);

  int version = 0;
  int fullReads = 0;

  @override
  Future<TeamRatingsSnapshot?> ratings(String key, {String? since}) async {
    final reviewer = _auth(key);
    if (since == '$version') return null;
    fullReads++;
    final voted = {
      for (final rating in stored)
        if (rating.reviewerId == reviewer.id)
          ratingKey(rating.visualId, rating.revision),
    };
    final hidden = <String, int>{};
    for (final rating in stored) {
      final slot = ratingKey(rating.visualId, rating.revision);
      if (!voted.contains(slot)) hidden[slot] = (hidden[slot] ?? 0) + 1;
    }
    return TeamRatingsSnapshot(
      version: '$version',
      reviewer: reviewer,
      ratings: [
        for (final rating in stored)
          if (voted.contains(ratingKey(rating.visualId, rating.revision)))
            rating,
      ],
      hiddenCounts: hidden,
      hiddenDiscarded: {
        for (final slot in hidden.keys)
          if (hidden[slot]! >= teamMinimumVotes &&
              _average(slot) < teamPotentialThreshold)
            slot,
      },
    );
  }

  double _average(String slot) {
    final scores = [
      for (final rating in stored)
        if (ratingKey(rating.visualId, rating.revision) == slot) rating.score,
    ];
    return scores.reduce((sum, score) => sum + score) / scores.length;
  }

  @override
  Future<TeamRating> rate(
    String key, {
    required String visualId,
    required String visualName,
    required String revision,
    required int score,
    String? comment,
  }) async {
    final reviewer = _auth(key);
    rateCalls.add((visualId: visualId, revision: revision, score: score));
    version++;
    stored.removeWhere(
      (rating) =>
          rating.reviewerId == reviewer.id &&
          rating.visualId == visualId &&
          rating.revision == revision,
    );
    final rating = TeamRating(
      visualId: visualId,
      revision: revision,
      reviewerId: reviewer.id,
      reviewerName: reviewer.name,
      score: score,
      comment: comment ?? '',
    );
    stored.add(rating);
    return rating;
  }
}

class _Controller extends SceneCompositorController {
  final visuals = <String>[];

  @override
  int? get textureId => visuals.isEmpty ? null : 7;
  @override
  String? get error => null;

  @override
  Future<void> setVisual(
    CreatorVisualDefinition visual, {
    required Size size,
    required double pixelRatio,
  }) async {
    visuals.add(visual.id);
    notifyListeners();
  }

  @override
  Future<void> resize(Size size, double pixelRatio) async {}
  @override
  Future<void> setReactive(bool reactive) async {}
  @override
  Future<void> setPlaying(bool playing) async {}
  @override
  Future<void> reset({int? qaSessionSeed}) async {}
  @override
  Future<void> sendSignal(SceneRenderSignalFrameV2 frame) async {}
  @override
  Future<void> close() async {}
}

void main() {
  group('visualRevision', () {
    test('ignores catalog text but follows the drawing', () {
      const renamed = CreatorVisualDefinition(
        id: 'aurora',
        name: 'Aurora boreal',
        description: 'Otra descripción',
        shaderSource: 'float4 paintVisual() { return float4(0); }',
      );
      const redrawn = CreatorVisualDefinition(
        id: 'aurora',
        name: 'Aurora',
        shaderSource: 'float4 paintVisual() { return float4(0.2); }',
      );
      expect(visualRevision(renamed), visualRevision(_aurora));
      expect(visualRevision(redrawn), isNot(visualRevision(_aurora)));
      expect(visualRevision(_aurora), matches(RegExp(r'^[0-9a-f]{16}$')));
    });

    test('ignores compiler output that differs between machines', () {
      CreatorVisualDefinition build(String compiler, String image) =>
          CreatorVisualDefinition(
            id: 'a',
            name: 'A',
            nativeSource: 'x',
            images: const {'sky': 'images/sky.png'},
            nativeBuild: {
              'abi': 1,
              'hash': 'hash-$compiler',
              'sdkHash': 'sdk-$compiler',
              'materials': {
                'm': {'compilerHash': compiler, 'metalSource': 'msl-$compiler'},
              },
              'imageHashes': {'sky': image},
            },
          );
      expect(
        visualRevision(build('xcode27', 'img1')),
        visualRevision(build('xcode26', 'img1')),
      );
      expect(
        visualRevision(build('xcode27', 'img2')),
        isNot(visualRevision(build('xcode27', 'img1'))),
      );
    });

    test('does not depend on map insertion order', () {
      const first = CreatorVisualDefinition(
        id: 'a',
        name: 'A',
        nativeSource: 'x',
        shaderSources: {'one': '1', 'two': '2'},
      );
      const second = CreatorVisualDefinition(
        id: 'a',
        name: 'A',
        nativeSource: 'x',
        shaderSources: {'two': '2', 'one': '1'},
      );
      expect(visualRevision(first), visualRevision(second));
    });
  });

  group('TeamReviewController', () {
    test('keeps team scores hidden until voting, then reveals them', () async {
      final client = _FakeClient();
      final franco = TeamReviewController(
        client: client,
        store: _MemoryStore('clr_franco'),
      );
      final katy = TeamReviewController(
        client: client,
        store: _MemoryStore('clr_katy'),
      );
      await franco.start();
      await katy.start();

      expect(
        await franco.rate(
          visualId: 'olas',
          visualName: 'Olas',
          revision: 'abcdef1234567890',
          score: 8,
        ),
        isNull,
      );
      await katy.refresh();
      expect(katy.hasVoted('olas', 'abcdef1234567890'), isFalse);
      expect(katy.hiddenCount('olas', 'abcdef1234567890'), 1);
      expect(katy.ratingsFor('olas', 'abcdef1234567890'), isEmpty);

      await katy.rate(
        visualId: 'olas',
        visualName: 'Olas',
        revision: 'abcdef1234567890',
        score: 6,
      );
      expect(katy.myRating('olas', 'abcdef1234567890')?.score, 6);
      expect(
        katy.ratingsFor('olas', 'abcdef1234567890').map((r) => r.score),
        unorderedEquals([8, 6]),
      );
      expect(katy.hiddenCount('olas', 'abcdef1234567890'), 0);
    });

    test('signs in once and forgets a revoked key', () async {
      final client = _FakeClient();
      final store = _MemoryStore();
      final controller = TeamReviewController(client: client, store: store);
      await controller.start();
      expect(controller.signedIn, isFalse);

      expect(await controller.signIn('franco'), isNotNull);
      expect(await controller.signIn('  clr_franco  '), isNull);
      expect(controller.reviewer?.name, 'Franco');
      expect(store.key, 'clr_franco');

      client.reviewers.remove('clr_franco');
      final error = await controller.rate(
        visualId: 'olas',
        visualName: 'Olas',
        revision: 'abcdef1234567890',
        score: 4,
      );
      expect(error, isNotNull);
      expect(controller.signedIn, isFalse);
      expect(store.key, isNull);
      expect(controller.myRating('olas', 'abcdef1234567890'), isNull);
    });
  });

  test(
    'live updates bring the team\'s new votes without touching anything',
    () async {
      final client = _FakeClient();
      final katy = TeamReviewController(
        client: client,
        store: _MemoryStore('clr_katy'),
        liveInterval: const Duration(milliseconds: 20),
      );
      final franco = TeamReviewController(
        client: client,
        store: _MemoryStore('clr_franco'),
      );
      var repaints = 0;
      await katy.start();
      katy.addListener(() => repaints++);
      await Future<void>.delayed(const Duration(milliseconds: 90));
      expect(repaints, 0, reason: 'idle polls must not repaint');
      final readsBefore = client.fullReads;

      await franco.start();
      await franco.rate(
        visualId: 'olas',
        visualName: 'Olas',
        revision: 'abcdef1234567890',
        score: 9,
      );
      await Future<void>.delayed(const Duration(milliseconds: 90));
      expect(katy.hiddenCount('olas', 'abcdef1234567890'), 1);
      expect(repaints, greaterThan(0));
      expect(client.fullReads - readsBefore, lessThanOrEqualTo(3));

      katy.setActive(false);
      final pausedReads = client.fullReads;
      client.version++;
      await Future<void>.delayed(const Duration(milliseconds: 90));
      expect(client.fullReads, pausedReads, reason: 'no polling in background');
      katy.dispose();
      franco.dispose();
    },
  );

  testWidgets('studio votes on the visible revision and jumps to the next', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final client = _FakeClient();
    // Katy and Ana already left Plasma as a total discard (average 2.5).
    for (final (who, name, score) in [('k', 'Katy', 2), ('a', 'Ana', 3)]) {
      client.stored.add(
        TeamRating(
          visualId: 'plasma',
          revision: visualRevision(_plasma),
          reviewerId: who,
          reviewerName: name,
          score: score,
        ),
      );
    }
    final review = TeamReviewController(
      client: client,
      store: _MemoryStore('clr_franco'),
    );
    final compositor = _Controller();
    await tester.pumpWidget(
      MaterialApp(
        home: CreatorStudio(
          catalogBuilder: () => [_aurora, _plasma, _tides],
          controllerFactory: () => compositor,
          recordingsLoader: () async => [],
          thumbnailBuilder: (_, _) => const SizedBox(),
          teamReview: review,
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(find.byKey(const ValueKey('team-rating-panel')), findsOneWidget);
    expect(find.text('Faltan 2'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey('team-rating-score-8')),
    );
    await tester.tap(find.byKey(const ValueKey('team-rating-score-8')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(client.rateCalls.single, (
      visualId: 'aurora',
      revision: visualRevision(_aurora),
      score: 8,
    ));
    expect(find.textContaining('Equipo 8'), findsOneWidget);

    // The team discarded Plasma, so the queue skips it.
    await tester.ensureVisible(find.byKey(const ValueKey('team-rating-next')));
    await tester.tap(find.byKey(const ValueKey('team-rating-next')));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(compositor.visuals.last, 'mareas_test');
    expect(find.text('Último por votar'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 50));
    unawaited(Future<void>.value());
  });

  test('ranking verdict comes only from the average of the votes', () async {
    final client =
        _FakeClient()
          ..reviewers['clr_ana'] = const TeamReviewer(id: 'a', name: 'Ana');
    TeamRating vote(String visual, String who, int score) => TeamRating(
      visualId: visual,
      revision: 'abcdef1234567890',
      reviewerId: who,
      reviewerName: {'f': 'Franco', 'k': 'Katy', 'a': 'Ana'}[who]!,
      score: score,
    );
    client.stored.addAll([
      vote('aurora', 'f', 8),
      vote('aurora', 'k', 6), // 7.0 exactly: approved
      vote('cielo', 'f', 5),
      vote('cielo', 'k', 6), // 5.5: discarded but worth improving
      vote('plasma', 'f', 3),
      vote('plasma', 'k', 4), // 3.5: total discard
      vote('olas', 'f', 9), // Katy hasn't voted: hidden
      vote('solo', 'k', 9), // only one vote: not enough to decide
      vote('feo', 'f', 2),
      vote('feo', 'a', 3), // hidden from Katy, but already a total discard
    ]);
    final katy = TeamReviewController(
      client: client,
      store: _MemoryStore('clr_katy'),
    );
    await katy.start();
    const revision = 'abcdef1234567890';
    final ranking = TeamRanking.build(katy, const [
      TeamRankingEntry(id: 'aurora', name: 'Aurora', revision: revision),
      TeamRankingEntry(id: 'cielo', name: 'Cielo', revision: revision),
      TeamRankingEntry(id: 'plasma', name: 'Plasma', revision: revision),
      TeamRankingEntry(id: 'olas', name: 'Olas', revision: revision),
      TeamRankingEntry(id: 'nuevo', name: 'Nuevo', revision: revision),
      TeamRankingEntry(id: 'solo', name: 'Solo', revision: revision),
      TeamRankingEntry(id: 'feo', name: 'Feo', revision: revision),
    ]);

    expect(ranking.voters, ['Franco', 'Katy']);
    expect(ranking.rows.map((row) => row.verdict), [
      TeamVerdict.approved,
      TeamVerdict.improvable,
      TeamVerdict.discarded,
      TeamVerdict.locked,
      TeamVerdict.noVotes,
      TeamVerdict.needsVotes,
      TeamVerdict.discarded,
    ]);
    expect(ranking.rows[6].scores, isEmpty, reason: 'scores stay hidden');
    expect(ranking.rows[0].average, 7.0);
    expect(ranking.rows[1].average, 5.5);
    expect(ranking.rows[2].average, 3.5);
    expect(ranking.rows[3].votes, 1);
    expect(ranking.rows[3].scores, isEmpty);
    expect(ranking.teamVotes, 10);
    expect(ranking.myVotes, 4);
    expect(ranking.overallAverage, closeTo(5.86, 0.01));
    expect(ranking.count(TeamVerdict.approved), 1);
    expect(ranking.count(TeamVerdict.improvable), 1);
    expect(ranking.count(TeamVerdict.discarded), 2);
    expect(ranking.count(TeamVerdict.needsVotes), 1);
  });

  testWidgets('ranking opens from the panel and a row opens that visual', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final client = _FakeClient();
    client.stored.add(
      TeamRating(
        visualId: 'mareas_test',
        revision: visualRevision(_tides),
        reviewerId: 'f',
        reviewerName: 'Franco',
        score: 7,
        comment: 'Me gusta el ritmo',
      ),
    );
    client.stored.add(
      TeamRating(
        visualId: 'mareas_test',
        revision: visualRevision(_tides),
        reviewerId: 'k',
        reviewerName: 'Katy',
        score: 7,
      ),
    );
    final review = TeamReviewController(
      client: client,
      store: _MemoryStore('clr_franco'),
    );
    final compositor = _Controller();
    await tester.pumpWidget(
      MaterialApp(
        home: CreatorStudio(
          catalogBuilder: () => [_aurora, _tides],
          controllerFactory: () => compositor,
          recordingsLoader: () async => [],
          thumbnailBuilder: (_, _) => const SizedBox(),
          teamReview: review,
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(compositor.visuals.last, 'aurora');

    await tester.ensureVisible(
      find.byKey(const ValueKey('team-rating-open-ranking')),
    );
    await tester.tap(find.byKey(const ValueKey('team-rating-open-ranking')));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(find.text('Ranking del equipo'), findsOneWidget);
    // Phone width: a list with name, state and average, no wide table.
    expect(find.byKey(const ValueKey('team-ranking-table')), findsNothing);
    final tile = find.byKey(const ValueKey('team-ranking-tile-mareas_test'));
    expect(
      find.descendant(of: tile, matching: find.text('Mareas')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: tile, matching: find.text('Aprobado')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: tile, matching: find.text('7.0')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: tile,
        matching: find.textContaining('2 votos · Franco 7 · Katy 7'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Mareas'));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Ranking del equipo'), findsNothing);
    expect(compositor.visuals.last, 'mareas_test');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('wide screens keep the full per-person table', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final client = _FakeClient();
    client.stored.add(
      TeamRating(
        visualId: 'aurora',
        revision: visualRevision(_aurora),
        reviewerId: 'f',
        reviewerName: 'Franco',
        score: 8,
        comment: 'Me gusta el ritmo',
      ),
    );
    final review = TeamReviewController(
      client: client,
      store: _MemoryStore('clr_franco'),
    );
    await review.start();
    await tester.pumpWidget(
      MaterialApp(
        home: TeamRankingScreen(
          controller: review,
          entries: [
            TeamRankingEntry(
              id: 'aurora',
              name: 'Aurora',
              revision: visualRevision(_aurora),
            ),
          ],
          onOpenVisual: (_) {},
        ),
      ),
    );
    await tester.pump();
    final table = find.byKey(const ValueKey('team-ranking-table'));
    expect(table, findsOneWidget);
    expect(
      find.descendant(of: table, matching: find.text('Franco')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: table, matching: find.textContaining('Me gusta')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
