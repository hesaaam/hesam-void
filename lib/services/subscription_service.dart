import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'subscription_parser.dart';

class SubscriptionFetchException implements Exception {
  final String message;
  const SubscriptionFetchException(this.message);

  @override
  String toString() => message;
}

/// Downloaded subscription content and the metadata providers send with it.
class SubscriptionResponse {
  final ParsedRoutes routes;
  final String? title;
  final SubscriptionUserInfo? userInfo;
  final int? updateIntervalHours;

  const SubscriptionResponse({
    required this.routes,
    this.title,
    this.userInfo,
    this.updateIntervalHours,
  });
}

/// Downloads subscription links. Requests go out over the device's current
/// route, so an active tunnel is used automatically when one is connected.
class SubscriptionService {
  const SubscriptionService._();

  static const Duration _timeout = Duration(seconds: 25);
  static const int _maxBytes = 8 * 1024 * 1024;

  /// Accepts http(s) links only; returns null for anything else.
  static Uri? parseUrl(String text) {
    final value = text.trim();
    if (value.contains(RegExp(r'\s'))) return null;
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasAuthority) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    return uri;
  }

  static Future<SubscriptionResponse> fetch(Uri uri) async {
    final client = http.Client();
    try {
      final request = http.Request('GET', uri)
        ..followRedirects = true
        ..maxRedirects = 5
        ..headers.addAll({'User-Agent': await _userAgent(), 'Accept': '*/*'});
      final response = await client.send(request).timeout(_timeout);
      if (response.statusCode != 200) {
        throw SubscriptionFetchException(_statusMessage(response.statusCode));
      }

      final bytes = <int>[];
      await for (final chunk in response.stream.timeout(_timeout)) {
        bytes.addAll(chunk);
        if (bytes.length > _maxBytes) {
          throw const SubscriptionFetchException(
            'The subscription is too large to import.',
          );
        }
      }

      final headers = response.headers;
      final body = utf8.decode(bytes, allowMalformed: true);
      return SubscriptionResponse(
        routes: SubscriptionParser.parse(body),
        title:
            SubscriptionParser.decodeProfileTitle(headers['profile-title']) ??
            SubscriptionParser.nameFromContentDisposition(
              headers['content-disposition'],
            ),
        userInfo: SubscriptionUserInfo.parse(headers['subscription-userinfo']),
        updateIntervalHours: SubscriptionParser.updateIntervalHours(
          headers['profile-update-interval'],
        ),
      );
    } on SubscriptionFetchException {
      rethrow;
    } on TimeoutException {
      throw const SubscriptionFetchException(
        'The subscription server did not respond in time.',
      );
    } on HandshakeException {
      throw const SubscriptionFetchException(
        'A secure connection to the subscription server failed.',
      );
    } on SocketException {
      throw const SubscriptionFetchException(
        'The subscription server could not be reached. If it is filtered '
        'on your network, connect first and update again.',
      );
    } on http.ClientException {
      throw const SubscriptionFetchException(
        'The subscription server could not be reached. If it is filtered '
        'on your network, connect first and update again.',
      );
    } finally {
      client.close();
    }
  }

  static String _statusMessage(int code) {
    if (code == 401 || code == 403) {
      return 'The subscription link was rejected. It may have expired.';
    }
    if (code == 404) return 'The subscription link no longer exists.';
    if (code >= 500) return 'The subscription server had an error ($code).';
    return 'The subscription server answered with code $code.';
  }

  static Future<String> _userAgent() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return 'HesamVoid/${info.version}';
    } catch (_) {
      return 'HesamVoid';
    }
  }
}
