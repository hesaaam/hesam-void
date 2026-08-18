import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_v2ray/flutter_v2ray.dart';
import 'package:path_provider/path_provider.dart';

import '../models/vpn_config.dart';

/// Owns the Windows Xray process for the desktop build.
///
/// The service deliberately starts exactly one native process and does not
/// poll in the background. Xray's native TUN inbound owns routing and Wintun;
/// Flutter only manages its lifecycle and renders its state.
class WindowsXrayService extends ChangeNotifier {
  WindowsXrayService._();

  static final WindowsXrayService instance = WindowsXrayService._();

  WindowsConnectionState _state = WindowsConnectionState.disconnected;
  String? _message;
  VpnConfig? _activeProfile;
  Process? _process;
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  String _lastNativeLog = '';

  WindowsConnectionState get state => _state;
  String? get message => _message;
  VpnConfig? get activeProfile => _activeProfile;
  bool get isRunning => _state == WindowsConnectionState.connected;
  bool get isBusy => _state == WindowsConnectionState.starting;
  String get lastNativeLog => _lastNativeLog;

  bool get isSupported => !kIsWeb && Platform.isWindows;

  /// Validates and writes the generated configuration without starting Xray.
  /// `xray run -test` is not a syntax-only probe for TUN: it attempts to open
  /// the adapter, which caused a false failure before the real process started.
  Future<WindowsValidationResult> validate(VpnConfig config) async {
    if (!isSupported) {
      return const WindowsValidationResult.unsupported();
    }

    try {
      await _prepareRuntimeFiles(config);
      return const WindowsValidationResult.valid();
    } catch (error) {
      return WindowsValidationResult.invalid(_safeNativeMessage('$error'));
    }
  }

  Future<void> connect(VpnConfig config) async {
    if (!isSupported) {
      _setState(
        WindowsConnectionState.failed,
        'Windows TUN mode is only available in the Windows desktop build.',
      );
      return;
    }

    if (_activeProfile?.id == config.id && isRunning) {
      await disconnect();
      return;
    }

    await disconnect(silent: true);
    _activeProfile = config;
    _setState(WindowsConnectionState.starting, 'Preparing protected route…');

    try {
      // A TUN configuration can only be validated by the elevated process
      // that owns the adapter. Start one managed Core process directly instead
      // of running a second `-test` process that would compete for the adapter.
      final files = await _prepareRuntimeFiles(config);
      final process = await Process.start(
        files.xray.path,
        <String>['run', '-c', files.config.path],
        workingDirectory: files.runtimeDirectory.path,
        mode: ProcessStartMode.normal,
        runInShell: false,
      );
      _process = process;
      _listenToNativeLogs(process);

      unawaited(
        process.exitCode.then((int code) {
          if (!identical(process, _process)) return;
          _process = null;
          if (_state == WindowsConnectionState.starting ||
              _state == WindowsConnectionState.connected) {
            _setState(
              WindowsConnectionState.failed,
              _safeNativeMessage(
                _lastNativeLog.isEmpty
                    ? 'Xray stopped unexpectedly (exit code $code).'
                    : _lastNativeLog,
              ),
            );
          }
        }),
      );

      // A surviving elevated Core process means the local TUN controller has
      // accepted the profile. No busy loop or periodic probe is started; this
      // keeps idle CPU usage near zero.
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      if (identical(process, _process)) {
        _setState(WindowsConnectionState.connected, 'TUN route is active');
      }
    } catch (error) {
      _process = null;
      _setState(WindowsConnectionState.failed, _safeNativeMessage('$error'));
    }
  }

  Future<void> disconnect({bool silent = false}) async {
    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    _stdoutSubscription = null;
    _stderrSubscription = null;

    final process = _process;
    _process = null;
    if (process != null) {
      process.kill();
      try {
        await process.exitCode.timeout(const Duration(seconds: 3));
      } on TimeoutException {
        process.kill();
      }
    }

    _activeProfile = null;
    if (!silent) {
      _setState(WindowsConnectionState.disconnected, 'Ready when you are');
    }
  }

  Future<void> disposeService() async {
    await disconnect(silent: true);
  }

