import 'package:audiovisual_creator/team_review/revision_links.dart';
import 'package:audiovisual_creator/team_review/team_ranking.dart';
import 'package:audiovisual_creator/team_review/team_review_client.dart';
import 'package:audiovisual_creator/team_review/team_review_controller.dart';
import 'package:audiovisual_creator/team_review/team_vote_filter.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reviewed links carry votes to an optimized revision; proposed, rejected
/// or mismatched links do not. The blind rule, the hidden gesture and the
/// stored votes stay exactly as they are.
void main() {
  const old = 'rev-old', current = 'rev-new';
  RevisionLinks links(String status) => RevisionLinks.parse(
    '{"schemaVersion":1,"links":[{"visualId":"aurora","from":"$old",'
    '"to":"$current","status":"$status","kind":"fpsOnly"}]}',
  );

  group('RevisionLinks', () {
    test('only reviewed links add equivalents, nearest first', () {
      expect(links('reviewed').equivalents('aurora', current), [current, old]);
      expect(links('proposed').equivalents('aurora', current), [current]);
      expect(links('rejected').equivalents('aurora', current), [current]);
      expect(links('bogus').equivalents('aurora', current), [current]);
      expect(links('reviewed').inherits('aurora', current), isTrue);
    });

    test('a link never flows forward or to another visual', () {
      final reviewed = links('reviewed');
      expect(reviewed.equivalents('aurora', old), [old]);
      expect(reviewed.equivalents('plasma', current), [current]);
      expect(reviewed.equivalents('aurora', 'rev-other'), ['rev-other']);
    });

    test('chains follow reviewed links and stop at cycles', () {
      final chain = RevisionLinks([
        const RevisionLink(
          visualId: 'a',
          from: 'r1',
          to: 'r2',
          status: RevisionLinkStatus.reviewed,
        ),
        const RevisionLink(
          visualId: 'a',
          from: 'r2',
          to: 'r3',
          status: RevisionLinkStatus.reviewed,
        ),
        const RevisionLink(
          visualId: 'a',
          from: 'r3',
          to: 'r1',
          status: RevisionLinkStatus.reviewed,
        ),
        const RevisionLink(
          visualId: 'a',
          from: 'r0',
          to: 'r2',
          status: RevisionLinkStatus.proposed,
        ),
      ]);
      expect(chain.equivalents('a', 'r3'), ['r3', 'r2', 'r1']);
      expect(chain.reviewedCount, 3);
    });

    test('malformed files mean no links', () {
      expect(RevisionLinks.parse('nope').isEmpty, isTrue);
      expect(
        RevisionLinks.parse('{"schemaVersion":2,"links":[]}').isEmpty,
        isTrue,
      );
      expect(
        RevisionLinks.parse(
          '{"schemaVersion":1,"links":[{"visualId":"a","from":"x","to":"x","status":"reviewed"}]}',
        ).isEmpty,
        isTrue,
      );
    });
  });

  group('TeamReviewController with links', () {
    late _FakeClient client;
    late TeamReviewController franco;

    setUp(() async {
      client = _FakeClient();
      // The whole team voted the old revision; Katy also voted the new one.
      client.stored.addAll(const [
        TeamRating(
          visualId: 'aurora',
          revision: old,
          reviewerId: 'f',
          reviewerName: 'Franco',
          score: 8,
          comment: 'bien',
        ),
        TeamRating(
          visualId: 'aurora',
          revision: old,
          reviewerId: 'k',
          reviewerName: 'Katy',
          score: 6,
        ),
        TeamRating(
          visualId: 'aurora',
          revision: current,
          reviewerId: 'k',
          reviewerName: 'Katy',
          score: 9,
        ),
      ]);
      franco = TeamReviewController(
        client: client,
        store: _MemoryStore('clr_franco'),
      );
      await franco.start();
    });

    test('without a link, votes stay per revision', () {
      expect(franco.hasVoted('aurora', current), isFalse);
      expect(franco.ratingsFor('aurora', current), isEmpty);
      expect(franco.hiddenCount('aurora', current), 1);
      expect(franco.inheritedRating('aurora', current), isNull);
    });

    test('a reviewed link counts the old votes for the new revision', () {
      franco.links = links('reviewed');
      expect(franco.hasVoted('aurora', current), isTrue);
      final mine = franco.inheritedRating('aurora', current)!;
      expect(mine.score, 8);
      expect(mine.revision, old, reason: 'the vote keeps its own revision');
      expect(mine.comment, 'bien');
      final team = franco.ratingsFor('aurora', current);
      expect(team.map((r) => '${r.reviewerName}:${r.score}@${r.revision}'), [
        'Franco:8@$old',
        'Katy:6@$old',
      ]);
      expect(franco.inheritedVoteCount('aurora', current), 2);
      // Katy's vote on the new revision stays hidden for Franco until he
      // votes it: the server rule, honestly counted.
      expect(franco.hiddenCount('aurora', current), 1);
      final row = TeamRankingRow.of(
        franco,
        const TeamRankingEntry(id: 'aurora', name: 'Aurora', revision: current),
      );
      expect(row.locked, isFalse);
      expect(row.inherited, 2);
      // Votes ON this revision: 0 visible + 1 hidden (Katy's 9). The two
      // inherited votes are reported apart, never summed into this total.
      expect(row.votes, 1);
      expect(row.hiddenHere, 1);
      // The visible average (7) omits Katy's hidden 9: it is partial.
      expect(row.incomplete, isTrue);
      expect(row.average, 7);
      expect(
        TeamVoteFilter.toVote.matches(
          franco,
          const TeamRankingEntry(
            id: 'aurora',
            name: 'Aurora',
            revision: current,
          ),
        ),
        isFalse,
      );
    });

    test('proposed and rejected links are ignored', () {
      for (final status in ['proposed', 'rejected']) {
        franco.links = links(status);
        expect(franco.hasVoted('aurora', current), isFalse, reason: status);
        expect(franco.ratingsFor('aurora', current), isEmpty, reason: status);
      }
    });

    test('the newest vote of a person wins the union', () async {
      final katy = TeamReviewController(
        client: client,
        store: _MemoryStore('clr_katy'),
        links: links('reviewed'),
      );
      await katy.start();
      expect(katy.myRating('aurora', current)!.score, 9);
      expect(katy.inheritedRating('aurora', current), isNull);
      expect(katy.ratingsFor('aurora', current).map((r) => r.score), [9, 8]);
      expect(katy.inheritedVoteCount('aurora', current), 1);
    });

    test(
      'voting the new revision after inheriting is a first vote there',
      () async {
        franco.links = links('reviewed');
        final error = await franco.rate(
          visualId: 'aurora',
          visualName: 'Aurora',
          revision: current,
          score: 7,
          change: true,
        );
        expect(error, isNull);
        expect(
          client.rateCalls.single.change,
          isFalse,
          reason: 'no vote on this revision to replace',
        );
        expect(client.rateCalls.single.revision, current);
        expect(franco.myRating('aurora', current)!.score, 7);
        expect(franco.inheritedRating('aurora', current), isNull);
        expect(
          client.stored
              .where((r) => r.revision == old && r.reviewerId == 'f')
              .single
              .score,
          8,
          reason: 'the old vote is untouched',
        );
        // Replacing the vote on this revision keeps the hidden gesture.
        await franco.rate(
          visualId: 'aurora',
          visualName: 'Aurora',
          revision: current,
          score: 5,
          change: true,
        );
        expect(client.rateCalls.last.change, isTrue);
      },
    );

    test(
      'a total discard on the old revision keeps the new one out of the queue',
      () async {
        client.stored
          ..clear()
          ..addAll(const [
            TeamRating(
              visualId: 'aurora',
              revision: old,
              reviewerId: 'k',
              reviewerName: 'Katy',
              score: 2,
            ),
            TeamRating(
              visualId: 'aurora',
              revision: old,
              reviewerId: 'p',
              reviewerName: 'Pavel',
              score: 3,
            ),
          ]);
        franco.links = links('reviewed');
        await franco.refresh();
        expect(franco.hasVoted('aurora', current), isFalse);
        expect(franco.isTeamDiscarded('aurora', current), isTrue);
        expect(
          franco.ratingsFor('aurora', current),
          isEmpty,
          reason: 'blind: never saw their scores',
        );
      },
    );
  });
}

