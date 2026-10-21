import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design-Tokens des Redesigns. Zugriff in Widgets: `final c = AppColors.of(context);`
@immutable
class AppColors extends ThemeExtension<AppColors> {
  final Color bg;          // Scaffold
  final Color card;        // Karten
  final Color cardAlt;     // Icon-Kacheln, Pills
  final Color line;        // Trenner, leere Rahmen
  final Color text;
  final Color muted;
  final Color dim;
  final Color accent;      // Flächen (Ring, Checkbox, aktive Pill)
  final Color accentText;  // Akzent als Schrift/Icon
  final Color onAccent;
  final Color streak;      // Flammen / XP
  final Color event;       // Termine
  final Color positive;
  final Color negative;
  final Color navBg;
  final Color navActive;
  final Color onNavActive;
  final Color scoreCard;   // Tages-Score-Karte (im Light-Mode bewusst dunkel)
  final Color onScoreCard;
  final Color onScoreCardMuted;
  final Color scoreTrack;

  const AppColors({
    required this.bg,
    required this.card,
    required this.cardAlt,
    required this.line,
    required this.text,
    required this.muted,
    required this.dim,
    required this.accent,
    required this.accentText,
    required this.onAccent,
    required this.streak,
    required this.event,
    required this.positive,
    required this.negative,
    required this.navBg,
    required this.navActive,
    required this.onNavActive,
    required this.scoreCard,
    required this.onScoreCard,
    required this.onScoreCardMuted,
    required this.scoreTrack,
  });

  static const dark = AppColors(
    bg: Color(0xFF0E0F11),
    card: Color(0xFF17181B),
    cardAlt: Color(0xFF1F2024),
    line: Color(0x1FFFFFFF),
    text: Color(0xFFF3F3F0),
    muted: Color(0xFF9C9DA3),
    dim: Color(0xFF6B6C72),
    accent: Color(0xFF5ED99E),
    accentText: Color(0xFF5ED99E),
    onAccent: Color(0xFF0E0F11),
    streak: Color(0xFFF2AF48),
    event: Color(0xFFBDADFF),
    positive: Color(0xFF5ED99E),
    negative: Color(0xFFFF9189),
    navBg: Color(0xEB1E1F23),
    navActive: Color(0xFF5ED99E),
    onNavActive: Color(0xFF0E0F11),
    scoreCard: Color(0xFF17181B),
    onScoreCard: Color(0xFFF3F3F0),
    onScoreCardMuted: Color(0xFF9C9DA3),
    scoreTrack: Color(0x12FFFFFF),
  );

  static const light = AppColors(
    bg: Color(0xFFF4F4F1),
    card: Color(0xFFFFFFFF),
    cardAlt: Color(0xFFF1F1EE),
    line: Color(0x1F000000),
    text: Color(0xFF121316),
    muted: Color(0xFF6A6B70),
    dim: Color(0xFF9A9BA0),
    accent: Color(0xFF5ED99E),
    accentText: Color(0xFF00804C),
    onAccent: Color(0xFF0E0F11),
    streak: Color(0xFFC66C00),
    event: Color(0xFF6451AC),
    positive: Color(0xFF00804C),
    negative: Color(0xFFC13C3B),
    navBg: Color(0xEBFFFFFF),
    navActive: Color(0xFF121316),
    onNavActive: Color(0xFFFFFFFF),
    scoreCard: Color(0xFF121316),
    onScoreCard: Color(0xFFF3F3F0),
    onScoreCardMuted: Color(0xFF9C9DA3),
    scoreTrack: Color(0x1AFFFFFF),
  );

  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>() ??
      (Theme.of(context).brightness == Brightness.dark ? dark : light);

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return t < 0.5 ? this : other;
  }
}

/// Zentrale Theme-Definition. Farben kommen aus [AppColors] (hell/dunkel).
class AppTheme {
  AppTheme._();

  /// Akzentgrün (wie `AppColors.accent`) – für konstante Standardwerte. Sonst `AppColors.of(context)` nutzen.
  static const Color primary = Color(0xFF5ED99E);

