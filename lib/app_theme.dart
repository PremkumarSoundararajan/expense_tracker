import 'package:flutter/material.dart';

@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.surfaceVariant,
    required this.headerDeep,
    required this.headerLight,
    required this.onHeader,
    required this.headerTrack,
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
  });

  final Color surfaceVariant;
  final Color headerDeep;
  final Color headerLight;
  final Color onHeader;
  final Color headerTrack;
  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;
  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color onWarningContainer;

  @override
  AppSemanticColors copyWith({
    Color? surfaceVariant,
    Color? headerDeep,
    Color? headerLight,
    Color? onHeader,
    Color? headerTrack,
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? onWarningContainer,
  }) => AppSemanticColors(
    surfaceVariant: surfaceVariant ?? this.surfaceVariant,
    headerDeep: headerDeep ?? this.headerDeep,
    headerLight: headerLight ?? this.headerLight,
    onHeader: onHeader ?? this.onHeader,
    headerTrack: headerTrack ?? this.headerTrack,
    success: success ?? this.success,
    onSuccess: onSuccess ?? this.onSuccess,
    successContainer: successContainer ?? this.successContainer,
    onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
    warning: warning ?? this.warning,
    onWarning: onWarning ?? this.onWarning,
    warningContainer: warningContainer ?? this.warningContainer,
    onWarningContainer: onWarningContainer ?? this.onWarningContainer,
  );

  @override
  AppSemanticColors lerp(
    covariant ThemeExtension<AppSemanticColors>? other,
    double t,
  ) {
    if (other is! AppSemanticColors) return this;
    return AppSemanticColors(
      surfaceVariant: Color.lerp(surfaceVariant, other.surfaceVariant, t)!,
      headerDeep: Color.lerp(headerDeep, other.headerDeep, t)!,
      headerLight: Color.lerp(headerLight, other.headerLight, t)!,
      onHeader: Color.lerp(onHeader, other.onHeader, t)!,
      headerTrack: Color.lerp(headerTrack, other.headerTrack, t)!,
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      successContainer: Color.lerp(
        successContainer,
        other.successContainer,
        t,
      )!,
      onSuccessContainer: Color.lerp(
        onSuccessContainer,
        other.onSuccessContainer,
        t,
      )!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      warningContainer: Color.lerp(
        warningContainer,
        other.warningContainer,
        t,
      )!,
      onWarningContainer: Color.lerp(
        onWarningContainer,
        other.onWarningContainer,
        t,
      )!,
    );
  }
}

@immutable
class AccentColorPair {
  const AccentColorPair({required this.icon, required this.container});

  final Color icon;
  final Color container;

  AccentColorPair lerp(AccentColorPair other, double t) => AccentColorPair(
    icon: Color.lerp(icon, other.icon, t)!,
    container: Color.lerp(container, other.container, t)!,
  );
}

@immutable
class AccentColors extends ThemeExtension<AccentColors> {
  const AccentColors({
    required this.teal,
    required this.green,
    required this.blue,
    required this.amber,
    required this.violet,
    required this.rose,
  });

  final AccentColorPair teal;
  final AccentColorPair green;
  final AccentColorPair blue;
  final AccentColorPair amber;
  final AccentColorPair violet;
  final AccentColorPair rose;

  List<AccentColorPair> get all => [teal, green, blue, amber, violet, rose];

  AccentColorPair forCategory(String key) {
    final hash = key.toLowerCase().codeUnits.fold<int>(
      0,
      (value, unit) => (value * 31 + unit) & 0x7fffffff,
    );
    return all[hash % 6];
  }

  @override
  AccentColors copyWith({
    AccentColorPair? teal,
    AccentColorPair? green,
    AccentColorPair? blue,
    AccentColorPair? amber,
    AccentColorPair? violet,
    AccentColorPair? rose,
  }) => AccentColors(
    teal: teal ?? this.teal,
    green: green ?? this.green,
    blue: blue ?? this.blue,
    amber: amber ?? this.amber,
    violet: violet ?? this.violet,
    rose: rose ?? this.rose,
  );

