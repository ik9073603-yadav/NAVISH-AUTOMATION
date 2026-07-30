import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// The design system: a premium-SaaS identity built on Navish's own brand
// gradient (violet -> teal -> magenta, from the app icon) rather than a
// generic palette — violet stays the signature/primary accent, teal and
// magenta surface as secondary accents, and status/category colors take a
// warm, soft-pastel-vivid register (color-blocked card fills, not dots)
// instead of harsh saturated red/green. One consistent, generous radius
// scale and soft ambient shadows replace the flat/bordered operational
// look. Every screen pulls from here instead of hardcoding TextStyle/
// Colors.* inline.

class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

class AppRadius {
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const pill = 999.0;
}

// Semantic status colors — warm, soft-pastel-vivid rather than default
// red/green (the inspiration's color-blocked cards read as premium because
// the hues are warm and sit comfortably next to each other, not because
// they're loud). Each pair keeps >=4.5:1 text contrast against its own
// container, and status is always paired with an icon/label, never color
// alone.
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
  final Color onInfo;
  final Color infoContainer;
  final Color onInfoContainer;

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
    required this.onInfo,
    required this.infoContainer,
    required this.onInfoContainer,
  });

  static const light = AppSemanticColors(
    success: Color(0xFF1F9254),
    onSuccess: Color(0xFFFFFFFF),
    successContainer: Color(0xFFD8F0E1),
    onSuccessContainer: Color(0xFF0B3B21),
    warning: Color(0xFFC97A00),
    onWarning: Color(0xFFFFFFFF),
    warningContainer: Color(0xFFFCE8BD),
    onWarningContainer: Color(0xFF4A2E00),
    danger: Color(0xFFD6493B),
    onDanger: Color(0xFFFFFFFF),
    dangerContainer: Color(0xFFFCE0DB),
    onDangerContainer: Color(0xFF4A1810),
    info: Color(0xFF2F6FE0),
    onInfo: Color(0xFFFFFFFF),
    infoContainer: Color(0xFFDCE8FC),
    onInfoContainer: Color(0xFF122F63),
  );

  static const dark = AppSemanticColors(
    success: Color(0xFF5FCB8D),
    onSuccess: Color(0xFF07331B),
    successContainer: Color(0xFF163A26),
    onSuccessContainer: Color(0xFFC5EFD6),
    warning: Color(0xFFF0B44D),
    onWarning: Color(0xFF3D2900),
    warningContainer: Color(0xFF483008),
    onWarningContainer: Color(0xFFFCE3B4),
    danger: Color(0xFFF0897C),
    onDanger: Color(0xFF400E08),
    dangerContainer: Color(0xFF522019),
    onDangerContainer: Color(0xFFFCDAD3),
    info: Color(0xFF83B2F7),
    onInfo: Color(0xFF0B2A54),
    infoContainer: Color(0xFF1E3A5F),
    onInfoContainer: Color(0xFFD3E4FC),
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

// Signature brand accents beyond the 3 ColorScheme slots — pulled straight
// from the app icon's gradient (violet primary, teal, magenta). Used
// sparingly for "this is the one thing to notice" moments: a featured KPI,
// an AI badge, a hero card — never as general-purpose UI color.
class AppAccents {
  final Color teal;
  final Color onTeal;
  final Color tealContainer;
  final Color onTealContainer;
  final Color magenta;
  final Color onMagenta;
  final Color magentaContainer;
  final Color onMagentaContainer;
  // The near-black/rich-violet "hero card" fill used for the single most
  // important actionable item on a screen, breaking the lighter field
  // around it — light mode uses near-black, dark mode uses a rich violet
  // (a black-on-black hero wouldn't read as elevated in dark mode).
  final Color hero;
  final Color onHero;

  const AppAccents({
    required this.teal,
    required this.onTeal,
    required this.tealContainer,
    required this.onTealContainer,
    required this.magenta,
    required this.onMagenta,
    required this.magentaContainer,
    required this.onMagentaContainer,
    required this.hero,
    required this.onHero,
  });

  static const light = AppAccents(
    teal: Color(0xFF0E9488),
    onTeal: Color(0xFFFFFFFF),
    tealContainer: Color(0xFFD3F2ED),
    onTealContainer: Color(0xFF063C36),
    magenta: Color(0xFFC23B8E),
    onMagenta: Color(0xFFFFFFFF),
    magentaContainer: Color(0xFFF9DCEE),
    onMagentaContainer: Color(0xFF4A1636),
    hero: Color(0xFF161320),
    onHero: Color(0xFFF5F3FA),
  );

  static const dark = AppAccents(
    teal: Color(0xFF5FD1C4),
    onTeal: Color(0xFF04332E),
    tealContainer: Color(0xFF124039),
    onTealContainer: Color(0xFFC7F2EB),
    magenta: Color(0xFFE87FC0),
    onMagenta: Color(0xFF43123A),
    magentaContainer: Color(0xFF4A1F42),
    onMagentaContainer: Color(0xFFF9D9EC),
    hero: Color(0xFF6D4FE0),
    onHero: Color(0xFFFFFFFF),
  );

  static AppAccents of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.brightness == Brightness.dark ? dark : light;
  }
}

class AppTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  // Applies tabular (fixed-width) figures to a text style — use for any
  // numeral that appears in a table, stat tile, or a gauge, so digits align
  // instead of jittering as they change.
  static TextStyle tabularFigures(TextStyle? style) =>
      (style ?? const TextStyle()).copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  // The small uppercase tracked-out "eyebrow" label used as a section
  // header throughout the reference ("PERSONAL RESET", "LAST 14 DAYS") —
  // pass already-uppercased text; this only supplies the style.
  static TextStyle eyebrow(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GoogleFonts.inter(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.0,
      color: scheme.onSurfaceVariant,
    );
  }

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    // Hand-tuned rather than ColorScheme.fromSeed — the brand's violet
    // needs a deliberate tonal ramp, not an algorithmic one seeded off it.
    final scheme = isDark
        ? const ColorScheme.dark(
            primary: Color(0xFFB4A0FF),
            onPrimary: Color(0xFF241560),
            primaryContainer: Color(0xFF3D2C85),
            onPrimaryContainer: Color(0xFFE7DFFF),
            secondary: Color(0xFFAEB1C4),
            onSecondary: Color(0xFF1F212B),
            secondaryContainer: Color(0xFF383B4A),
            onSecondaryContainer: Color(0xFFDCDDE8),
            tertiary: Color(0xFF5FD1C4),
            onTertiary: Color(0xFF04332E),
            tertiaryContainer: Color(0xFF124039),
            onTertiaryContainer: Color(0xFFC7F2EB),
            error: Color(0xFFF0897C),
            onError: Color(0xFF400E08),
            errorContainer: Color(0xFF522019),
            onErrorContainer: Color(0xFFFCDAD3),
            surface: Color(0xFF1C1A20),
            onSurface: Color(0xFFEDE9F2),
            onSurfaceVariant: Color(0xFFACA6B8),
            outline: Color(0xFF5F5A6C),
            outlineVariant: Color(0xFF35323D),
            surfaceContainerLowest: Color(0xFF0C0A10),
            surfaceContainerLow: Color(0xFF181620),
            surfaceContainer: Color(0xFF201D28),
            surfaceContainerHigh: Color(0xFF29252F),
            surfaceContainerHighest: Color(0xFF322E3B),
            inverseSurface: Color(0xFFEDE9F2),
            onInverseSurface: Color(0xFF29252F),
            inversePrimary: Color(0xFF6D4FE0),
            scrim: Colors.black,
            shadow: Colors.black,
          )
        : const ColorScheme.light(
            primary: Color(0xFF6D4FE0),
            onPrimary: Color(0xFFFFFFFF),
            primaryContainer: Color(0xFFE9E2FC),
            onPrimaryContainer: Color(0xFF3A2585),
            secondary: Color(0xFF5B5F73),
            onSecondary: Color(0xFFFFFFFF),
            secondaryContainer: Color(0xFFE2E2ED),
            onSecondaryContainer: Color(0xFF32354A),
            tertiary: Color(0xFF0E9488),
            onTertiary: Color(0xFFFFFFFF),
            tertiaryContainer: Color(0xFFD3F2ED),
            onTertiaryContainer: Color(0xFF063C36),
            error: Color(0xFFD6493B),
            onError: Color(0xFFFFFFFF),
            errorContainer: Color(0xFFFCE0DB),
            onErrorContainer: Color(0xFF4A1810),
            surface: Color(0xFFFFFFFF),
            onSurface: Color(0xFF1E1B24),
            onSurfaceVariant: Color(0xFF63606E),
            outline: Color(0xFF938F9E),
            outlineVariant: Color(0xFFE4E0EB),
            surfaceContainerLowest: Color(0xFFFFFFFF),
            surfaceContainerLow: Color(0xFFF7F5F2),
            surfaceContainer: Color(0xFFF1EEEA),
            surfaceContainerHigh: Color(0xFFEBE7E3),
            surfaceContainerHighest: Color(0xFFE4E0DB),
            inverseSurface: Color(0xFF322E3B),
            onInverseSurface: Color(0xFFF5F2FA),
            inversePrimary: Color(0xFFB4A0FF),
            scrim: Colors.black,
            shadow: Colors.black,
          );

    // Two-tier system: Plus Jakarta Sans carries headings/hero numbers
    // (geometric, warm, confident at large sizes — reads premium, not
    // generic), Inter carries body/tables (unmatched legibility at small
    // sizes, tabular figures, full language coverage for the dense/
    // bilingual screens most of this app actually is).
    final displayFont = GoogleFonts.plusJakartaSans;
    final bodyFont = GoogleFonts.inter;
    // Neither Latin face covers Devanagari. When the Hindi locale is
    // active, Text widgets render Devanagari — without a fallback those
    // characters draw as tofu boxes. Noto Sans Devanagari fills in exactly
    // those glyphs while leaving Latin text on the chosen face untouched.
    final devanagariFallback = [GoogleFonts.notoSansDevanagari().fontFamily!];

    final base = ThemeData(colorScheme: scheme, useMaterial3: true, brightness: brightness);

    // Confident hierarchy: display sizes are larger and heavier than the
    // flat operational scale (this app should have hero numbers, not just
    // readable ones), while body/label sizes stay tuned for dense tables.
    final textTheme = TextTheme(
      displayLarge: displayFont(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -0.6),
      displayMedium: displayFont(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.4),
      displaySmall: displayFont(fontSize: 23, fontWeight: FontWeight.w700, letterSpacing: -0.3),
      headlineLarge: displayFont(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.2),
      headlineMedium: displayFont(fontSize: 18, fontWeight: FontWeight.w700),
      headlineSmall: displayFont(fontSize: 16, fontWeight: FontWeight.w700),
      titleLarge: displayFont(fontSize: 15, fontWeight: FontWeight.w700),
      titleMedium: bodyFont(fontSize: 14, fontWeight: FontWeight.w600),
      titleSmall: bodyFont(fontSize: 13, fontWeight: FontWeight.w600),
      bodyLarge: bodyFont(fontSize: 15, fontWeight: FontWeight.w400),
      bodyMedium: bodyFont(fontSize: 14, fontWeight: FontWeight.w400),
      bodySmall: bodyFont(fontSize: 12, fontWeight: FontWeight.w400, color: scheme.onSurfaceVariant),
      labelLarge: bodyFont(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.1),
      labelMedium: bodyFont(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.1),
      labelSmall: bodyFont(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.1),
    ).apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
      fontFamilyFallback: devanagariFallback,
    );

    // The scaffold sits a shade deeper than card/appbar/nav surfaces — that
    // gentle separation reads as layered structure. Warm off-white/near-
    // black rather than cool gray, matching the softer, friendlier palette.
    final scaffoldBg = isDark ? const Color(0xFF121014) : const Color(0xFFF7F5F2);

    return base.copyWith(
      scaffoldBackgroundColor: scaffoldBg,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldBg,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.headlineSmall,
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: isDark ? 0 : 1,
        shadowColor: Colors.black.withValues(alpha: isDark ? 0.5 : 0.06),
        surfaceTintColor: Colors.transparent,
        margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: isDark ? 0.6 : 0.7)),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.md),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
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
