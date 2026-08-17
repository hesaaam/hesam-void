import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/vpn_config.dart';
import '../utils/app_theme.dart';

/// QR Code Display Dialog
class QRDisplayDialog extends StatelessWidget {
  final VpnConfig config;

  const QRDisplayDialog({super.key, required this.config});

  static Future<void> show(BuildContext context, VpnConfig config) {
    return showDialog(
      context: context,
      builder: (context) => QRDisplayDialog(config: config),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child:
          Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppTheme.backgroundCard,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: AppTheme.primaryGreen.withValues(alpha: 0.3),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryGreen.withValues(alpha: 0.2),
                      blurRadius: 30,
                      spreadRadius: 0,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryGreen.withValues(
                              alpha: 0.15,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.qr_code_rounded,
                            color: AppTheme.primaryGreen,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Export QR Code',
                                style: TextStyle(
                                  color: AppTheme.primaryGreen,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'JetBrainsMono',
                                ),
                              ),
                              Text(
                                config.name,
                                style: const TextStyle(
                                  color: AppTheme.textMuted,
                                  fontSize: 12,
                                  fontFamily: 'JetBrainsMono',
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                          color: AppTheme.textMuted,
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // QR Code
                    Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primaryGreen.withValues(
                                  alpha: 0.3,
                                ),
                                blurRadius: 20,
                                spreadRadius: 0,
                              ),
                            ],
                          ),
                          child: QrImageView(
                            data: config.rawUrl,
                            version: QrVersions.auto,
                            size: 220,
                            backgroundColor: Colors.white,
                            eyeStyle: const QrEyeStyle(
                              eyeShape: QrEyeShape.square,
                              color: Color(0xFF0A0A0A),
                            ),
                            dataModuleStyle: const QrDataModuleStyle(
                              dataModuleShape: QrDataModuleShape.square,
                              color: Color(0xFF0A0A0A),
                            ),
                          ),
                        )
                        .animate()
                        .fadeIn(duration: 400.ms)
                        .scale(
                          begin: const Offset(0.8, 0.8),
                          end: const Offset(1, 1),
                        ),

                    const SizedBox(height: 20),

                    // Protocol info
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.getProtocolColor(
                          config.protocolString,
                        ).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppTheme.getProtocolColor(
                            config.protocolString,
                          ).withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        config.subtitle,
                        style: TextStyle(
                          color: AppTheme.getProtocolColor(
                            config.protocolString,
                          ),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'JetBrainsMono',
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Copy button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: config.rawUrl));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Row(
                                children: [
                                  Icon(
                                    Icons.check_circle,
                                    color: AppTheme.primaryGreen,
                                  ),
                                  SizedBox(width: 12),
                                  Text('Config copied to clipboard'),
                                ],
                              ),
                              backgroundColor: AppTheme.backgroundElevated,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: const BorderSide(
                                  color: AppTheme.primaryGreen,
                                ),
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.content_copy_rounded),
                        label: const Text('COPY CONFIG URL'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryGreen,
                          foregroundColor: AppTheme.backgroundDark,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              )
              .animate()
              .fadeIn(duration: 300.ms)
              .scale(begin: const Offset(0.9, 0.9), end: const Offset(1, 1)),
    );
  }
}

/// Import Options Dialog
class ImportOptionsDialog extends StatelessWidget {
  final VoidCallback onClipboardImport;
  final VoidCallback onQRScan;

  const ImportOptionsDialog({
    super.key,
    required this.onClipboardImport,
    required this.onQRScan,
  });

  static Future<void> show(
    BuildContext context, {
    required VoidCallback onClipboardImport,
    required VoidCallback onQRScan,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => ImportOptionsDialog(
        onClipboardImport: onClipboardImport,
        onQRScan: onQRScan,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppTheme.backgroundCard,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(
              color: AppTheme.primaryGreen.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.textMuted,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              const SizedBox(height: 24),

              // Title
              const Text(
                'Import Configuration',
                style: TextStyle(
                  color: AppTheme.primaryGreen,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'JetBrainsMono',
                ),
              ),

              const SizedBox(height: 8),

              Text(
                'Choose how to import your VPN config',
                style: TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 14,
                  fontFamily: 'JetBrainsMono',
                ),
              ),

              const SizedBox(height: 32),

              // Options
              Row(
                children: [
                  Expanded(
                    child: _ImportOptionCard(
                      icon: Icons.content_paste_rounded,
                      title: 'Clipboard',
                      subtitle: 'Paste from clipboard',
                      color: AppTheme.accentCyan,
                      onTap: () {
                        Navigator.pop(context);
                        onClipboardImport();
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _ImportOptionCard(
                      icon: Icons.qr_code_scanner_rounded,
                      title: 'QR Code',
                      subtitle: 'Scan QR code',
                      color: AppTheme.accentPurple,
                      onTap: () {
                        Navigator.pop(context);
                        onQRScan();
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),
            ],
          ),
        )
        .animate()
        .slideY(
          begin: 0.3,
          end: 0,
          duration: 300.ms,
          curve: Curves.easeOutCubic,
        )
        .fadeIn(duration: 300.ms);
  }
}

class _ImportOptionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ImportOptionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 32),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                fontFamily: 'JetBrainsMono',
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                color: AppTheme.textMuted,
                fontSize: 11,
                fontFamily: 'JetBrainsMono',
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Delete Confirmation Dialog
class DeleteConfirmDialog extends StatelessWidget {
  final VpnConfig config;
  final VoidCallback onConfirm;

  const DeleteConfirmDialog({
    super.key,
    required this.config,
    required this.onConfirm,
  });

  static Future<bool?> show(BuildContext context, VpnConfig config) {
    return showDialog<bool>(
      context: context,
      builder: (context) => DeleteConfirmDialog(
        config: config,
        onConfirm: () => Navigator.pop(context, true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child:
          Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppTheme.backgroundCard,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppTheme.accentRed.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.accentRed.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.delete_forever_rounded,
                        color: AppTheme.accentRed,
                        size: 40,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Delete Configuration?',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'JetBrainsMono',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Are you sure you want to delete\n"${config.name}"?',
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 14,
                        fontFamily: 'JetBrainsMono',
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('CANCEL'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: onConfirm,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.accentRed,
                            ),
                            child: const Text('DELETE'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              )
              .animate()
              .fadeIn(duration: 200.ms)
              .shake(duration: 400.ms, hz: 2, offset: const Offset(2, 0)),
    );
  }
}