  void _listenToNativeLogs(Process process) {
    _stdoutSubscription = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_captureNativeLog);
    _stderrSubscription = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_captureNativeLog);
  }

  void _captureNativeLog(String line) {
    if (line.trim().isEmpty) return;
    _lastNativeLog = _safeNativeMessage(line);
  }

  Future<_RuntimeFiles> _prepareRuntimeFiles(VpnConfig config) async {
    final support = await getApplicationSupportDirectory();
    final runtimeDirectory = Directory(
      '${support.path}${Platform.pathSeparator}runtime',
    );
    if (!await runtimeDirectory.exists()) {
      await runtimeDirectory.create(recursive: true);
    }

    final executableDirectory = File(Platform.resolvedExecutable).parent;
    final packagedRuntime = Directory(
      '${executableDirectory.path}${Platform.pathSeparator}data${Platform.pathSeparator}'
      'flutter_assets${Platform.pathSeparator}assets${Platform.pathSeparator}'
      'runtime${Platform.pathSeparator}win32',
    );
    final xray = File(
      '${packagedRuntime.path}${Platform.pathSeparator}xray.exe',
    );
    final wintun = File(
      '${packagedRuntime.path}${Platform.pathSeparator}wintun.dll',
    );

    if (!await xray.exists() || !await wintun.exists()) {
      throw StateError(
        'Windows runtime files are missing. Reinstall the official 4SUPER Windows package.',
      );
    }

    // Xray loads wintun.dll from its current working directory. Copy only when
    // a runtime changes; this avoids repeated disk I/O on every connection.
    final localXray = File(
      '${runtimeDirectory.path}${Platform.pathSeparator}xray.exe',
    );
    final localWintun = File(
      '${runtimeDirectory.path}${Platform.pathSeparator}wintun.dll',
    );
    await _copyIfChanged(xray, localXray);
    await _copyIfChanged(wintun, localWintun);

    final configFile = File(
      '${runtimeDirectory.path}${Platform.pathSeparator}active-xray.json',
    );
    await configFile.writeAsString(
      const JsonEncoder.withIndent(
        '  ',
      ).convert(_buildTunConfiguration(config)),
      flush: true,
    );
    return _RuntimeFiles(runtimeDirectory, localXray, configFile);
  }

  Future<void> _copyIfChanged(File source, File target) async {
    if (await target.exists() &&
        await source.length() == await target.length() &&
        await source.lastModified() == await target.lastModified()) {
      return;
    }
    await source.copy(target.path);
    await target.setLastModified(await source.lastModified());
  }

  Map<String, dynamic> _buildTunConfiguration(VpnConfig config) =>
      buildWindowsTunConfiguration(config.rawUrl);

  void _setState(WindowsConnectionState value, String? nextMessage) {
    _state = value;
    _message = nextMessage;
    notifyListeners();
  }

  String _safeNativeMessage(String value) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) return 'Windows Core could not start.';
    // Native diagnostics may echo a remote address. Keep desktop errors useful
    // but never surface an unbounded raw log in the UI.
    return normalized.length > 700
        ? '${normalized.substring(0, 697)}…'
        : normalized;
  }
}

/// Generates the Windows-native Xray configuration without touching disk or
/// starting a process. Keeping this pure makes the routing contract testable.
Map<String, dynamic> buildWindowsTunConfiguration(String rawUrl) {
  final parsed = FlutterV2ray.parseFromURL(rawUrl);
  final configuration =
      jsonDecode(parsed.getFullConfiguration()) as Map<String, dynamic>;
  _normalizeModernXrayConfiguration(configuration);

  configuration['log'] = <String, dynamic>{'loglevel': 'warning'};
  configuration['inbounds'] = <Map<String, dynamic>>[
    <String, dynamic>{
      'tag': 'super-tun',
      'protocol': 'tun',
      'settings': <String, dynamic>{
        'name': 'hesamvoid',
        'desc': 'Hesam Void 4SUPER',
        'mtu': 1500,
        'gateway': <String>['172.27.0.1/30', 'fd00:4::1/126'],
        'dns': <String>['1.1.1.1', '1.0.0.1'],
        'userLevel': 0,
        'autoSystemRoutingTable': <String>['0.0.0.0/0', '::/0'],
        // Prevent the Xray upstream itself from being sent into the new TUN.
        'autoOutboundsInterface': 'auto',
      },
    },
  ];
  configuration['routing'] = <String, dynamic>{
    'domainStrategy': 'AsIs',
    'rules': <Map<String, dynamic>>[],
  };
  return configuration;
}

/// Normalizes parser output for the bundled modern Xray Core without changing
/// the user's original URL. flutter_v2ray 1.0.9 still emits two legacy keys:
/// `publicKey` for Reality and `allowInsecure` for TLS. New Xray releases use
/// `password` for Reality and reject `allowInsecure` entirely, even when false.
void _normalizeModernXrayConfiguration(Object? node) {
  if (node is Map) {
    // Xray 26+ refuses this legacy field. Removing it preserves normal TLS
    // certificate validation; profiles that require insecure TLS are rejected
    // by their server trust chain instead of silently disabling verification.
    node.remove('allowInsecure');

    final reality = node['realitySettings'];
    if (reality is Map &&
        reality['password'] == null &&
        reality['publicKey'] != null) {
      reality['password'] = reality['publicKey'];
      reality.remove('publicKey');
    }
    for (final value in node.values) {
      _normalizeModernXrayConfiguration(value);
    }
  } else if (node is List) {
    for (final value in node) {
      _normalizeModernXrayConfiguration(value);
    }
  }
}

enum WindowsConnectionState { disconnected, starting, connected, failed }

class WindowsValidationResult {
  const WindowsValidationResult._(this.isValid, this.message);

  const WindowsValidationResult.valid()
    : this._(true, 'Xray configuration is valid');
  const WindowsValidationResult.unsupported()
    : this._(false, 'Windows validation is unavailable on this platform');
  const WindowsValidationResult.invalid(String message)
    : this._(false, message);

  final bool isValid;
  final String message;
}

class _RuntimeFiles {
  const _RuntimeFiles(this.runtimeDirectory, this.xray, this.config);

  final Directory runtimeDirectory;
  final File xray;
  final File config;
}
