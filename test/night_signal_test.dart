import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hesam_void/models/vpn_config.dart';
import 'package:hesam_void/screens/smart_connect_radar_screen.dart';
import 'package:hesam_void/services/session_history_service.dart';
import 'package:hesam_void/services/smart_connect_service.dart';
import 'package:hesam_void/services/vpn_service.dart';
import 'package:hesam_void/widgets/night/night_controls.dart';
import 'package:hesam_void/widgets/night/route_widgets.dart';
import 'package:hesam_void/widgets/night/signal_scene.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: Padding(padding: const EdgeInsets.all(24), child: child),
    ),
  ),
);

VpnConfig _route(String id, {int? ping}) => VpnConfig(
  id: id,
  name: 'Route $id',
  rawUrl: 'vless://$id@example.com:443#$id',
  protocolString: 'vless',
  address: 'example.com',
  port: 443,
  ping: ping,
);

ConnectionSession _session(DateTime start, Duration length, {int down = 0}) =>
    ConnectionSession(
      configId: 'a',
      routeName: 'A',
      start: start,
      end: start.add(length),
      downloadBytes: down,
    );

void main() {
  group('SignalScene', () {
    for (final status in VpnStatus.values) {
      testWidgets('renders the ${status.name} state on a narrow phone', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(340, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          _host(
            SignalScene(
              status: status,
              stats: ValueNotifier(VpnStats(downloadSpeed: 2 * 1024 * 1024)),
              accent: Colors.green,
              eyebrow: 'Internet verified',
              headline: 'You are protected',
              serverLabel: 'Germany',
              latencyLabel: '182 ms',
              animate: false,
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('You are protected'), findsOneWidget);
      });
    }
  });

  group('PowerButton', () {
    testWidgets('is a labelled button that reports taps', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(
          PowerButton(
            status: VpnStatus.disconnected,
            busy: false,
            accent: Colors.green,
            semanticLabel: 'Connect',
            onPressed: () => taps++,
          ),
        ),
      );
      expect(find.bySemanticsLabel('Connect'), findsOneWidget);
      await tester.tap(find.byType(PowerButton));
      expect(taps, 1);
    });
  });

  group('RouteRow', () {
    testWidgets('shows latency and opens the actions sheet', (tester) async {
      var selected = 0;
      await tester.pumpWidget(
        _host(
          RouteRow(
            config: _route('a', ping: 182),
            selected: true,
            favorite: true,
            testing: false,
            accent: Colors.green,
            actions: RouteActions(
              onSelect: () => selected++,
              onTest: () {},
              onToggleFavorite: () {},
              onCopy: () {},
              onShowQr: () {},
              onDelete: () {},
            ),
          ),
        ),
      );
      expect(find.text('182 ms'), findsOneWidget);
      await tester.tap(find.text('Route a'));
      expect(selected, 1);
      await tester.tap(find.byTooltip('Route actions'));
      await tester.pumpAndSettle();
      expect(find.text('Check latency'), findsOneWidget);
    });
  });

  group('RadarView', () {
    test('places faster routes closer to the centre and the winner in it', () {
      const center = Offset(RadarView.size / 2, RadarView.size / 2);
      final fast = RadarView.positionOf(
        const RadarBlip(
          id: 'f',
          name: 'F',
          state: BlipState.measured,
          realDelayMs: 90,
        ),
        0,
      );
      final slow = RadarView.positionOf(
        const RadarBlip(
          id: 's',
          name: 'S',
          state: BlipState.measured,
          realDelayMs: 800,
        ),
        0,
      );
      final winner = RadarView.positionOf(
        const RadarBlip(
          id: 'w',
          name: 'W',
          state: BlipState.winner,
          realDelayMs: 90,
        ),
        3,
      );
      expect((fast - center).distance, lessThan((slow - center).distance));
      expect(winner, center);
    });
  });

  group('SessionHistoryService aggregations', () {
    final day = DateTime(2026, 11, 10);

    test('summarizes time and splits traffic at range edges', () {
      final sessions = [
        // 22:00 → 02:00 next day, 4 GB in total.
        _session(
          day.add(const Duration(hours: 22)),
          const Duration(hours: 4),
          down: 4000,
        ),
      ];
      final first = SessionHistoryService.summarize(
        sessions,
        day,
        day.add(const Duration(days: 1)),
      );
      expect(first.protected, const Duration(hours: 2));
      expect(first.downloadBytes, 2000);
      expect(first.sessions, 1);
    });

    test('spreads minutes over hours of the day', () {
      final sessions = [
        _session(
          day.add(const Duration(hours: 9, minutes: 30)),
          const Duration(hours: 1),
        ),
      ];
      final hours = SessionHistoryService.minutesByHour(
        sessions,
        day,
        day.add(const Duration(days: 1)),
      );
      expect(hours[9], 30);
      expect(hours[10], 30);
      expect(hours.where((m) => m > 0), hasLength(2));
    });

    test('lists protected minutes per day ending today', () {
      final sessions = [
        _session(
          day.add(const Duration(hours: 8)),
          const Duration(minutes: 45),
        ),
        _session(
          day.subtract(const Duration(days: 1)).add(const Duration(hours: 8)),
          const Duration(minutes: 15),
        ),
      ];
      final minutes = SessionHistoryService.minutesPerDay(sessions, day, 3);
      expect(minutes, [0, 15, 45]);
    });

    test('round-trips sessions through JSON', () {
      final session = _session(day, const Duration(minutes: 5), down: 42);
      final restored = ConnectionSession.fromJson(session.toJson())!;
      expect(restored.start, session.start);
      expect(restored.end, session.end);
      expect(restored.downloadBytes, 42);
    });
  });
}
