import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/ssh_config.dart';
import '../models/vpn_config.dart';
import '../providers/config_provider.dart';
import '../services/config_editor.dart';
import '../services/config_parser_service.dart';
import '../utils/night_signal.dart';
import '../widgets/ssh_check_sheet.dart';

/// What the form returns: the saved route and whether to connect now.
class SshFormResult {
  final VpnConfig config;
  final bool connect;
  const SshFormResult(this.config, {this.connect = false});
}

/// Adds or edits an SSH server with the fields a typical SSH account has.
class SshFormScreen extends StatefulWidget {
  final VpnConfig? existing;
  final Color accent;

  const SshFormScreen({super.key, this.existing, required this.accent});

  static Future<SshFormResult?> open(
    BuildContext context, {
    VpnConfig? existing,
    required Color accent,
  }) {
    return Navigator.of(context).push<SshFormResult>(
      MaterialPageRoute(
        builder: (_) => SshFormScreen(existing: existing, accent: accent),
      ),
    );
  }

  @override
  State<SshFormScreen> createState() => _SshFormScreenState();
}

enum _Auth { password, key }

class _SshFormScreenState extends State<SshFormScreen> {
  final _name = TextEditingController();
  final _host = TextEditingController();
  final _port = TextEditingController(text: '22');
  final _user = TextEditingController();
  final _password = TextEditingController();
  final _key = TextEditingController();
  final _keyPass = TextEditingController();
  final _sni = TextEditingController();
  final _wsPath = TextEditingController();
  final _wsHost = TextEditingController();
  final _proxy = TextEditingController();
  final _payload = TextEditingController();
  final _udpgw = TextEditingController(text: '7300');
  final _dns = TextEditingController();

  SshConfigType _type = SshConfigType.direct;
  _Auth _auth = _Auth.password;
  bool _wsTls = false;
  bool _wsFraming = false;
  bool _udpgwDns = true;
  bool _showPassword = false;
  bool _advancedOpen = false;
  bool _dirty = false;
  bool _saving = false;
  String? _error;

