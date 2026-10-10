import 'team_ranking.dart';
import 'team_review_controller.dart';

/// Which visuals the studio shows, by how the vote is going for you.
///
/// The verdict filters only include visuals you already voted: before
/// voting nobody sees the team's opinion, not even through a filter.
enum TeamVoteFilter {
  all('En evaluación'),
  toVote('Por votar'),
  voted('Ya votados'),
  approved('Aprobados'),
  improvable('Con potencial'),
  discarded('Descartados'),
  waiting('Esperando votos'),
  accepted('Ya aceptados');

  const TeamVoteFilter(this.label);

  final String label;

  bool matches(TeamReviewController controller, TeamRankingEntry entry) {
    final voted = controller.hasVoted(entry.id, entry.revision);
    if (this == all) return true;
    // Like the voting queue: what the team already discarded isn't asked.
    if (this == toVote) {
      return !voted && !controller.isTeamDiscarded(entry.id, entry.revision);
    }
    if (!voted) return false;
    if (this == TeamVoteFilter.voted) return true;
    final verdict = TeamRankingRow.of(controller, entry).verdict;
    return switch (this) {
      approved => verdict == TeamVerdict.approved,
      improvable => verdict == TeamVerdict.improvable,
      discarded => verdict == TeamVerdict.discarded,
      waiting => verdict == TeamVerdict.needsVotes,
      _ => false,
    };
  }
}
