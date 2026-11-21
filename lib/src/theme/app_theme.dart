import 'package:material_ui/material_ui.dart';

/// Palet warna satu mode (gelap atau terang). Terinspirasi gaya modern-minimalis
/// (Linear/Raycast) dengan aksen indigo-violet.
class Palette {
  const Palette({
    required this.brightness,
    required this.bg,
    required this.surface,
    required this.surfaceHigh,
    required this.surfaceInput,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textMuted,
    required this.textFaint,
    required this.accent,
    required this.accentHover,
    required this.accentSoft,
    required this.onAccent,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.violet,
    required this.shadow,
  });

  final Brightness brightness;
  final Color bg; // latar aplikasi
  final Color surface; // panel/kartu
  final Color surfaceHigh; // elevasi: menu, dialog, hover
  final Color surfaceInput; // isian field
  final Color border; // garis halus
  final Color borderStrong; // garis lebih tegas
  final Color textPrimary;
  final Color textMuted; // teks sekunder
  final Color textFaint; // teks paling redup
  final Color accent;
  final Color accentHover;
  final Color accentSoft; // tint latar aksen (sudah di-blend)
  final Color onAccent; // teks di atas aksen
  final Color success;
  final Color warning;
  final Color danger;
  final Color info;
  final Color violet; // aksen sekunder
  final Color shadow;

  bool get isDark => brightness == Brightness.dark;

  /// Gelap — near-black kebiruan, kontras lembut, nyaman untuk sesi panjang.
  static const dark = Palette(
    brightness: Brightness.dark,
    bg: Color(0xFF0B0C0F),
    surface: Color(0xFF141519),
    surfaceHigh: Color(0xFF1C1D23),
    surfaceInput: Color(0xFF191A1F),
    border: Color(0xFF262830),
    borderStrong: Color(0xFF343640),
    textPrimary: Color(0xFFEDEEF2),
    textMuted: Color(0xFF9B9FA9),
    textFaint: Color(0xFF6B6E78),
    accent: Color(0xFF6E79F2),
    accentHover: Color(0xFF828CF5),
    accentSoft: Color(0xFF20233A),
    onAccent: Color(0xFFFFFFFF),
    success: Color(0xFF3FD07E),
    warning: Color(0xFFE3B341),
    danger: Color(0xFFF26D78),
    info: Color(0xFF5B9DF0),
    violet: Color(0xFFBC8CFF),
    shadow: Color(0x66000000),
  );

  /// Terang — putih lembut keabuan, garis tipis, aksen indigo lebih pekat.
  static const light = Palette(
    brightness: Brightness.light,
    bg: Color(0xFFF6F7F9),
    surface: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFFFFFFF),
    surfaceInput: Color(0xFFF1F2F5),
    border: Color(0xFFE6E8EC),
    borderStrong: Color(0xFFD3D6DE),
    textPrimary: Color(0xFF16181D),
    textMuted: Color(0xFF5B606B),
    textFaint: Color(0xFF8A8F9A),
    accent: Color(0xFF5A57E6),
    accentHover: Color(0xFF4F4CDD),
    accentSoft: Color(0xFFECEDFB),
    onAccent: Color(0xFFFFFFFF),
    success: Color(0xFF15A35B),
    warning: Color(0xFFBE7A12),
    danger: Color(0xFFDC4B57),
    info: Color(0xFF2563EB),
    violet: Color(0xFF7C3AED),
    shadow: Color(0x1F101828),
  );
}

/// Facade warna aktif aplikasi. Semua anggota adalah getter dinamis yang
/// membaca [current] sehingga seluruh UI otomatis mengikuti mode gelap/terang.
/// Panggil [setPaletteFor] saat brightness berubah (dilakukan di root app).
class AppTheme {
  AppTheme._();

  static Palette current = Palette.dark;

  static void setPaletteFor(Brightness b) {
    current = b == Brightness.dark ? Palette.dark : Palette.light;
  }

  // Token inti (nama dipertahankan agar kompatibel dengan kode lama).
  static Color get bg => current.bg;
  static Color get surface => current.surface;
  static Color get surfaceHigh => current.surfaceHigh;
  static Color get surfaceInput => current.surfaceInput;
  static Color get border => current.border;
  static Color get borderStrong => current.borderStrong;
  static Color get textPrimary => current.textPrimary;
  static Color get textMuted => current.textMuted;
  static Color get textFaint => current.textFaint;
  static Color get accent => current.accent;
  static Color get accentHover => current.accentHover;
  static Color get accentSoft => current.accentSoft;
  static Color get onAccent => current.onAccent;
  static Color get success => current.success;
  static Color get warning => current.warning;
  static Color get danger => current.danger;
  static Color get info => current.info;
  static Color get violet => current.violet;
  static Color get shadow => current.shadow;

  // ── Token desain ────────────────────────────────────────────────
  static const double rSm = 8; // radius kecil
  static const double rMd = 10;
  static const double rLg = 14;
  static const double rXl = 20;
  static const double rPill = 999;

  static const Duration fast = Duration(milliseconds: 120);
  static const Duration med = Duration(milliseconds: 220);

  static List<BoxShadow> softShadow(Palette p) => [
        BoxShadow(
          color: p.shadow,
          blurRadius: p.isDark ? 18 : 16,
          spreadRadius: p.isDark ? -6 : -8,
          offset: const Offset(0, 6),
        ),
      ];

  /// ThemeData Material untuk sebuah [Palette] — menata dialog, menu, slider,
  /// snackbar, tooltip, dsb agar konsisten di kedua mode.
  static ThemeData themeFor(Palette p) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: p.brightness,
    );
    final scheme = ColorScheme.fromSeed(
      seedColor: p.accent,
      brightness: p.brightness,
    ).copyWith(
      primary: p.accent,
      onPrimary: p.onAccent,
      surface: p.surface,
      onSurface: p.textPrimary,
      error: p.danger,
    );
    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: p.bg,
      canvasColor: p.bg,
      dividerColor: p.border,
      splashFactory: InkSparkle.splashFactory,
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: p.accent,
        selectionColor: p.accent.withValues(alpha: 0.30),
        selectionHandleColor: p.accent,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surfaceHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(rLg),
          side: BorderSide(color: p.border),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.surfaceHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(rMd),
          side: BorderSide(color: p.border),
        ),
        textStyle: TextStyle(color: p.textPrimary, fontSize: 13),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.surfaceHigh,
        contentTextStyle: TextStyle(color: p.textPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(rMd),
          side: BorderSide(color: p.border),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: p.surfaceHigh,
          borderRadius: BorderRadius.circular(rSm),
          border: Border.all(color: p.border),
        ),
        textStyle: TextStyle(color: p.textPrimary, fontSize: 12),
        waitDuration: const Duration(milliseconds: 500),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: p.accent,
        inactiveTrackColor: p.border,
        thumbColor: p.accent,
        overlayColor: p.accent.withValues(alpha: 0.15),
        trackHeight: 3,
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
      ),
      iconTheme: IconThemeData(color: p.textMuted),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(p.borderStrong),
        thickness: const WidgetStatePropertyAll(6),
        radius: const Radius.circular(8),
      ),
    );
  }

  static ThemeData get dark => themeFor(Palette.dark);
  static ThemeData get light => themeFor(Palette.light);
}
