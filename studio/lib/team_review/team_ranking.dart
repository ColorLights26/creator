import 'team_review_client.dart';
import 'team_review_controller.dart';

/// The team's verdict comes only from the average of the votes, with the
/// same three bands (and colors) as the old shared sheet.
const teamApprovalThreshold = 7.0;
const teamPotentialThreshold = 5.0;

/// A single vote never decides: below this the state is "Faltan votos".
/// The chic-ads server uses the same value to flag hidden total discards.
const teamMinimumVotes = 2;

enum TeamVerdict {
  /// Average >= [teamApprovalThreshold].
  approved,

  /// Average >= [teamPotentialThreshold]: discarded, but worth improving.
  improvable,

  /// Average below [teamPotentialThreshold].
  discarded,

  /// Some votes, but fewer than [teamMinimumVotes].
  needsVotes,

  /// Others voted but you didn't yet, so the average stays hidden.
  locked,
  noVotes,
}

/// One catalog visual as this studio sees it right now.
class TeamRankingEntry {
  const TeamRankingEntry({
    required this.id,
    required this.name,
    required this.revision,
    this.technical,
  });

  final String id;
  final String name;
  final String revision;

  /// Technical readiness label for this revision (Mac checks and device
  /// card), separate from the team's vote; null when the studio has none.
  final String? technical;
}

class TeamRankingRow {
  /// What [controller] lets this reviewer see about one visual.
  factory TeamRankingRow.of(
    TeamReviewController controller,
    TeamRankingEntry entry, {
    int number = 0,
  }) {
    final ratings = controller.ratingsFor(entry.id, entry.revision);
    // Exact votes on this revision the reviewer has not unlocked; and whether
    // anyone hidden voted here or on a reviewed equivalent (for the lock).
    final hiddenHere = controller.hiddenCount(entry.id, entry.revision);
    final hasHidden = controller.hasHiddenVotes(entry.id, entry.revision);
    final scores = {
      for (final rating in ratings) rating.reviewerName: rating.score,
    };
    // Votes ON this exact revision: own visible (a vote cast on this revision)
    // plus the ones still hidden here. Inherited votes live on another
    // revision and are reported apart as [inherited], so a person who voted
    // both an old and the new revision is never counted twice in one total.
    final ownVisible =
        ratings.where((rating) => rating.revision == entry.revision).length;
    return TeamRankingRow(
      number: number,
      entry: entry,
      scores: scores,
      votes: ownVisible + hiddenHere,
      hiddenHere: hiddenHere,
      // The unlocked average is partial while votes on THIS revision stay
      // hidden: shown as "media parcial", never as a complete average.
      incomplete: scores.isNotEmpty && hiddenHere > 0,
      // Someone who voted on this revision or on a reviewed equivalent sees
      // the team's scores; only a reviewer who never voted stays blind.
      locked: hasHidden && !controller.hasVoted(entry.id, entry.revision),
      inherited: controller.inheritedVoteCount(entry.id, entry.revision),
      average:
          scores.isEmpty
              ? null
              : scores.values.reduce((sum, score) => sum + score) /
                  scores.length,
      comments: [
        for (final rating in ratings)
          if (rating.comment.isNotEmpty) rating,
      ],
      discardedByTeam: controller.isTeamDiscarded(entry.id, entry.revision),
    );
  }

  const TeamRankingRow({
    required this.number,
    required this.entry,
    required this.scores,
    required this.votes,
    required this.locked,
    required this.average,
    required this.comments,
    this.discardedByTeam = false,
    this.inherited = 0,
    this.hiddenHere = 0,
    this.incomplete = false,
  });

  /// 1-based position in the catalog, like the N° column of the old sheet.
  final int number;
  final TeamRankingEntry entry;

  /// Visible scores by reviewer name.
  final Map<String, int> scores;

  /// Votes ON this exact revision: own visible plus [hiddenHere]. Inherited
  /// votes (cast on a reviewed-equivalent earlier revision) are not in here;
  /// they are counted in [inherited], so no person is double-counted.
  final int votes;

  /// Votes cast on THIS exact revision that the reviewer has not unlocked
  /// yet. Shown as "≥ N en esta versión" because a hidden voter may also be
  /// among the inherited visible votes; it is not added to [votes].
  final int hiddenHere;

  /// The visible average omits hidden votes on this revision: it is partial,
  /// never presented as the whole team's verdict.
  final bool incomplete;

  /// Others voted but you didn't yet: their scores stay hidden.
  final bool locked;

  /// Visible votes that were cast on an earlier revision reviewed as
  /// equivalent to this one. They keep their own revision and comments.
  final int inherited;

  /// Average of the visible scores; null when there are none.
  final double? average;
  final List<TeamRating> comments;

  /// The team already discarded it. Only used to keep it out of the voting
  /// queue: someone who hasn't voted never sees others' opinion, not even
  /// the verdict, so this does not change [verdict].
  final bool discardedByTeam;

  TeamVerdict get verdict {
    if (locked) return TeamVerdict.locked;
    final value = average;
    if (value == null) return TeamVerdict.noVotes;
    // A partial average (hidden votes on this revision) is never a settled
    // verdict: it still needs those votes before it can read approved or
    // discarded.
    if (incomplete) return TeamVerdict.needsVotes;
    if (scores.length < teamMinimumVotes) return TeamVerdict.needsVotes;
    if (value >= teamApprovalThreshold) return TeamVerdict.approved;
    if (value >= teamPotentialThreshold) return TeamVerdict.improvable;
    return TeamVerdict.discarded;
  }
}

/// The team table: one row per visual in the current catalog revision.
class TeamRanking {
  const TeamRanking({
    required this.rows,
    required this.voters,
    required this.teamVotes,
    required this.myVotes,
    required this.overallAverage,
  });

  factory TeamRanking.build(
    TeamReviewController controller,
    List<TeamRankingEntry> entries,
  ) {
    final voters = <String>{};
    final visibleScores = <int>[];
    var teamVotes = 0;
    var myVotes = 0;
    final rows = <TeamRankingRow>[];
    for (var index = 0; index < entries.length; index++) {
      final entry = entries[index];
      final row = TeamRankingRow.of(controller, entry, number: index + 1);
      voters.addAll(row.scores.keys);
      visibleScores.addAll(row.scores.values);
      teamVotes += row.votes;
      if (controller.hasVoted(entry.id, entry.revision)) myVotes++;
      rows.add(row);
    }
    return TeamRanking(
      rows: rows,
      voters: voters.toList()..sort(),
      teamVotes: teamVotes,
      myVotes: myVotes,
      overallAverage:
          visibleScores.isEmpty
              ? null
              : visibleScores.reduce((sum, score) => sum + score) /
                  visibleScores.length,
    );
  }

  final List<TeamRankingRow> rows;

  /// Column order: alphabetical, so everyone sees the same layout.
  final List<String> voters;
  final int teamVotes;
  final int myVotes;
  final double? overallAverage;

  int count(TeamVerdict verdict) =>
      rows.where((row) => row.verdict == verdict).length;
}
