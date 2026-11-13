import 'package:flutter/material.dart';

/// Mist's soft forms with the Vermilion palette.
class AppColors {
  AppColors._();
  static const bg = Color(0xFFF4F0E6);
  static const bgElevated = bg;
  static const bgCard = bg;
  static const bgCardHover = Color(0xFFEADBC9);
  static const border = Color(0xFFD9D3C5);
  static const borderFocus = accent;
  static const textPrimary = Color(0xFF292A23);
  static const textSecondary = Color(0xFF827F71);
  static const textMuted = textSecondary;
  static const accent = Color(0xFFC64129);
  static const onAccent = Color(0xFFFFF9ED);
  static const accentSoft = Color(0xFFEADBC9);
  static const danger = Color(0xFFB33524);
  static const talkA = bg;
  static const talkB = Color(0xFFE6E3D6);
  static const navigation = Color(0xFFE9E5D9);
  // Semantic aliases keep existing device and processing states consistent.
  static const mint = accent;
  static const amber = textSecondary;
  static const coral = danger;
  static const violet = accent;
  static const gradientTop = bg;
  static const gradientBottom = bg;

  static List<BoxShadow> get cardShadow => [
    BoxShadow(
      color: textPrimary.withValues(alpha: 0.045),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ];
}

class AppTypography {
  AppTypography._();
  static const serif = 'Songti SC';
  static const serifFallback = ['STSong', 'Noto Serif CJK SC', 'serif'];
  static const heading = TextStyle(
    fontFamily: serif,
    fontFamilyFallback: serifFallback,
    fontSize: 29,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.5,
    color: AppColors.textPrimary,
  );
  static const number = TextStyle(
    fontFamily: 'Baskerville',
    fontFamilyFallback: ['Georgia', 'Songti SC', 'serif'],
    fontWeight: FontWeight.w400,
    color: AppColors.accent,
  );
}

class AppTheme {
  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      fontFamily: 'PingFang SC',
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: const ColorScheme.light(
        surface: AppColors.bgElevated,
        primary: AppColors.accent,
        secondary: AppColors.mint,
        error: AppColors.coral,
        onPrimary: AppColors.onAccent,
        onSurface: AppColors.textPrimary,
        outline: AppColors.border,
        outlineVariant: AppColors.border,
        primaryContainer: AppColors.accentSoft,
        onPrimaryContainer: AppColors.textPrimary,
        onSecondary: AppColors.onAccent,
        secondaryContainer: AppColors.navigation,
        onSecondaryContainer: AppColors.textPrimary,
        tertiary: AppColors.accent,
        onTertiary: AppColors.onAccent,
        tertiaryContainer: AppColors.accentSoft,
        onTertiaryContainer: AppColors.textPrimary,
        onError: AppColors.onAccent,
        errorContainer: AppColors.accentSoft,
        onErrorContainer: AppColors.danger,
        onSurfaceVariant: AppColors.textSecondary,
        surfaceDim: AppColors.navigation,
        surfaceBright: AppColors.onAccent,
        surfaceContainerLowest: AppColors.bg,
        surfaceContainerLow: AppColors.bg,
        surfaceContainer: AppColors.bg,
        surfaceContainerHigh: AppColors.accentSoft,
        surfaceContainerHighest: AppColors.talkB,
        surfaceTint: Colors.transparent,
        inverseSurface: AppColors.textPrimary,
        onInverseSurface: AppColors.bg,
        inversePrimary: AppColors.accentSoft,
        shadow: AppColors.textPrimary,
        scrim: AppColors.textPrimary,
      ),
    );

    return base.copyWith(
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.accentSoft.withValues(alpha: .35),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(23),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(23),
          borderSide: const BorderSide(color: AppColors.border),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: const WidgetStatePropertyAll(StadiumBorder()),
          side: const WidgetStatePropertyAll(BorderSide.none),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? AppColors.accentSoft
                : AppColors.navigation,
          ),
          foregroundColor: const WidgetStatePropertyAll(AppColors.textPrimary),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(38)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: AppTypography.heading.copyWith(fontSize: 26),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: AppTypography.heading,
        iconTheme: IconThemeData(color: AppColors.textPrimary),
      ),
      textTheme: base.textTheme.merge(
        const TextTheme(
          displayLarge: TextStyle(
            fontFamily: AppTypography.serif,
            fontFamilyFallback: AppTypography.serifFallback,
            fontSize: 34,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
            letterSpacing: 1,
            height: 1.1,
          ),
          headlineMedium: TextStyle(
            fontFamily: AppTypography.serif,
            fontFamilyFallback: AppTypography.serifFallback,
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
            letterSpacing: -0.4,
          ),
          titleMedium: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
          bodyLarge: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w400,
            color: AppColors.textPrimary,
            height: 1.4,
          ),
          bodyMedium: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w400,
            color: AppColors.textSecondary,
            height: 1.4,
          ),
          labelLarge: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.bgElevated,
        contentTextStyle: const TextStyle(color: AppColors.textPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
        elevation: 4,
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(AppColors.bgCard),
        ),
      ),
    );
  }

  /// Backward-compatible alias.
  static ThemeData get dark => light;
}
