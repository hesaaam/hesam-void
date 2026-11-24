import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hesam_void/models/ssh_config.dart';
import 'package:hesam_void/models/vpn_config.dart';
import 'package:hesam_void/providers/config_provider.dart';
import 'package:hesam_void/screens/ssh_form_screen.dart';
import 'package:hesam_void/screens/ssh_tab.dart';
import 'package:hesam_void/services/config_parser_service.dart';
import 'package:provider/provider.dart';

Widget _host(Widget child) => ChangeNotifierProvider(
  create: (_) => ConfigProvider(),
  child: MaterialApp(home: child),
);

void _phone(WidgetTester tester, {double height = 2340}) {
  tester.view.physicalSize = Size(1080, height);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('add form shows the common SSH fields', (tester) async {
    // Tall enough for the whole form to be built at once.
    _phone(tester, height: 6000);
    await tester.pumpWidget(_host(const SshFormScreen(accent: Colors.teal)));
    expect(find.text('Add SSH server'), findsOneWidget);
    for (final label in [
      'SSH host',
      'Port',
      'Username',
      'Password',
      'UDPGW port',
    ]) {
      expect(find.widgetWithText(TextField, label), findsOneWidget);
    }
    expect(find.text('DNS through the UDP gateway'), findsOneWidget);
    // Direct needs no SNI.
    expect(
      find.widgetWithText(TextField, 'SNI (server name sent in TLS)'),
      findsNothing,
    );

    await tester.tap(find.text('SSL / TLS'));
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(TextField, 'SNI (server name sent in TLS)'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextField, '443'), findsOneWidget);

    await tester.tap(find.text('WebSocket'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Path'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Host header'), findsOneWidget);

    await tester.tap(find.text('Private key'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Private key'), findsOneWidget);
  });

  testWidgets('saving an incomplete form explains what is missing', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(_host(const SshFormScreen(accent: Colors.teal)));
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();
    expect(find.text('Enter the SSH host without spaces.'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'SSH host'),
      'ssh.example.com',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();
    expect(find.text('Enter the SSH username.'), findsOneWidget);
  });

  testWidgets('editing fills the form from the saved link', (tester) async {
    _phone(tester, height: 6000);
    final ssh = SshConfig(
      id: 'r1',
      remarks: 'Frankfurt',
      configType: SshConfigType.ssl,
      sshHost: 'de1.example.net',
      sshPort: 443,
      sshUsername: 'user01',
      sshPassword: 'pw',
      sni: 'front.example.org',
      udpgwPort: 7300,
    );
    final route = ConfigParserService.sshVpnConfig(ssh, rawUrl: ssh.toSshUrl());
    await tester.pumpWidget(
      _host(SshFormScreen(existing: route, accent: Colors.teal)),
    );
    expect(find.text('Edit SSH server'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'de1.example.net'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'front.example.org'), findsOneWidget);
    expect(find.widgetWithText(TextField, '7300'), findsOneWidget);
  });

  testWidgets('SSH tab offers adding the first server', (tester) async {
    _phone(tester);
    var added = 0;
    await tester.pumpWidget(
      _host(
        Scaffold(
          body: SshTab(
            accent: Colors.teal,
            rowBuilder: (_, _, VpnConfig c) => Text(c.name),
            onAdd: () => added++,
            onPasteLink: () {},
            onCheckAll: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('Add your first SSH server'), findsOneWidget);
    await tester.tap(find.text('Add SSH server'));
    expect(added, 1);
  });
}
