import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'storage_service.dart';
import 'vpn_service.dart';

/// One protected period: from a connected tunnel until it closed.
class ConnectionSession {
  final String configId;
  final String routeName;
  final DateTime start;
  DateTime end;
  int downloadBytes;
  int uploadBytes;
  bool open;

  ConnectionSession({
    required this.configId,
    required this.routeName,
    required this.start,
    required this.end,
    this.downloadBytes = 0,
    this.uploadBytes = 0,
    this.open = false,
  });

  Duration get duration => end.difference(start);

  Map<String, dynamic> toJson() => <String, dynamic>{
    'configId': configId,
    'routeName': routeName,
    'start': start.toUtc().toIso8601String(),
    'end': end.toUtc().toIso8601String(),
    'down': downloadBytes,
    'up': uploadBytes,
    'open': open,
  };

  static ConnectionSession? fromJson(Map<dynamic, dynamic> json) {
    final start = DateTime.tryParse(json['start']?.toString() ?? '');
    final end = DateTime.tryParse(json['end']?.toString() ?? '');
    if (start == null || end == null) return null;
    return ConnectionSession(
      configId: json['configId']?.toString() ?? '',
      routeName: json['routeName']?.toString() ?? '',
      start: start.toLocal(),
      end: end.toLocal(),
      downloadBytes: (json['down'] as num?)?.toInt() ?? 0,
      uploadBytes: (json['up'] as num?)?.toInt() ?? 0,
      open: json['open'] == true,
    );
  }
}

/// Totals for one range of Insights.
class InsightsSummary {
  final Duration protected;
  final int downloadBytes;
  final int uploadBytes;
  final int sessions;

  const InsightsSummary({
    required this.protected,
    required this.downloadBytes,
    required this.uploadBytes,
    required this.sessions,
  });

  int get totalBytes => downloadBytes + uploadBytes;
}

/// Local record of protected sessions for Insights.
///
/// Stored only in the encrypted settings box, kept for 62 days, never sent
/// anywhere. Byte counts come from the engine's own traffic counters.
class SessionHistoryService extends ChangeNotifier {
  static final SessionHistoryService _instance =
      SessionHistoryService._internal();
  factory SessionHistoryService() => _instance;
  SessionHistoryService._internal();

  static const _storageKey = 'session_history_v1';
  static const _retention = Duration(days: 62);
  static const _maxSessions = 2000;
  static const _checkpointEvery = Duration(seconds: 60);

  final List<ConnectionSession> _sessions = <ConnectionSession>[];
  VpnService? _vpn;
  ConnectionSession? _current;
  DateTime _lastCheckpoint = DateTime.fromMillisecondsSinceEpoch(0);
  bool _isInitialized = false;

  List<ConnectionSession> get sessions => List.unmodifiable(_sessions);

  Future<void> initialize() async {
    if (_isInitialized) return;
    await StorageService.initialize();
    final stored = StorageService.getSetting<dynamic>(_storageKey);
    if (stored is List) {
      for (final item in stored.whereType<Map<dynamic, dynamic>>()) {
        final session = ConnectionSession.fromJson(item);
        if (session == null) continue;
        // A session still open from a previous run ended at its last
        // checkpoint (the app or device stopped meanwhile).
        session.open = false;
        _sessions.add(session);
      }
    }
    _prune(DateTime.now());
    _isInitialized = true;
    notifyListeners();
  }

  /// Starts following [vpn]'s state and traffic counters.
  void attach(VpnService vpn) {
    if (identical(_vpn, vpn)) return;
    _vpn?.removeListener(_onVpnChanged);
    _vpn?.statsListenable.removeListener(_onStats);
    _vpn = vpn;
    vpn.addListener(_onVpnChanged);
    vpn.statsListenable.addListener(_onStats);
    _onVpnChanged();
  }

  void _onVpnChanged() {
    final vpn = _vpn;
    if (vpn == null) return;
    final config = vpn.currentConfig;
    if (vpn.isConnected && config != null) {
      if (_current == null || _current!.configId != config.id) {
        _closeCurrent();
        final now = DateTime.now();
        _current = ConnectionSession(
          configId: config.id,
          routeName: config.name,
          start: now,
          end: now,
          open: true,
        );
        _sessions.add(_current!);
        unawaited(_persist());
        notifyListeners();
      }
    } else if (!vpn.isConnected && _current != null) {
      _closeCurrent();
    }
  }

  void _onStats() {
    final current = _current;
    final vpn = _vpn;
    if (current == null || vpn == null) return;
    final stats = vpn.stats;
    current.end = DateTime.now();
    current.downloadBytes = math.max(
      current.downloadBytes,
      stats.totalDownload,
    );
    current.uploadBytes = math.max(current.uploadBytes, stats.totalUpload);
    if (current.end.difference(_lastCheckpoint) >= _checkpointEvery) {
      _lastCheckpoint = current.end;
      unawaited(_persist());
      notifyListeners();
    }
  }

