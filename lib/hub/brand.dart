import 'package:flutter/material.dart';

/// Assimilis Mobile brand (owner decision, 2026-11-22): violet + graphite, with magenta, red and green as
/// accents. The mascot is the Core (lib/hub/core_orb.dart): a glowing magenta heart inside violet orbits.
/// Screens follow the HES look: graphite panels, corner brackets, mono uppercase labels, soft glow.
class AssimilisBrand {
  // Brand colours
  static const violet = Color(0xFFA855F7); // primary
  static const violetSoft = Color(0xFFC084FC);
  static const violetDeep = Color(0xFF7C3AED);
  static const magenta = Color(0xFFE61478); // the core's heart
  static const red = Color(0xFFEF4444);
  static const green = Color(0xFF3D8C6E);
  static const mint = Color(0xFF7FD8B5);

  // Graphite surfaces
  static const graphite = Color(0xFF121216); // page background
  static const panel = Color(0xFF1A1A20);
  static const raised = Color(0xFF23232B);
  static const line = Color(0xFF34343F);
  static const text = Color(0xFFEDEDF2);
  static const muted = Color(0xFF9A9AAA);
  static const faint = Color(0xFF5E5E6C);

  // Kept for older screens (now graphite-based).
  static const navy = graphite;
  static const navyDeep = Color(0xFF0D0D10);
  static const navyRaised = raised;

  static const icon = 'assets/brand/assimilis-core-512.png';

  static TextStyle display(double size, {Color color = text, FontWeight w = FontWeight.w700}) =>
      TextStyle(fontFamily: 'Orbitron', fontSize: size, color: color, fontWeight: w, letterSpacing: 1.5);
  static TextStyle label(double size, {Color color = muted, FontWeight w = FontWeight.w600}) =>
      TextStyle(fontFamily: 'JetBrainsMono', fontSize: size, color: color, fontWeight: w, letterSpacing: 1.6);
  static TextStyle body(double size, {Color color = text, FontWeight w = FontWeight.w400}) =>
      TextStyle(fontFamily: 'Inter', fontSize: size, color: color, fontWeight: w, height: 1.4);

  /// Rank colours shared by HES and the hub.
  static Color rankColor(String r) => switch (r) {
        'E' => const Color(0xFF8A8A99),
        'D' => const Color(0xFF8BC34A),
        'C' => const Color(0xFF26C6DA),
        'B' => const Color(0xFF42A5F5),
        'A' => violet,
        'S' => const Color(0xFFFFB300),
        'SS' => const Color(0xFFFF7043),
        _ => magenta,
      };

  static ThemeData theme() {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: graphite,
      colorScheme: const ColorScheme.dark(
        primary: violet,
        secondary: magenta,
        tertiary: green,
        error: red,
        surface: panel,
        onSurface: text,
      ),
      textTheme: base.textTheme.apply(fontFamily: 'Inter', bodyColor: text, displayColor: text),
      appBarTheme: AppBarTheme(
        backgroundColor: graphite,
        foregroundColor: text,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: display(16, w: FontWeight.w600),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: panel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6), side: const BorderSide(color: line)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(backgroundColor: panel),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: raised,
        hintStyle: const TextStyle(color: faint),
        labelStyle: const TextStyle(color: muted),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: line)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: line)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: violet)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: violet,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: violetSoft,
          side: const BorderSide(color: violet),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: violetSoft)),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: raised,
        selectedColor: violet.withValues(alpha: 0.3),
        side: const BorderSide(color: line),
        labelStyle: const TextStyle(color: text, fontFamily: 'Inter'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? violet : muted),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? violet.withValues(alpha: 0.35) : raised),
      ),
      radioTheme: RadioThemeData(fillColor: WidgetStateProperty.all(violet)),
      checkboxTheme: CheckboxThemeData(fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? violet : Colors.transparent)),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: violet),
      tabBarTheme: TabBarThemeData(
        labelColor: text,
        unselectedLabelColor: muted,
        indicatorColor: violet,
        labelStyle: label(12, color: text),
        unselectedLabelStyle: label(12),
        dividerColor: line,
      ),
      dividerColor: line,
      dividerTheme: const DividerThemeData(color: line, thickness: 1),
      listTileTheme: const ListTileThemeData(iconColor: violetSoft, textColor: text),
      snackBarTheme: const SnackBarThemeData(backgroundColor: raised, contentTextStyle: TextStyle(color: text)),
    );
  }
}
