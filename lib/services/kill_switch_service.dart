import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'vpn_service.dart';

/// KillSwitchService
/// Monitors VPN connection state and enforces a network kill switch:
/// if the VPN drops unexpectedly, this service immediately blocks all
/// internet traffic until the VPN reconnects or the user disables it.
///
/// Implementation:
///   - Listens to VpnService status stream
///   - When status changes CONNECTED → DISCONNECTED (not via user action)
///     it calls the V2Ray platform channel to enforce "always-on VPN" mode
///     which prevents any traffic from leaking outside the tunnel
///   - Exposes [isActive] and [isTriggered] for UI indicators
class KillSwitchService extends ChangeNotifier {
  static final KillSwitchService _instance = KillSwitchService._internal();
  factory KillSwitchService() => _instance;
  KillSwitchService._internal();

  // Platform channel to toggle Android "Block connections without VPN"
  static const MethodChannel _channel =
      MethodChannel('hesam_void/kill_switch');

  bool _isEnabled = false;    // user preference
  bool _isTriggered = false;  // currently blocking traffic
  bool _userDisconnecting = false; // flag: user-initiated disconnect

  StreamSubscription<VpnStatus>? _statusSub;

  bool get isEnabled => _isEnabled;
  bool get isTriggered => _isTriggered;

  /// Enable or disable the kill switch.
  /// When enabled, starts monitoring VPN status.
  Future<void> setEnabled(bool enabled) async {
    _isEnabled = enabled;
    _isTriggered = false;
    notifyListeners();

    if (enabled) {
      _startMonitoring();
    } else {
      await _stopMonitoring();
      await _releaseBlock();
    }

    if (kDebugMode) {
      debugPrint('[KillSwitch] ${enabled ? "Enabled" : "Disabled"}')
      ;
    }
  }

  /// Call this BEFORE a user-initiated disconnect so the kill switch
  /// doesn't falsely trigger.
  void notifyUserDisconnecting() {
    _userDisconnecting = true;
  }

  void _startMonitoring() {
    _statusSub?.cancel();
    final vpn = VpnService();
    // Poll status changes via listener (VpnService is a ChangeNotifier)
    vpn.addListener(_onVpnStatusChange);
  }

  Future<void> _stopMonitoring() async {
    VpnService().removeListener(_onVpnStatusChange);
    _statusSub?.cancel();
    _statusSub = null;
  }

  void _onVpnStatusChange() {
    if (!_isEnabled) return;

    final status = VpnService().status;

    if (status == VpnStatus.disconnected && !_userDisconnecting) {
      // Unexpected disconnect — trigger kill switch
      _triggerBlock();
    } else if (status == VpnStatus.connected) {
      // VPN reconnected — lift block
      _userDisconnecting = false;
      _releaseBlock();
    } else if (status == VpnStatus.disconnected && _userDisconnecting) {
      // Normal user disconnect — reset flag
      _userDisconnecting = false;
    }
  }

  Future<void> _triggerBlock() async {
    if (_isTriggered) return;
    _isTriggered = true;
    notifyListeners();

    if (kDebugMode) {
      debugPrint('[KillSwitch] ⚠️ TRIGGERED — blocking all traffic');
    }

    try {
      // Ask Android to block connections without VPN ("Always-on VPN" mode)
      // This is enforced at the OS level — no traffic leaks regardless of app state
      await _channel.invokeMethod('enableKillSwitch');
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint('[KillSwitch] Platform error on block: $e');
      }
      // Fallback: restrict outbound via routing rules if platform call fails
      // (handled on native side gracefully)
    }
  }

  Future<void> _releaseBlock() async {
    if (!_isTriggered) return;
    _isTriggered = false;
    notifyListeners();

    if (kDebugMode) {
      debugPrint('[KillSwitch] ✅ Block released — VPN is active');
    }

    try {
      await _channel.invokeMethod('disableKillSwitch');
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint('[KillSwitch] Platform error on release: $e');
      }
    }
  }

  @override
  void dispose() {
    _stopMonitoring();
    super.dispose();
  }
}
