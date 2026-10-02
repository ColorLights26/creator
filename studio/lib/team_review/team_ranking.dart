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
  });

  final String id;
  final String name;
  final String revision;
}

class TeamRankingRow {
  /// What [controller] lets this reviewer see about one visual.
  factory TeamRankingRow.of(
    TeamReviewController controller,
    TeamRankingEntry entry, {
    int number = 0,
  }) {
    final ratings = controller.ratingsFor(entry.id, entry.revision);
    final hidden = controller.hiddenCount(entry.id, entry.revision);
    final scores = {
      for (final rating in ratings) rating.reviewerName: rating.score,
    };
    return TeamRankingRow(
      number: number,
      entry: entry,
      scores: scores,
      votes: ratings.length + hidden,
      locked: hidden > 0,
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
  });

  /// 1-based position in the catalog, like the N° column of the old sheet.
  final int number;
  final TeamRankingEntry entry;

  /// Visible scores by reviewer name.
  final Map<String, int> scores;

  /// Every vote on this revision, including the ones still hidden.
  final int votes;

  /// Others voted but you didn't yet: their scores stay hidden.
  final bool locked;

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
