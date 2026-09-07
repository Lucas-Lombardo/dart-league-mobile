import 'package:flutter/material.dart';

/// Visual system (2026-09 "Système D"): Manrope, one accent, flat surfaces,
/// hairline borders, sentence case. Colors are the historical tokens; what
/// changed is how few of them any one screen is allowed to use:
/// - ONE filled primary block per screen (the main action) + the Play button.
/// - accent (gold) = premium crown and physical trophies only.
/// - secondary (rose) = "live" dot, and the opponent identity in-match.
/// - success / error = win / loss / presence.
class AppTheme {
  static const String fontFamily = 'Manrope';

  // Colors
  static const Color background = Color(0xFF0F172A); // Slate 900
  static const Color surface = Color(0xFF1E293B); // Slate 800
  static const Color surfaceLight = Color(0xFF334155); // Slate 700
  /// The hairline on every card and row: surfaceLight at 50 %.
  static const Color border = Color(0x80334155);

  static const Color primary = Color(0xFF0EA5E9); // Sky 500
  static const Color primaryDark = Color(0xFF0284C7); // Sky 600
  /// Sky 400 — links, active tab, "you" highlights on dark surfaces.
  static const Color primaryLight = Color(0xFF38BDF8);

  static const Color secondary = Color(0xFFF43F5E); // Rose 500
  static const Color accent = Color(0xFFEAB308); // Yellow 500 (Gold)

  static const Color textPrimary = Color(0xFFF8FAFC); // Slate 50
  static const Color textSecondary = Color(0xFF94A3B8); // Slate 400
  static const Color textTertiary = Color(0xFF64748B); // Slate 500

  static const Color success = Color(0xFF22C55E); // Green 500
  static const Color error = Color(0xFFEF4444); // Red 500

  // Game-screen palette. In-match screens keep a blue-vs-pink player
  // identity: blue is always ME, pink is always the opponent, on both the
  // "your turn" and "opponent turn" layouts.
  static const Color gameBackground = background;
  static const Color gamePanel = surface;
  static const Color gamePanelEmpty = Color(0xFF111A2E);
  static const Color playerBlue = Color(0xFF38BDF8);
  static const Color playerBlueBright = Color(0xFF7DD3FC);
  static const Color playerBlueDim = Color(0xFF0284C7);
  static const Color opponentPink = Color(0xFFF43F5E);
  static const Color opponentPinkBright = Color(0xFFFDA4AF);
  static const Color warnBannerBg = Color(0xFF2A1621);

  // Medal / placement colors (1st / 2nd / 3rd) — shared so gold/silver/bronze
  // stay consistent across the history card and the end-of-tournament screen.
  static const Color gold = Color(0xFFFFD700);
  static const Color silver = Color(0xFFC0C0C0);
  static const Color bronze = Color(0xFFCD7F32);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, primaryDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Page backgrounds used to be a slate 800→700 wash; the system is flat, so
  /// this now paints the plain background wherever it is still referenced.
  static const LinearGradient surfaceGradient = LinearGradient(
    colors: [background, background],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Radii
  static const double radiusCard = 20;
  static const double radiusControl = 14;
  static const double radiusRow = 16;

  // Text Styles (the Manrope scale of the system sheet)
  /// Hero number (ELO, score): 34 / 700, tight, tabular.
  static const TextStyle displayLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 34,
    fontWeight: FontWeight.w700,
    color: textPrimary,
    letterSpacing: -0.7,
    height: 1.0,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// Screen title: 24 / 800.
  static const TextStyle displayMedium = TextStyle(
    fontFamily: fontFamily,
    fontSize: 24,
    fontWeight: FontWeight.w800,
    color: textPrimary,
    letterSpacing: -0.5,
    height: 1.1,
  );

  /// Block title (the primary row, a card heading): 17 / 700.
  static const TextStyle titleLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 17,
    fontWeight: FontWeight.w700,
    color: textPrimary,
  );

