import 'package:flutter/material.dart';

import 'team_ranking.dart';
import 'team_review_controller.dart';

const _accent = Color(0xFF73F572);
const _fair = Color(0xFFFFD27A);
const _poor = Color(0xFFFF8B80);

/// What the reviewer chose on the closing summary.
enum TeamSummaryAction { nextToVote, ranking, allVisuals, openVisual }

typedef TeamSummaryChoice = ({TeamSummaryAction action, String? visualId});

/// The end of a voting round, shown when "Siguiente" has nowhere left to go
/// or from "Todo votado": whether anything is left to vote, how the team's
/// verdicts stand and where to go next. Pops with a [TeamSummaryChoice].
class TeamVotingSummaryScreen extends StatelessWidget {
  const TeamVotingSummaryScreen({
    required this.controller,
    required this.entries,
    super.key,
  });

  final TeamReviewController controller;

  /// Every visual of the current catalog revision.
  final List<TeamRankingEntry> entries;

  void _choose(
    BuildContext context,
    TeamSummaryAction action, [
    String? visualId,
  ]) => Navigator.of(context).pop((action: action, visualId: visualId));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey('team-voting-summary'),
      appBar: AppBar(title: const Text('Resumen de la votación')),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final ranking = TeamRanking.build(controller, entries);
          // Same rule as the voting queue and the "Por votar" filter.
          final pending =
              ranking.rows
                  .where(
                    (row) =>
                        !controller.hasVoted(
                          row.entry.id,
                          row.entry.revision,
                        ) &&
                        !row.discardedByTeam,
                  )
                  .length;
          final skipped =
              ranking.rows
                  .where((row) => row.locked && row.discardedByTeam)
                  .length;
          final mine = [
            for (final entry in entries)
              if (controller.myRating(entry.id, entry.revision)
                  case final rating?)
                rating.score,
          ];
          final best =
              ranking.rows
                  .where((row) => row.verdict == TeamVerdict.approved)
                  .toList()
                ..sort((a, b) => b.average!.compareTo(a.average!));
          final done = pending == 0;
          final name = controller.reviewer?.name ?? '';
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              Icon(
                done ? Icons.verified_rounded : Icons.flag_rounded,
                size: 56,
                color: done ? _accent : _fair,
              ),
              const SizedBox(height: 12),
              Text(
                done ? '¡Votaste todo!' : 'No hay más en este filtro',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                done
                    ? 'Ya no quedan visuales por votar'
                        '${name.isEmpty ? '' : ', $name'}.'
                    : 'Te ${pending == 1 ? 'falta 1' : 'faltan $pending'} '
                        'por votar.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.white.withValues(alpha: 0.75),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  _stat('Tus votos', '${mine.length}'),
                  const SizedBox(width: 10),
                  _stat('Tu promedio', _average(mine)),
                  const SizedBox(width: 10),
                  _stat(
                    'Promedio del equipo',
                    ranking.overallAverage?.toStringAsFixed(1) ?? '—',
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _heading('CÓMO VA EL EQUIPO'),
              _verdict(
                'Aprobado',
                ranking.count(TeamVerdict.approved),
                _accent,
              ),
              _verdict(
                'Descarte pero tiene potencial al mejorar',
                ranking.count(TeamVerdict.improvable),
                _fair,
              ),
              _verdict(
                'Descarte total',
                ranking.count(TeamVerdict.discarded),
                _poor,
              ),
              _verdict(
                'Faltan votos de otros',
                ranking.count(TeamVerdict.needsVotes),
                Colors.white70,
              ),
              if (skipped > 0)
                _verdict('Ya descartados sin tu voto', skipped, Colors.white38),
              if (best.isNotEmpty) ...[
                const SizedBox(height: 20),
                _heading('LO MEJOR DEL EQUIPO'),
                for (final row in best.take(3))
                  ListTile(
                    key: ValueKey('team-summary-best-${row.entry.id}'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(
                      row.entry.name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    trailing: Text(
                      row.average!.toStringAsFixed(1),
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: _accent,
                        fontSize: 16,
                      ),
                    ),
                    onTap:
                        () => _choose(
                          context,
                          TeamSummaryAction.openVisual,
                          row.entry.id,
                        ),
                  ),
              ],
              const SizedBox(height: 24),
              if (!done) ...[
                FilledButton(
                  key: const ValueKey('team-summary-next'),
                  onPressed:
                      () => _choose(context, TeamSummaryAction.nextToVote),
                  style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.black,
                  ),
                  child: const Text(
                    'Ir al siguiente por votar',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              OutlinedButton.icon(
                key: const ValueKey('team-summary-ranking'),
                onPressed: () => _choose(context, TeamSummaryAction.ranking),
                icon: const Icon(Icons.leaderboard_rounded, color: _accent),
                label: const Text('Ver ranking del equipo'),
              ),
              const SizedBox(height: 10),
              TextButton(
                key: const ValueKey('team-summary-all'),
                onPressed: () => _choose(context, TeamSummaryAction.allVisuals),
                child: const Text('Ver todos los visuales'),
              ),
            ],
          );
        },
      ),
    );
  }

  static String _average(List<int> scores) =>
      scores.isEmpty
          ? '—'
          : (scores.reduce((sum, score) => sum + score) / scores.length)
              .toStringAsFixed(1);

  Widget _stat(String label, String value) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: const TextStyle(fontSize: 11.5, color: Colors.white60),
          ),
        ],
      ),
    ),
  );

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.8,
        color: Colors.white54,
      ),
    ),
  );

  Widget _verdict(String label, int count, Color color) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(label)),
        Text('$count', style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    ),
  );
}
