import 'package:flutter/material.dart';

/// Terminal Green Theme for Hesam Void
class AppTheme {
  // Primary Colors - Terminal Green Aesthetic
  static const Color primaryGreen = Color(0xFF00FF41);
  static const Color darkGreen = Color(0xFF00CC33);
  static const Color lightGreen = Color(0xFF39FF14);
  static const Color matrixGreen = Color(0xFF00FF00);
  
  // Background Colors
  static const Color backgroundDark = Color(0xFF0A0A0A);
  static const Color backgroundCard = Color(0xFF121212);
  static const Color backgroundElevated = Color(0xFF1A1A1A);
  static const Color backgroundSurface = Color(0xFF0D0D0D);
  
  // Accent Colors
  static const Color accentCyan = Color(0xFF00D9FF);
  static const Color accentPurple = Color(0xFF9D00FF);
  static const Color accentRed = Color(0xFFFF0040);
  static const Color accentOrange = Color(0xFFFF6B00);
  static const Color accentYellow = Color(0xFFFFD700);
  
  // Text Colors
  static const Color textPrimary = Color(0xFFE0E0E0);
  static const Color textSecondary = Color(0xFF9E9E9E);
  static const Color textMuted = Color(0xFF616161);
  static const Color textGreen = primaryGreen;
  
  // Status Colors
  static const Color statusExcellent = Color(0xFF00FF41);
  static const Color statusGood = Color(0xFF7CFC00);
  static const Color statusFair = Color(0xFFFFD700);
  static const Color statusPoor = Color(0xFFFF4500);
  static const Color statusUnknown = Color(0xFF808080);
  
  // Protocol Colors
  static const Color protocolVless = Color(0xFF00FF41);
  static const Color protocolVmess = Color(0xFF00D9FF);
  static const Color protocolTrojan = Color(0xFFFF6B00);
  static const Color protocolShadowsocks = Color(0xFF9D00FF);
  
  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primaryGreen, darkGreen],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  static const LinearGradient cardGradient = LinearGradient(
    colors: [backgroundCard, backgroundElevated],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
  
  static const LinearGradient glowGradient = LinearGradient(
    colors: [
      Color(0x4000FF41),
      Color(0x0000FF41),
    ],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  /// Main Theme Data
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: backgroundDark,
      primaryColor: primaryGreen,
      colorScheme: const ColorScheme.dark(
        primary: primaryGreen,
        secondary: accentCyan,
        surface: backgroundCard,
        error: accentRed,
        onPrimary: backgroundDark,
        onSecondary: backgroundDark,
        onSurface: textPrimary,
        onError: textPrimary,
      ),
      
      // AppBar Theme
      appBarTheme: const AppBarTheme(
        backgroundColor: backgroundDark,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: 'JetBrainsMono',
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: primaryGreen,
          letterSpacing: 2,
        ),
        iconTheme: IconThemeData(color: primaryGreen),
      ),
      
      // Card Theme
      cardTheme: CardThemeData(
        color: backgroundCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF2A2A2A), width: 1),
        ),
      ),
      
      // Floating Action Button Theme
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primaryGreen,
        foregroundColor: backgroundDark,
        elevation: 8,
        shape: CircleBorder(),
      ),
      
      // Icon Theme
      iconTheme: const IconThemeData(
        color: primaryGreen,
        size: 24,
      ),
      
      // Text Theme
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontFamily: 'JetBrainsMono',
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: textPrimary,
          letterSpacing: 1.5,
        ),
        displayMedium: TextStyle(
          fontFamily: 'JetBrainsMono',
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: textPrimary,
        ),
        headlineLarge: TextStyle(
          fontFamily: 'JetBrainsMono',
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: textPrimary,
        ),
        headlineMedium: TextStyle(
          fontFamily: 'JetBrainsMono',
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        titleLarge: TextStyle(
          fontFamily: 'JetBrainsMono',
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        titleMedium: TextStyle(
          fontFamily: 'JetBrainsMono',
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: textPrimary,
        ),
        bodyLarge: TextStyle(
          fontFamily: 'JetBrainsMono',
          fontSize: 16,
          color: textPrimary,
        ),
        bodyMedium: TextStyle(
          fontFamily: 'JetBrainsMono',
          fontSize: 14,
          color: textSecondary,
        ),
        bodySmall: TextStyle(
          fontFamily: 'JetBrainsMono',
          fontSize: 12,
          color: textMuted,
        ),
        labelLarge: TextStyle(
          fontFamily: 'JetBrainsMono',
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: primaryGreen,
          letterSpacing: 1.2,
        ),
      ),
      
      // Input Decoration Theme
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: backgroundElevated,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2A2A2A)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2A2A2A)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryGreen, width: 2),
        ),
        hintStyle: const TextStyle(color: textMuted),
        labelStyle: const TextStyle(color: textSecondary),
      ),
      
      // Elevated Button Theme
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryGreen,
          foregroundColor: backgroundDark,
          elevation: 4,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 14,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
      ),
      
      // Outlined Button Theme
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryGreen,
          side: const BorderSide(color: primaryGreen, width: 2),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 14,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
      ),
      
      // Bottom Navigation Bar Theme
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: backgroundCard,
        selectedItemColor: primaryGreen,
        unselectedItemColor: textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 16,
        selectedLabelStyle: TextStyle(
          fontFamily: 'JetBrainsMono',
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: TextStyle(
          fontFamily: 'JetBrainsMono',
          fontSize: 12,
        ),
      ),
      
      // Snackbar Theme
      snackBarTheme: SnackBarThemeData(
        backgroundColor: backgroundElevated,
        contentTextStyle: const TextStyle(
          fontFamily: 'JetBrainsMono',
          color: textPrimary,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: primaryGreen),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      
      // Dialog Theme
      dialogTheme: DialogThemeData(
        backgroundColor: backgroundCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFF2A2A2A)),
        ),
        titleTextStyle: const TextStyle(
          fontFamily: 'JetBrainsMono',
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: primaryGreen,
        ),
      ),
      
      // Divider Theme
      dividerTheme: const DividerThemeData(
        color: Color(0xFF2A2A2A),
        thickness: 1,
      ),
    );
  }

  /// Get color for ping status
  static Color getPingColor(int? ping) {
    if (ping == null) return statusUnknown;
    if (ping < 100) return statusExcellent;
    if (ping < 200) return statusGood;
    if (ping < 500) return statusFair;
    return statusPoor;
  }

  /// Get color for protocol type
  static Color getProtocolColor(String protocol) {
    switch (protocol.toLowerCase()) {
      case 'vless':
        return protocolVless;
      case 'vmess':
        return protocolVmess;
      case 'trojan':
        return protocolTrojan;
      case 'ss':
      case 'shadowsocks':
        return protocolShadowsocks;
      default:
        return textMuted;
    }
  }

  /// Box decoration with glow effect
  static BoxDecoration glowingBox({Color color = primaryGreen, double blur = 20}) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: color.withValues(alpha: 0.5), width: 1),
      boxShadow: [
        BoxShadow(
          color: color.withValues(alpha: 0.3),
          blurRadius: blur,
          spreadRadius: 0,
        ),
      ],
    );
  }
}