  @override
  AccentColors lerp(covariant ThemeExtension<AccentColors>? other, double t) {
    if (other is! AccentColors) return this;
    return AccentColors(
      teal: teal.lerp(other.teal, t),
      green: green.lerp(other.green, t),
      blue: blue.lerp(other.blue, t),
      amber: amber.lerp(other.amber, t),
      violet: violet.lerp(other.violet, t),
      rose: rose.lerp(other.rose, t),
    );
  }
}

abstract final class AppTheme {
  static const _brand = Color(0xFF1B4D3E);
  static const _brandDarkMode = Color(0xFF9DD7C2);
  static const _errorLight = Color(0xFFB3261E);
  static const _errorDark = Color(0xFFFFB4AB);

  static final ThemeData light = _build(Brightness.light);
  static final ThemeData dark = _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final primary = isLight ? _brand : _brandDarkMode;
    final surface = isLight ? const Color(0xFFF8F8F8) : const Color(0xFF121212);
    final onSurface = isLight
        ? const Color(0xFF1A1A1A)
        : const Color(0xFFE6E6E6);
    final surfaceVariant = isLight
        ? const Color(0xFFE2E2E2)
        : const Color(0xFF303030);
    final onSurfaceVariant = isLight
        ? const Color(0xFF414141)
        : const Color(0xFFC1C1C1);
    final outline = isLight ? const Color(0xFF6A6A6A) : const Color(0xFF909090);
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: _brand,
          brightness: brightness,
          primary: primary,
          secondary: primary,
          tertiary: primary,
          surface: surface,
          error: isLight ? _errorLight : _errorDark,
        ).copyWith(
          primary: primary,
          onPrimary: isLight ? Colors.white : const Color(0xFF00382B),
          primaryContainer: isLight
              ? const Color(0xFFDDECE5)
              : const Color(0xFF00513E),
          onPrimaryContainer: isLight
              ? const Color(0xFF173B30)
              : const Color(0xFFB7F1DC),
          secondary: primary,
          onSecondary: isLight ? Colors.white : const Color(0xFF00382B),
          secondaryContainer: isLight
              ? const Color(0xFFDDECE5)
              : const Color(0xFF00513E),
          onSecondaryContainer: isLight
              ? const Color(0xFF173B30)
              : const Color(0xFFB7F1DC),
          tertiary: primary,
          onTertiary: isLight ? Colors.white : const Color(0xFF00382B),
          tertiaryContainer: isLight
              ? const Color(0xFFDDECE5)
              : const Color(0xFF00513E),
          onTertiaryContainer: isLight
              ? const Color(0xFF173B30)
              : const Color(0xFFB7F1DC),
          error: isLight ? _errorLight : _errorDark,
          onError: isLight ? Colors.white : const Color(0xFF690005),
          errorContainer: isLight
              ? const Color(0xFFF9DEDC)
              : const Color(0xFF93000A),
          onErrorContainer: isLight
              ? const Color(0xFF410E0B)
              : const Color(0xFFFFDAD6),
          surface: surface,
          onSurface: onSurface,
          onSurfaceVariant: onSurfaceVariant,
          outline: outline,
          outlineVariant: isLight
              ? const Color(0xFF858585)
              : const Color(0xFF646464),
          surfaceContainerLowest: isLight
              ? const Color(0xFFFFFFFF)
              : const Color(0xFF0D0D0D),
          surfaceContainerLow: isLight
              ? const Color(0xFFF4F4F4)
              : const Color(0xFF1A1A1A),
          surfaceContainer: isLight
              ? const Color(0xFFEEEEEE)
              : const Color(0xFF1E1E1E),
          surfaceContainerHigh: isLight
              ? const Color(0xFFE8E8E8)
              : const Color(0xFF262626),
          surfaceContainerHighest: surfaceVariant,
          surfaceDim: isLight ? const Color(0xFFE6E6E6) : surface,
          surfaceBright: isLight
              ? const Color(0xFFFFFFFF)
              : const Color(0xFF383838),
          inverseSurface: isLight
              ? const Color(0xFF2E2E2E)
              : const Color(0xFFE6E6E6),
          inversePrimary: isLight ? _brandDarkMode : _brand,
        );
    final accentColors = AccentColors(
      teal: AccentColorPair(
        icon: isLight ? const Color(0xFF236A7A) : const Color(0xFF8FD3E0),
        container: isLight ? const Color(0xFFD6EEF2) : const Color(0xFF1E3A41),
      ),
      green: AccentColorPair(
        icon: isLight ? const Color(0xFF2E7D5B) : const Color(0xFF8FD9B6),
        container: isLight ? const Color(0xFFD5EFE2) : const Color(0xFF1C3A2D),
      ),
      blue: AccentColorPair(
        icon: isLight ? const Color(0xFF3A64B8) : const Color(0xFF9DB8F0),
        container: isLight ? const Color(0xFFDCE6F8) : const Color(0xFF1F2D4A),
      ),
      amber: AccentColorPair(
        icon: isLight ? const Color(0xFFA06A00) : const Color(0xFFF0C766),
        container: isLight ? const Color(0xFFF8E8C4) : const Color(0xFF3F3014),
      ),
      violet: AccentColorPair(
        icon: isLight ? const Color(0xFF6A4FB3) : const Color(0xFFC0AEF0),
        container: isLight ? const Color(0xFFE6DEF6) : const Color(0xFF2E2548),
      ),
      rose: AccentColorPair(
        icon: isLight ? const Color(0xFFA8447A) : const Color(0xFFEFA3CB),
        container: isLight ? const Color(0xFFF6DCEA) : const Color(0xFF40203A),
      ),
    );
    final semanticColors = AppSemanticColors(
      surfaceVariant: surfaceVariant,
      headerDeep: isLight
          ? const Color(0xFF165A68)
          : const Color(0xFF123D46),
      headerLight: isLight
          ? const Color(0xFF236A7A)
          : const Color(0xFF1E5660),
      onHeader: Colors.white,
      headerTrack: const Color(0x66FFFFFF),
      success: isLight ? _brand : _brandDarkMode,
      onSuccess: isLight ? Colors.white : const Color(0xFF00382B),
      successContainer: isLight
          ? const Color(0xFFDDECE5)
          : const Color(0xFF00513E),
      onSuccessContainer: isLight
          ? const Color(0xFF173B30)
          : const Color(0xFFB7F1DC),
      warning: isLight ? const Color(0xFF765600) : const Color(0xFFF3C969),
      onWarning: isLight ? Colors.white : const Color(0xFF2C2100),
      warningContainer: isLight
          ? const Color(0xFFFFF1C2)
          : const Color(0xFF493800),
      onWarningContainer: isLight
          ? const Color(0xFF493500)
          : const Color(0xFFFFE4A8),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      extensions: [semanticColors, accentColors],
      scaffoldBackgroundColor: colorScheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: semanticColors.headerDeep,
        foregroundColor: semanticColors.onHeader,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainerLow,
        elevation: 2,
        shadowColor: colorScheme.shadow.withValues(alpha: isLight ? 0.12 : 0.2),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        linearMinHeight: 10,
        linearTrackColor: colorScheme.primaryContainer,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surface,
        indicatorColor: accentColors.teal.container,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? accentColors.teal.icon
                : colorScheme.onSurfaceVariant,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? accentColors.teal.icon
                : colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surface,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
      ),
    );
  }
}

extension AppThemeContext on BuildContext {
  AppSemanticColors get semanticColors =>
      Theme.of(this).extension<AppSemanticColors>()!;
  AccentColors get accentColors => Theme.of(this).extension<AccentColors>()!;
}
