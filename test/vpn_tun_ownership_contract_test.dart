import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Android CoreController TUN ownership contract', () {
    test(
      'VPN service delegates the established TUN only to the modern Core',
      () {
        final serviceFile = File(
          'packages/flutter_v2ray_modern/android/src/main/java/'
          'com/github/blueboytm/flutter_v2ray/v2ray/services/'
          'V2rayVPNService.java',
        );
        final source = serviceFile.readAsStringSync();

        expect(source, contains('startCore(v2rayConfig, mInterface.getFd())'));
        expect(
          source,
          contains('builder.addDisallowedApplication(getPackageName())'),
        );
        expect(source, isNot(contains('runTun2socks(')));
        expect(source, isNot(contains('sendFileDescriptor(')));
        expect(source, isNot(contains('libtun2socks.so')));
        expect(source, isNot(contains('LocalSocket')));
      },
    );
  });
}
