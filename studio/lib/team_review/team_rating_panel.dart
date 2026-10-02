import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'team_review_client.dart';
import 'team_review_controller.dart';

const _accent = Color(0xFF73F572);
const _warning = Color(0xFFFFB74D);
const _danger = Color(0xFFFF8B80);

/// A visual the reviewer is expected to vote on, in catalog order.
typedef TeamRatingCandidate = ({String id, String revision});

/// "Tu nota" 1-10 for the selected visual, the team's scores once you have
/// voted, and a shortcut to the next visual still waiting for your vote.
///
/// Picking a number is only a choice until "Confirmar": the confirmed vote is
/// final, because confirming reveals the team's scores.
class TeamRatingPanel extends StatefulWidget {
  const TeamRatingPanel({
    required this.controller,
    required this.visualId,
    required this.visualName,
    required this.revision,
    required this.queue,
    required this.onSelectVisual,
    this.onOpenRanking,
    super.key,
  });

  final TeamReviewController controller;
  final String visualId;
  final String visualName;
  final String revision;
  final List<TeamRatingCandidate> queue;
  final ValueChanged<String> onSelectVisual;

  /// Opens the whole team table (every visual, every voter).
  final VoidCallback? onOpenRanking;

  @override
  State<TeamRatingPanel> createState() => _TeamRatingPanelState();
}

class _TeamRatingPanelState extends State<TeamRatingPanel> {
  /// The number picked but not yet confirmed (nothing sent, nothing seen).
  int? _pending;
  bool _confirming = false;

  TeamReviewController get controller => widget.controller;
  String get visualId => widget.visualId;
  String get visualName => widget.visualName;
  String get revision => widget.revision;
  List<TeamRatingCandidate> get queue => widget.queue;
  ValueChanged<String> get onSelectVisual => widget.onSelectVisual;
  VoidCallback? get onOpenRanking => widget.onOpenRanking;

