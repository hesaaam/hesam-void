import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/subscription.dart';
import '../models/vpn_config.dart';
import '../providers/config_provider.dart';
import '../utils/theme_manager.dart';
import '../widgets/subscription_folder_card.dart';

/// The inside of a subscription folder: its status and its routes.
class SubscriptionScreen extends StatelessWidget {
  final String subscriptionId;
  final AppThemeData theme;

  /// Builds the same route card the Servers tab uses.
  final Widget Function(BuildContext, ConfigProvider, VpnConfig) cardBuilder;
  final Future<void> Function(List<VpnConfig> routes) onRunChecks;
  final void Function(List<VpnConfig> routes) onSmartConnect;
  final void Function(String message, {bool success}) onMessage;

  const SubscriptionScreen({
    super.key,
    required this.subscriptionId,
    required this.theme,
    required this.cardBuilder,
    required this.onRunChecks,
    required this.onSmartConnect,
    required this.onMessage,
  });

  static const _intervals = <int, String>{
    0: 'Off',
    6: 'Every 6 hours',
    12: 'Every 12 hours',
    24: 'Every day',
    72: 'Every 3 days',
  };

  Future<void> _refresh(BuildContext context) async {
    final result = await context.read<ConfigProvider>().refreshSubscription(
      subscriptionId,
    );
    onMessage(result.message, success: result.success);
  }

  Future<void> _rename(BuildContext context, Subscription subscription) async {
    final controller = TextEditingController(text: subscription.name);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: theme.surfaceColor,
        title: Text('Rename folder', style: TextStyle(color: theme.textColor)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: theme.textColor),
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null && context.mounted) {
      await context.read<ConfigProvider>().renameSubscription(
        subscriptionId,
        name,
      );
    }
  }

  Future<void> _chooseInterval(
    BuildContext context,
    Subscription subscription,
  ) async {
    final hours = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: theme.surfaceColor,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Automatic update',
                style: TextStyle(
                  color: theme.textColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            for (final entry in _intervals.entries)
              ListTile(
                title: Text(
                  entry.value,
                  style: TextStyle(color: theme.textColor),
                ),
                trailing: subscription.autoUpdateHours == entry.key
                    ? Icon(Icons.check_rounded, color: theme.primaryColor)
                    : null,
                onTap: () => Navigator.pop(sheetContext, entry.key),
              ),
          ],
        ),
      ),
    );
    if (hours != null && context.mounted) {
      await context.read<ConfigProvider>().setSubscriptionAutoUpdate(
        subscriptionId,
        hours,
      );
    }
  }

  Future<void> _delete(BuildContext context, Subscription subscription) async {
    final count = context.read<ConfigProvider>().configsFor(subscriptionId);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: theme.surfaceColor,
        title: Text(
          'Delete "${subscription.name}"?',
          style: TextStyle(color: theme.textColor),
        ),
        content: Text(
          'The folder and its ${count.length} '
          'route${count.length == 1 ? '' : 's'} will be removed from this '
          'device. You can add the link again later.',
          style: TextStyle(color: theme.textColor.withValues(alpha: 0.75)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFFF5C6C),
            ),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      final provider = context.read<ConfigProvider>();
      Navigator.of(context).pop();
      await provider.deleteSubscription(subscriptionId);
      onMessage('Subscription deleted', success: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ConfigProvider>(
      builder: (context, provider, _) {
        final subscription = provider.subscriptionById(subscriptionId);
        if (subscription == null) {
          return Scaffold(backgroundColor: theme.backgroundColor);
        }
        final routes = provider.configsFor(subscriptionId);
        final refreshing = provider.isRefreshing(subscriptionId);

        return Scaffold(
          backgroundColor: theme.backgroundColor,
          appBar: AppBar(
            backgroundColor: theme.backgroundColor,
            foregroundColor: theme.textColor,
            title: Text(
              subscription.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              PopupMenuButton<String>(
                color: theme.surfaceColor,
                iconColor: theme.textColor,
                onSelected: (value) async {
                  switch (value) {
                    case 'rename':
                      await _rename(context, subscription);
                    case 'interval':
                      await _chooseInterval(context, subscription);
                    case 'copy':
                      await Clipboard.setData(
                        ClipboardData(text: subscription.url),
                      );
                      onMessage('Subscription link copied', success: true);
                    case 'delete':
                      await _delete(context, subscription);
                  }
                },
                itemBuilder: (_) => [
                  _menuItem('rename', Icons.edit_rounded, 'Rename'),
                  _menuItem('interval', Icons.schedule_rounded, 'Auto update'),
                  _menuItem('copy', Icons.link_rounded, 'Copy link'),
                  _menuItem(
                    'delete',
                    Icons.delete_outline_rounded,
                    'Delete folder',
                    color: const Color(0xFFFF5C6C),
                  ),
                ],
              ),
            ],
          ),
          body: RefreshIndicator(
            color: theme.primaryColor,
            onRefresh: () => _refresh(context),
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 40),
              itemCount: routes.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _StatusHeader(
                    subscription: subscription,
                    routeCount: routes.length,
                    refreshing: refreshing,
                    checking: provider.isTestingPing,
                    theme: theme,
                    intervalLabel:
                        _intervals[subscription.autoUpdateHours] ??
                        'Every ${subscription.autoUpdateHours} hours',
                    onRefresh: () => _refresh(context),
                    onRunChecks: () => onRunChecks(routes),
                    onSmartConnect: () {
                      Navigator.of(context).pop();
                      onSmartConnect(routes);
                    },
                    onChangeInterval: () =>
                        _chooseInterval(context, subscription),
                  );
                }
                return cardBuilder(context, provider, routes[index - 1]);
              },
            ),
          ),
        );
      },
    );
  }

  PopupMenuItem<String> _menuItem(
    String value,
    IconData icon,
    String label, {
    Color? color,
  }) {
    final tint = color ?? theme.textColor;
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 19, color: tint),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(color: tint)),
        ],
      ),
    );
  }
}

