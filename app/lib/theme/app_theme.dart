import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// The design system: a deliberate luxury palette (deep charcoal/near-black
// in dark, warm cream/paper in light — one champagne-gold accent used
// sparingly for emphasis) elevated into a full ColorScheme, a real type
// scale (Sora for anything that should feel crafted — headings, buttons,
// numbers; Inter for anything read in bulk — body copy, list rows), a
// spacing scale, and shared card/surface shaping. Every screen pulls from
// here instead of hardcoding TextStyle/Colors.* inline.

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
// mode with the lights off." Deliberately restrained jewel tones (deep
// teal for success, muted ochre for warning, muted burgundy for danger) —
// none of them the flat/bright hues that read cheap, and none of them
// competing with the champagne-gold accent used for primary actions.
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
    success: Color(0xFF2F6F5E),
    onSuccess: Color(0xFFFFFFFF),
    successContainer: Color(0xFFDCEEE6),
    onSuccessContainer: Color(0xFF0E3A2E),
    warning: Color(0xFFA05D18),
    onWarning: Color(0xFFFFFFFF),
    warningContainer: Color(0xFFF5DFBD),
    onWarningContainer: Color(0xFF402400),
    danger: Color(0xFF9C3B3B),
    onDanger: Color(0xFFFFFFFF),
    dangerContainer: Color(0xFFF2D9D6),
    onDangerContainer: Color(0xFF4A1414),
    info: Color(0xFF3D5A75),
    infoContainer: Color(0xFFDCE6EE),
  );

  static const dark = AppSemanticColors(
    success: Color(0xFF6FC9AC),
    onSuccess: Color(0xFF08281F),
    successContainer: Color(0xFF17392E),
    onSuccessContainer: Color(0xFFC9EEDF),
    warning: Color(0xFFE3A55E),
    onWarning: Color(0xFF3D2200),
    warningContainer: Color(0xFF4A3115),
    onWarningContainer: Color(0xFFF6DEB8),
    danger: Color(0xFFE1877E),
    onDanger: Color(0xFF400E0B),
    dangerContainer: Color(0xFF5A211C),
    onDangerContainer: Color(0xFFF6D9D4),
    info: Color(0xFF9BC0DD),
    infoContainer: Color(0xFF26445A),
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

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    // Hand-tuned rather than ColorScheme.fromSeed — a true near-black base
    // with a single champagne-gold accent needs deliberate values, not an
    // algorithmic tonal palette (which never quite reaches "near-black").
    final scheme = isDark
        ? const ColorScheme.dark(
            primary: Color(0xFFC6A15B),
            onPrimary: Color(0xFF1A1409),
            primaryContainer: Color(0xFF3A2F17),
            onPrimaryContainer: Color(0xFFE9CE96),
            secondary: Color(0xFFB7B2A6),
            onSecondary: Color(0xFF211F1A),
            secondaryContainer: Color(0xFF33312A),
            onSecondaryContainer: Color(0xFFDAD5C7),
            tertiary: Color(0xFF8C6A3F),
            onTertiary: Color(0xFFFFFFFF),
            tertiaryContainer: Color(0xFF3E2F16),
            onTertiaryContainer: Color(0xFFE9CE96),
            error: Color(0xFFE1877E),
            onError: Color(0xFF400E0B),
            errorContainer: Color(0xFF5A211C),
            onErrorContainer: Color(0xFFF6D9D4),
            surface: Color(0xFF16151A),
            onSurface: Color(0xFFF1ECE0),
            onSurfaceVariant: Color(0xFFA29C8E),
            outline: Color(0xFF56504A),
            outlineVariant: Color(0xFF322F37),
            surfaceContainerLowest: Color(0xFF08080A),
            surfaceContainerLow: Color(0xFF121116),
            surfaceContainer: Color(0xFF1B1A1F),
            surfaceContainerHigh: Color(0xFF201E24),
            surfaceContainerHighest: Color(0xFF29272E),
            inverseSurface: Color(0xFFF1ECE0),
            onInverseSurface: Color(0xFF201E24),
            inversePrimary: Color(0xFF8A6A2E),
            scrim: Colors.black,
            shadow: Colors.black,
          )
        : const ColorScheme.light(
            primary: Color(0xFF8A6A2E),
            onPrimary: Color(0xFFFFFFFF),
            primaryContainer: Color(0xFFE8D9AE),
            onPrimaryContainer: Color(0xFF4A3714),
            secondary: Color(0xFF8A8272),
            onSecondary: Color(0xFFFFFFFF),
            secondaryContainer: Color(0xFFEDE7D8),
            onSecondaryContainer: Color(0xFF3A362A),
            tertiary: Color(0xFF6E4F26),
            onTertiary: Color(0xFFFFFFFF),
            tertiaryContainer: Color(0xFFEFDFC0),
            onTertiaryContainer: Color(0xFF3A2A10),
            error: Color(0xFF9C3B3B),
            onError: Color(0xFFFFFFFF),
            errorContainer: Color(0xFFF2D9D6),
            onErrorContainer: Color(0xFF4A1414),
            surface: Color(0xFFFFFDF8),
            onSurface: Color(0xFF221C10),
            onSurfaceVariant: Color(0xFF6B6252),
            outline: Color(0xFFB4A98A),
            outlineVariant: Color(0xFFE3D9BF),
            surfaceContainerLowest: Color(0xFFFFFFFF),
            surfaceContainerLow: Color(0xFFF7F2E7),
            surfaceContainer: Color(0xFFF1EAD8),
            surfaceContainerHigh: Color(0xFFEBE3CE),
            surfaceContainerHighest: Color(0xFFE5DBC2),
            inverseSurface: Color(0xFF362F22),
            onInverseSurface: Color(0xFFF7F2E7),
            inversePrimary: Color(0xFFC6A15B),
            scrim: Colors.black,
            shadow: Colors.black,
          );

    final displayFont = GoogleFonts.sora;
    final bodyFont = GoogleFonts.inter;
    // Sora/Inter only cover Latin glyphs. When the Hindi locale is active,
    // Text widgets render Devanagari — without a fallback those characters
    // draw as tofu boxes. Noto Sans Devanagari fills in exactly those
    // glyphs while leaving Latin text on Sora/Inter untouched.
    final devanagariFallback = [GoogleFonts.notoSansDevanagari().fontFamily!];

    final base = ThemeData(colorScheme: scheme, useMaterial3: true, brightness: brightness);

    final textTheme = TextTheme(
      displayLarge: displayFont(fontSize: 40, fontWeight: FontWeight.w800, letterSpacing: -0.6),
      displayMedium: displayFont(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -0.5),
      displaySmall: displayFont(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.3),
      headlineLarge: displayFont(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.2),
      headlineMedium: displayFont(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.1),
      headlineSmall: displayFont(fontSize: 18, fontWeight: FontWeight.w700),
      titleLarge: displayFont(fontSize: 17, fontWeight: FontWeight.w700),
      titleMedium: bodyFont(fontSize: 15, fontWeight: FontWeight.w600),
      titleSmall: bodyFont(fontSize: 13, fontWeight: FontWeight.w600),
      bodyLarge: bodyFont(fontSize: 16, fontWeight: FontWeight.w400),
      bodyMedium: bodyFont(fontSize: 14, fontWeight: FontWeight.w400),
      bodySmall: bodyFont(fontSize: 12, fontWeight: FontWeight.w400, color: scheme.onSurfaceVariant),
      labelLarge: bodyFont(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.2),
      labelMedium: bodyFont(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.2),
      labelSmall: bodyFont(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.2),
    ).apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
      fontFamilyFallback: devanagariFallback,
    );

    // The scaffold sits a shade deeper than card/appbar/nav surfaces —
    // that gentle separation is what reads as "layered, considered depth"
    // instead of one flat slab of color.
    final scaffoldBg = isDark ? const Color(0xFF0C0C0E) : const Color(0xFFF7F2E7);

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
        elevation: isDark ? 2 : 1,
        shadowColor: Colors.black.withValues(alpha: isDark ? 0.5 : 0.10),
        surfaceTintColor: Colors.transparent,
        margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: isDark ? 0.7 : 0.6)),
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
          side: BorderSide(color: scheme.outline.withValues(alpha: 0.5)),
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
      dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.6)),
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
