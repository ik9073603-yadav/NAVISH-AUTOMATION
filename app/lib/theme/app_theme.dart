import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// The design system: one seed color elevated into a full light/dark palette,
// a real type scale (Sora for anything that should feel crafted — headings,
// buttons, numbers; Inter for anything that gets read in bulk — body copy,
// list rows), a spacing scale, and shared card/surface shaping. Every screen
// pulls from here instead of hardcoding TextStyle/Colors.* inline.

class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

class AppRadius {
  static const sm = 10.0;
  static const md = 16.0;
  static const lg = 20.0;
  static const pill = 999.0;
}

// Semantic colors, tuned separately for light/dark rather than one set
// dimmed by opacity — that's what keeps dark mode from reading as "light
// mode with the lights off."
class AppSemanticColors {
  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;
  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color onWarningContainer;
  final Color danger;
  final Color onDanger;
  final Color dangerContainer;
  final Color onDangerContainer;
  final Color info;
  final Color infoContainer;

  const AppSemanticColors({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.danger,
    required this.onDanger,
    required this.dangerContainer,
    required this.onDangerContainer,
    required this.info,
    required this.infoContainer,
  });

  static const light = AppSemanticColors(
    success: Color(0xFF1E7D4D),
    onSuccess: Color(0xFFFFFFFF),
    successContainer: Color(0xFFDCF3E4),
    onSuccessContainer: Color(0xFF0B3D22),
    warning: Color(0xFFB4740E),
    onWarning: Color(0xFFFFFFFF),
    warningContainer: Color(0xFFFCEACB),
    onWarningContainer: Color(0xFF4A2E00),
    danger: Color(0xFFC22B3B),
    onDanger: Color(0xFFFFFFFF),
    dangerContainer: Color(0xFFFBDBDE),
    onDangerContainer: Color(0xFF5C0E17),
    info: Color(0xFF2563A8),
    infoContainer: Color(0xFFDBEAFB),
  );

  static const dark = AppSemanticColors(
    success: Color(0xFF6FDB9C),
    onSuccess: Color(0xFF063820),
    successContainer: Color(0xFF14512F),
    onSuccessContainer: Color(0xFFC3F2D5),
    warning: Color(0xFFF3BB63),
    onWarning: Color(0xFF422A00),
    warningContainer: Color(0xFF5F3F06),
    onWarningContainer: Color(0xFFFBE2B8),
    danger: Color(0xFFF2909B),
    onDanger: Color(0xFF57070F),
    dangerContainer: Color(0xFF7A1F29),
    onDangerContainer: Color(0xFFFAD3D7),
    info: Color(0xFF8FC1F0),
    infoContainer: Color(0xFF204A70),
  );
}

class AppColors {
  static AppSemanticColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.brightness == Brightness.dark
        ? AppSemanticColors.dark
        : AppSemanticColors.light;
  }
}

class AppTheme {
  static const _seed = Color(0xFF0F5132);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);

    final displayFont = GoogleFonts.sora;
    final bodyFont = GoogleFonts.inter;
    // Sora/Inter only cover Latin glyphs. When the Hindi locale is active,
    // Text widgets render Devanagari — without a fallback those characters
    // draw as tofu boxes. Noto Sans Devanagari fills in exactly those
    // glyphs while leaving Latin text on Sora/Inter untouched.
    final devanagariFallback = [GoogleFonts.notoSansDevanagari().fontFamily!];

    final base = ThemeData(colorScheme: scheme, useMaterial3: true, brightness: brightness);

    final textTheme = TextTheme(
      displayLarge: displayFont(fontSize: 40, fontWeight: FontWeight.w800, letterSpacing: -0.5),
      displayMedium: displayFont(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -0.4),
      displaySmall: displayFont(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.2),
      headlineLarge: displayFont(fontSize: 24, fontWeight: FontWeight.w700),
      headlineMedium: displayFont(fontSize: 20, fontWeight: FontWeight.w700),
      headlineSmall: displayFont(fontSize: 18, fontWeight: FontWeight.w700),
      titleLarge: displayFont(fontSize: 17, fontWeight: FontWeight.w700),
      titleMedium: bodyFont(fontSize: 15, fontWeight: FontWeight.w600),
      titleSmall: bodyFont(fontSize: 13, fontWeight: FontWeight.w600),
      bodyLarge: bodyFont(fontSize: 16, fontWeight: FontWeight.w400),
      bodyMedium: bodyFont(fontSize: 14, fontWeight: FontWeight.w400),
      bodySmall: bodyFont(fontSize: 12, fontWeight: FontWeight.w400, color: scheme.onSurfaceVariant),
      labelLarge: bodyFont(fontSize: 14, fontWeight: FontWeight.w600),
      labelMedium: bodyFont(fontSize: 12, fontWeight: FontWeight.w600),
      labelSmall: bodyFont(fontSize: 11, fontWeight: FontWeight.w600),
    ).apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
      fontFamilyFallback: devanagariFallback,
    );

    final cardSurface = isDark ? const Color(0xFF1B2320) : Colors.white;

    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.headlineSmall,
      ),
      cardTheme: CardThemeData(
        color: cardSurface,
        elevation: isDark ? 0 : 1,
        shadowColor: Colors.black.withValues(alpha: isDark ? 0 : 0.08),
        surfaceTintColor: Colors.transparent,
        margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(
            color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
          ),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? Colors.white.withValues(alpha: 0.04) : scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.md),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.md),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(textStyle: textTheme.labelLarge),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: cardSurface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        elevation: 0,
        height: 64,
        labelTextStyle: WidgetStateProperty.all(textTheme.labelSmall),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: cardSurface,
        indicatorColor: scheme.primaryContainer,
        selectedLabelTextStyle: textTheme.labelMedium?.copyWith(color: scheme.onSurface),
        unselectedLabelTextStyle: textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      }),
    );
  }
}