  /// Section title ("Matchs récents"): 15 / 700.
  static const TextStyle sectionTitle = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: textPrimary,
  );

  /// List row title: 15 / 600.
  static const TextStyle rowTitle = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: textPrimary,
  );

  static const TextStyle bodyLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w500,
    color: textSecondary,
    height: 1.4,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: textSecondary,
    height: 1.4,
  );

  /// Secondary line under a row title: 12 / 500.
  static const TextStyle caption = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: textSecondary,
  );

  static const TextStyle labelLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: textPrimary,
  );

  /// Group label ("AUJOURD’HUI", "PRÉFÉRENCES"): 11 / 700, spaced.
  static const TextStyle labelSmall = TextStyle(
    fontFamily: fontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: textSecondary,
    letterSpacing: 1.1,
  );

  // Input Decoration
  static InputDecoration inputDecoration({
    required String label,
    required IconData prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: textSecondary),
      prefixIcon: Icon(prefixIcon, color: textSecondary, size: 20),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusControl),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusControl),
        borderSide: const BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusControl),
        borderSide: const BorderSide(color: primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusControl),
        borderSide: const BorderSide(color: error, width: 1),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  // Button Style
  static final ButtonStyle primaryButtonStyle = ElevatedButton.styleFrom(
    backgroundColor: primary,
    foregroundColor: Colors.white,
    disabledBackgroundColor: surfaceLight,
    disabledForegroundColor: textSecondary,
    minimumSize: const Size(64, 48),
    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radiusControl),
    ),
    elevation: 0,
    shadowColor: Colors.transparent,
    textStyle: const TextStyle(
      fontFamily: fontFamily,
      fontSize: 15,
      fontWeight: FontWeight.w700,
    ),
  );

  static final ButtonStyle secondaryButtonStyle = OutlinedButton.styleFrom(
    foregroundColor: textPrimary,
    minimumSize: const Size(64, 48),
    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
    side: const BorderSide(color: surfaceLight),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radiusControl),
    ),
    textStyle: const TextStyle(
      fontFamily: fontFamily,
      fontSize: 15,
      fontWeight: FontWeight.w700,
    ),
  );

  static ThemeData get themeData {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: fontFamily,
    );
    final textTheme = base.textTheme
        .apply(
          fontFamily: fontFamily,
          bodyColor: textPrimary,
          displayColor: textPrimary,
        )
        .copyWith(
          displayLarge: displayLarge,
          displayMedium: displayMedium,
          headlineMedium: displayMedium,
          titleLarge: titleLarge,
          titleMedium: sectionTitle,
          titleSmall: rowTitle,
          bodyLarge: bodyLarge.copyWith(color: textPrimary),
          bodyMedium: bodyMedium.copyWith(color: textPrimary),
          bodySmall: caption,
          labelLarge: labelLarge,
          labelSmall: labelSmall,
        );
    return base.copyWith(
      scaffoldBackgroundColor: background,
      primaryColor: primary,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: secondary,
        surface: surface,
        error: error,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: textPrimary,
        outline: surfaceLight,
      ),
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: displayMedium.copyWith(fontSize: 22),
        iconTheme: const IconThemeData(color: textPrimary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(style: primaryButtonStyle),
      outlinedButtonTheme:
          OutlinedButtonThemeData(style: secondaryButtonStyle),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryLight,
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        labelStyle: const TextStyle(color: textSecondary),
        hintStyle: const TextStyle(color: textTertiary),
        prefixIconColor: textSecondary,
        suffixIconColor: textSecondary,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusControl),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusControl),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusControl),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusControl),
          borderSide: const BorderSide(color: error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusControl),
          borderSide: const BorderSide(color: error, width: 1.5),
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
          side: const BorderSide(color: border),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: border,
        thickness: 1,
        space: 1,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
        ),
        titleTextStyle: titleLarge,
        contentTextStyle: bodyMedium,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        trackColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? primary : surfaceLight,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surface,
        contentTextStyle: labelLarge,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: border),
        ),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: textPrimary,
        unselectedLabelColor: textSecondary,
        indicatorColor: primary,
        dividerColor: Colors.transparent,
      ),
    );
  }
}
