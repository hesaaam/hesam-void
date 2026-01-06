import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/vpn_config.dart';
import '../utils/app_theme.dart';

/// Animated VPN Config Card Widget
class ConfigCard extends StatefulWidget {
  final VpnConfig config;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onExportClipboard;
  final VoidCallback? onExportQR;
  final VoidCallback? onTestPing;
  final bool isSelected;
  final bool isTesting;
  final int index;
  final Color? primaryColor;
  final Color? surfaceColor;
  final Color? textColor;
  
  const ConfigCard({
    super.key,
    required this.config,
    this.onTap,
    this.onDelete,
    this.onExportClipboard,
    this.onExportQR,
    this.onTestPing,
    this.isSelected = false,
    this.isTesting = false,
    this.index = 0,
    this.primaryColor,
    this.surfaceColor,
    this.textColor,
  });
  
  @override
  State<ConfigCard> createState() => _ConfigCardState();
}

class _ConfigCardState extends State<ConfigCard>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;

  Color get _primaryColor => widget.primaryColor ?? AppTheme.primaryGreen;
  Color get _surfaceColor => widget.surfaceColor ?? AppTheme.backgroundCard;
  Color get _textColor => widget.textColor ?? AppTheme.textPrimary;

  @override
  Widget build(BuildContext context) {
    return Animate(
      effects: [
        FadeEffect(
          duration: 400.ms,
          delay: (50 * widget.index).ms,
        ),
        SlideEffect(
          begin: const Offset(0.1, 0),
          end: Offset.zero,
          duration: 400.ms,
          delay: (50 * widget.index).ms,
          curve: Curves.easeOutCubic,
        ),
      ],
      child: GestureDetector(
        onTap: () {
          setState(() => _isExpanded = !_isExpanded);
          widget.onTap?.call();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: _surfaceColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: widget.isSelected
                  ? _primaryColor
                  : AppTheme.getProtocolColor(widget.config.protocolString)
                      .withValues(alpha: 0.3),
              width: widget.isSelected ? 2 : 1,
            ),
            boxShadow: widget.isSelected
                ? [
                    BoxShadow(
                      color: _primaryColor.withValues(alpha: 0.3),
                      blurRadius: 20,
                      spreadRadius: 0,
                    ),
                  ]
                : null,
          ),
          child: Column(
            children: [
              // Main card content
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    // Protocol badge
                    _buildProtocolBadge(),
                    const SizedBox(width: 12),
                    
                    // Server info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.config.name,
                            style: TextStyle(
                              color: _textColor,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'JetBrainsMono',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.config.subtitle,
                            style: TextStyle(
                              color: AppTheme.getProtocolColor(
                                  widget.config.protocolString),
                              fontSize: 12,
                              fontFamily: 'JetBrainsMono',
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${widget.config.address}:${widget.config.port}',
                            style: TextStyle(
                              color: _textColor.withValues(alpha: 0.5),
                              fontSize: 11,
                              fontFamily: 'JetBrainsMono',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    
                    // Ping indicator
                    _buildPingIndicator(),
                  ],
                ),
              ),
              
              // Expanded actions
              AnimatedCrossFade(
                firstChild: const SizedBox.shrink(),
                secondChild: _buildExpandedActions(),
                crossFadeState: _isExpanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 300),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProtocolBadge() {
    final color = AppTheme.getProtocolColor(widget.config.protocolString);
    
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Center(
        child: Text(
          widget.config.protocol.shortName,
          style: TextStyle(
            color: color,
            fontSize: 16,
            fontWeight: FontWeight.bold,
            fontFamily: 'JetBrainsMono',
          ),
        ),
      ),
    );
  }

  Widget _buildPingIndicator() {
    if (widget.isTesting) {
      return Container(
        width: 60,
        height: 36,
        decoration: BoxDecoration(
          color: _primaryColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(_primaryColor),
            ),
          ),
        ),
      );
    }
    
    final ping = widget.config.ping;
    final color = AppTheme.getPingColor(ping);
    
    return GestureDetector(
      onTap: widget.onTestPing,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.5),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Text(
              ping != null ? '${ping}ms' : 'Test',
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFamily: 'JetBrainsMono',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedActions() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildActionButton(
            icon: Icons.content_copy_rounded,
            label: 'Copy',
            color: AppTheme.accentCyan,
            onTap: () {
              Clipboard.setData(ClipboardData(text: widget.config.rawUrl));
              widget.onExportClipboard?.call();
            },
          ),
          _buildActionButton(
            icon: Icons.qr_code_rounded,
            label: 'QR',
            color: AppTheme.accentPurple,
            onTap: widget.onExportQR,
          ),
          _buildActionButton(
            icon: Icons.speed_rounded,
            label: 'Ping',
            color: _primaryColor,
            onTap: widget.onTestPing,
          ),
          _buildActionButton(
            icon: Icons.delete_outline_rounded,
            label: 'Delete',
            color: AppTheme.accentRed,
            onTap: widget.onDelete,
          ),
        ],
      ),
    )
        .animate(target: _isExpanded ? 1 : 0)
        .fadeIn(duration: 200.ms)
        .slideY(begin: -0.2, end: 0, duration: 200.ms);
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                fontFamily: 'JetBrainsMono',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Empty state widget
class EmptyConfigsWidget extends StatelessWidget {
  final VoidCallback? onAddConfig;
  final Color? primaryColor;
  final Color? textColor;
  
  const EmptyConfigsWidget({
    super.key, 
    this.onAddConfig,
    this.primaryColor,
    this.textColor,
  });
  
  @override
  Widget build(BuildContext context) {
    final color = primaryColor ?? AppTheme.primaryGreen;
    final text = textColor ?? AppTheme.textPrimary;
    
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.shield_outlined,
            size: 80,
            color: color.withValues(alpha: 0.3),
          )
              .animate(onPlay: (c) => c.repeat())
              .shimmer(duration: 2000.ms, color: color.withValues(alpha: 0.5)),
          const SizedBox(height: 24),
          Text(
            'No Configurations',
            style: TextStyle(
              color: text,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              fontFamily: 'JetBrainsMono',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add your first VPN config to get started',
            style: TextStyle(
              color: text.withValues(alpha: 0.5),
              fontSize: 14,
              fontFamily: 'JetBrainsMono',
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: onAddConfig,
            icon: const Icon(Icons.add_rounded),
            label: const Text('ADD CONFIG'),
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              foregroundColor: AppTheme.backgroundDark,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            ),
          )
              .animate()
              .fadeIn(duration: 500.ms)
              .scale(begin: const Offset(0.8, 0.8), end: const Offset(1, 1)),
        ],
      ),
    );
  }
}
