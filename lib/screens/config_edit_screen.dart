import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/vpn_config.dart';
import '../providers/config_provider.dart';
import '../services/config_editor.dart';
import '../services/ping_service.dart';
import '../utils/night_signal.dart';
import '../widgets/night/route_widgets.dart';

/// Edits every part of a saved route, from a single link or a subscription.
///
/// Returns the saved [VpnConfig], or null when nothing was changed.
class ConfigEditScreen extends StatefulWidget {
  final VpnConfig config;
  final Color accent;

  const ConfigEditScreen({
    super.key,
    required this.config,
    required this.accent,
  });

  static Future<VpnConfig?> open(
    BuildContext context,
    VpnConfig config, {
    required Color accent,
  }) {
    return Navigator.of(context).push<VpnConfig>(
      MaterialPageRoute(
        builder: (_) => ConfigEditScreen(config: config, accent: accent),
      ),
    );
  }

  @override
  State<ConfigEditScreen> createState() => _ConfigEditScreenState();
}

enum _Mode { fields, link }

enum _Check { idle, running, ok, failed }

class _ConfigEditScreenState extends State<ConfigEditScreen> {
  late ConfigDraft _draft;
  final Map<EditField, TextEditingController> _controllers = {};
  final Map<EditField, bool> _revealed = {};
  final Set<EditSection> _open = {};
  late final TextEditingController _jsonController;
  late final TextEditingController _linkController;

  _Mode _mode = _Mode.fields;
  bool _dirty = false;
  bool _saving = false;
  String? _error;
  _Check _check = _Check.idle;
  int? _checkMs;

  Color get _accent => widget.accent;

  @override
  void initState() {
    super.initState();
    final draft = ConfigDraft.fromConfig(widget.config);
    _linkController = TextEditingController(text: widget.config.rawUrl);
    if (draft == null) {
      // A format without fields: it can still be edited as a link.
      _mode = _Mode.link;
      _draft = ConfigDraft.parse(
        'vless://placeholder@invalid:1',
        widget.config,
      )!;
    } else {
      _draft = draft;
    }
    _jsonController = TextEditingController(text: _draft.jsonText);
    _bindControllers();
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _jsonController.dispose();
    _linkController.dispose();
    super.dispose();
  }

