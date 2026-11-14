import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/app_usage_service.dart';
import '../services/connection_health_service.dart';
import '../services/session_history_service.dart';
import '../utils/night_signal.dart';
import '../widgets/subscription_folder_card.dart' show formatDataSize;

enum InsightsRange { day, week, month }

/// Local history of protected time, data and the apps used meanwhile.
class InsightsTab extends StatefulWidget {
  final Color accent;
  final bool animate;

  const InsightsTab({super.key, required this.accent, this.animate = true});

  @override
  State<InsightsTab> createState() => _InsightsTabState();
}

class _InsightsTabState extends State<InsightsTab> with WidgetsBindingObserver {
  final SessionHistoryService _history = SessionHistoryService();
  InsightsRange _range = InsightsRange.week;
  bool? _usageAccess;
  Future<List<AppUsageEntry>>? _apps;
  String _appsKey = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _history.addListener(_onHistory);
    _checkAccess();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _history.removeListener(_onHistory);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The user may return from system settings with Usage access granted.
    if (state == AppLifecycleState.resumed) _checkAccess();
  }

  void _onHistory() {
    if (mounted) setState(() {});
  }

  Future<void> _checkAccess() async {
    final access = await AppUsageService.hasAccess();
    if (!mounted) return;
    setState(() {
      _usageAccess = access;
      _appsKey = '';
    });
  }

  (DateTime, DateTime) _window(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    switch (_range) {
      case InsightsRange.day:
        return (today, now);
      case InsightsRange.week:
        return (today.subtract(const Duration(days: 6)), now);
      case InsightsRange.month:
        return (today.subtract(const Duration(days: 29)), now);
    }
  }

  Future<List<AppUsageEntry>>? _appsFor(DateTime from, DateTime to) {
    if (_usageAccess != true) return null;
    final key = '${_range.name}-${_history.sessions.length}';
    if (key != _appsKey) {
      _appsKey = key;
      final intervals = SessionHistoryService.intervals(
        _history.sessions,
        from,
        to,
      );
      _apps = AppUsageService.foregroundTime(intervals);
    }
    return _apps;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final (from, to) = _window(now);
    final sessions = _history.sessions;
    final summary = SessionHistoryService.summarize(sessions, from, to);
    final drops = ConnectionHealthService().countEvents(
      ConnectionEventType.dropped,
      from,
      to,
    );
    final accent = widget.accent;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 120),
      children: [
        Text('Insights', style: NightSignal.title()),
        const SizedBox(height: 3),
        const Text(
          'Kept only on this phone',
          style: TextStyle(color: NightSignal.muted, fontSize: 12),
        ),
        const SizedBox(height: 14),
        _RangePicker(
          value: _range,
          onChanged: (range) => setState(() {
            _range = range;
            _appsKey = '';
          }),
        ),
        const SizedBox(height: 14),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Protected time',
                style: TextStyle(color: NightSignal.muted, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                _formatDuration(summary.protected),
                style: NightSignal.title(size: 36, color: accent),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _Metric(
                    value: formatDataSize(summary.totalBytes),
                    label: 'data used',
                  ),
                  _Metric(value: '${summary.sessions}', label: 'sessions'),
                  _Metric(value: '$drops', label: 'drops'),
                ],
              ),
              if (sessions.isEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'Connect once and your history starts here.',
                  style: TextStyle(color: NightSignal.soft, fontSize: 13),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Card(child: _appsSection(from, to)),
        const SizedBox(height: 12),
        _Card(
          child: _Calendar(
            minutes: SessionHistoryService.minutesPerDay(sessions, now, 35),
            today: now,
            accent: accent,
          ),
        ),
        const SizedBox(height: 12),
        _Card(
          child: _HourChart(
            minutes: SessionHistoryService.minutesByHour(sessions, from, to),
            accent: accent,
          ),
        ),
        const SizedBox(height: 12),
        _Card(
          child: _DataChart(
            days: SessionHistoryService.bytesPerDay(sessions, now, 7),
            today: now,
            accent: accent,
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton.icon(
            onPressed: sessions.isEmpty ? null : _confirmClear,
            icon: const Icon(Icons.delete_sweep_outlined, size: 18),
            label: const Text('Clear history'),
            style: TextButton.styleFrom(foregroundColor: NightSignal.muted),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        backgroundColor: NightSignal.surface,
        title: const Text(
          'Clear history?',
          style: TextStyle(color: NightSignal.text),
        ),
        content: const Text(
          'Protected sessions and data totals are removed from this phone.',
          style: TextStyle(color: NightSignal.soft),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog, true),
            style: TextButton.styleFrom(foregroundColor: NightSignal.danger),
            child: const Text('CLEAR'),
          ),
        ],
      ),
    );
    if (ok == true) await _history.clear();
  }

  Widget _appsSection(DateTime from, DateTime to) {
    const title = Text(
      'Apps while protected',
      style: TextStyle(
        color: NightSignal.text,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
    );
    if (!AppUsageService.isSupported) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title,
          SizedBox(height: 10),
          Text(
            'Available on Android.',
            style: TextStyle(color: NightSignal.soft),
          ),
        ],
      );
    }
    if (_usageAccess != true) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title,
          const SizedBox(height: 10),
          const Text(
            'See which apps you used while protected. Android asks you to '
            'allow Usage access for Hesam Void once. Nothing leaves this phone.',
            style: TextStyle(
              color: NightSignal.soft,
              fontSize: 13,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: AppUsageService.openSettings,
            style: FilledButton.styleFrom(
              backgroundColor: widget.accent,
              foregroundColor: NightSignal.background,
              minimumSize: const Size(0, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
            ),
            child: const Text('Allow usage access'),
          ),
        ],
      );
    }
    return FutureBuilder<List<AppUsageEntry>>(
      future: _appsFor(from, to),
      builder: (context, snapshot) {
        final entries = snapshot.data ?? const <AppUsageEntry>[];
        final loading = snapshot.connectionState != ConnectionState.done;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            title,
            const SizedBox(height: 14),
            if (loading)
              const SizedBox(
                height: 128,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (entries.isEmpty)
              const Text(
                'No app activity recorded while protected in this period.',
                style: TextStyle(color: NightSignal.soft, fontSize: 13),
              )
            else
              _AppsDonut(entries: entries, accent: widget.accent),
          ],
        );
      },
    );
  }
}

