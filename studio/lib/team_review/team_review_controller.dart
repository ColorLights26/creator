import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'team_ranking.dart';
import 'team_review_client.dart';

/// Where the reviewer's personal key lives on this device.
abstract interface class ReviewerKeyStore {
  Future<String?> read();
  Future<void> write(String? key);
}

class PreferencesReviewerKeyStore implements ReviewerKeyStore {
  static const _key = 'creator_team_review_key_v1';

  @override
  Future<String?> read() async =>
      (await SharedPreferences.getInstance()).getString(_key);

  @override
  Future<void> write(String? key) async {
    final preferences = await SharedPreferences.getInstance();
    if (key == null) {
      await preferences.remove(_key);
    } else {
      await preferences.setString(_key, key);
    }
  }
}

/// Team 1-10 ratings for the studio: who is voting, what they may see and
/// which visual revisions still need their vote.
class TeamReviewController extends ChangeNotifier {
  TeamReviewController({
    required this.client,
    required this.store,
    this.liveInterval,
  });

  final TeamReviewClient client;
  final ReviewerKeyStore store;

  /// How often to look for the team's new votes while the studio is open.
  /// Null disables live updates (tests).
  final Duration? liveInterval;

  String? _key;
  TeamReviewer? _reviewer;
  Map<String, List<TeamRating>> _visible = {};
  Map<String, int> _hidden = {};
  Set<String> _hiddenDiscarded = {};
  final Set<String> _saving = {};
  bool _started = false;
  bool _loading = false;
  bool _disposed = false;
  bool _active = true;
  String? _version;
  Timer? _liveTimer;
  String? _error;

  TeamReviewer? get reviewer => _reviewer;
  bool get signedIn => _reviewer != null;
  bool get loading => _loading;
  String? get error => _error;

  bool isSaving(String visualId, String revision) =>
      _saving.contains(ratingKey(visualId, revision));

  TeamRating? myRating(String visualId, String revision) {
    final id = _reviewer?.id;
    if (id == null) return null;
    for (final rating in ratingsFor(visualId, revision)) {
      if (rating.reviewerId == id) return rating;
    }
    return null;
  }

  bool hasVoted(String visualId, String revision) =>
      myRating(visualId, revision) != null;

  /// Every visible rating for the revision, including the reviewer's own.
  List<TeamRating> ratingsFor(String visualId, String revision) =>
      _visible[ratingKey(visualId, revision)] ?? const [];

  int hiddenCount(String visualId, String revision) =>
      _hidden[ratingKey(visualId, revision)] ?? 0;

