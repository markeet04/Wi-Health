import 'package:flutter/material.dart';

/// Wi-Health design tokens — "calm air": soft periwinkle blues and lavender
/// on a warm porcelain canvas. Related to the Wi-Netra family look (white
/// cards, soft shadows, pill accents) but with its own gentler identity.
class WiColors {
  WiColors._();

  // Brand — soft cornflower / periwinkle
  static const primary = Color(0xFF6C8CF5);
  static const primaryDeep = Color(0xFF5674E6);
  static const primarySoft = Color(0xFFEDF1FE);

  // Secondary accent — gentle lavender
  static const lilac = Color(0xFF9B7BF7);
  static const lilacSoft = Color(0xFFF3EFFE);

  // Canvas & surfaces
  static const bg = Color(0xFFF7F8FC);
  static const card = Colors.white;
  static const line = Color(0xFFECEFF6);
  static const field = Color(0xFFF2F4FA);

  // Ink — soft indigo-slate, never harsh black
  static const ink = Color(0xFF2A3356);
  static const inkSoft = Color(0xFF6C7590);
  static const inkFaint = Color(0xFFA2A9C0);

  // Status — muted, pastel-backed
  static const green = Color(0xFF57C29A); // sage
  static const greenSoft = Color(0xFFE9F7F1);
  static const red = Color(0xFFF07575); // coral, not alarm-red
  static const redSoft = Color(0xFFFDEDED);
  static const amber = Color(0xFFF0A868); // apricot
  static const amberSoft = Color(0xFFFCF2E7);
  static const blue = Color(0xFF54B4E4); // sky
  static const blueSoft = Color(0xFFE9F5FC);
  static const violet = Color(0xFF9B7BF7);
  static const violetSoft = Color(0xFFF3EFFE);
  static const nightIndigo = Color(0xFF5D6B96);
  static const nightSoft = Color(0xFFEEF0F8);
}

/// Soft drop shadow used by every card — a touch airier than before.
List<BoxShadow> get wiCardShadow => [
      BoxShadow(
        color: const Color(0xFF3A4A7A).withValues(alpha: 0.055),
        blurRadius: 26,
        offset: const Offset(0, 9),
      ),
    ];

List<BoxShadow> get wiButtonShadow => [
      BoxShadow(
        color: WiColors.primary.withValues(alpha: 0.32),
        blurRadius: 20,
        offset: const Offset(0, 9),
      ),
    ];

/// Periwinkle → deeper cornflower, with a whisper of lavender.
const wiBrandGradient = LinearGradient(
  colors: [Color(0xFF8CA4F9), Color(0xFF5E7DF0)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

/// Splash / hero wash.
const wiSkyGradient = LinearGradient(
  colors: [Color(0xFFEEF2FF), Color(0xFFF7F8FC)],
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
);

ThemeData buildWiTheme() {
  final base = ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: WiColors.bg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: WiColors.primary,
      primary: WiColors.primary,
      surface: WiColors.bg,
    ),
    splashFactory: InkSparkle.splashFactory,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: WiColors.ink,
      displayColor: WiColors.ink,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: WiColors.bg,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      foregroundColor: WiColors.ink,
      titleTextStyle: TextStyle(
        color: WiColors.ink,
        fontSize: 17,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
    ),
    dividerTheme: const DividerThemeData(color: WiColors.line, thickness: 1),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: WiColors.ink,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13.5),
    ),
  );
}

/// Frequently reused text styles.
class WiText {
  WiText._();

  static const h1 = TextStyle(
      fontSize: 26, fontWeight: FontWeight.w800, color: WiColors.ink, height: 1.15);
  static const h2 = TextStyle(
      fontSize: 19, fontWeight: FontWeight.w800, color: WiColors.ink);
  static const title = TextStyle(
      fontSize: 15.5, fontWeight: FontWeight.w700, color: WiColors.ink);
  static const body = TextStyle(
      fontSize: 13.5, color: WiColors.inkSoft, height: 1.35);
  static const caption = TextStyle(
      fontSize: 11.5, color: WiColors.inkFaint, height: 1.3);
  static const label = TextStyle(
    fontSize: 10.5,
    fontWeight: FontWeight.w700,
    color: WiColors.inkFaint,
    letterSpacing: 1.2,
  );
}
