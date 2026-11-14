import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hesam_void/models/subscription.dart';
import 'package:hesam_void/models/vpn_config.dart';
import 'package:hesam_void/services/subscription_parser.dart';
import 'package:hesam_void/services/subscription_service.dart';
import 'package:hesam_void/services/xray_json_config.dart';
import 'package:hesam_void/widgets/subscription_folder_card.dart';

const _vless =
    'vless://11111111-1111-1111-1111-111111111111@one.example.com:443'
    '?type=tcp&security=reality&sni=www.example.com&pbk=key&sid=ab#One';
const _trojan = 'trojan://secret@two.example.com:443?security=tls#Two';

Map<String, dynamic> _xray({
  String remarks = 'Germany',
  bool proxyFirst = true,
  String proxyTag = 'proxy',
}) {
  final proxy = {
    'tag': proxyTag,
    'protocol': 'vless',
    'settings': {
      'vnext': [
        {
          'address': 'de.example.com',
          'port': 443,
          'users': [
            {'id': '11111111-1111-1111-1111-111111111111'},
          ],
        },
      ],
    },
    'streamSettings': {
      'network': 'ws',
      'security': 'tls',
      'tlsSettings': {'serverName': 'cdn.example.com'},
    },
  };
  final direct = {'tag': 'direct', 'protocol': 'freedom'};
  return {
    'remarks': remarks,
    'outbounds': proxyFirst ? [proxy, direct] : [direct, proxy],
    'routing': {
      'rules': [
        {'type': 'field', 'outboundTag': proxyTag, 'network': 'tcp,udp'},
      ],
    },
  };
}

