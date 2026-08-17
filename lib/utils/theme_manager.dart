import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Custom Theme Data Model
class AppThemeData {
  final String id;
  final String name;
  final Color primaryColor;
  final Color secondaryColor;
  final Color backgroundColor;
  final Color surfaceColor;
  final Color textColor;
  final Color accentColor;
  final Brightness brightness;

  const AppThemeData({
    required this.id,
    required this.name,
    required this.primaryColor,
    required this.secondaryColor,
    required this.backgroundColor,
    required this.surfaceColor,
    required this.textColor,
    required this.accentColor,
    required this.brightness,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'primaryColor': primaryColor.toARGB32(),
    'secondaryColor': secondaryColor.toARGB32(),
    'backgroundColor': backgroundColor.toARGB32(),
    'surfaceColor': surfaceColor.toARGB32(),
    'textColor': textColor.toARGB32(),
    'accentColor': accentColor.toARGB32(),
    'brightness': brightness.index,
  };

  factory AppThemeData.fromJson(Map<String, dynamic> json) => AppThemeData(
    id: json['id'] as String,
    name: json['name'] as String,
    primaryColor: Color(json['primaryColor'] as int),
    secondaryColor: Color(json['secondaryColor'] as int),
    backgroundColor: Color(json['backgroundColor'] as int),
    surfaceColor: Color(json['surfaceColor'] as int),
    textColor: Color(json['textColor'] as int),
    accentColor: Color(json['accentColor'] as int),
    brightness: Brightness.values[json['brightness'] as int],
  );
}

/// Predefined Themes
class PredefinedThemes {
  // 1. Terminal Green (Default - Matrix Style)
  static const terminalGreen = AppThemeData(
    id: 'terminal_green',
    name: 'Terminal Green',
    primaryColor: Color(0xFF00FF41),
    secondaryColor: Color(0xFF00D93D),
    backgroundColor: Color(0xFF0D0D0D),
    surfaceColor: Color(0xFF1A1A1A),
    textColor: Color(0xFF00FF41),
    accentColor: Color(0xFF00FF41),
    brightness: Brightness.dark,
  );

  // 2. Cyberpunk Purple
  static const cyberpunkPurple = AppThemeData(
    id: 'cyberpunk_purple',
    name: 'Cyberpunk Purple',
    primaryColor: Color(0xFFBB86FC),
    secondaryColor: Color(0xFF9C64FF),
    backgroundColor: Color(0xFF121212),
    surfaceColor: Color(0xFF1E1E2E),
    textColor: Color(0xFFE0E0FF),
    accentColor: Color(0xFFFF0080),
    brightness: Brightness.dark,
  );

  // 3. Ocean Blue
  static const oceanBlue = AppThemeData(
    id: 'ocean_blue',
    name: 'Ocean Blue',
    primaryColor: Color(0xFF00D4FF),
    secondaryColor: Color(0xFF0099CC),
    backgroundColor: Color(0xFF0A1929),
    surfaceColor: Color(0xFF132F4C),
    textColor: Color(0xFFB2E5FC),
    accentColor: Color(0xFF00D4FF),
    brightness: Brightness.dark,
  );

  // 4. Blood Red
  static const bloodRed = AppThemeData(
    id: 'blood_red',
    name: 'Blood Red',
    primaryColor: Color(0xFFFF1744),
    secondaryColor: Color(0xFFD50000),
    backgroundColor: Color(0xFF1A0A0A),
    surfaceColor: Color(0xFF2D1515),
    textColor: Color(0xFFFFCCCC),
    accentColor: Color(0xFFFF1744),
    brightness: Brightness.dark,
  );

  // 5. Neon Orange
  static const neonOrange = AppThemeData(
    id: 'neon_orange',
    name: 'Neon Orange',
    primaryColor: Color(0xFFFF6D00),
    secondaryColor: Color(0xFFFF9100),
    backgroundColor: Color(0xFF1A1208),
    surfaceColor: Color(0xFF2D2010),
    textColor: Color(0xFFFFE0B2),
    accentColor: Color(0xFFFF6D00),
    brightness: Brightness.dark,
  );

