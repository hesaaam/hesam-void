import 'package:flutter/material.dart';

/// The "Night Signal" look introduced in 4.3: a deep night background,
/// one signal colour for live state, monospace numbers.
class NightSignal {
  const NightSignal._();

  static const Color background = Color(0xFF0A0E13);
  static const Color scene = Color(0xFF10161E);
  static const Color surface = Color(0xFF121821);
  static const Color raised = Color(0xFF19212C);
  static const Color line = Color(0x14FFFFFF);
  static const Color lineStrong = Color(0x24FFFFFF);
  static const Color text = Color(0xFFE8EEF5);
  static const Color muted = Color(0xFF8C9AAB);
  static const Color soft = Color(0xFFAEB9C6);
  static const Color faint = Color(0xFF5C6878);

  static const Color signal = Color(0xFF34E1A1);
  static const Color upload = Color(0xFF5AA9FF);
  static const Color violet = Color(0xFFB98CFF);
  static const Color warning = Color(0xFFFFB547);
  static const Color orange = Color(0xFFFF8A3D);
  static const Color danger = Color(0xFFFF6B7A);

  static const String mono = 'JetBrainsMono';

  static BoxDecoration card({double radius = 20, Color? border}) {
    return BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: border ?? line),
    );
  }

  static TextStyle title({double size = 26, Color color = text}) {
    return TextStyle(
      color: color,
      fontSize: size,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.2,
      height: 1.15,
    );
  }

  static TextStyle eyebrow({Color color = muted}) {
    return TextStyle(
      color: color,
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.4,
    );
  }

  static TextStyle number({
    double size = 15,
    Color color = text,
    FontWeight weight = FontWeight.w700,
  }) {
    return TextStyle(
      color: color,
      fontSize: size,
      fontFamily: mono,
      fontWeight: weight,
    );
  }

  /// Latency colour shared by rows, radar and charts.
  static Color forLatency(int? ms, {Color good = signal}) {
    if (ms == null || ms < 0) return danger;
    if (ms < 250) return good;
    if (ms < 500) return warning;
    return orange;
  }
}