class _StatusHeader extends StatelessWidget {
  final Subscription subscription;
  final int routeCount;
  final bool refreshing;
  final bool checking;
  final AppThemeData theme;
  final String intervalLabel;
  final VoidCallback onRefresh;
  final VoidCallback onRunChecks;
  final VoidCallback onSmartConnect;
  final VoidCallback onChangeInterval;

  const _StatusHeader({
    required this.subscription,
    required this.routeCount,
    required this.refreshing,
    required this.checking,
    required this.theme,
    required this.intervalLabel,
    required this.onRefresh,
    required this.onRunChecks,
    required this.onSmartConnect,
    required this.onChangeInterval,
  });

  @override
  Widget build(BuildContext context) {
    final text = theme.textColor;
    final accent = theme.primaryColor;
    final usage = subscription.usageFraction;
    final used = subscription.usedBytes;
    final days = subscription.daysLeft();

    Widget stat(String label, String value, {Color? color}) => Expanded(
      child: Column(
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color ?? text,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(color: text.withValues(alpha: 0.5), fontSize: 11),
          ),
        ],
      ),
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.surfaceColor.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              stat('routes', '$routeCount'),
              stat(
                'used',
                used == null ? '—' : formatDataSize(used),
                color: usage != null && usage > 0.9
                    ? const Color(0xFFFF5C6C)
                    : null,
              ),
              stat(
                'allowance',
                subscription.totalBytes == null
                    ? (used == null ? '—' : '∞')
                    : formatDataSize(subscription.totalBytes!),
              ),
              stat(
                'remaining',
                days == null ? '—' : (days < 0 ? 'Expired' : '$days d'),
                color: days == null ? null : expiryColor(days),
              ),
            ],
          ),
          if (usage != null) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: usage,
                minHeight: 7,
                color: usage > 0.9
                    ? const Color(0xFFFF5C6C)
                    : usage > 0.75
                    ? const Color(0xFFFFB020)
                    : accent,
                backgroundColor: text.withValues(alpha: 0.1),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(
                Icons.update_rounded,
                size: 15,
                color: text.withValues(alpha: 0.5),
              ),
              Text(
                'Updated ${formatAgo(subscription.updatedAt)}',
                style: TextStyle(
                  color: text.withValues(alpha: 0.6),
                  fontSize: 12,
                ),
              ),
              InkWell(
                onTap: onChangeInterval,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  child: Text(
                    'Auto: $intervalLabel',
                    style: TextStyle(
                      color: accent,
                      fontSize: 12,
                      decoration: TextDecoration.underline,
                      decorationColor: accent.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (subscription.lastError != null) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  size: 16,
                  color: Color(0xFFFFB020),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Last update failed: ${subscription.lastError}',
                    style: const TextStyle(
                      color: Color(0xFFFFB020),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: routeCount == 0 ? null : onSmartConnect,
                  icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                  label: const Text('SMART CONNECT'),
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.black,
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _SquareButton(
                tooltip: 'Check routes',
                icon: Icons.speed_rounded,
                busy: checking,
                color: accent,
                onTap: checking ? null : onRunChecks,
              ),
              const SizedBox(width: 8),
              _SquareButton(
                tooltip: 'Update now',
                icon: Icons.sync_rounded,
                busy: refreshing,
                color: accent,
                onTap: refreshing ? null : onRefresh,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SquareButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final bool busy;
  final Color color;
  final VoidCallback? onTap;

  const _SquareButton({
    required this.tooltip,
    required this.icon,
    required this.busy,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color.withValues(alpha: 0.5)),
          padding: const EdgeInsets.all(12),
          minimumSize: const Size(48, 44),
        ),
        child: busy
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: color),
              )
            : Icon(icon, size: 20),
      ),
    );
  }
}