  /// The team already left this revision as "Descarte total": enough votes
  /// and an average below [teamPotentialThreshold].
  bool isTeamDiscarded(String visualId, String revision) {
    if (_hiddenDiscarded.contains(ratingKey(visualId, revision))) return true;
    final ratings = ratingsFor(visualId, revision);
    if (ratings.length < teamMinimumVotes) return false;
    final average =
        ratings.fold<int>(0, (sum, rating) => sum + rating.score) /
        ratings.length;
    return average < teamPotentialThreshold;
  }

  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      _key = await store.read();
    } on Object catch (error, stack) {
      _log('Could not read the reviewer key', error, stack);
    }
    if (_key != null) await refresh();
  }

  /// Fetches the team's votes. A [quiet] refresh is the live poll: it asks
  /// only for changes since the last version and repaints only if any.
  Future<void> refresh({bool quiet = false}) async {
    final key = _key;
    if (key == null || _disposed) return;
    if (quiet && (_loading || _saving.isNotEmpty)) return;
    _loading = true;
    if (!quiet) _notify();
    try {
      final snapshot = await client.ratings(
        key,
        since: quiet ? _version : null,
      );
      if (snapshot != null && _saving.isEmpty) {
        _apply(snapshot);
        _error = null;
        if (quiet) _notify();
      }
      if (!quiet) _error = null;
    } on TeamReviewException catch (error) {
      if (error.unauthorized) {
        await _forget();
      }
      if (!quiet || error.unauthorized) {
        _error = error.message;
        if (quiet) _notify();
      }
    } finally {
      _loading = false;
      if (!quiet) _notify();
      _scheduleLive();
    }
  }

  /// The studio went to the background (false) or came back (true).
  void setActive(bool active) {
    if (_active == active) return;
    _active = active;
    if (active) {
      unawaited(refresh(quiet: true));
    } else {
      _liveTimer?.cancel();
      _liveTimer = null;
    }
  }

  void _scheduleLive() {
    final interval = liveInterval;
    if (interval == null || _disposed || !_active || _key == null) return;
    if (_liveTimer?.isActive ?? false) return;
    _liveTimer = Timer(interval, () {
      _liveTimer = null;
      unawaited(refresh(quiet: true));
    });
  }

  /// Returns an error message, or null when the key was accepted.
  Future<String?> signIn(String rawKey) async {
    final key = rawKey.trim();
    if (!key.startsWith('clr_')) {
      return 'La clave empieza con «clr_». Cópiala completa desde Chic Team.';
    }
    try {
      final reviewer = await client.me(key);
      await store.write(key);
      _reviewer = reviewer;
      _key = key;
    } on TeamReviewException catch (error) {
      return error.message;
    } on Object catch (error, stack) {
      _log('Could not save the reviewer key', error, stack);
      return 'No se pudo guardar la clave en este dispositivo.';
    }
    _error = null;
    _notify();
    await refresh();
    return null;
  }

  Future<void> signOut() async {
    await _forget();
    _error = null;
    _notify();
  }

  /// Saves the vote immediately; the team's scores for this revision become
  /// visible once the server has it. [change] replaces a confirmed vote.
  /// Returns an error message or null.
  Future<String?> rate({
    required String visualId,
    required String visualName,
    required String revision,
    required int score,
    String? comment,
    bool change = false,
  }) async {
    final key = _key;
    final reviewer = _reviewer;
    if (key == null || reviewer == null) return 'Primero pega tu clave.';
    final slot = ratingKey(visualId, revision);
    final previous = List<TeamRating>.of(_visible[slot] ?? const []);
    final mine = TeamRating(
      visualId: visualId,
      revision: revision,
      reviewerId: reviewer.id,
      reviewerName: reviewer.name,
      score: score,
      comment: comment ?? myRating(visualId, revision)?.comment ?? '',
    );
    _visible = {
      ..._visible,
      slot: [
        for (final rating in previous)
          if (rating.reviewerId != reviewer.id) rating,
        mine,
      ],
    };
    _saving.add(slot);
    _notify();
    try {
      await client.rate(
        key,
        visualId: visualId,
        visualName: visualName,
        revision: revision,
        score: score,
        comment: comment,
        change: change,
      );
      _saving.remove(slot);
      _error = null;
      // Voting lifts the blind: fetch the team's scores for this revision.
      await refresh();
      return null;
    } on TeamReviewException catch (error) {
      _saving.remove(slot);
      _visible = {..._visible, slot: previous};
      if (error.unauthorized) await _forget();
      _error = error.message;
      _notify();
      return error.message;
    }
  }

  void _apply(TeamRatingsSnapshot snapshot) {
    _reviewer = snapshot.reviewer;
    _version = snapshot.version;
    final visible = <String, List<TeamRating>>{};
    for (final rating in snapshot.ratings) {
      (visible[ratingKey(rating.visualId, rating.revision)] ??= []).add(rating);
    }
    _visible = visible;
    _hidden = snapshot.hiddenCounts;
    _hiddenDiscarded = snapshot.hiddenDiscarded;
  }

  Future<void> _forget() async {
    _key = null;
    _reviewer = null;
    _visible = {};
    _hidden = {};
    _hiddenDiscarded = {};
    _version = null;
    _liveTimer?.cancel();
    _liveTimer = null;
    try {
      await store.write(null);
    } on Object catch (error, stack) {
      _log('Could not remove the reviewer key', error, stack);
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _log(String message, Object error, StackTrace stack) {
    developer.log(
      message,
      name: 'creator_team_review',
      error: error,
      stackTrace: stack,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _liveTimer?.cancel();
    super.dispose();
  }
}
