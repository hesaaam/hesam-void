import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Foreground time of one app while the tunnel was connected.
class AppUsageEntry {
  final String packageName;
  final String appName;
  final Duration time;
  final Uint8List? icon;

  const AppUsageEntry({
    required this.packageName,
    required this.appName,
    required this.time,
    this.icon,
  });
}

/// Reads Android's own app usage records for Insights.
///
/// Needs the "Usage access" permission, which the user grants in system
/// settings. Everything is computed on the device and nothing is stored or
/// sent: the app only asks Android how long each app was in the foreground
/// during the given protected intervals.
class AppUsageService {
  const AppUsageService._();

  static const MethodChannel _channel = MethodChannel('hesam_void/app_usage');

  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  static Future<bool> hasAccess() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('hasAccess') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openSettings() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('openSettings');
    } catch (_) {
      // Some devices do not expose the screen; nothing else to do.
    }
  }

  /// Foreground time per app inside [intervals], largest first.
  static Future<List<AppUsageEntry>> foregroundTime(
    List<(DateTime, DateTime)> intervals,
  ) async {
    if (!isSupported || intervals.isEmpty) return const [];
    final raw = await _channel.invokeMethod<List<dynamic>>('foregroundTime', {
      'intervals': [
        for (final (start, end) in intervals)
          [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
      ],
    });
    final entries = <AppUsageEntry>[];
    for (final item in raw ?? const []) {
      if (item is! Map) continue;
      final ms = (item['ms'] as num?)?.toInt() ?? 0;
      if (ms <= 0) continue;
      final icon = item['icon'];
      entries.add(
        AppUsageEntry(
          packageName: item['packageName']?.toString() ?? '',
          appName: item['appName']?.toString() ?? '',
          time: Duration(milliseconds: ms),
          icon: icon is Uint8List ? icon : null,
        ),
      );
    }
    entries.sort((a, b) => b.time.compareTo(a.time));
    return entries;
  }
}