void main() {
  group('SubscriptionParser', () {
    test('reads a plain list of links and skips duplicates', () {
      final result = SubscriptionParser.parse('$_vless\n$_trojan\n$_vless\n');
      expect(result.format, ContentFormat.links);
      expect(result.configs.map((c) => c.name), ['One', 'Two']);
    });

    test('decodes a base64 subscription body', () {
      final body = base64.encode(utf8.encode('$_vless\r\n$_trojan'));
      final result = SubscriptionParser.parse(body);
      expect(result.format, ContentFormat.base64Links);
      expect(result.configs, hasLength(2));
    });

    test('keeps provider order for newest-first sorting', () {
      final result = SubscriptionParser.parse('$_vless\n$_trojan');
      final sorted = [...result.configs]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      expect(sorted.map((c) => c.name), ['One', 'Two']);
    });

    test('counts links with unsupported protocols', () {
      final result = SubscriptionParser.parse(
        '$_vless\nhysteria2://pass@h.example.com:443#H\ntuic://x@t:1#T',
      );
      expect(result.configs, hasLength(1));
      expect(result.unsupported, 2);
    });

    test('imports Xray JSON objects and arrays', () {
      final single = SubscriptionParser.parse(jsonEncode(_xray()));
      expect(single.format, ContentFormat.xrayJson);
      final config = single.configs.single;
      expect(config.protocol, VpnProtocol.json);
      expect(config.name, 'Germany');
      expect(config.address, 'de.example.com');
      expect(config.port, 443);
      expect(config.transportString, 'ws');
      expect(config.sni, 'cdn.example.com');

      final array = SubscriptionParser.parse(
        jsonEncode([_xray(remarks: 'A'), _xray(remarks: 'B')]),
      );
      expect(array.configs.map((c) => c.name), ['A', 'B']);
    });

    test('recognises sing-box and Clash profiles as unsupported formats', () {
      final singBox = SubscriptionParser.parse(
        jsonEncode({
          'outbounds': [
            {'type': 'vless', 'server': 'x', 'server_port': 443},
          ],
        }),
      );
      expect(singBox.format, ContentFormat.singBox);
      expect(singBox.isUnsupportedFormat, isTrue);

      final clash = SubscriptionParser.parse(
        'proxies:\n  - name: a\n    type: vmess\n',
      );
      expect(clash.format, ContentFormat.clash);
      expect(clash.emptyReason, contains('Clash'));
    });

    test('reads provider titles and update intervals', () {
      expect(SubscriptionParser.decodeProfileTitle('My VPN'), 'My VPN');
      expect(
        SubscriptionParser.decodeProfileTitle(
          'base64:${base64.encode(utf8.encode('سرور من'))}',
        ),
        'سرور من',
      );
      expect(
        SubscriptionParser.nameFromContentDisposition(
          'attachment; filename="Premium.txt"',
        ),
        'Premium',
      );
      expect(SubscriptionParser.updateIntervalHours('24'), 24);
      expect(SubscriptionParser.updateIntervalHours('0'), isNull);
    });
  });

  group('SubscriptionUserInfo', () {
    test('parses usage and expiry', () {
      final info = SubscriptionUserInfo.parse(
        'upload=1073741824; download=2147483648; total=10737418240; '
        'expire=1893456000',
      )!;
      expect(info.upload, 1073741824);
      expect(info.download, 2147483648);
      expect(info.total, 10737418240);
      expect(info.expire, DateTime.fromMillisecondsSinceEpoch(1893456000000));
    });

    test('treats zero total and expiry as unlimited', () {
      final info = SubscriptionUserInfo.parse(
        'upload=0; download=5; total=0; expire=0',
      )!;
      expect(info.total, isNull);
      expect(info.expire, isNull);
    });
  });

  group('SubscriptionMerge', () {
    test('keeps unchanged routes, adds new ones and removes missing ones', () {
      final first = SubscriptionParser.parse('$_vless\n$_trojan').configs;
      final stored = [
        for (final c in first) c.copyWith(subscriptionId: 'sub', ping: 120),
      ];

      final next = SubscriptionParser.parse(
        '$_vless\nss://YWVzLTI1Ni1nY206cGFzcw@three.example.com:8388#Three',
      ).configs;
      final merge = SubscriptionMerge.apply(
        subscriptionId: 'sub',
        existing: stored,
        incoming: next,
      );

      expect(merge.routes.map((c) => c.name), ['One', 'Three']);
      // The kept route is the same stored route with its latency.
      expect(merge.routes.first.id, stored.first.id);
      expect(merge.routes.first.ping, 120);
      expect(merge.added.single.name, 'Three');
      expect(merge.added.single.subscriptionId, 'sub');
      expect(merge.removed.single.name, 'Two');
    });
  });

  group('Subscription', () {
    test('round-trips through JSON and reports remaining days', () {
      final now = DateTime(2026, 11, 14, 12);
      final subscription = Subscription(
        id: 'a',
        url: 'https://example.com/sub/token',
        name: 'Provider',
        createdAt: now,
        updatedAt: now,
        uploadBytes: 10,
        downloadBytes: 30,
        totalBytes: 100,
        expiresAt: now.add(const Duration(days: 5, hours: 2)),
        autoUpdateHours: 6,
      );
      final restored = Subscription.fromJson(subscription.toJson())!;
      expect(restored.name, 'Provider');
      expect(restored.usageFraction, closeTo(0.4, 0.0001));
      expect(restored.daysLeft(now), 6);
      expect(restored.isDue(now.add(const Duration(hours: 5))), isFalse);
      expect(restored.isDue(now.add(const Duration(hours: 6))), isTrue);
    });
  });

  group('SubscriptionService.parseUrl', () {
    test('accepts http(s) links only', () {
      expect(
        SubscriptionService.parseUrl('https://a.example/sub/x'),
        isNotNull,
      );
      expect(SubscriptionService.parseUrl(' http://a.example/s '), isNotNull);
      expect(SubscriptionService.parseUrl(_vless), isNull);
      expect(SubscriptionService.parseUrl('https://a b'), isNull);
    });
  });

  group('XrayJsonConfig.prepareForEngine', () {
    test('adds a SOCKS inbound when the profile has none', () {
      final prepared = jsonDecode(
        XrayJsonConfig.prepareForEngine(jsonEncode(_xray())),
      );
      final inbound = (prepared['inbounds'] as List).first as Map;
      expect(inbound['protocol'], 'socks');
      expect(inbound['port'], XrayJsonConfig.defaultSocksPort);
      expect(prepared.containsKey('remarks'), isFalse);
    });

    test('moves the server outbound first and tags it proxy', () {
      final prepared = jsonDecode(
        XrayJsonConfig.prepareForEngine(
          jsonEncode(_xray(proxyFirst: false, proxyTag: 'de-out')),
        ),
      );
      final outbounds = prepared['outbounds'] as List;
      expect(outbounds.first['protocol'], 'vless');
      expect(outbounds.first['tag'], 'proxy');
      // Routing still points at the same outbound.
      final rule = (prepared['routing']['rules'] as List).first as Map;
      expect(rule['outboundTag'], 'proxy');
    });

    test('keeps an existing SOCKS inbound', () {
      final profile = _xray()
        ..['inbounds'] = [
          {'tag': 'in', 'protocol': 'socks', 'port': 2080},
        ];
      final prepared = jsonDecode(
        XrayJsonConfig.prepareForEngine(jsonEncode(profile)),
      );
      final inbounds = prepared['inbounds'] as List;
      expect(inbounds, hasLength(1));
      expect(inbounds.first['port'], 2080);
    });

    test('reduces DoH and object DNS servers to IPs for the tunnel', () {
      // Shape of a real panel profile (BPB-style) that failed to connect.
      final profile = _xray()
        ..['dns'] = {
          'hosts': {'geosite:category-ads-all': '#3'},
          'servers': [
            {'address': 'https://8.8.8.8/dns-query', 'tag': 'remote-dns'},
            {
              'address': '8.8.8.8',
              'domains': ['geosite:category-ir'],
              'skipFallback': true,
            },
            {'address': 'https://dns.google/dns-query'},
            'localhost',
          ],
          'queryStrategy': 'UseIP',
          'tag': 'dns',
        };
      final prepared = jsonDecode(
        XrayJsonConfig.prepareForEngine(jsonEncode(profile)),
      );
      final dns = prepared['dns'] as Map;
      expect(dns['servers'], ['8.8.8.8']);
      expect(dns['hosts'], isNotEmpty);
      expect(dns['queryStrategy'], 'UseIP');
      // DNS queries now leave through the server.
      final first = (prepared['routing']['rules'] as List).first as Map;
      expect(first['inboundTag'], [dns['tag']]);
      expect(first['outboundTag'], 'proxy');
    });

    test('falls back to public resolvers when no DNS IP is known', () {
      final profile = _xray()
        ..['dns'] = {
          'servers': ['https://dns.google/dns-query'],
        };
      final prepared = jsonDecode(
        XrayJsonConfig.prepareForEngine(jsonEncode(profile)),
      );
      expect(prepared['dns']['servers'], ['1.1.1.1', '8.8.8.8']);
    });

    test('leaves plain IP DNS lists and routing untouched', () {
      final profile = _xray()
        ..['dns'] = {
          'servers': ['1.1.1.1', '8.8.4.4'],
        };
      final prepared = jsonDecode(
        XrayJsonConfig.prepareForEngine(jsonEncode(profile)),
      );
      expect(prepared['dns']['servers'], ['1.1.1.1', '8.8.4.4']);
      expect(prepared['dns'].containsKey('tag'), isFalse);
      expect(prepared['routing']['rules'], hasLength(1));
    });

    test('translates settings newer than the bundled engine', () {
      final profile = _xray();
      (profile['outbounds'] as List).add({
        'tag': 'dns-out',
        'protocol': 'dns',
        'settings': {'nonIPQuery': 'reject'},
      });
      final prepared = jsonDecode(
        XrayJsonConfig.prepareForEngine(jsonEncode(profile)),
      );
      final dnsOut = (prepared['outbounds'] as List).firstWhere(
        (o) => o['protocol'] == 'dns',
      );
      expect(dnsOut['settings']['nonIPQuery'], 'drop');
    });

    test('explains transports the bundled engine cannot run', () {
      final profile = _xray();
      ((profile['outbounds'] as List).first as Map)['streamSettings'] = {
        'network': 'xhttp',
      };
      expect(
        () => XrayJsonConfig.prepareForEngine(jsonEncode(profile)),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('XHTTP'),
          ),
        ),
      );
    });

    test('rejects a profile without a usable server', () {
      expect(
        () => XrayJsonConfig.prepareForEngine(
          jsonEncode({
            'outbounds': [
              {'protocol': 'freedom'},
            ],
          }),
        ),
        throwsFormatException,
      );
    });
  });

  group('SubscriptionFolderCard', () {
    testWidgets('fits a long name, usage and expiry on a narrow screen', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var opened = 0;
      final now = DateTime.now();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: SubscriptionFolderCard(
                subscription: Subscription(
                  id: 'a',
                  url: 'https://example.com/s',
                  name: 'A provider with a very long subscription name',
                  createdAt: now,
                  updatedAt: now.subtract(const Duration(hours: 3)),
                  uploadBytes: 1 << 30,
                  downloadBytes: 37 << 30,
                  totalBytes: 50 << 30,
                  expiresAt: now.add(const Duration(days: 2)),
                ),
                routeCount: 24,
                bestPing: 85,
                isRefreshing: false,
                containsSelection: true,
                accentColor: Colors.green,
                surfaceColor: Colors.black,
                textColor: Colors.white,
                onOpen: () => opened++,
                onRefresh: () {},
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('38.0 GB of 50.0 GB used'), findsOneWidget);
      expect(find.text('2 days left'), findsOneWidget);
      await tester.tap(find.byType(SubscriptionFolderCard));
      expect(opened, 1);
    });

    test('formats sizes and ages', () {
      expect(formatDataSize(512), '512 B');
      expect(formatDataSize(1536), '1.5 KB');
      expect(formatDataSize(5 << 30), '5.0 GB');
      final now = DateTime(2026, 1, 1, 12);
      expect(
        formatAgo(now.subtract(const Duration(seconds: 20)), now),
        'just now',
      );
      expect(formatAgo(now.subtract(const Duration(hours: 5)), now), '5h ago');
      expect(formatAgo(null, now), 'never');
    });
  });
}
