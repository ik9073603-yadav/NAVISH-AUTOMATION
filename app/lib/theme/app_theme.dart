import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// The design system: an operations-platform identity — neutral cool-gray
// surfaces with a single restrained indigo accent (pulled from the app
// icon's dominant hue, desaturated for all-day dashboard use), one type
// family (Inter) sized for dense tables and long sessions rather than a
// marketing-site display face, and status conveyed by color + icon/label
// together, never color alone. Every screen pulls from here instead of
// hardcoding TextStyle/Colors.* inline.

class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

class AppRadius {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const pill = 999.0;
}

// Semantic status colors, tuned separately for light/dark. Deliberately a
// different hue family from the primary accent (teal-green / amber / brick
// red / slate-blue vs. the indigo primary) so "this is clickable" and
// "this is a status" are never visually confused — and each pair keeps
// >=4.5:1 text contrast against its own container.
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
    success: Color(0xFF1F7A5C),
    onSuccess: Color(0xFFFFFFFF),
    successContainer: Color(0xFFD8F0E4),
    onSuccessContainer: Color(0xFF0B3B2A),
    warning: Color(0xFF8A5A00),
    onWarning: Color(0xFFFFFFFF),
    warningContainer: Color(0xFFF6E2B8),
    onWarningContainer: Color(0xFF3D2600),
    danger: Color(0xFFB3261E),
    onDanger: Color(0xFFFFFFFF),
    dangerContainer: Color(0xFFF9DEDC),
    onDangerContainer: Color(0xFF410E0B),
    info: Color(0xFF3B5BA5),
    infoContainer: Color(0xFFDCE6F5),
  );

  static const dark = AppSemanticColors(
    success: Color(0xFF6FD3AE),
    onSuccess: Color(0xFF07332A),
    successContainer: Color(0xFF15382C),
    onSuccessContainer: Color(0xFFBEEBD7),
    warning: Color(0xFFE0A93D),
    onWarning: Color(0xFF3D2900),
    warningContainer: Color(0xFF493107),
    onWarningContainer: Color(0xFFF6DFB0),
    danger: Color(0xFFE2897F),
    onDanger: Color(0xFF410E0B),
    dangerContainer: Color(0xFF54221D),
    onDangerContainer: Color(0xFFF9DAD6),
    info: Color(0xFF9AC0EE),
    infoContainer: Color(0xFF23375A),
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
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  // Applies tabular (fixed-width) figures to a text style — use for any
  // numeral that appears in a table, stat tile, or the Health Score gauge,
  // so digits align instead of jittering as they change.
  static TextStyle tabularFigures(TextStyle? style) =>
      (style ?? const TextStyle()).copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    // Hand-tuned rather than ColorScheme.fromSeed — a true neutral-gray
    // base with one indigo accent needs deliberate values, not an
    // algorithmic tonal palette built around the seed hue everywhere.
    final scheme = isDark
        ? const ColorScheme.dark(
            primary: Color(0xFF8C93F0),
            onPrimary: Color(0xFF1B1F4D),
            primaryContainer: Color(0xFF333B85),
            onPrimaryContainer: Color(0xFFE1E2FA),
            secondary: Color(0xFFAEB1C4),
            onSecondary: Color(0xFF1F212B),
            secondaryContainer: Color(0xFF383B4A),
            onSecondaryContainer: Color(0xFFDCDDE8),
            tertiary: Color(0xFF7C97C9),
            onTertiary: Color(0xFF0F2038),
            tertiaryContainer: Color(0xFF223357),
            onTertiaryContainer: Color(0xFFD3E1F5),
            error: Color(0xFFE2897F),
            onError: Color(0xFF410E0B),
            errorContainer: Color(0xFF54221D),
            onErrorContainer: Color(0xFFF9DAD6),
            surface: Color(0xFF121317),
            onSurface: Color(0xFFE7E8ED),
            onSurfaceVariant: Color(0xFFA6A9B4),
            outline: Color(0xFF5C5F6B),
            outlineVariant: Color(0xFF34363F),
            surfaceContainerLowest: Color(0xFF08090B),
            surfaceContainerLow: Color(0xFF17181D),
            surfaceContainer: Color(0xFF1C1D23),
            surfaceContainerHigh: Color(0xFF212228),
            surfaceContainerHighest: Color(0xFF2A2B33),
            inverseSurface: Color(0xFFE7E8ED),
            onInverseSurface: Color(0xFF212228),
            inversePrimary: Color(0xFF4B57C9),
            scrim: Colors.black,
            shadow: Colors.black,
          )
        : const ColorScheme.light(
            primary: Color(0xFF4B57C9),
            onPrimary: Color(0xFFFFFFFF),
            primaryContainer: Color(0xFFE1E2FA),
            onPrimaryContainer: Color(0xFF232A73),
            secondary: Color(0xFF5B5F73),
            onSecondary: Color(0xFFFFFFFF),
            secondaryContainer: Color(0xFFE2E2ED),
            onSecondaryContainer: Color(0xFF32354A),
            tertiary: Color(0xFF3F5B8C),
            onTertiary: Color(0xFFFFFFFF),
            tertiaryContainer: Color(0xFFD9E5F7),
            onTertiaryContainer: Color(0xFF122544),
            error: Color(0xFFB3261E),
            onError: Color(0xFFFFFFFF),
            errorContainer: Color(0xFFF9DEDC),
            onErrorContainer: Color(0xFF410E0B),
            surface: Color(0xFFF8F9FB),
            onSurface: Color(0xFF1B1C20),
            onSurfaceVariant: Color(0xFF5B5E68),
            outline: Color(0xFF8B8E99),
            outlineVariant: Color(0xFFD8DADF),
            surfaceContainerLowest: Color(0xFFFFFFFF),
            surfaceContainerLow: Color(0xFFF1F2F5),
            surfaceContainer: Color(0xFFECEDF1),
            surfaceContainerHigh: Color(0xFFE6E7ED),
            surfaceContainerHighest: Color(0xFFE0E1E8),
            inverseSurface: Color(0xFF2E2F36),
            onInverseSurface: Color(0xFFF1F1F5),
            inversePrimary: Color(0xFFBAC0F5),
            scrim: Colors.black,
            shadow: Colors.black,
          );

    // One font family for the whole app — Inter — rather than a separate
    // display face. Dense tables, stat tiles, and long sessions read
    // better from one well-hinted grotesque than a two-family split whose
    // only job was decorative flourish.
    final uiFont = GoogleFonts.inter;
    // Inter covers Latin only. When the Hindi locale is active, Text
    // widgets render Devanagari — without a fallback those characters draw
    // as tofu boxes. Noto Sans Devanagari fills in exactly those glyphs
    // while leaving Latin text on Inter untouched.
    final devanagariFallback = [GoogleFonts.notoSansDevanagari().fontFamily!];

    final base = ThemeData(colorScheme: scheme, useMaterial3: true, brightness: brightness);

    // Compressed vs. a marketing-site scale — almost every Navish screen
    // is a list, table, or form, not a landing page, so display sizes stay
    // modest and body/label sizes get the real estate.
    final textTheme = TextTheme(
      displayLarge: uiFont(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.4),
      displayMedium: uiFont(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.3),
      displaySmall: uiFont(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.2),
      headlineLarge: uiFont(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.1),
      headlineMedium: uiFont(fontSize: 17, fontWeight: FontWeight.w700),
      headlineSmall: uiFont(fontSize: 16, fontWeight: FontWeight.w700),
      titleLarge: uiFont(fontSize: 15, fontWeight: FontWeight.w700),
      titleMedium: uiFont(fontSize: 14, fontWeight: FontWeight.w600),
      titleSmall: uiFont(fontSize: 13, fontWeight: FontWeight.w600),
      bodyLarge: uiFont(fontSize: 15, fontWeight: FontWeight.w400),
      bodyMedium: uiFont(fontSize: 14, fontWeight: FontWeight.w400),
      bodySmall: uiFont(fontSize: 12, fontWeight: FontWeight.w400, color: scheme.onSurfaceVariant),
      labelLarge: uiFont(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.1),
      labelMedium: uiFont(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.1),
      labelSmall: uiFont(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.1),
    ).apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
      fontFamilyFallback: devanagariFallback,
    );

    // The scaffold sits a shade deeper than card/appbar/nav surfaces — that
    // gentle separation reads as layered structure instead of one flat slab.
    final scaffoldBg = isDark ? const Color(0xFF0A0B0D) : const Color(0xFFF2F3F6);

    return base.copyWith(
      scaffoldBackgroundColor: scaffoldBg,
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
        color: scheme.surface,
        elevation: isDark ? 1 : 0,
        shadowColor: Colors.black.withValues(alpha: isDark ? 0.4 : 0.08),
        surfaceTintColor: Colors.transparent,
        margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: isDark ? 0.7 : 0.8)),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHigh,
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
          borderSide: BorderSide(color: scheme.primary, width: 2),
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
          side: BorderSide(color: scheme.outline.withValues(alpha: 0.6)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(textStyle: textTheme.labelLarge),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        elevation: 0,
        height: 64,
        labelTextStyle: WidgetStateProperty.all(textTheme.labelSmall),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        selectedLabelTextStyle: textTheme.labelMedium?.copyWith(color: scheme.onSurface),
        unselectedLabelTextStyle: textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: scheme.onInverseSurface),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
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
