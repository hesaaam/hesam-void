import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/config_provider.dart';
import '../services/subscription_service.dart';

/// Bottom sheet for adding a subscription link. It downloads the
/// subscription itself and reports problems inline, so the user can fix the
/// link without starting over. Returns the result on success.
class AddSubscriptionSheet extends StatefulWidget {
  final Color accentColor;
  final Color surfaceColor;
  final Color textColor;

  const AddSubscriptionSheet({
    super.key,
    required this.accentColor,
    required this.surfaceColor,
    required this.textColor,
  });

  static Future<ImportResult?> show(
    BuildContext context, {
    required Color accentColor,
    required Color surfaceColor,
    required Color textColor,
  }) {
    return showModalBottomSheet<ImportResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddSubscriptionSheet(
        accentColor: accentColor,
        surfaceColor: surfaceColor,
        textColor: textColor,
      ),
    );
  }

  @override
  State<AddSubscriptionSheet> createState() => _AddSubscriptionSheetState();
}

class _AddSubscriptionSheetState extends State<AddSubscriptionSheet> {
  final _urlController = TextEditingController();
  final _nameController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _prefillFromClipboard();
  }

  Future<void> _prefillFromClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim() ?? '';
      if (mounted &&
          _urlController.text.isEmpty &&
          SubscriptionService.parseUrl(text) != null) {
        setState(() => _urlController.text = text);
      }
    } catch (_) {
      // Clipboard access is optional.
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (SubscriptionService.parseUrl(_urlController.text) == null) {
      setState(() => _error = 'Enter a link that starts with https://');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await context.read<ConfigProvider>().addSubscription(
      _urlController.text,
      name: _nameController.text,
    );
    if (!mounted) return;
    if (result.success) {
      Navigator.of(context).pop(result);
    } else {
      setState(() {
        _busy = false;
        _error = result.message;
      });
    }
  }

  InputDecoration _decoration(String label, IconData icon, {String? hint}) {
    final text = widget.textColor;
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, color: text.withValues(alpha: 0.6)),
      labelStyle: TextStyle(color: text.withValues(alpha: 0.7)),
      hintStyle: TextStyle(color: text.withValues(alpha: 0.35)),
      filled: true,
      fillColor: text.withValues(alpha: 0.05),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: text.withValues(alpha: 0.15)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: widget.accentColor, width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.textColor;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          decoration: BoxDecoration(
            color: widget.surfaceColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            border: Border.all(
              color: widget.accentColor.withValues(alpha: 0.25),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: text.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Icon(Icons.folder_special_rounded, color: widget.accentColor),
                  const SizedBox(width: 10),
                  Text(
                    'Add subscription',
                    style: TextStyle(
                      color: text,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Its routes are kept together in one folder and can be '
                'updated with one tap.',
                style: TextStyle(
                  color: text.withValues(alpha: 0.6),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _urlController,
                enabled: !_busy,
                keyboardType: TextInputType.url,
                autocorrect: false,
                style: TextStyle(color: text),
                decoration: _decoration(
                  'Subscription link',
                  Icons.link_rounded,
                  hint: 'https://…',
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameController,
                enabled: !_busy,
                textInputAction: TextInputAction.done,
                style: TextStyle(color: text),
                decoration: _decoration(
                  'Folder name (optional)',
                  Icons.drive_file_rename_outline_rounded,
                  hint: 'Uses the provider name when empty',
                ),
                onSubmitted: (_) => _submit(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: Color(0xFFFF5C6C),
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          color: Color(0xFFFF5C6C),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _submit,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : const Icon(Icons.download_rounded),
                  label: Text(_busy ? 'DOWNLOADING…' : 'ADD SUBSCRIPTION'),
                  style: FilledButton.styleFrom(
                    backgroundColor: widget.accentColor,
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: widget.accentColor.withValues(
                      alpha: 0.5,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