String _formatDuration(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  if (hours == 0) return '${d.inMinutes}m';
  return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: NightSignal.card(radius: 22),
      child: child,
    );
  }
}

class _Metric extends StatelessWidget {
  final String value;
  final String label;
  const _Metric({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: NightSignal.number(size: 16)),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(color: NightSignal.muted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _RangePicker extends StatelessWidget {
  final InsightsRange value;
  final ValueChanged<InsightsRange> onChanged;
  const _RangePicker({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const labels = {
      InsightsRange.day: 'Day',
      InsightsRange.week: 'Week',
      InsightsRange.month: 'Month',
    };
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: NightSignal.card(radius: 14),
      child: Row(
        children: [
          for (final range in InsightsRange.values)
            Expanded(
              child: Semantics(
                selected: range == value,
                button: true,
                child: GestureDetector(
                  onTap: () => onChanged(range),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: range == value
                          ? NightSignal.text
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      labels[range]!,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: range == value
                            ? NightSignal.background
                            : NightSignal.soft,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AppsDonut extends StatelessWidget {
  final List<AppUsageEntry> entries;
  final Color accent;
  const _AppsDonut({required this.entries, required this.accent});

  @override
  Widget build(BuildContext context) {
    final palette = [
      accent,
      NightSignal.upload,
      NightSignal.violet,
      NightSignal.warning,
      const Color(0xFFFF8A7A),
    ];
    final top = entries.take(4).toList();
    final rest = entries
        .skip(4)
        .fold<Duration>(Duration.zero, (sum, e) => sum + e.time);
    final slices = <(String, Duration, Color, AppUsageEntry?)>[
      for (var i = 0; i < top.length; i++)
        (top[i].appName, top[i].time, palette[i], top[i]),
      if (rest > Duration.zero) ('Other apps', rest, palette[4], null),
    ];
    final total = slices.fold<Duration>(Duration.zero, (sum, s) => sum + s.$2);

    return Row(
      children: [
        SizedBox(
          width: 128,
          height: 128,
          child: Stack(
            alignment: Alignment.center,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeOutCubic,
                builder: (context, t, _) => CustomPaint(
                  size: const Size(128, 128),
                  painter: _DonutPainter(
                    values: [for (final s in slices) s.$2.inSeconds.toDouble()],
                    colors: [for (final s in slices) s.$3],
                    progress: t,
                  ),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatDuration(total),
                    style: NightSignal.number(size: 17),
                  ),
                  const Text(
                    'in apps',
                    style: TextStyle(color: NightSignal.muted, fontSize: 10),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            children: [
              for (final s in slices)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.5),
                  child: Row(
                    children: [
                      _AppIcon(entry: s.$4, color: s.$3, name: s.$1),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          s.$1,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: NightSignal.text,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Text(
                        _formatDuration(s.$2),
                        style: NightSignal.number(
                          size: 12,
                          color: NightSignal.soft,
                          weight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AppIcon extends StatelessWidget {
  final AppUsageEntry? entry;
  final Color color;
  final String name;
  const _AppIcon({
    required this.entry,
    required this.color,
    required this.name,
  });

  @override
  Widget build(BuildContext context) {
    final icon = entry?.icon;
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color, width: 1.5),
        color: icon == null ? color : null,
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: icon != null
          ? Image.memory(icon, width: 21, height: 21, gaplessPlayback: true)
          : Text(
              name.isEmpty ? '?' : name[0].toUpperCase(),
              style: const TextStyle(
                color: NightSignal.background,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<double> values;
  final List<Color> colors;
  final double progress;
  const _DonutPainter({
    required this.values,
    required this.colors,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(14);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16;
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      paint..color = const Color(0x0FFFFFFF),
    );
    final total = values.fold<double>(0, (a, b) => a + b);
    if (total <= 0) return;
    var start = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = values[i] / total * math.pi * 2 * progress;
      canvas.drawArc(
        rect,
        start,
        math.max(0, sweep - 0.04),
        false,
        paint..color = colors[i],
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.progress != progress || old.values != values;
}

class _Calendar extends StatelessWidget {
  final List<double> minutes;
  final DateTime today;
  final Color accent;
  const _Calendar({
    required this.minutes,
    required this.today,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    // Five full weeks, Monday first, ending with the current week.
    final todayDate = DateTime(today.year, today.month, today.day);
    final weekStart = todayDate.subtract(Duration(days: todayDate.weekday - 1));
    final gridStart = weekStart.subtract(const Duration(days: 28));
    final firstDataDay = todayDate.subtract(Duration(days: minutes.length - 1));
    final peak = minutes.fold<double>(0, math.max);

    Color shade(double m) {
      if (m <= 0 || peak <= 0) return const Color(0x0DFFFFFF);
      final level = (m / peak).clamp(0.0, 1.0);
      if (level > 0.85) return accent;
      return accent.withValues(alpha: 0.2 + level * 0.55);
    }

    const days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Last 5 weeks',
              style: TextStyle(
                color: NightSignal.text,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              'less → more',
              style: TextStyle(color: NightSignal.muted, fontSize: 11),
            ),
          ],
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          children: [
            for (final d in days)
              Center(
                child: Text(
                  d,
                  style: const TextStyle(
                    color: NightSignal.faint,
                    fontSize: 10,
                  ),
                ),
              ),
            for (var i = 0; i < 35; i++)
              Builder(
                builder: (context) {
                  final day = gridStart.add(Duration(days: i));
                  final index = day.difference(firstDataDay).inDays;
                  final future = day.isAfter(todayDate);
                  final value = (index >= 0 && index < minutes.length)
                      ? minutes[index]
                      : 0.0;
                  return Tooltip(
                    message: future ? '' : '${value.round()} min',
                    child: Container(
                      decoration: BoxDecoration(
                        color: future ? Colors.transparent : shade(value),
                        borderRadius: BorderRadius.circular(6),
                        border: day == todayDate
                            ? Border.all(color: NightSignal.soft, width: 1)
                            : null,
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ],
    );
  }
}

class _HourChart extends StatelessWidget {
  final List<double> minutes;
  final Color accent;
  const _HourChart({required this.minutes, required this.accent});

  @override
  Widget build(BuildContext context) {
    final peak = minutes.fold<double>(0, math.max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'When you connect',
          style: TextStyle(
            color: NightSignal.text,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 70,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var h = 0; h < 24; h++) ...[
                Expanded(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(
                      begin: 0,
                      end: peak <= 0 ? 0 : minutes[h] / peak,
                    ),
                    duration: Duration(milliseconds: 500 + h * 20),
                    curve: Curves.easeOutCubic,
                    builder: (context, v, _) => Container(
                      height: math.max(4, v * 70),
                      decoration: BoxDecoration(
                        color: peak > 0 && minutes[h] == peak
                            ? accent
                            : accent.withValues(alpha: 0.22 + v * 0.5),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ),
                if (h < 23) const SizedBox(width: 3),
              ],
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final t in ['00', '06', '12', '18', '24'])
              Text(
                t,
                style: NightSignal.number(
                  size: 10,
                  color: NightSignal.faint,
                  weight: FontWeight.w500,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _DataChart extends StatelessWidget {
  final List<(int, int)> days;
  final DateTime today;
  final Color accent;
  const _DataChart({
    required this.days,
    required this.today,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final peak = days.fold<int>(0, (m, d) => math.max(m, d.$1 + d.$2));
    const names = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Data this week',
                style: TextStyle(
                  color: NightSignal.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            _Legend(color: accent, label: 'down'),
            const SizedBox(width: 12),
            const _Legend(color: NightSignal.upload, label: 'up'),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 96,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < days.length; i++) ...[
                Expanded(
                  child: Tooltip(
                    message:
                        '${formatDataSize(days[i].$1)} down · ${formatDataSize(days[i].$2)} up',
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: Duration(milliseconds: 600 + i * 50),
                      curve: Curves.easeOutCubic,
                      builder: (context, t, _) {
                        final down = peak <= 0
                            ? 0.0
                            : days[i].$1 / peak * 92 * t;
                        final up = peak <= 0 ? 0.0 : days[i].$2 / peak * 92 * t;
                        return Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Container(
                              height: up,
                              decoration: const BoxDecoration(
                                color: NightSignal.upload,
                                borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(4),
                                ),
                              ),
                            ),
                            Container(
                              height: math.max(peak <= 0 ? 3.0 : 0.0, down),
                              color: peak <= 0
                                  ? const Color(0x0FFFFFFF)
                                  : accent,
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                if (i < days.length - 1) const SizedBox(width: 10),
              ],
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (var i = 0; i < days.length; i++) ...[
              Expanded(
                child: Text(
                  names[today
                          .subtract(Duration(days: days.length - 1 - i))
                          .weekday -
                      1],
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: NightSignal.faint,
                    fontSize: 10,
                  ),
                ),
              ),
              if (i < days.length - 1) const SizedBox(width: 10),
            ],
          ],
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(color: NightSignal.soft, fontSize: 11),
        ),
      ],
    );
  }
}