  Color get _accent => widget.accent;
  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      final ssh = SshConfig.tryParse(existing.rawUrl, existing.id);
      if (ssh != null) _fill(ssh);
      _name.text = existing.name;
    }
    for (final controller in _controllers) {
      controller.addListener(_markDirty);
    }
  }

  List<TextEditingController> get _controllers => [
    _name,
    _host,
    _port,
    _user,
    _password,
    _key,
    _keyPass,
    _sni,
    _wsPath,
    _wsHost,
    _proxy,
    _payload,
    _udpgw,
    _dns,
  ];

  void _markDirty() {
    if (!_dirty || _error != null) {
      setState(() {
        _dirty = true;
        _error = null;
      });
    }
  }

  void _fill(SshConfig ssh) {
    _name.text = ssh.remarks;
    _host.text = ssh.sshHost;
    _port.text = '${ssh.sshPort}';
    _user.text = ssh.sshUsername;
    _password.text = ssh.sshPassword;
    _key.text = ssh.privateKey ?? '';
    _keyPass.text = ssh.keyPassphrase ?? '';
    _sni.text = ssh.sni ?? '';
    _wsPath.text = ssh.wsPath ?? '';
    _wsHost.text = ssh.wsHost ?? '';
    _proxy.text = ssh.httpProxy ?? '';
    _payload.text = ssh.payload ?? '';
    _udpgw.text = ssh.udpEnabled ? '${ssh.udpgwPort}' : '';
    _dns.text = ssh.dnsServer ?? '';
    _type = ssh.configType == SshConfigType.slowDns
        ? SshConfigType.direct
        : ssh.configType;
    _auth = ssh.usesPrivateKey ? _Auth.key : _Auth.password;
    _wsTls = ssh.wsTls;
    _wsFraming = ssh.wsFraming;
    _udpgwDns = ssh.udpgwTransparentDNS;
    _advancedOpen =
        (ssh.payload ?? '').isNotEmpty ||
        (ssh.httpProxy ?? '').isNotEmpty ||
        (ssh.dnsServer ?? '').isNotEmpty;
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pasteLink() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    final ssh = SshConfig.tryParse(text, 'paste');
    if (ssh == null) {
      setState(
        () => _error =
            'The clipboard has no SSH link. Copy an ssh:// or npvt-ssh:// link first.',
      );
      return;
    }
    setState(() {
      _fill(ssh);
      _dirty = true;
      _error = null;
    });
  }

  /// The form as a profile, or null with [_error] set.
  SshConfig? _build() {
    String? text(TextEditingController c) {
      final value = c.text.trim();
      return value.isEmpty ? null : value;
    }

    final host = _host.text.trim();
    final port = int.tryParse(_port.text.trim());
    final user = _user.text.trim();
    String? problem;
    if (host.isEmpty || host.contains(RegExp(r'\s'))) {
      problem = 'Enter the SSH host without spaces.';
    } else if (port == null || port < 1 || port > 65535) {
      problem = 'Port must be a number from 1 to 65535.';
    } else if (user.isEmpty) {
      problem = 'Enter the SSH username.';
    } else if (_auth == _Auth.password && _password.text.isEmpty) {
      problem = 'Enter the SSH password.';
    } else if (_auth == _Auth.key && _key.text.trim().isEmpty) {
      problem = 'Paste the private key.';
    } else if (_udpgw.text.trim().isNotEmpty &&
        (int.tryParse(_udpgw.text.trim()) == null)) {
      problem = 'UDPGW port must be a number.';
    } else if (_type == SshConfigType.ssl && _proxy.text.trim().isNotEmpty) {
      problem = 'An HTTP proxy cannot be combined with SSL/TLS yet.';
    }
    if (problem != null) {
      setState(() => _error = problem);
      HapticFeedback.heavyImpact();
      return null;
    }
    final name = _name.text.trim();
    return SshConfig(
      id: widget.existing?.id ?? const Uuid().v4(),
      remarks: name.isEmpty ? '$user@$host' : name,
      configType: _type,
      sshHost: host,
      sshPort: port!,
      sshUsername: user,
      sshPassword: _auth == _Auth.password ? _password.text : '',
      privateKey: _auth == _Auth.key ? _key.text.trim() : null,
      keyPassphrase: _auth == _Auth.key ? text(_keyPass) : null,
      sni: _type == SshConfigType.direct ? null : text(_sni),
      wsPath: _type == SshConfigType.websocket ? text(_wsPath) : null,
      wsHost: _type == SshConfigType.websocket ? text(_wsHost) : null,
      wsTls: _type == SshConfigType.websocket && _wsTls,
      wsFraming: _type == SshConfigType.websocket && _wsFraming,
      httpProxy: text(_proxy),
      payload: _payload.text.trim().isEmpty ? null : _payload.text,
      udpgwPort: int.tryParse(_udpgw.text.trim()) ?? 0,
      udpgwTransparentDNS: _udpgwDns,
      dnsServer: text(_dns),
    );
  }

  Future<void> _check() async {
    FocusScope.of(context).unfocus();
    final ssh = _build();
    if (ssh == null) return;
    final choice = await SshCheckSheet.show(context, ssh, accent: _accent);
    if (choice == SshCheckChoice.saveAndConnect && mounted) {
      await _save(connect: true);
    }
  }

  Future<void> _save({bool connect = false}) async {
    FocusScope.of(context).unfocus();
    final ssh = _build();
    if (ssh == null) return;
    final provider = context.read<ConfigProvider>();
    final existing = widget.existing;
    var route = ConfigParserService.sshVpnConfig(ssh, rawUrl: ssh.toSshUrl());
    if (existing != null) {
      final reset = ConfigDraft.connectionDiffers(route, existing);
      route = route.copyWith(
        id: existing.id,
        createdAt: existing.createdAt,
        isActive: existing.isActive,
        country: existing.country,
        countryCode: existing.countryCode,
        subscriptionId: existing.subscriptionId,
        ping: reset ? null : existing.ping,
        lastTestedAt: reset ? null : existing.lastTestedAt,
        clearPing: reset,
      );
    }
    setState(() => _saving = true);
    final ok = existing != null
        ? await provider.replaceConfig(route)
        : await provider.addConfig(route);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _saving = false;
        _error = existing == null
            ? 'This SSH server is already saved.'
            : 'The changes could not be saved. Try again.';
      });
      return;
    }
    _dirty = false;
    Navigator.of(context).pop(SshFormResult(route, connect: connect));
  }

  Future<bool> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        backgroundColor: NightSignal.raised,
        title: const Text(
          'Discard changes?',
          style: TextStyle(color: NightSignal.text),
        ),
        content: const Text(
          'This SSH server has not been saved.',
          style: TextStyle(color: NightSignal.soft),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: Text('Keep editing', style: TextStyle(color: _accent)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text(
              'Discard',
              style: TextStyle(color: NightSignal.danger),
            ),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  // ---------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty || _saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmDiscard() && mounted) {
          _dirty = false;
          navigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: NightSignal.background,
        appBar: AppBar(
          backgroundColor: NightSignal.background,
          foregroundColor: NightSignal.text,
          surfaceTintColor: Colors.transparent,
          title: Text(_editing ? 'Edit SSH server' : 'Add SSH server'),
          actions: [
            TextButton(
              onPressed: _saving ? null : () => _save(),
              child: Text(
                'Save',
                style: TextStyle(color: _accent, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 6),
          ],
        ),
        body: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              _pasteCard(),
              const SizedBox(height: 12),
              _card('SERVER', [
                _field(_name, 'Name', hint: 'My SSH'),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _field(
                        _host,
                        'SSH host',
                        hint: 'ssh.example.com',
                        mono: true,
                        keyboard: TextInputType.url,
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 96,
                      child: _field(_port, 'Port', mono: true, number: true),
                    ),
                  ],
                ),
              ]),
              const SizedBox(height: 12),
              _card('CONNECTION TYPE', [
                _segmented<SshConfigType>(
                  const [
                    (SshConfigType.direct, 'Direct'),
                    (SshConfigType.ssl, 'SSL / TLS'),
                    (SshConfigType.websocket, 'WebSocket'),
                  ],
                  _type,
                  (value) => setState(() {
                    _type = value;
                    _dirty = true;
                    if (value == SshConfigType.ssl && _port.text == '22') {
                      _port.text = '443';
                    }
                  }),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: Column(
                    children: [
                      if (_type != SshConfigType.direct) ...[
                        const SizedBox(height: 12),
                        _field(
                          _sni,
                          'SNI (server name sent in TLS)',
                          hint: _type == SshConfigType.websocket
                              ? 'Only for WebSocket over TLS'
                              : 'allowed.example.com',
                          mono: true,
                        ),
                      ],
                      if (_type == SshConfigType.websocket) ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _field(
                                _wsPath,
                                'Path',
                                hint: '/',
                                mono: true,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _field(
                                _wsHost,
                                'Host header',
                                hint: 'cdn.example.com',
                                mono: true,
                              ),
                            ),
                          ],
                        ),
                        _switch(
                          'WebSocket over TLS (wss)',
                          'Usually on for port 443',
                          _wsTls,
                          (v) => setState(() {
                            _wsTls = v;
                            _dirty = true;
                          }),
                        ),
                      ],
                    ],
                  ),
                ),
                if (_type == SshConfigType.direct)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Text(
                      'SSL / TLS adds an SNI field; WebSocket adds path and Host header.',
                      style: TextStyle(
                        color: NightSignal.muted,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
              ]),
              const SizedBox(height: 12),
              _card('SIGN-IN', [
                _field(_user, 'Username', mono: true),
                _segmented<_Auth>(
                  const [
                    (_Auth.password, 'Password'),
                    (_Auth.key, 'Private key'),
                  ],
                  _auth,
                  (value) => setState(() {
                    _auth = value;
                    _dirty = true;
                  }),
                ),
                const SizedBox(height: 12),
                if (_auth == _Auth.password)
                  _field(
                    _password,
                    'Password',
                    obscure: !_showPassword,
                    suffix: IconButton(
                      tooltip: _showPassword ? 'Hide' : 'Show',
                      icon: Icon(
                        _showPassword
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        size: 20,
                        color: NightSignal.muted,
                      ),
                      onPressed: () =>
                          setState(() => _showPassword = !_showPassword),
                    ),
                  )
                else ...[
                  _field(
                    _key,
                    'Private key',
                    hint: '-----BEGIN OPENSSH PRIVATE KEY-----',
                    mono: true,
                    lines: 5,
                  ),
                  _field(_keyPass, 'Key passphrase (if any)', obscure: true),
                ],
              ]),
              const SizedBox(height: 12),
              _card('CALLS, GAMES & DNS', [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    SizedBox(
                      width: 120,
                      child: _field(
                        _udpgw,
                        'UDPGW port',
                        hint: 'none',
                        mono: true,
                        number: true,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(bottom: 18),
                        child: Text(
                          'Carries voice and video calls and games. Leave empty if your server has no UDP gateway.',
                          style: TextStyle(
                            color: NightSignal.muted,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                _switch(
                  'DNS through the UDP gateway',
                  'The server answers DNS; safest on filtered networks.',
                  _udpgwDns,
                  (v) => setState(() {
                    _udpgwDns = v;
                    _dirty = true;
                  }),
                ),
              ]),
              const SizedBox(height: 12),
              _advanced(),
            ],
          ),
        ),
        bottomNavigationBar: _bottomBar(),
      ),
    );
  }

  Widget _pasteCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: NightSignal.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NightSignal.lineStrong),
      ),
      child: Row(
        children: [
          const Icon(Icons.link_rounded, size: 18, color: NightSignal.soft),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Have a link? Paste ssh:// or npvt-ssh:// to fill the form.',
              style: TextStyle(
                color: NightSignal.soft,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
          TextButton(
            onPressed: _pasteLink,
            style: TextButton.styleFrom(
              foregroundColor: NightSignal.text,
              backgroundColor: NightSignal.raised,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Paste'),
          ),
        ],
      ),
    );
  }

  Widget _card(String title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      decoration: NightSignal.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: NightSignal.eyebrow()),
          const SizedBox(height: 12),
          ...children,
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _advanced() {
    return Container(
      decoration: NightSignal.card(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _advancedOpen = !_advancedOpen),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  const Icon(
                    Icons.tune_rounded,
                    size: 18,
                    color: NightSignal.soft,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Advanced',
                          style: TextStyle(
                            color: NightSignal.text,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Custom DNS server · Payload · HTTP proxy',
                          style: TextStyle(
                            color: NightSignal.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: _advancedOpen ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(
                      Icons.expand_more_rounded,
                      color: NightSignal.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !_advancedOpen
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _field(
                          _dns,
                          'DNS server',
                          hint: '1.1.1.1 (used when there is no UDP gateway)',
                          mono: true,
                        ),
                        _field(
                          _payload,
                          'Payload',
                          hint: 'GET / HTTP/1.1[crlf]Host: [host][crlf][crlf]',
                          mono: true,
                          lines: 4,
                        ),
                        _field(
                          _proxy,
                          'HTTP proxy',
                          hint: 'host:port',
                          mono: true,
                        ),
                        if (_type == SshConfigType.websocket)
                          _switch(
                            'WebSocket frames',
                            'Only for servers such as websockify; most SSH WebSocket servers relay raw data.',
                            _wsFraming,
                            (v) => setState(() {
                              _wsFraming = v;
                              _dirty = true;
                            }),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  InputDecoration _decoration(String label, {String? hint, Widget? suffix}) {
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: color),
    );
    return InputDecoration(
      labelText: label,
      hintText: hint,
      suffixIcon: suffix,
      filled: true,
      fillColor: NightSignal.raised,
      labelStyle: const TextStyle(color: NightSignal.muted),
      floatingLabelStyle: TextStyle(color: _accent),
      hintStyle: const TextStyle(color: NightSignal.faint),
      enabledBorder: border(NightSignal.line),
      focusedBorder: border(_accent),
      border: border(NightSignal.line),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    bool mono = false,
    bool number = false,
    bool obscure = false,
    int lines = 1,
    TextInputType? keyboard,
    Widget? suffix,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        autocorrect: false,
        enableSuggestions: false,
        minLines: lines,
        maxLines: lines == 1 ? 1 : lines + 3,
        keyboardType: number
            ? TextInputType.number
            : lines > 1
            ? TextInputType.multiline
            : keyboard ?? TextInputType.text,
        inputFormatters: number
            ? [FilteringTextInputFormatter.digitsOnly]
            : null,
        style: TextStyle(
          color: NightSignal.text,
          fontFamily: mono ? NightSignal.mono : null,
          fontSize: mono ? 13 : 14,
        ),
        decoration: _decoration(label, hint: hint, suffix: suffix),
      ),
    );
  }

  Widget _segmented<T>(
    List<(T, String)> options,
    T selected,
    ValueChanged<T> onChanged,
  ) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: NightSignal.background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (final (value, label) in options)
            Expanded(
              child: Semantics(
                button: true,
                selected: value == selected,
                child: GestureDetector(
                  onTap: () => onChanged(value),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: value == selected
                          ? NightSignal.raised
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: value == selected
                            ? NightSignal.lineStrong
                            : Colors.transparent,
                      ),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        color: value == selected
                            ? NightSignal.text
                            : NightSignal.muted,
                        fontSize: 13,
                        fontWeight: value == selected
                            ? FontWeight.w600
                            : FontWeight.w400,
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

  Widget _switch(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        title,
        style: const TextStyle(color: NightSignal.text, fontSize: 14),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: NightSignal.muted, fontSize: 12),
      ),
      value: value,
      activeThumbColor: _accent,
      onChanged: onChanged,
    );
  }

  Widget _bottomBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: const BoxDecoration(
          color: NightSignal.surface,
          border: Border(top: BorderSide(color: NightSignal.line)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              child: _error == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            size: 18,
                            color: NightSignal.danger,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                color: NightSignal.danger,
                                fontSize: 13,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving ? null : _check,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: NightSignal.text,
                      side: const BorderSide(color: NightSignal.lineStrong),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.fact_check_outlined, size: 18),
                    label: const Text('Check server'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: _saving ? null : () => _save(),
                    style: FilledButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: NightSignal.background,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Save',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
