// Test dasar untuk Nexus Terminal.
//
// Catatan: TerminalScreen menyalakan sesi PTY (shell asli) yang bergantung
// pada platform, sehingga tidak cocok dijalankan di lingkungan unit test
// headless. Untuk sekarang kita uji lapisan yang murni & deterministik
// (tema aplikasi). Test integrasi untuk terminal akan ditambahkan terpisah.

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexus_term/src/theme/app_theme.dart';

void main() {
  group('AppTheme', () {
    test('menyediakan tema gelap dengan latar yang benar', () {
      final theme = AppTheme.dark;
      expect(theme.scaffoldBackgroundColor, AppTheme.bg);
      expect(theme.brightness, Brightness.dark);
    });

    test('warna aksen & teks terdefinisi konsisten', () {
      expect(AppTheme.accent, const Color(0xFF2F81F7));
      expect(AppTheme.textPrimary, const Color(0xFFE6EDF3));
    });
  });
}