  /// In Tests abschalten: GoogleFonts lädt Schriften sonst aus dem Netz.
  @visibleForTesting
  static bool useGoogleFonts = true;

  static const double radiusCard = 22;
  static const double radiusHero = 28;

  static ThemeData get darkTheme => _build(Brightness.dark, AppColors.dark);
  static ThemeData get lightTheme => _build(Brightness.light, AppColors.light);

  static ThemeData _build(Brightness b, AppColors c) {
    final isDark = b == Brightness.dark;
    final scheme = ColorScheme(
      brightness: b,
      primary: c.accent,
      onPrimary: c.onAccent,
      secondary: c.muted,
      onSecondary: c.bg,
      surface: c.card,
      onSurface: c.text,
      error: c.negative,
      onError: Colors.white,
    );

    final base = ThemeData(useMaterial3: true, brightness: b);
    // Geist (Design-Vorlage) ist in google_fonts 6.3.x nicht enthalten – Inter kommt ihm am nächsten.
    final textTheme = useGoogleFonts ? GoogleFonts.interTextTheme(_textTheme(c)) : _textTheme(c);

    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: c.line, width: 1),
    );

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: c.bg,
      canvasColor: c.bg,
      hintColor: c.dim,
      dividerColor: c.line,
      textTheme: textTheme,
      extensions: [c],
      appBarTheme: AppBarTheme(
        backgroundColor: c.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        titleTextStyle: textTheme.headlineSmall,
        iconTheme: IconThemeData(color: c.text),
      ),
      cardTheme: CardTheme(
        color: c.card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusCard)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.card,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(borderSide: BorderSide(color: c.accentText, width: 1.5)),
        labelStyle: TextStyle(color: c.muted),
        hintStyle: TextStyle(color: c.dim),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.accent,
          foregroundColor: c.onAccent,
          elevation: 0,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 22),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.accentText,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        elevation: 0,
        shape: const StadiumBorder(),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.accent : Colors.transparent),
        checkColor: WidgetStatePropertyAll(c.onAccent),
        side: BorderSide(color: c.line, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: c.accent, linearTrackColor: c.line),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.bg,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: TextStyle(color: c.text, fontSize: 15),
      ),
      iconTheme: IconThemeData(color: c.muted),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: c.card,
        selectedItemColor: c.accentText,
        unselectedItemColor: c.muted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: c.card, border: inputBorder),
      ),
    );
  }

  static TextTheme _textTheme(AppColors c) {
    TextStyle s(double size, FontWeight w, Color col, [double ls = 0]) =>
        TextStyle(color: col, fontSize: size, fontWeight: w, letterSpacing: ls);
    return TextTheme(
      displayLarge: s(44, FontWeight.w600, c.text, -1.5),
      displayMedium: s(34, FontWeight.w600, c.text, -1),
      displaySmall: s(28, FontWeight.w600, c.text, -0.7),
      headlineLarge: s(28, FontWeight.w600, c.text, -0.7),
      headlineMedium: s(22, FontWeight.w600, c.text, -0.4),
      headlineSmall: s(17, FontWeight.w600, c.text, -0.2),
      titleLarge: s(17, FontWeight.w600, c.text, -0.2),
      titleMedium: s(15, FontWeight.w600, c.text),
      titleSmall: s(14, FontWeight.w600, c.text),
      bodyLarge: s(15, FontWeight.w500, c.text),
      bodyMedium: s(14, FontWeight.w400, c.text),
      bodySmall: s(13, FontWeight.w400, c.muted),
      labelLarge: s(14, FontWeight.w600, c.text),
      labelMedium: s(12, FontWeight.w400, c.muted),
      labelSmall: s(11, FontWeight.w500, c.dim, 0.4),
    );
  }

  /// Karten-Dekoration (kompatibel mit bestehenden Screens).
  static BoxDecoration cardDecoration(BuildContext context) => BoxDecoration(
        color: AppColors.of(context).card,
        borderRadius: BorderRadius.circular(radiusCard),
      );

  static Color divider(BuildContext context) => AppColors.of(context).line;
}