  void _closeCurrent() {
    final current = _current;
    if (current == null) return;
    current.end = DateTime.now();
    current.open = false;
    _current = null;
    // Ignore taps that never really carried traffic.
    if (current.duration < const Duration(seconds: 5)) {
      _sessions.remove(current);
    }
    unawaited(_persist());
    notifyListeners();
  }

  Future<void> clear() async {
    _sessions.clear();
    if (_current != null) _sessions.add(_current!);
    await _persist();
    notifyListeners();
  }

  void _prune(DateTime now) {
    final cutoff = now.subtract(_retention);
    _sessions.removeWhere((s) => s.end.isBefore(cutoff));
    if (_sessions.length > _maxSessions) {
      _sessions.removeRange(0, _sessions.length - _maxSessions);
    }
  }

  Future<void> _persist() async {
    _prune(DateTime.now());
    await StorageService.setSetting<dynamic>(
      _storageKey,
      _sessions.map((s) => s.toJson()).toList(),
    );
  }

  // ---------------------------------------------------------------------
  // Aggregations (pure, so they can be tested without storage).
  // ---------------------------------------------------------------------

  /// Sessions clipped to [from]..[to].
  static List<(DateTime, DateTime)> intervals(
    Iterable<ConnectionSession> sessions,
    DateTime from,
    DateTime to,
  ) {
    final result = <(DateTime, DateTime)>[];
    for (final session in sessions) {
      final start = session.start.isBefore(from) ? from : session.start;
      final end = session.end.isAfter(to) ? to : session.end;
      if (end.isAfter(start)) result.add((start, end));
    }
    return result;
  }

  static InsightsSummary summarize(
    Iterable<ConnectionSession> sessions,
    DateTime from,
    DateTime to,
  ) {
    var protected = Duration.zero;
    var down = 0;
    var up = 0;
    var count = 0;
    for (final session in sessions) {
      final start = session.start.isBefore(from) ? from : session.start;
      final end = session.end.isAfter(to) ? to : session.end;
      if (!end.isAfter(start)) continue;
      count++;
      protected += end.difference(start);
      // Bytes are attributed in proportion to the part inside the range.
      final total = session.duration.inMilliseconds;
      final share = total <= 0
          ? 1.0
          : end.difference(start).inMilliseconds / total;
      down += (session.downloadBytes * share).round();
      up += (session.uploadBytes * share).round();
    }
    return InsightsSummary(
      protected: protected,
      downloadBytes: down,
      uploadBytes: up,
      sessions: count,
    );
  }

  /// Protected minutes per local day, oldest first, ending with [today].
  static List<double> minutesPerDay(
    Iterable<ConnectionSession> sessions,
    DateTime today,
    int days,
  ) {
    final firstDay = DateTime(today.year, today.month, today.day - days + 1);
    final values = List<double>.filled(days, 0);
    for (var i = 0; i < days; i++) {
      final from = DateTime(firstDay.year, firstDay.month, firstDay.day + i);
      final to = DateTime(from.year, from.month, from.day + 1);
      values[i] = summarize(sessions, from, to).protected.inSeconds / 60;
    }
    return values;
  }

  /// Download and upload bytes per local day, oldest first.
  static List<(int, int)> bytesPerDay(
    Iterable<ConnectionSession> sessions,
    DateTime today,
    int days,
  ) {
    final firstDay = DateTime(today.year, today.month, today.day - days + 1);
    return List.generate(days, (i) {
      final from = DateTime(firstDay.year, firstDay.month, firstDay.day + i);
      final to = DateTime(from.year, from.month, from.day + 1);
      final summary = summarize(sessions, from, to);
      return (summary.downloadBytes, summary.uploadBytes);
    });
  }

  /// Protected minutes by hour of day (0–23) within [from]..[to].
  static List<double> minutesByHour(
    Iterable<ConnectionSession> sessions,
    DateTime from,
    DateTime to,
  ) {
    final values = List<double>.filled(24, 0);
    for (final (start, end) in intervals(sessions, from, to)) {
      var cursor = start;
      while (cursor.isBefore(end)) {
        final nextHour = DateTime(
          cursor.year,
          cursor.month,
          cursor.day,
          cursor.hour + 1,
        );
        final sliceEnd = nextHour.isBefore(end) ? nextHour : end;
        values[cursor.hour] += sliceEnd.difference(cursor).inSeconds / 60;
        cursor = sliceEnd;
      }
    }
    return values;
  }
}
