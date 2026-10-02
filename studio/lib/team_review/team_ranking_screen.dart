import 'dart:async';

import 'package:flutter/material.dart';

import 'team_ranking.dart';
import 'team_review_controller.dart';

const _headerColor = Color(0xFF1F4E79);
const _good = Color(0xFFB7E1CD);
const _fair = Color(0xFFFCE8B2);
const _poor = Color(0xFFF4C7C3);

/// The team's sheet inside Creator: every visual, each person's score,
/// votes, average and the owner's decision. Replaces the shared Excel.
class TeamRankingScreen extends StatefulWidget {
  const TeamRankingScreen({
    required this.controller,
    required this.entries,
    required this.onOpenVisual,
    super.key,
  });

  final TeamReviewController controller;
  final List<TeamRankingEntry> entries;

  /// Called with a visual id when a row is tapped.
  final ValueChanged<String> onOpenVisual;

  @override
  State<TeamRankingScreen> createState() => _TeamRankingScreenState();
}

class _TeamRankingScreenState extends State<TeamRankingScreen> {
  bool _byAverage = false;

  @override
  void initState() {
    super.initState();
    // After the first frame: refresh notifies listeners synchronously, and
    // the route is still being built here.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(widget.controller.refresh());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ranking del equipo'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed:
                widget.controller.loading
                    ? null
                    : () => unawaited(widget.controller.refresh()),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final ranking = TeamRanking.build(widget.controller, widget.entries);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Text(
                'Toca una fila para abrir ese visual. Las notas de los demás '
                'aparecen cuando votas ese visual.',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
              if (widget.controller.error case final String error) ...[
                const SizedBox(height: 8),
                Text(error, style: const TextStyle(color: Color(0xFFFF8B80))),
              ],
              const SizedBox(height: 12),
              _table(ranking),
              const SizedBox(height: 20),
              _summary(ranking),
            ],
          );
        },
      ),
    );
  }

  Widget _table(TeamRanking ranking) {
    final rows = List.of(ranking.rows);
    if (_byAverage) {
      rows.sort(
        (left, right) => (right.average ?? -1).compareTo(left.average ?? -1),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SingleChildScrollView(
        key: const ValueKey('team-ranking-table'),
        scrollDirection: Axis.horizontal,
        child: DataTable(
          showCheckboxColumn: false,
          sortColumnIndex: _byAverage ? ranking.voters.length + 3 : 0,
          sortAscending: !_byAverage,
          headingRowColor: const WidgetStatePropertyAll(_headerColor),
          headingTextStyle: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
          dataRowMinHeight: 52,
          dataRowMaxHeight: 60,
          columnSpacing: 20,
          border: TableBorder.symmetric(
            inside: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
          columns: [
            DataColumn(
              label: const Text('N°'),
              numeric: true,
              onSort: (_, _) => setState(() => _byAverage = false),
            ),
            const DataColumn(label: Text('Visual')),
            for (final voter in ranking.voters)
              DataColumn(label: Text(voter), numeric: true),
            const DataColumn(label: Text('N votos'), numeric: true),
            DataColumn(
              label: const Text('Promedio'),
              numeric: true,
              onSort: (_, _) => setState(() => _byAverage = true),
            ),
            const DataColumn(label: Text('Estado')),
            const DataColumn(label: Text('Comentarios')),
          ],
          rows: [
            for (final row in rows)
              DataRow(
                key: ValueKey('team-ranking-row-${row.entry.id}'),
                onSelectChanged: (_) => widget.onOpenVisual(row.entry.id),
                cells: [
                  DataCell(Text('${row.number}')),
                  DataCell(_visualCell(row)),
                  for (final voter in ranking.voters)
                    DataCell(_scoreCell(row, voter)),
                  DataCell(Text('${row.votes}')),
                  DataCell(_averageCell(row)),
                  DataCell(_verdictCell(row.verdict)),
                  DataCell(_commentsCell(row)),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _visualCell(TeamRankingRow row) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          row.entry.name,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        Text(
          row.entry.id,
          style: TextStyle(
            fontSize: 11,
            color: Colors.white.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }

  Widget _scoreCell(TeamRankingRow row, String voter) {
    final score = row.scores[voter];
    if (score != null) {
      return Text(
        '$score',
        style: const TextStyle(fontWeight: FontWeight.w800),
      );
    }
    return Text(
      row.locked ? '🔒' : '—',
      style: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
    );
  }

  Widget _averageCell(TeamRankingRow row) {
    final average = row.average;
    if (average == null) {
      return Text(
        row.locked ? 'Vota para ver' : '—',
        style: TextStyle(
          fontSize: 12,
          color: Colors.white.withValues(alpha: 0.45),
        ),
      );
    }
    return Container(
      width: 56,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color:
            average >= teamApprovalThreshold
                ? _good
                : average >= teamPotentialThreshold
                ? _fair
                : _poor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        average.toStringAsFixed(1),
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.black,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _verdictCell(TeamVerdict verdict) {
    final (label, color) = switch (verdict) {
      TeamVerdict.approved => ('Aprobado', const Color(0xFF73F572)),
      TeamVerdict.improvable => (
        'Descarte pero tiene potencial al mejorar',
        const Color(0xFFFFD27A),
      ),
      TeamVerdict.discarded => ('Descarte total', const Color(0xFFFF8B80)),
      TeamVerdict.locked => ('Vota para ver', Colors.white54),
      TeamVerdict.noVotes => ('Sin votos', Colors.white38),
    };
    return SizedBox(
      width: 170,
      child: Text(
        label,
        maxLines: 2,
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _commentsCell(TeamRankingRow row) {
    if (row.comments.isEmpty) {
      return Text(
        '—',
        style: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
      );
    }
    final first = row.comments.first;
    final more = row.comments.length - 1;
    return SizedBox(
      width: 240,
      child: Text(
        '${first.reviewerName}: ${first.comment}${more > 0 ? '  (+$more)' : ''}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12),
      ),
    );
  }

  Widget _summary(TeamRanking ranking) {
    final average = ranking.overallAverage;
    final items = [
      ('Votos del equipo', '${ranking.teamVotes}'),
      ('Tus votos', '${ranking.myVotes} de ${ranking.rows.length}'),
      ('Promedio general', average == null ? '—' : average.toStringAsFixed(1)),
      (
        'Aprobado (promedio ≥ ${teamApprovalThreshold.toStringAsFixed(0)})',
        '${ranking.count(TeamVerdict.approved)}',
      ),
      (
        'Descarte pero tiene potencial al mejorar '
            '(${teamPotentialThreshold.toStringAsFixed(0)} a '
            '${(teamApprovalThreshold - 0.1).toStringAsFixed(1)})',
        '${ranking.count(TeamVerdict.improvable)}',
      ),
      (
        'Descarte total (menos de '
            '${teamPotentialThreshold.toStringAsFixed(0)})',
        '${ranking.count(TeamVerdict.discarded)}',
      ),
      ('Te faltan por votar', '${ranking.count(TeamVerdict.locked)}'),
      ('Sin votos', '${ranking.count(TeamVerdict.noVotes)}'),
    ];
    return Container(
      key: const ValueKey('team-ranking-summary'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'RESUMEN',
            style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.8),
          ),
          const SizedBox(height: 8),
          for (final (label, value) in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(child: Text(label)),
                  Text(
                    value,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