  // 6. Electric Teal
  static const electricTeal = AppThemeData(
    id: 'electric_teal',
    name: 'Electric Teal',
    primaryColor: Color(0xFF00E5CC),
    secondaryColor: Color(0xFF00BFA5),
    backgroundColor: Color(0xFF0A1A18),
    surfaceColor: Color(0xFF152D2A),
    textColor: Color(0xFFB2DFDB),
    accentColor: Color(0xFF00E5CC),
    brightness: Brightness.dark,
  );

  // 7. Midnight Gold
  static const midnightGold = AppThemeData(
    id: 'midnight_gold',
    name: 'Midnight Gold',
    primaryColor: Color(0xFFFFD700),
    secondaryColor: Color(0xFFFFC107),
    backgroundColor: Color(0xFF0D0D15),
    surfaceColor: Color(0xFF1A1A2E),
    textColor: Color(0xFFFFF8E1),
    accentColor: Color(0xFFFFD700),
    brightness: Brightness.dark,
  );

  // 8. Light Mode - Clean White
  static const cleanWhite = AppThemeData(
    id: 'clean_white',
    name: 'Clean White',
    primaryColor: Color(0xFF2196F3),
    secondaryColor: Color(0xFF1976D2),
    backgroundColor: Color(0xFFFAFAFA),
    surfaceColor: Color(0xFFFFFFFF),
    textColor: Color(0xFF212121),
    accentColor: Color(0xFF2196F3),
    brightness: Brightness.light,
  );

  static List<AppThemeData> get all => [
    terminalGreen,
    cyberpunkPurple,
    oceanBlue,
    bloodRed,
    neonOrange,
    electricTeal,
    midnightGold,
    cleanWhite,
  ];
}

/// Theme Manager with Persistence
class ThemeManager extends ChangeNotifier {
  static final ThemeManager _instance = ThemeManager._internal();
  factory ThemeManager() => _instance;
  ThemeManager._internal();

  static const String _boxName = 'theme_settings';
  static const String _themeKey = 'current_theme';
  static const String _customThemesKey = 'custom_themes';

  Box? _box;
  AppThemeData _currentTheme = PredefinedThemes.terminalGreen;
  List<AppThemeData> _customThemes = [];

  AppThemeData get currentTheme => _currentTheme;
  List<AppThemeData> get customThemes => _customThemes;
  List<AppThemeData> get allThemes => [
    ...PredefinedThemes.all,
    ..._customThemes,
  ];

  /// Initialize Theme Manager
  Future<void> initialize() async {
    _box = await Hive.openBox(_boxName);
    await _loadTheme();
    await _loadCustomThemes();
  }

  /// Load saved theme
  Future<void> _loadTheme() async {
    final themeId =
        _box?.get(_themeKey, defaultValue: 'terminal_green') as String?;
    if (themeId != null) {
      _currentTheme = allThemes.firstWhere(
        (t) => t.id == themeId,
        orElse: () => PredefinedThemes.terminalGreen,
      );
    }
  }

