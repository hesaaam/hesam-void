import 'package:flutter/services.dart';

/// Starts and stops the Android foreground service that keeps the app's
/// process (where SSH runs) alive while a tunnel is active.
class SshKeepAlive {
  const SshKeepAlive._();

  static const _channel = MethodChannel('hesam_void/ssh_keepalive');

  static Future<void> start(String title) async {
    try {
      await _channel.invokeMethod<bool>('start', {'title': title});
    } catch (_) {
      // Not on Android, or refused: the tunnel still works while the app
      // stays on screen.
    }
  }

  static Future<void> stop() async {
    try {
      await _channel.invokeMethod<bool>('stop');
    } catch (_) {
      // Not on Android, or nothing to stop.
    }
  }
}
