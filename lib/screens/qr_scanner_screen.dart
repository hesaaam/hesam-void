import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../utils/app_theme.dart';
import '../services/config_parser_service.dart';

/// QR Code Scanner Screen
class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _scanLineController;
  bool _isProcessing = false;
  final TextEditingController _manualInputController = TextEditingController();
  final MobileScannerController _cameraController = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );
  bool _showManualInput = false;

  @override
  void initState() {
    super.initState();
    _scanLineController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    // On web, show manual input by default
    if (kIsWeb) {
      _showManualInput = true;
    }
  }

  @override
  void dispose() {
    _scanLineController.dispose();
    _manualInputController.dispose();
    _cameraController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppTheme.backgroundDark,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: AppTheme.primaryGreen,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'SCAN QR CODE',
          style: TextStyle(
            color: AppTheme.primaryGreen,
            fontSize: 18,
            fontWeight: FontWeight.bold,
            fontFamily: 'JetBrainsMono',
            letterSpacing: 2,
          ),
        ),
        actions: [
          if (!_showManualInput && !kIsWeb)
            IconButton(
              tooltip: 'Toggle flash',
              icon: const Icon(
                Icons.flash_on_rounded,
                color: AppTheme.primaryGreen,
              ),
              onPressed: _cameraController.toggleTorch,
            ),
          IconButton(
            tooltip: _showManualInput
                ? 'Open camera scanner'
                : 'Enter manually',
            icon: Icon(
              _showManualInput ? Icons.qr_code_scanner : Icons.edit,
              color: AppTheme.primaryGreen,
            ),
            onPressed: () async {
              final showManual = !_showManualInput;
              setState(() => _showManualInput = showManual);
              if (kIsWeb) return;
              if (showManual) {
                await _cameraController.stop();
              } else {
                await _cameraController.start();
              }
            },
          ),
        ],
      ),
      body: _showManualInput ? _buildManualInput() : _buildScannerView(),
    );
  }

  Widget _buildScannerView() {
    if (kIsWeb) {
      return _buildWebFallback();
    }

    return Stack(
      children: [
        Positioned.fill(
          child: MobileScanner(
            controller: _cameraController,
            errorBuilder: (context, error) => _buildCameraError(error),
            onDetect: _onDetect,
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppTheme.backgroundDark.withValues(alpha: 0.45),
                    Colors.transparent,
                    AppTheme.backgroundDark.withValues(alpha: 0.65),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Scan overlay
        _buildScanOverlay(),

        // Bottom controls
        Positioned(
          bottom: 40,
          left: 0,
          right: 0,
          child: Column(
            children: [
              if (_isProcessing)
                const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(AppTheme.primaryGreen),
                )
              else
                ElevatedButton.icon(
                  onPressed: () => setState(() => _showManualInput = true),
                  icon: const Icon(Icons.edit),
                  label: const Text('ENTER MANUALLY'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.backgroundCard,
                    foregroundColor: AppTheme.primaryGreen,
                    side: const BorderSide(color: AppTheme.primaryGreen),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWebFallback() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryGreen.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppTheme.primaryGreen.withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Icon(
                    Icons.qr_code_scanner_rounded,
                    size: 64,
                    color: AppTheme.primaryGreen,
                  ),
                )
                .animate(onPlay: (c) => c.repeat())
                .shimmer(
                  duration: 2000.ms,
                  color: AppTheme.primaryGreen.withValues(alpha: 0.3),
                ),
            const SizedBox(height: 32),
            const Text(
              'Camera Unavailable',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                fontFamily: 'JetBrainsMono',
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'QR scanning is available on mobile.\nYou can paste your config manually.',
              style: TextStyle(
                color: AppTheme.textMuted,
                fontSize: 14,
                fontFamily: 'JetBrainsMono',
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => setState(() => _showManualInput = true),
              icon: const Icon(Icons.edit_rounded),
              label: const Text('ENTER CONFIG MANUALLY'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryGreen,
                foregroundColor: AppTheme.backgroundDark,
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManualInput() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Icon
          Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.accentCyan.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppTheme.accentCyan.withValues(alpha: 0.3),
                  ),
                ),
                child: const Icon(
                  Icons.content_paste_rounded,
                  size: 40,
                  color: AppTheme.accentCyan,
                ),
              )
              .animate()
              .fadeIn(duration: 400.ms)
              .scale(begin: const Offset(0.5, 0.5), end: const Offset(1, 1)),

          const SizedBox(height: 24),

          // Title
          const Text(
            'Paste Configuration',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              fontFamily: 'JetBrainsMono',
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 8),

          const Text(
            'Paste your VPN config URL below',
            style: TextStyle(
              color: AppTheme.textMuted,
              fontSize: 14,
              fontFamily: 'JetBrainsMono',
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 32),

          // Text input
          Container(
                decoration: BoxDecoration(
                  color: AppTheme.backgroundCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppTheme.accentCyan.withValues(alpha: 0.3),
                  ),
                ),
                child: TextField(
                  controller: _manualInputController,
                  maxLines: 6,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontFamily: 'JetBrainsMono',
                  ),
                  decoration: InputDecoration(
                    hintText:
                        'vless://...  or  vmess://...  or  trojan://...  or  ss://...',
                    hintStyle: TextStyle(
                      color: AppTheme.textMuted.withValues(alpha: 0.5),
                      fontSize: 13,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(16),
                  ),
                ),
              )
              .animate()
              .fadeIn(duration: 400.ms, delay: 100.ms)
              .slideY(begin: 0.2, end: 0),

          const SizedBox(height: 16),

          // Supported protocols
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.backgroundElevated,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Supported Protocols:',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    fontFamily: 'JetBrainsMono',
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildProtocolChip('VLESS', AppTheme.protocolVless),
                    _buildProtocolChip('VMess', AppTheme.protocolVmess),
                    _buildProtocolChip('Trojan', AppTheme.protocolTrojan),
                    _buildProtocolChip('SS', AppTheme.protocolShadowsocks),
                  ],
                ),
              ],
            ),
          ).animate().fadeIn(duration: 400.ms, delay: 200.ms),

          const SizedBox(height: 32),

          // Import button
          ElevatedButton(
                onPressed: _handleManualImport,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryGreen,
                  foregroundColor: AppTheme.backgroundDark,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.download_rounded),
                    SizedBox(width: 8),
                    Text(
                      'IMPORT CONFIG',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'JetBrainsMono',
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              )
              .animate()
              .fadeIn(duration: 400.ms, delay: 300.ms)
              .slideY(begin: 0.2, end: 0),

          const SizedBox(height: 16),

          // Cancel button
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.textSecondary,
              side: const BorderSide(color: AppTheme.textMuted),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text('CANCEL'),
          ),
        ],
      ),
    );
  }

  Widget _buildProtocolChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          fontFamily: 'JetBrainsMono',
        ),
      ),
    );
  }

  Widget _buildScanOverlay() {
    return Center(
      child:
          Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  border: Border.all(color: AppTheme.primaryGreen, width: 2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Stack(
                  children: [
                    // Corner decorations
                    ..._buildCorners(),

                    // Scan line
                    AnimatedBuilder(
                      animation: _scanLineController,
                      builder: (context, child) {
                        return Positioned(
                          top: _scanLineController.value * 260 + 10,
                          left: 10,
                          right: 10,
                          child: Container(
                            height: 2,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.transparent,
                                  AppTheme.primaryGreen,
                                  Colors.transparent,
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.primaryGreen.withValues(
                                    alpha: 0.5,
                                  ),
                                  blurRadius: 10,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              )
              .animate()
              .fadeIn(duration: 500.ms)
              .scale(begin: const Offset(0.8, 0.8), end: const Offset(1, 1)),
    );
  }

  List<Widget> _buildCorners() {
    const cornerSize = 30.0;
    const cornerWidth = 4.0;

    return [
      // Top left
      Positioned(
        top: 0,
        left: 0,
        child: Container(
          width: cornerSize,
          height: cornerSize,
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: AppTheme.primaryGreen, width: cornerWidth),
              left: BorderSide(
                color: AppTheme.primaryGreen,
                width: cornerWidth,
              ),
            ),
          ),
        ),
      ),
      // Top right
      Positioned(
        top: 0,
        right: 0,
        child: Container(
          width: cornerSize,
          height: cornerSize,
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: AppTheme.primaryGreen, width: cornerWidth),
              right: BorderSide(
                color: AppTheme.primaryGreen,
                width: cornerWidth,
              ),
            ),
          ),
        ),
      ),
      // Bottom left
      Positioned(
        bottom: 0,
        left: 0,
        child: Container(
          width: cornerSize,
          height: cornerSize,
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: AppTheme.primaryGreen,
                width: cornerWidth,
              ),
              left: BorderSide(
                color: AppTheme.primaryGreen,
                width: cornerWidth,
              ),
            ),
          ),
        ),
      ),
      // Bottom right
      Positioned(
        bottom: 0,
        right: 0,
        child: Container(
          width: cornerSize,
          height: cornerSize,
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: AppTheme.primaryGreen,
                width: cornerWidth,
              ),
              right: BorderSide(
                color: AppTheme.primaryGreen,
                width: cornerWidth,
              ),
            ),
          ),
        ),
      ),
    ];
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing || capture.barcodes.isEmpty) return;
    final value = capture.barcodes.first.rawValue?.trim();
    if (value == null || value.isEmpty) return;
    _handleScannedValue(value);
  }

  Future<void> _handleScannedValue(String value) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    await _cameraController.stop();

    if (!ConfigParserService.isValidConfigUrl(value)) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      _showError('This QR code does not contain a supported configuration');
      await _cameraController.start();
      return;
    }

    if (mounted) Navigator.pop(context, value);
  }

  Widget _buildCameraError(MobileScannerException error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.no_photography_outlined,
              size: 52,
              color: AppTheme.accentRed,
            ),
            const SizedBox(height: 16),
            const Text(
              'Camera unavailable',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFamily: 'JetBrainsMono',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Allow camera permission or enter the configuration manually. (${error.errorCode.name})',
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontFamily: 'JetBrainsMono',
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => setState(() => _showManualInput = true),
              child: const Text('ENTER MANUALLY'),
            ),
          ],
        ),
      ),
    );
  }

  void _handleManualImport() {
    final text = _manualInputController.text.trim();

    if (text.isEmpty) {
      _showError('Please enter a configuration');
      return;
    }

    if (!ConfigParserService.isValidConfigUrl(text)) {
      _showError('Invalid configuration format');
      return;
    }

    Navigator.pop(context, text);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: AppTheme.accentRed),
            const SizedBox(width: 12),
            Text(message),
          ],
        ),
        backgroundColor: AppTheme.backgroundElevated,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppTheme.accentRed),
        ),
      ),
    );
  }
}