  @override
  void didUpdateWidget(TeamRatingPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visualId != visualId || oldWidget.revision != revision) {
      _pending = null;
    }
  }

  Future<void> _confirm() async {
    final score = _pending;
    if (score == null || _confirming) return;
    setState(() => _confirming = true);
    final error = await controller.rate(
      visualId: visualId,
      visualName: visualName,
      revision: revision,
      score: score,
    );
    if (!mounted) return;
    setState(() {
      _confirming = false;
      if (error == null) _pending = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder:
          (context, _) => Container(
            key: const ValueKey('team-rating-panel'),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            ),
            child:
                controller.signedIn
                    ? _buildVoting(context)
                    : _buildSignedOut(context),
          ),
    );
  }

  Widget _buildSignedOut(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.groups_rounded, size: 18, color: Colors.white70),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            controller.error ?? 'Vota del 1 al 10 con el equipo',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: controller.error == null ? Colors.white70 : _danger,
            ),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          key: const ValueKey('team-rating-sign-in'),
          onPressed:
              controller.loading ? null : () => unawaited(_showSignIn(context)),
          style: FilledButton.styleFrom(
            backgroundColor: _accent,
            foregroundColor: Colors.black,
            visualDensity: VisualDensity.compact,
          ),
          child: const Text(
            'Votar',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }

  Widget _buildVoting(BuildContext context) {
    final mine = controller.myRating(visualId, revision);
    final saving = controller.isSaving(visualId, revision);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      mine == null ? 'TU NOTA' : 'TU VOTO · DEFINITIVO',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                  if (saving) ...[
                    const SizedBox(width: 8),
                    const SizedBox.square(
                      dimension: 10,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: _accent,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            _buildNextButton(),
            _buildReviewerMenu(context),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (var score = 1; score <= 10; score++) ...[
              if (score > 1) const SizedBox(width: 4),
              Expanded(
                child: _scoreButton(
                  score,
                  selected:
                      mine?.score == score ||
                      (mine == null && _pending == score),
                  locked: mine != null,
                ),
              ),
            ],
          ],
        ),
        if (mine == null) ...[
          const SizedBox(height: 8),
          if (_pending == null)
            Text(
              'Antes de votar, pruébalo con varias pistas y en silencio.',
              style: TextStyle(
                fontSize: 11.5,
                color: _warning.withValues(alpha: 0.9),
                fontWeight: FontWeight.w600,
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Al confirmar ya no se puede cambiar y verás las notas '
                    'del equipo.',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const ValueKey('team-rating-confirm'),
                  onPressed: _confirming ? null : () => unawaited(_confirm()),
                  style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.black,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(
                    _confirming ? 'Guardando…' : 'Confirmar $_pending',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _buildTeamLine(mine)),
            IconButton(
              key: const ValueKey('team-rating-comment'),
              tooltip:
                  mine == null ? 'Vota primero para comentar' : 'Comentarios',
              onPressed:
                  mine == null
                      ? null
                      : () => unawaited(_showComments(context, mine)),
              visualDensity: VisualDensity.compact,
              icon: Icon(
                mine?.comment.isNotEmpty ?? false
                    ? Icons.chat_bubble_rounded
                    : Icons.chat_bubble_outline_rounded,
                size: 18,
                color: mine == null ? Colors.white24 : Colors.white70,
              ),
            ),
            if (onOpenRanking case final VoidCallback open)
              IconButton(
                key: const ValueKey('team-rating-open-ranking'),
                tooltip: 'Ranking del equipo',
                onPressed: open,
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  Icons.leaderboard_rounded,
                  size: 20,
                  color: _accent,
                ),
              ),
          ],
        ),
        if (controller.error case final String error)
          Text(error, style: const TextStyle(fontSize: 11, color: _danger)),
      ],
    );
  }

  Widget _scoreButton(
    int score, {
    required bool selected,
    required bool locked,
  }) {
    return Semantics(
      button: !locked,
      selected: selected,
      label: 'Nota $score',
      child: Material(
        color:
            selected
                ? _accent
                : Colors.white.withValues(alpha: locked ? 0.04 : 0.1),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          key: ValueKey('team-rating-score-$score'),
          borderRadius: BorderRadius.circular(10),
          // A confirmed vote is final: the numbers no longer react.
          onTap:
              locked
                  ? null
                  : () {
                    unawaited(HapticFeedback.selectionClick());
                    setState(() => _pending = score);
                  },
          child: SizedBox(
            height: 36,
            child: Center(
              child: Text(
                '$score',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color:
                      selected
                          ? Colors.black
                          : locked
                          ? Colors.white30
                          : Colors.white,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTeamLine(TeamRating? mine) {
    const style = TextStyle(fontSize: 12, color: Colors.white70, height: 1.3);
    if (mine == null) {
      final hidden = controller.hiddenCount(visualId, revision);
      return Text(
        hidden == 0
            ? 'Nadie ha votado esta versión todavía.'
            : '$hidden ${hidden == 1 ? 'voto' : 'votos'} del equipo · '
                'se ven cuando votes',
        style: style,
      );
    }
    final ratings = controller.ratingsFor(visualId, revision);
    final average =
        ratings.fold<int>(0, (sum, rating) => sum + rating.score) /
        ratings.length;
    final others = [
      for (final rating in ratings)
        if (rating.reviewerId != mine.reviewerId) rating,
    ];
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          TextSpan(
            text: 'Equipo ${_formatScore(average)}',
            style: const TextStyle(fontWeight: FontWeight.w800, color: _accent),
          ),
          TextSpan(
            text:
                others.isEmpty
                    ? ' · sólo tu voto por ahora'
                    : others
                        .map(
                          (rating) =>
                              ' · ${rating.reviewerName} ${rating.score}',
                        )
                        .join(),
          ),
        ],
      ),
    );
  }

  Widget _buildNextButton() {
    final unrated = [
      for (final candidate in queue)
        if (!controller.hasVoted(candidate.id, candidate.revision)) candidate,
    ];
    final others = unrated.where((candidate) => candidate.id != visualId);
    if (others.isEmpty) {
      return Text(
        unrated.isEmpty ? '✓ Todo votado' : 'Último por votar',
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: _accent,
        ),
      );
    }
    final current = queue.indexWhere((candidate) => candidate.id == visualId);
    final next = others.firstWhere(
      (candidate) => queue.indexOf(candidate) > current,
      orElse: () => others.first,
    );
    return TextButton.icon(
      key: const ValueKey('team-rating-next'),
      onPressed: () => onSelectVisual(next.id),
      style: TextButton.styleFrom(
        foregroundColor: _warning,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      icon: const Icon(Icons.skip_next_rounded, size: 18),
      label: Text(
        'Faltan ${unrated.length}',
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _buildReviewerMenu(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: controller.reviewer?.name ?? '',
      color: const Color(0xFF162521),
      onSelected: (value) {
        if (value == 'refresh') unawaited(controller.refresh());
        if (value == 'sign-out') unawaited(controller.signOut());
      },
      itemBuilder:
          (context) => [
            PopupMenuItem(
              enabled: false,
              child: Text(
                'Votas como ${controller.reviewer?.name ?? ''}',
                style: const TextStyle(color: Colors.white70),
              ),
            ),
            const PopupMenuItem(
              value: 'refresh',
              child: Text('Actualizar votos'),
            ),
            const PopupMenuItem(
              value: 'sign-out',
              child: Text('Cambiar de clave'),
            ),
          ],
      child: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: CircleAvatar(
          radius: 12,
          backgroundColor: Colors.white12,
          child: Text(
            _initial(controller.reviewer?.name),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showSignIn(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _SignInDialog(controller: controller),
    );
  }

  Future<void> _showComments(BuildContext context, TeamRating mine) async {
    final others = [
      for (final rating in controller.ratingsFor(visualId, revision))
        if (rating.reviewerId != mine.reviewerId && rating.comment.isNotEmpty)
          rating,
    ];
    await showDialog<void>(
      context: context,
      builder:
          (context) => _CommentDialog(
            controller: controller,
            visualId: visualId,
            visualName: visualName,
            revision: revision,
            mine: mine,
            others: others,
          ),
    );
  }
}

class _SignInDialog extends StatefulWidget {
  const _SignInDialog({required this.controller});

  final TeamReviewController controller;

  @override
  State<_SignInDialog> createState() => _SignInDialogState();
}

class _SignInDialogState extends State<_SignInDialog> {
  final _field = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await widget.controller.signIn(_field.text);
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Votación del equipo'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Pega la clave personal que te dieron desde Chic Team. '
            'Se guarda en este dispositivo y sólo hay que hacerlo una vez.',
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('team-rating-key-field'),
            controller: _field,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              hintText: 'clr_…',
              errorText: _error,
              errorMaxLines: 3,
            ),
            onSubmitted: (_) => unawaited(_submit()),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const ValueKey('team-rating-key-submit'),
          onPressed: _busy ? null : () => unawaited(_submit()),
          child: Text(_busy ? 'Comprobando…' : 'Entrar'),
        ),
      ],
    );
  }
}

class _CommentDialog extends StatefulWidget {
  const _CommentDialog({
    required this.controller,
    required this.visualId,
    required this.visualName,
    required this.revision,
    required this.mine,
    required this.others,
  });

  final TeamReviewController controller;
  final String visualId;
  final String visualName;
  final String revision;
  final TeamRating mine;
  final List<TeamRating> others;

  @override
  State<_CommentDialog> createState() => _CommentDialogState();
}

class _CommentDialogState extends State<_CommentDialog> {
  late final _field = TextEditingController(text: widget.mine.comment);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await widget.controller.rate(
      visualId: widget.visualId,
      visualName: widget.visualName,
      revision: widget.revision,
      score: widget.mine.score,
      comment: _field.text.trim(),
    );
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.visualName),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final rating in widget.others) ...[
              Text(
                '${rating.reviewerName} · ${rating.score}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              Text(rating.comment),
              const SizedBox(height: 10),
            ],
            TextField(
              key: const ValueKey('team-rating-comment-field'),
              controller: _field,
              maxLength: 500,
              minLines: 2,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: 'Tu comentario (nota ${widget.mine.score})',
                hintText: 'Qué cambiarías o qué te gustó',
                errorText: _error,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
        FilledButton(
          key: const ValueKey('team-rating-comment-save'),
          onPressed: _busy ? null : () => unawaited(_save()),
          child: Text(_busy ? 'Guardando…' : 'Guardar'),
        ),
      ],
    );
  }
}

String _formatScore(double value) =>
    value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);

String _initial(String? name) {
  final trimmed = name?.trim() ?? '';
  return trimmed.isEmpty ? '?' : trimmed.characters.first.toUpperCase();
}
