// Test dasar untuk HegiKetok.
//
// Catatan: TerminalScreen menyalakan sesi PTY (shell asli) yang bergantung
// pada platform, sehingga tidak cocok dijalankan di lingkungan unit test
// headless. Untuk sekarang kita uji lapisan yang murni & deterministik
// (sistem tema). Test integrasi untuk terminal ditambahkan terpisah.

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexus_term/src/theme/app_theme.dart';

void main() {
  group('AppTheme / Palette', () {
    test('ThemeData gelap & terang sesuai palet masing-masing', () {
      final dark = AppTheme.dark;
      expect(dark.brightness, Brightness.dark);
      expect(dark.scaffoldBackgroundColor, Palette.dark.bg);

      final light = AppTheme.light;
      expect(light.brightness, Brightness.light);
      expect(light.scaffoldBackgroundColor, Palette.light.bg);
    });

    test('facade mengikuti brightness aktif', () {
      AppTheme.setPaletteFor(Brightness.dark);
      expect(AppTheme.bg, Palette.dark.bg);
      expect(AppTheme.accent, Palette.dark.accent);
      expect(AppTheme.current.isDark, isTrue);

      AppTheme.setPaletteFor(Brightness.light);
      expect(AppTheme.bg, Palette.light.bg);
      expect(AppTheme.accent, Palette.light.accent);
      expect(AppTheme.current.isDark, isFalse);

      // kembalikan ke default agar tidak memengaruhi test lain
      AppTheme.setPaletteFor(Brightness.dark);
    });

    test('mode gelap & terang punya warna latar berbeda', () {
      expect(Palette.dark.bg, isNot(Palette.light.bg));
      expect(Palette.dark.textPrimary, isNot(Palette.light.textPrimary));
    });
  });
}
