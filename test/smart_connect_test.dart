import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hesam_void/models/vpn_config.dart';
import 'package:hesam_void/services/connection_error_explainer.dart';
import 'package:hesam_void/services/smart_connect_service.dart';
import 'package:hesam_void/services/vpn_service.dart';
import 'package:hesam_void/widgets/alive_signal_canvas.dart';

VpnConfig _config(String id) => VpnConfig(
  id: id,
  name: 'Route $id',
  rawUrl: 'vless://$id@example.com:443#$id',
  protocolString: 'vless',
  address: 'example.com',
  port: 443,
);

void main() {
  group('SmartConnectService.rank', () {
    test('puts routes proven by Real Delay first, fastest first', () {
      final ranked = SmartConnectService.rank([
        SmartCandidate(config: _config('a'), tcpMs: 20, healthScore: 90),
        SmartCandidate(
          config: _config('b'),
          tcpMs: 300,
          healthScore: 40,
          realDelayMs: 420,
        ),
        SmartCandidate(
          config: _config('c'),
          tcpMs: 80,
          healthScore: 70,
          realDelayMs: 180,
        ),
      ]);

      expect(ranked.map((c) => c.config.id), ['c', 'b', 'a']);
    });

    test('moves routes whose Real Delay failed to the end', () {
      final ranked = SmartConnectService.rank([
        SmartCandidate(
          config: _config('failed'),
          tcpMs: 10,
          healthScore: 99,
          realDelayMs: -1,
        ),
        SmartCandidate(
          config: _config('untested'),
          tcpMs: 500,
          healthScore: 20,
        ),
      ]);

      expect(ranked.map((c) => c.config.id), ['untested', 'failed']);
    });

    test('orders unmeasured routes by local health, then latency', () {
      final ranked = SmartConnectService.rank([
        SmartCandidate(config: _config('slow'), tcpMs: 400, healthScore: 70),
        SmartCandidate(config: _config('fast'), tcpMs: 40, healthScore: 70),
        SmartCandidate(config: _config('healthy'), tcpMs: 900, healthScore: 85),
      ]);

      expect(ranked.map((c) => c.config.id), ['healthy', 'fast', 'slow']);
    });
  });

  group('ConnectionErrorExplainer', () {
    test('explains a tunnel that carries no traffic', () {
      final insight = ConnectionErrorExplainer.explain(kTunnelNoInternetError);
      expect(insight.title, contains('internet'));
      expect(insight.suggestOtherRoute, isTrue);
    });

    test('does not suggest another route for a permission problem', () {
      final insight = ConnectionErrorExplainer.explain(
        'VPN permission denied. Please allow VPN permission.',
      );
      expect(insight.title, 'VPN permission is needed');
      expect(insight.suggestOtherRoute, isFalse);
    });

    test('recognises unreachable servers', () {
      final insight = ConnectionErrorExplainer.explain(
        'Connection failed: SocketException: Connection timed out',
      );
      expect(insight.title, 'The server did not answer');
    });

    test('falls back to a generic explanation', () {
      final insight = ConnectionErrorExplainer.explain(null);
      expect(insight.title, isNotEmpty);
      expect(insight.hint, isNotEmpty);
    });
  });

  group('AliveSignalCanvas', () {
    Widget host(Widget child, {Size size = const Size(360, 640)}) {
      return MediaQuery(
        data: MediaQueryData(size: size),
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(padding: const EdgeInsets.all(20), child: child),
            ),
          ),
        ),
      );
    }

    testWidgets('offers Smart Connect when no route is selected', (
      tester,
    ) async {
      var smartRuns = 0;
      await tester.pumpWidget(
        host(
          AliveSignalCanvas(
            status: VpnStatus.disconnected,
            config: null,
            stats: VpnStats(),
            accentColor: Colors.green,
            surfaceColor: Colors.black,
            textColor: Colors.white,
            onPrimaryAction: () => smartRuns++,
            onChooseRoute: () {},
            onOpenStory: () {},
            onSmartConnect: () {},
          ),
        ),
      );

      expect(find.text('SMART CONNECT'), findsOneWidget);
      await tester.tap(find.text('SMART CONNECT'));
      expect(smartRuns, 1);
    });

    testWidgets('shows progress and cancels while Smart Connect runs', (
      tester,
    ) async {
      var cancelled = 0;
      await tester.pumpWidget(
        host(
          AliveSignalCanvas(
            status: VpnStatus.disconnected,
            config: _config('a'),
            stats: VpnStats(),
            accentColor: Colors.green,
            surfaceColor: Colors.black,
            textColor: Colors.white,
            onPrimaryAction: () {},
            onChooseRoute: () {},
            onOpenStory: () {},
            smartActive: true,
            smartHeadline: 'Checking your routes',
            smartDetail: 'Checked 3 of 8 routes',
            smartProgress: 3 / 8,
            onSmartConnect: () {},
            onCancelSmart: () => cancelled++,
          ),
          // A short screen uses the compact canvas; it must not overflow.
          size: const Size(360, 600),
        ),
      );

      expect(find.text('Checking your routes'), findsOneWidget);
      expect(find.text('Checked 3 of 8 routes'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      await tester.tap(find.text('CANCEL'));
      expect(cancelled, 1);
    });
  });
}
