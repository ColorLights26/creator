/// Reviewed equivalences between revisions of one visual.
///
/// Pure Dart: no Flutter, so the readiness tool and the studio share it.
library;

import 'dart:convert';

/// How far a link proposal got with the maintainer.
enum RevisionLinkStatus {
  /// Automatic evidence exists; nobody looked at the A/B yet. Carries no vote.
  proposed,

  /// The maintainer watched both revisions and confirmed they look and move
  /// the same. Only this status carries votes.
  reviewed,

  /// The maintainer saw a real difference: the new revision needs new votes.
  rejected,
}

/// Equivalence between two revisions of one visual: the drawing the team
/// voted on ([from]) and an optimized revision ([to]).
///
/// The revision is the vote fingerprint (`visual_revision.dart`): code,
/// materials, images, FPS, seed, controls, colors and modifiers. A link never
/// edits that fingerprint and never copies a vote: the studio only counts the
/// votes stored on [from] when it shows [to], and only while the link is
/// [RevisionLinkStatus.reviewed].
class RevisionLink {
  const RevisionLink({
    required this.visualId,
    required this.from,
    required this.to,
    required this.status,
    this.kind = '',
    this.summary = '',
    this.reviewer = '',
  });

  factory RevisionLink.fromJson(Map<String, Object?> json) {
    RevisionLinkStatus? status;
    for (final value in RevisionLinkStatus.values) {
      if (value.name == json['status']) status = value;
    }
    return RevisionLink(
      visualId: json['visualId'] as String? ?? '',
      from: json['from'] as String? ?? '',
      to: json['to'] as String? ?? '',
      // An unknown status never carries votes.
      status: status ?? RevisionLinkStatus.proposed,
      kind: json['kind'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      reviewer: json['reviewer'] as String? ?? '',
    );
  }

  final String visualId;
  final String from;
  final String to;
  final RevisionLinkStatus status;

  /// What the evidence showed (`fpsOnly`, `pixelParity`, ...). Informational.
  final String kind;
  final String summary;
  final String reviewer;

  bool get reviewed => status == RevisionLinkStatus.reviewed;
  bool get isValid =>
      visualId.isNotEmpty && from.isNotEmpty && to.isNotEmpty && from != to;
}

/// The links of the catalog, as the studio uses them.
class RevisionLinks {
  RevisionLinks(Iterable<RevisionLink> links) : _byVisual = {} {
    for (final link in links) {
      if (link.isValid) (_byVisual[link.visualId] ??= []).add(link);
    }
  }

  const RevisionLinks.none() : _byVisual = const {};

  /// Parses `readiness/revision_links.json`. A malformed file yields no
  /// links instead of breaking the studio: votes then stay per revision.
  factory RevisionLinks.parse(String json) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      return const RevisionLinks.none();
    }
    if (decoded is! Map<String, Object?> || decoded['schemaVersion'] != 1) {
      return const RevisionLinks.none();
    }
    final items = decoded['links'];
    if (items is! List) return const RevisionLinks.none();
    return RevisionLinks([
      for (final item in items)
        if (item is Map<String, Object?>) RevisionLink.fromJson(item),
    ]);
  }

  final Map<String, List<RevisionLink>> _byVisual;

  /// Longest chain of reviewed links followed; a cycle or a typo stops here.
  static const maximumDepth = 8;

  bool get isEmpty => _byVisual.isEmpty;

  int get reviewedCount {
    var count = 0;
    for (final links in _byVisual.values) {
      count += links.where((link) => link.reviewed).length;
    }
    return count;
  }

  List<RevisionLink> linksFor(String visualId) =>
      List.unmodifiable(_byVisual[visualId] ?? const []);

  /// Revisions whose votes count for [visualId]@[revision]: the revision
  /// itself first, then every reviewed predecessor, nearest first.
  ///
  /// Only `to == revision` links are followed, so a vote never flows
  /// forward into an unreviewed drawing, and a rejected or proposed link is
  /// ignored exactly like a missing one.
  List<String> equivalents(String visualId, String revision) {
    final result = [revision];
    final links = _byVisual[revision.isEmpty ? '' : visualId];
    if (links == null) return result;
    var frontier = [revision];
    for (var depth = 0; depth < maximumDepth && frontier.isNotEmpty; depth++) {
      final next = <String>[];
      for (final link in links) {
        if (!link.reviewed || !frontier.contains(link.to)) continue;
        if (result.contains(link.from)) continue;
        result.add(link.from);
        next.add(link.from);
      }
      frontier = next;
    }
    return result;
  }

  /// Whether [visualId]@[revision] counts votes from an earlier revision.
  bool inherits(String visualId, String revision) =>
      equivalents(visualId, revision).length > 1;
}
