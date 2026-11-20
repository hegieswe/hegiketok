import 'package:material_ui/material_ui.dart';

/// Tema visual aplikasi. Terinspirasi palet gelap modern (GitHub Dark),
/// nyaman di mata untuk sesi terminal yang panjang.
class AppTheme {
  AppTheme._();

  // Warna inti
  static const Color bg = Color(0xFF0D1117); // latar utama
  static const Color surface = Color(0xFF161B22); // panel/kartu
  static const Color border = Color(0xFF30363D); // garis pemisah
  static const Color accent = Color(0xFF2F81F7); // aksen biru
  static const Color textPrimary = Color(0xFFE6EDF3);
  static const Color textMuted = Color(0xFF8B949E);
  static const Color success = Color(0xFF3FB950);

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: bg,
      colorScheme: base.colorScheme.copyWith(
        primary: accent,
        surface: surface,
        onSurface: textPrimary,
      ),
      dividerColor: border,
    );
  }
}