class _MemoryStore implements ReviewerKeyStore {
  _MemoryStore([this.key]);

  String? key;

  @override
  Future<String?> read() async => key;

  @override
  Future<void> write(String? key) async => this.key = key;
}

/// Server double with the same blind rule as chic-ads: a revision's scores
/// are visible only to who voted on that exact revision.
class _FakeClient implements TeamReviewClient {
  final reviewers = <String, TeamReviewer>{
    'clr_franco': const TeamReviewer(id: 'f', name: 'Franco'),
    'clr_katy': const TeamReviewer(id: 'k', name: 'Katy'),
  };
  final stored = <TeamRating>[];
  final rateCalls = <({String revision, int score, bool change})>[];
  int version = 0;

  TeamReviewer _auth(String key) =>
      reviewers[key] ??
      (throw const TeamReviewException('revoked', unauthorized: true));

  @override
  Future<TeamReviewer> me(String key) async => _auth(key);

  @override
  Future<TeamRatingsSnapshot?> ratings(String key, {String? since}) async {
    final reviewer = _auth(key);
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
    double average(String slot) {
      final scores = [
        for (final r in stored)
          if (ratingKey(r.visualId, r.revision) == slot) r.score,
      ];
      return scores.reduce((a, b) => a + b) / scores.length;
    }

    return TeamRatingsSnapshot(
      version: '${version++}',
      reviewer: reviewer,
      ratings: [
        for (final r in stored)
          if (voted.contains(ratingKey(r.visualId, r.revision))) r,
      ],
      hiddenCounts: hidden,
      hiddenDiscarded: {
        for (final slot in hidden.keys)
          if (hidden[slot]! >= teamMinimumVotes &&
              average(slot) < teamPotentialThreshold)
            slot,
      },
    );
  }

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
    final reviewer = _auth(key);
    rateCalls.add((revision: revision, score: score, change: change));
    final existing = stored.indexWhere(
      (r) =>
          r.visualId == visualId &&
          r.revision == revision &&
          r.reviewerId == reviewer.id,
    );
    if (existing >= 0 && !change) throw const TeamReviewException('vote-final');
    final rating = TeamRating(
      visualId: visualId,
      revision: revision,
      reviewerId: reviewer.id,
      reviewerName: reviewer.name,
      score: score,
      comment: comment ?? (existing >= 0 ? stored[existing].comment : ''),
    );
    if (existing >= 0) {
      stored[existing] = rating;
    } else {
      stored.add(rating);
    }
    return rating;
  }
}
