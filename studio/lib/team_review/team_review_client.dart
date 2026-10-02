import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Endpoint of the team ratings service (Chic Team, project chic-ads).
/// Override with `--dart-define=CREATOR_REVIEW_URL=...` to test locally.
const creatorReviewUrl = String.fromEnvironment(
  'CREATOR_REVIEW_URL',
  defaultValue: 'https://chic-ads.web.app/api/creator-review',
);

class TeamReviewer {
  const TeamReviewer({required this.id, required this.name});

  final String id;
  final String name;
}

class TeamRating {
  const TeamRating({
    required this.visualId,
    required this.revision,
    required this.reviewerId,
    required this.reviewerName,
    required this.score,
    this.comment = '',
  });

  factory TeamRating.fromJson(Map<String, Object?> json) => TeamRating(
    visualId: json['visualId'] as String? ?? '',
    revision: json['revision'] as String? ?? '',
    reviewerId: json['reviewerId'] as String? ?? '',
    reviewerName: json['reviewerName'] as String? ?? '',
    score: (json['score'] as num?)?.toInt() ?? 0,
    comment: json['comment'] as String? ?? '',
  );

  final String visualId;
  final String revision;
  final String reviewerId;
  final String reviewerName;
  final int score;
  final String comment;
}

/// Ratings the reviewer may see. Team scores of a revision stay hidden
/// (only counted) until the reviewer votes on it.
class TeamRatingsSnapshot {
  const TeamRatingsSnapshot({
    required this.reviewer,
    required this.ratings,
    required this.hiddenCounts,
  });

  final TeamReviewer reviewer;
  final List<TeamRating> ratings;

  /// Keyed by [ratingKey].
  final Map<String, int> hiddenCounts;
}

String ratingKey(String visualId, String revision) => '$visualId@$revision';

class TeamReviewException implements Exception {
  const TeamReviewException(this.message, {this.unauthorized = false});

  final String message;
  final bool unauthorized;

  @override
  String toString() => message;
}

abstract interface class TeamReviewClient {
  Future<TeamReviewer> me(String key);
  Future<TeamRatingsSnapshot> ratings(String key);
  Future<TeamRating> rate(
    String key, {
    required String visualId,
    required String visualName,
    required String revision,
    required int score,
    String? comment,
  });
}

class HttpTeamReviewClient implements TeamReviewClient {
  HttpTeamReviewClient({
    Uri? baseUri,
    this.timeout = const Duration(seconds: 12),
  }) : baseUri = baseUri ?? Uri.parse(creatorReviewUrl);

  final Uri baseUri;
  final Duration timeout;

  @override
  Future<TeamReviewer> me(String key) async {
    final json = await _send('GET', '/me', key);
    return _reviewer(json['reviewer']);
  }

  @override
  Future<TeamRatingsSnapshot> ratings(String key) async {
    final json = await _send('GET', '/ratings', key);
    return TeamRatingsSnapshot(
      reviewer: _reviewer(json['reviewer']),
      ratings: [
        for (final item in json['ratings'] as List<Object?>? ?? const [])
          if (item is Map<String, Object?>) TeamRating.fromJson(item),
      ],
      hiddenCounts: {
        for (final item in json['hidden'] as List<Object?>? ?? const [])
          if (item is Map<String, Object?>)
            ratingKey(
                  item['visualId'] as String? ?? '',
                  item['revision'] as String? ?? '',
                ):
                (item['count'] as num?)?.toInt() ?? 0,
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
  }) async {
    final json = await _send('POST', '/ratings', key, {
      'visualId': visualId,
      'visualName': visualName,
      'revision': revision,
      'score': score,
      if (comment != null) 'comment': comment,
    });
    final rating = json['rating'];
    if (rating is! Map<String, Object?>) {
      throw const TeamReviewException('Respuesta inválida del servidor.');
    }
    return TeamRating.fromJson(rating);
  }

  TeamReviewer _reviewer(Object? json) {
    if (json is! Map<String, Object?> ||
        json['id'] is! String ||
        json['name'] is! String) {
      throw const TeamReviewException('Respuesta inválida del servidor.');
    }
    return TeamReviewer(
      id: json['id']! as String,
      name: json['name']! as String,
    );
  }

  Future<Map<String, Object?>> _send(
    String method,
    String path,
    String key, [
    Map<String, Object?>? body,
  ]) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final uri = baseUri.replace(path: '${baseUri.path}$path');
      final request = await client.openUrl(method, uri).timeout(timeout);
      request.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer $key')
        ..set(HttpHeaders.acceptHeader, 'application/json');
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close().timeout(timeout);
      final text = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      final decoded = text.isEmpty ? null : jsonDecode(text);
      if (response.statusCode == HttpStatus.unauthorized) {
        throw const TeamReviewException(
          'La clave no es válida o fue revocada.',
          unauthorized: true,
        );
      }
      if (response.statusCode >= 400) {
        final message =
            decoded is Map<String, Object?>
                ? decoded['message'] as String?
                : null;
        throw TeamReviewException(
          message ?? 'El servidor respondió ${response.statusCode}.',
        );
      }
      if (decoded is! Map<String, Object?>) {
        throw const TeamReviewException('Respuesta inválida del servidor.');
      }
      return decoded;
    } on TimeoutException {
      throw const TeamReviewException(
        'El servidor no respondió. Revisa tu conexión.',
      );
    } on SocketException {
      throw const TeamReviewException(
        'No se pudo conectar con el servidor de votos. Tu nota no se guardó.',
      );
    } on HttpException catch (error) {
      throw TeamReviewException('Error de red: ${error.message}');
    } on FormatException {
      throw const TeamReviewException('Respuesta inválida del servidor.');
    } finally {
      client.close(force: true);
    }
  }
}
