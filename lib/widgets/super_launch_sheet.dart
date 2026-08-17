import 'package:flutter/material.dart';

class SuperLaunchSheet extends StatelessWidget {
  final Color accentColor;
  final Color surfaceColor;
  final Color textColor;
  final VoidCallback onStart;

  const SuperLaunchSheet({
    super.key,
    required this.accentColor,
    required this.surfaceColor,
    required this.textColor,
    required this.onStart,
  });

  static Future<void> show(
    BuildContext context, {
    required Color accentColor,
    required Color surfaceColor,
    required Color textColor,
    required VoidCallback onStart,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      enableDrag: true,
      builder: (_) => SuperLaunchSheet(
        accentColor: accentColor,
        surfaceColor: surfaceColor,
        textColor: textColor,
        onStart: onStart,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          border: Border.all(color: accentColor.withValues(alpha: .28)),
        ),
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: textColor.withValues(alpha: .22),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 22),
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accentColor.withValues(alpha: .16),
                border: Border.all(color: accentColor.withValues(alpha: .66)),
                boxShadow: [
                  BoxShadow(
                    color: accentColor.withValues(alpha: .22),
                    blurRadius: 24,
                  ),
                ],
              ),
              child: Icon(Icons.bolt_rounded, color: accentColor, size: 30),
            ),
            const SizedBox(height: 18),
            Text(
              'WELCOME TO 4SUPER',
              style: TextStyle(
                color: textColor,
                fontFamily: 'JetBrainsMono',
                fontWeight: FontWeight.bold,
                fontSize: 18,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'A clearer, calmer way to choose, protect, and understand your routes.',
              style: TextStyle(
                color: textColor.withValues(alpha: .58),
                fontFamily: 'JetBrainsMono',
                fontSize: 11.5,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 20),
            _FeatureLine(
              icon: Icons.radar_rounded,
              color: accentColor,
              title: 'Alive Signal',
              detail:
                  'Watch real connection states instead of a static connect screen.',
              textColor: textColor,
            ),
            const SizedBox(height: 14),
            _FeatureLine(
              icon: Icons.auto_awesome_rounded,
              color: const Color(0xFF20E870),
              title: 'Quick Connect',
              detail:
                  'Choose a route with local health context and clear reasons.',
              textColor: textColor,
            ),
            const SizedBox(height: 14),
            _FeatureLine(
              icon: Icons.timeline_rounded,
              color: const Color(0xFFFFB020),
              title: 'Connection Story',
              detail: 'See local checks, connects, drops, and recovery events.',
              textColor: textColor,
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  onStart();
                },
                icon: const Icon(Icons.arrow_forward_rounded),
                label: const Text('EXPLORE 4SUPER'),
                style: FilledButton.styleFrom(
                  backgroundColor: accentColor,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(
                    fontFamily: 'JetBrainsMono',
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureLine extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String detail;
  final Color textColor;

  const _FeatureLine({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .13),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, color: color, size: 19),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: textColor,
                  fontFamily: 'JetBrainsMono',
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                detail,
                style: TextStyle(
                  color: textColor.withValues(alpha: .52),
                  fontFamily: 'JetBrainsMono',
                  fontSize: 10,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
