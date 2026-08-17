import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_v2ray/flutter_v2ray.dart';

void main() {
  test('current Xray validates VLESS Reality Vision ML-KEM JSON', () async {
    final xray = Platform.environment['XRAY_BINARY'];
    final auth = Platform.environment['VLESS_ENCRYPTION_AUTH'];
    final realityPassword = Platform.environment['REALITY_PUBLIC_KEY'];

    if (xray == null || auth == null || realityPassword == null) {
      return;
    }

    final raw =
        'vless://33333333-3333-3333-3333-333333333333@reality.example.com:443?encryption=mlkem768x25519plus.native.0rtt.$auth&flow=xtls-rprx-vision&security=reality&sni=www.example.com&fp=chrome&pbk=$realityPassword&sid=6bad&spx=%2F&type=tcp&headerType=none#Reality%20Vision';
    final config = FlutterV2ray.parseFromURL(raw).getFullConfiguration();
    final parsed = jsonDecode(config) as Map<String, dynamic>;
    final reality =
        ((parsed['outbounds'] as List).first
                as Map<String, dynamic>)['streamSettings']
            as Map<String, dynamic>;

    expect(reality['security'], 'reality');
    expect(
      (reality['realitySettings'] as Map<String, dynamic>)['password'],
      realityPassword,
    );

    final temp = File(
      '${Directory.systemTemp.path}/hesam_void_reality_${DateTime.now().microsecondsSinceEpoch}.json',
    );
    await temp.writeAsString(config);
    try {
      final result = await Process.run(xray, ['run', '-test', '-c', temp.path]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    } finally {
      if (await temp.exists()) {
        await temp.delete();
      }
    }
  });
}