  void _bindControllers() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _controllers.clear();
    for (final field in _draft.fields) {
      if (field.kind == EditKind.choice || field.kind == EditKind.toggle) {
        continue;
      }
      _controllers[field] = TextEditingController(text: field.value);
    }
  }

  void _edited() {
    if (!_dirty || _error != null || _check != _Check.idle) {
      setState(() {
        _dirty = true;
        _error = null;
        _check = _Check.idle;
      });
    }
  }

  // ---------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------

  /// The current state of the editor as a draft, from fields or link text.
  ConfigDraft _currentDraft() {
    if (_mode == _Mode.fields) return _draft;
    final parsed = ConfigDraft.parse(_linkController.text, widget.config);
    if (parsed == null) {
      throw const ConfigEditException(
        'This link could not be read. Supported links start with vless://, '
        'vmess://, trojan://, ss:// or npvt-ssh://.',
      );
    }
    return parsed;
  }

  void _switchMode(_Mode mode) {
    if (mode == _mode) return;
    try {
      if (mode == _Mode.link) {
        _linkController.text = _draft.buildLink();
      } else {
        _draft = _currentDraft();
        _jsonController.text = _draft.jsonText;
        _bindControllers();
      }
      setState(() {
        _mode = mode;
        _error = null;
      });
    } on ConfigEditException catch (e) {
      setState(() => _error = e.message);
    }
  }

  Future<void> _checkServer() async {
    FocusScope.of(context).unfocus();
    final VpnConfig preview;
    try {
      preview = _currentDraft().build();
    } on ConfigEditException catch (e) {
      setState(() => _error = e.message);
      return;
    }
    setState(() {
      _error = null;
      _check = _Check.running;
    });
    final ms = await PingService.testPing(
      preview.copyWith(id: 'edit-preview-${preview.id}'),
      useCache: false,
    );
    if (!mounted) return;
    setState(() {
      _checkMs = ms;
      _check = ms == null ? _Check.failed : _Check.ok;
    });
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final VpnConfig updated;
    try {
      updated = _currentDraft().build();
    } on ConfigEditException catch (e) {
      setState(() => _error = e.message);
      HapticFeedback.heavyImpact();
      return;
    }
    if (identical(updated, widget.config)) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _saving = true);
    final saved = await context.read<ConfigProvider>().replaceConfig(updated);
    if (!mounted) return;
    if (!saved) {
      setState(() {
        _saving = false;
        _error = 'The changes could not be saved. Try again.';
      });
      return;
    }
    _dirty = false;
    Navigator.of(context).pop(updated);
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
          'Your edits to this route have not been saved.',
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

  Future<void> _addParameter() async {
    final key = TextEditingController();
    final value = TextEditingController();
    String? problem;
    final added = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, setDialogState) => AlertDialog(
          backgroundColor: NightSignal.raised,
          title: const Text(
            'Add parameter',
            style: TextStyle(color: NightSignal.text),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: key,
                autofocus: true,
                style: const TextStyle(color: NightSignal.text),
                decoration: _decoration('Name', hint: 'allowInsecure'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: value,
                style: const TextStyle(color: NightSignal.text),
                decoration: _decoration('Value'),
              ),
              if (problem != null) ...[
                const SizedBox(height: 10),
                Text(
                  problem!,
                  style: const TextStyle(color: NightSignal.danger),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text(
                'Cancel',
                style: TextStyle(color: NightSignal.muted),
              ),
            ),
            TextButton(
              onPressed: () {
                final result = _draft.addParameter(key.text, value.text);
                if (result != null) {
                  setDialogState(() => problem = result);
                } else {
                  Navigator.pop(dialog, true);
                }
              },
              child: Text('Add', style: TextStyle(color: _accent)),
            ),
          ],
        ),
      ),
    );
    key.dispose();
    value.dispose();
    if (added == true) {
      _bindControllers();
      _edited();
      setState(() {});
    }
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
          title: const Text('Edit route'),
          actions: [
            TextButton(
              onPressed: _saving ? null : _save,
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
            children: [
              _header(),
              if (!_draft.isJson) ...[
                const SizedBox(height: 14),
                _modeSwitch(),
              ],
              const SizedBox(height: 14),
              if (_mode == _Mode.link)
                _linkEditor()
              else ...[
                _serverCard(),
                if (_draft.isJson)
                  _jsonEditor()
                else
                  for (final section in const [
                    EditSection.identity,
                    EditSection.transport,
                    EditSection.security,
                    EditSection.advanced,
                  ])
                    _sectionCard(section),
              ],
            ],
          ),
        ),
        bottomNavigationBar: _bottomBar(),
      ),
    );
  }

  Widget _header() {
    final config = widget.config;
    final protocolColor = RouteRow.protocolColor(config.protocol, _accent);
    final provider = context.read<ConfigProvider>();
    final subscription = config.subscriptionId == null
        ? null
        : provider.subscriptionById(config.subscriptionId!);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: NightSignal.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: protocolColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  config.isJson
                      ? 'JSON · ${(config.flow ?? '').toUpperCase()}'
                      : config.protocol.displayName,
                  style: NightSignal.number(size: 11, color: protocolColor),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  config.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NightSignal.title(size: 17),
                ),
              ),
            ],
          ),
          if (subscription != null) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.folder_special_rounded,
                  size: 16,
                  color: NightSignal.muted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'From ${subscription.name}. Updating the subscription '
                    'may bring back the provider\'s version of this route.',
                    style: const TextStyle(
                      color: NightSignal.muted,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _modeSwitch() {
    Widget option(_Mode mode, IconData icon, String label) {
      final active = _mode == mode;
      return Expanded(
        child: Semantics(
          button: true,
          selected: active,
          child: GestureDetector(
            onTap: () => _switchMode(mode),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: active ? NightSignal.raised : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: active ? NightSignal.lineStrong : Colors.transparent,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 16,
                    color: active ? _accent : NightSignal.muted,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      color: active ? NightSignal.text : NightSignal.muted,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: NightSignal.card(radius: 16),
      child: Row(
        children: [
          option(_Mode.fields, Icons.tune_rounded, 'Fields'),
          option(_Mode.link, Icons.link_rounded, 'Link'),
        ],
      ),
    );
  }

  Widget _serverCard() {
    final name = _draft.field(ConfigDraft.nameKey);
    final address = _draft.field(ConfigDraft.addressKey);
    final port = _draft.field(ConfigDraft.portKey);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      decoration: NightSignal.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('SERVER', style: NightSignal.eyebrow()),
          const SizedBox(height: 12),
          _input(name),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _input(address)),
              const SizedBox(width: 10),
              SizedBox(width: 104, child: _input(port)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionCard(EditSection section) {
    final fields = _draft.section(section);
    final advanced = section == EditSection.advanced;
    if (fields.isEmpty && !(advanced && _draft.supportsCustomParameters)) {
      return const SizedBox.shrink();
    }
    final open = _open.contains(section);
    final edited = fields.any((f) => f.changed);
    final filled = fields.where((f) => f.value.isNotEmpty).length;
    final (title, icon) = switch (section) {
      EditSection.identity => ('Identity', Icons.key_rounded),
      EditSection.transport => ('Transport', Icons.swap_horiz_rounded),
      EditSection.security => ('Security', Icons.shield_outlined),
      EditSection.advanced => ('Advanced', Icons.data_object_rounded),
      EditSection.server => ('Server', Icons.dns_rounded),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        decoration: NightSignal.card(),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            InkWell(
              onTap: () => setState(
                () => open ? _open.remove(section) : _open.add(section),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Icon(icon, size: 18, color: NightSignal.soft),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: NightSignal.text,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    if (edited)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          'Edited',
                          style: TextStyle(color: _accent, fontSize: 12),
                        ),
                      )
                    else if (filled > 0)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          '$filled set',
                          style: const TextStyle(
                            color: NightSignal.muted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    AnimatedRotation(
                      turns: open ? 0.5 : 0,
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
              child: open
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final field in fields) _fieldWidget(field),
                          if (advanced && _draft.supportsCustomParameters)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: _addParameter,
                                icon: Icon(
                                  Icons.add_rounded,
                                  size: 18,
                                  color: _accent,
                                ),
                                label: Text(
                                  'Add parameter',
                                  style: TextStyle(color: _accent),
                                ),
                              ),
                            ),
                        ],
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fieldWidget(EditField field) {
    switch (field.kind) {
      case EditKind.choice:
        return _choice(field);
      case EditKind.toggle:
        return _toggle(field);
      case EditKind.text:
      case EditKind.number:
      case EditKind.multiline:
        return _input(field);
    }
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

  Widget _input(EditField field) {
    final controller = _controllers[field]!;
    final hidden = field.secret && !(_revealed[field] ?? false);
    final number = field.kind == EditKind.number;
    final multiline = field.kind == EditKind.multiline;
    Widget? suffix;
    if (field.secret) {
      suffix = IconButton(
        tooltip: hidden ? 'Show' : 'Hide',
        icon: Icon(
          hidden ? Icons.visibility_rounded : Icons.visibility_off_rounded,
          size: 20,
          color: NightSignal.muted,
        ),
        onPressed: () => setState(() => _revealed[field] = hidden),
      );
    } else if (field.custom) {
      suffix = IconButton(
        tooltip: 'Remove parameter',
        icon: const Icon(
          Icons.remove_circle_outline_rounded,
          size: 20,
          color: NightSignal.danger,
        ),
        onPressed: () {
          _draft.removeField(field);
          _controllers.remove(field)?.dispose();
          _edited();
          setState(() {});
        },
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        obscureText: hidden,
        autocorrect: false,
        enableSuggestions: false,
        keyboardType: number
            ? TextInputType.number
            : multiline
            ? TextInputType.multiline
            : (field.key == ConfigDraft.addressKey
                  ? TextInputType.url
                  : TextInputType.text),
        inputFormatters: number
            ? [FilteringTextInputFormatter.digitsOnly]
            : null,
        minLines: multiline ? 3 : 1,
        maxLines: multiline ? 8 : 1,
        style: TextStyle(
          color: NightSignal.text,
          fontFamily: field.key == ConfigDraft.nameKey
              ? null
              : NightSignal.mono,
          fontSize: 14,
        ),
        decoration: _decoration(field.label, hint: field.hint, suffix: suffix),
        onChanged: (text) {
          field.value = text;
          _edited();
        },
      ),
    );
  }

  Widget _choice(EditField field) {
    final options = [
      if (field.key != ConfigDraft.methodKey) '',
      ...field.options,
      if (field.value.isNotEmpty && !field.options.contains(field.value))
        field.value,
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        key: ObjectKey(field),
        initialValue: options.contains(field.value) ? field.value : null,
        isExpanded: true,
        dropdownColor: NightSignal.raised,
        iconEnabledColor: NightSignal.muted,
        style: const TextStyle(
          color: NightSignal.text,
          fontFamily: NightSignal.mono,
          fontSize: 14,
        ),
        decoration: _decoration(field.label),
        items: [
          for (final option in options)
            DropdownMenuItem(
              value: option,
              child: Text(
                option.isEmpty ? 'Not set' : option,
                overflow: TextOverflow.ellipsis,
                style: option.isEmpty
                    ? const TextStyle(color: NightSignal.muted)
                    : null,
              ),
            ),
        ],
        onChanged: (value) {
          field.value = value ?? '';
          _edited();
          setState(() {});
        },
      ),
    );
  }

  Widget _toggle(EditField field) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        title: Text(
          field.label,
          style: const TextStyle(color: NightSignal.text, fontSize: 14),
        ),
        value: field.value == 'true',
        activeThumbColor: _accent,
        onChanged: (on) {
          field.value = '$on';
          _edited();
          setState(() {});
        },
      ),
    );
  }

  Widget _monoEditor({
    required TextEditingController controller,
    required String label,
    required String help,
    required int minLines,
    required ValueChanged<String> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: NightSignal.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: NightSignal.eyebrow())),
              IconButton(
                tooltip: 'Copy',
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  Icons.copy_rounded,
                  size: 18,
                  color: NightSignal.muted,
                ),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: controller.text));
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('Copied')));
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            help,
            style: const TextStyle(
              color: NightSignal.muted,
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            minLines: minLines,
            maxLines: null,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.multiline,
            style: const TextStyle(
              color: NightSignal.text,
              fontFamily: NightSignal.mono,
              fontSize: 12.5,
              height: 1.4,
            ),
            decoration: _decoration('').copyWith(labelText: null),
            onChanged: (text) {
              onChanged(text);
              _edited();
            },
          ),
        ],
      ),
    );
  }

  Widget _linkEditor() {
    return _monoEditor(
      controller: _linkController,
      label: 'LINK',
      help:
          'Edit or paste the whole link. It replaces this route when you '
          'save, and keeps its place, favorite and history.',
      minLines: 5,
      onChanged: (_) {},
    );
  }

  Widget _jsonEditor() {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: _monoEditor(
        controller: _jsonController,
        label: 'FULL CONFIGURATION',
        help:
            'The complete Xray JSON. Server address and port above are '
            'applied to its first server outbound.',
        minLines: 14,
        onChanged: (text) => _draft.jsonText = text,
      ),
    );
  }

  Widget _bottomBar() {
    Widget? status;
    if (_error != null) {
      status = _statusLine(
        Icons.error_outline_rounded,
        _error!,
        NightSignal.danger,
      );
    } else if (_check == _Check.ok) {
      status = _statusLine(
        Icons.check_circle_rounded,
        'Server answered in $_checkMs ms',
        NightSignal.forLatency(_checkMs, good: _accent),
      );
    } else if (_check == _Check.failed) {
      status = _statusLine(
        Icons.portable_wifi_off_rounded,
        'No answer from this address and port',
        NightSignal.warning,
      );
    }
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
              child: status == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: status,
                    ),
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _check == _Check.running || _saving
                        ? null
                        : _checkServer,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: NightSignal.text,
                      side: const BorderSide(color: NightSignal.lineStrong),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: _check == _Check.running
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: NightSignal.warning,
                            ),
                          )
                        : const Icon(Icons.speed_rounded, size: 18),
                    label: const Text('Check server'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: NightSignal.background,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text(
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

  Widget _statusLine(IconData icon, String text, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: color, fontSize: 13, height: 1.35),
          ),
        ),
      ],
    );
  }
}