  /// Load custom themes
  Future<void> _loadCustomThemes() async {
    final customData = _box?.get(_customThemesKey) as List<dynamic>?;
    if (customData != null) {
      _customThemes = customData
          .map(
            (e) => AppThemeData.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList();
    }
  }

  /// Set current theme
  Future<void> setTheme(AppThemeData theme) async {
    _currentTheme = theme;
    await _box?.put(_themeKey, theme.id);
    notifyListeners();
  }

  /// Add custom theme
  Future<void> addCustomTheme(AppThemeData theme) async {
    _customThemes.add(theme);
    await _saveCustomThemes();
    notifyListeners();
  }

  /// Remove custom theme
  Future<void> removeCustomTheme(String themeId) async {
    _customThemes.removeWhere((t) => t.id == themeId);
    await _saveCustomThemes();
    notifyListeners();
  }

  /// Save custom themes
  Future<void> _saveCustomThemes() async {
    await _box?.put(
      _customThemesKey,
      _customThemes.map((t) => t.toJson()).toList(),
    );
  }

  /// Create custom theme
  AppThemeData createCustomTheme({
    required String name,
    required Color primaryColor,
    Color? secondaryColor,
    Color? backgroundColor,
    Color? surfaceColor,
    Color? textColor,
    bool isDark = true,
  }) {
    final id = 'custom_${DateTime.now().millisecondsSinceEpoch}';
    return AppThemeData(
      id: id,
      name: name,
      primaryColor: primaryColor,
      secondaryColor: secondaryColor ?? primaryColor.withValues(alpha: 0.8),
      backgroundColor:
          backgroundColor ??
          (isDark ? const Color(0xFF0D0D0D) : const Color(0xFFFAFAFA)),
      surfaceColor:
          surfaceColor ??
          (isDark ? const Color(0xFF1A1A1A) : const Color(0xFFFFFFFF)),
      textColor: textColor ?? (isDark ? primaryColor : const Color(0xFF212121)),
      accentColor: primaryColor,
      brightness: isDark ? Brightness.dark : Brightness.light,
    );
  }

  /// Convert AppThemeData to Flutter ThemeData
  ThemeData toThemeData(AppThemeData appTheme) {
    final isDark = appTheme.brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      brightness: appTheme.brightness,
      primaryColor: appTheme.primaryColor,
      scaffoldBackgroundColor: appTheme.backgroundColor,
      colorScheme: ColorScheme(
        brightness: appTheme.brightness,
        primary: appTheme.primaryColor,
        onPrimary: isDark ? Colors.black : Colors.white,
        secondary: appTheme.secondaryColor,
        onSecondary: isDark ? Colors.black : Colors.white,
        error: Colors.red,
        onError: Colors.white,
        surface: appTheme.surfaceColor,
        onSurface: appTheme.textColor,
      ),
      cardTheme: CardThemeData(
        color: appTheme.surfaceColor,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: appTheme.primaryColor.withValues(alpha: 0.3)),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: appTheme.backgroundColor,
        foregroundColor: appTheme.textColor,
        elevation: 0,
      ),
      iconTheme: IconThemeData(color: appTheme.primaryColor),
      textTheme: TextTheme(
        displayLarge: TextStyle(color: appTheme.textColor),
        displayMedium: TextStyle(color: appTheme.textColor),
        displaySmall: TextStyle(color: appTheme.textColor),
        headlineLarge: TextStyle(color: appTheme.textColor),
        headlineMedium: TextStyle(color: appTheme.textColor),
        headlineSmall: TextStyle(color: appTheme.textColor),
        titleLarge: TextStyle(color: appTheme.textColor),
        titleMedium: TextStyle(color: appTheme.textColor),
        titleSmall: TextStyle(color: appTheme.textColor),
        bodyLarge: TextStyle(color: appTheme.textColor),
        bodyMedium: TextStyle(color: appTheme.textColor),
        bodySmall: TextStyle(color: appTheme.textColor.withValues(alpha: 0.7)),
        labelLarge: TextStyle(color: appTheme.textColor),
        labelMedium: TextStyle(color: appTheme.textColor),
        labelSmall: TextStyle(color: appTheme.textColor.withValues(alpha: 0.7)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: appTheme.primaryColor,
          foregroundColor: isDark ? Colors.black : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: appTheme.primaryColor,
        foregroundColor: isDark ? Colors.black : Colors.white,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return appTheme.primaryColor;
          }
          return Colors.grey;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return appTheme.primaryColor.withValues(alpha: 0.5);
          }
          return Colors.grey.withValues(alpha: 0.3);
        }),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: appTheme.primaryColor,
        thumbColor: appTheme.primaryColor,
        inactiveTrackColor: appTheme.primaryColor.withValues(alpha: 0.3),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: appTheme.primaryColor,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: appTheme.surfaceColor,
        contentTextStyle: TextStyle(color: appTheme.textColor),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: appTheme.primaryColor.withValues(alpha: 0.5)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: appTheme.surfaceColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: appTheme.primaryColor.withValues(alpha: 0.3)),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: appTheme.surfaceColor,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: appTheme.primaryColor,
        unselectedLabelColor: appTheme.textColor.withValues(alpha: 0.5),
        indicatorColor: appTheme.primaryColor,
      ),
    );
  }

  /// Get current Flutter ThemeData
  ThemeData get themeData => toThemeData(_currentTheme);
}
