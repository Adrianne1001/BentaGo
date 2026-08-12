import 'package:flutter/material.dart';

/// Palette drawn from Philippine banknotes: the P1000 blue-teal as primary,
/// the P500 ochre as accent, P200 green for gains and P20 orange for warnings.
abstract class BrandColors {
  static const primary = Color(0xFF1B4D6B);
  static const primaryDark = Color(0xFF7FBBDC);
  static const accent = Color(0xFFA9761A);
  static const accentDark = Color(0xFFDDA850);

  static const good = Color(0xFF2C6E4E);
  static const goodDark = Color(0xFF79C69B);
  static const warn = Color(0xFF9A4A19);
  static const warnDark = Color(0xFFE09466);
  static const danger = Color(0xFFA02D2D);
  static const dangerDark = Color(0xFFE58585);

  static const groundLight = Color(0xFFF6F8F7);
  static const surfaceLight = Color(0xFFFFFFFF);
  static const groundDark = Color(0xFF0D161D);
  static const surfaceDark = Color(0xFF14212B);
}

/// Semantic colors that flip with the active brightness. Read these instead of
/// reaching for a literal, so every screen stays legible in both themes.
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.good,
    required this.warn,
    required this.danger,
    required this.accent,
    required this.muted,
    required this.chartGrid,
    required this.cashTint,
    required this.creditTint,
    required this.gcashTint,
  });

  final Color good;
  final Color warn;
  final Color danger;
  final Color accent;
  final Color muted;
  final Color chartGrid;
  final Color cashTint;
  final Color creditTint;
  final Color gcashTint;

  static const light = AppColors(
    good: BrandColors.good,
    warn: BrandColors.warn,
    danger: BrandColors.danger,
    accent: BrandColors.accent,
    muted: Color(0xFF647680),
    chartGrid: Color(0xFFE2E8E9),
    cashTint: BrandColors.good,
    creditTint: BrandColors.warn,
    gcashTint: Color(0xFF3F6BA8),
  );

  static const dark = AppColors(
    good: BrandColors.goodDark,
    warn: BrandColors.warnDark,
    danger: BrandColors.dangerDark,
    accent: BrandColors.accentDark,
    muted: Color(0xFF8298A5),
    chartGrid: Color(0xFF22343F),
    cashTint: BrandColors.goodDark,
    creditTint: BrandColors.warnDark,
    gcashTint: Color(0xFF89AEE0),
  );

  @override
  AppColors copyWith({
    Color? good,
    Color? warn,
    Color? danger,
    Color? accent,
    Color? muted,
    Color? chartGrid,
    Color? cashTint,
    Color? creditTint,
    Color? gcashTint,
  }) {
    return AppColors(
      good: good ?? this.good,
      warn: warn ?? this.warn,
      danger: danger ?? this.danger,
      accent: accent ?? this.accent,
      muted: muted ?? this.muted,
      chartGrid: chartGrid ?? this.chartGrid,
      cashTint: cashTint ?? this.cashTint,
      creditTint: creditTint ?? this.creditTint,
      gcashTint: gcashTint ?? this.gcashTint,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      good: Color.lerp(good, other.good, t)!,
      warn: Color.lerp(warn, other.warn, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      chartGrid: Color.lerp(chartGrid, other.chartGrid, t)!,
      cashTint: Color.lerp(cashTint, other.cashTint, t)!,
      creditTint: Color.lerp(creditTint, other.creditTint, t)!,
      gcashTint: Color.lerp(gcashTint, other.gcashTint, t)!,
    );
  }
}

extension AppColorsX on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
  ColorScheme get scheme => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
}

abstract class AppTheme {
  /// Tap targets are deliberately larger than Material's default. This is used
  /// one-handed, at speed, sometimes in poor light.
  static const double minTap = 52;
  static const double primaryTap = 60;

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: BrandColors.primary,
      brightness: brightness,
    ).copyWith(
      primary: isDark ? BrandColors.primaryDark : BrandColors.primary,
      onPrimary: isDark ? const Color(0xFF0A141B) : Colors.white,
      surface: isDark ? BrandColors.surfaceDark : BrandColors.surfaceLight,
      surfaceContainerLowest:
          isDark ? BrandColors.groundDark : BrandColors.groundLight,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor:
          isDark ? BrandColors.groundDark : BrandColors.groundLight,
      visualDensity: VisualDensity.standard,
    );

    return base.copyWith(
      extensions: [isDark ? AppColors.dark : AppColors.light],
      textTheme: base.textTheme.copyWith(
        displaySmall: base.textTheme.displaySmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
        headlineSmall: base.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        labelLarge: base.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor:
            isDark ? BrandColors.groundDark : BrandColors.groundLight,
        foregroundColor: scheme.onSurface,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, primaryTap),
          textStyle: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, minTap),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? const Color(0xFF1B2C38)
            : const Color(0xFFEDF1F1).withValues(alpha: 0.7),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.7),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primary.withValues(alpha: isDark ? 0.28 : 0.14),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.6),
        space: 1,
        thickness: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}
