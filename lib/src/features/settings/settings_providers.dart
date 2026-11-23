import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' show ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';

import 'terminal_themes.dart';

/// Preferensi tampilan aplikasi.
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.dark,
    this.themeName = kDefaultThemeName,
    this.fontSize = 14,
    this.cpuAlert = 90,
    this.memAlert = 90,
    this.diskAlert = 90,
    this.autoCheckUpdates = true,
  });

  /// Mode tema aplikasi (ikuti sistem / terang / gelap).
  final ThemeMode themeMode;

  final String themeName;
  final double fontSize;

  /// Ambang peringatan (persen) untuk CPU, memory, dan disk pada dashboard.
  final double cpuAlert;
  final double memAlert;
  final double diskAlert;

  /// Periksa rilis baru secara otomatis (paling sering sekali sehari). Hanya
  /// satu GET publik ke GitHub; tidak ada data pengguna yang dikirim.
  final bool autoCheckUpdates;

  AppSettings copyWith({
    ThemeMode? themeMode,
    String? themeName,
    double? fontSize,
    double? cpuAlert,
    double? memAlert,
    double? diskAlert,
    bool? autoCheckUpdates,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        themeName: themeName ?? this.themeName,
        fontSize: fontSize ?? this.fontSize,
        cpuAlert: cpuAlert ?? this.cpuAlert,
        memAlert: memAlert ?? this.memAlert,
        diskAlert: diskAlert ?? this.diskAlert,
        autoCheckUpdates: autoCheckUpdates ?? this.autoCheckUpdates,
      );
}

/// Instance SharedPreferences — di-override di `main()` setelah di-load.
final sharedPrefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPrefsProvider harus di-override'),
);

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

class SettingsNotifier extends Notifier<AppSettings> {
  SharedPreferences get _prefs => ref.read(sharedPrefsProvider);

  @override
  AppSettings build() {
    return AppSettings(
      themeMode: _parseMode(_prefs.getString('themeMode')),
      themeName: _prefs.getString('themeName') ?? kDefaultThemeName,
      fontSize: _prefs.getDouble('fontSize') ?? 14,
      cpuAlert: _prefs.getDouble('cpuAlert') ?? 90,
      memAlert: _prefs.getDouble('memAlert') ?? 90,
      diskAlert: _prefs.getDouble('diskAlert') ?? 90,
      autoCheckUpdates: _prefs.getBool('autoCheckUpdates') ?? true,
    );
  }

  static ThemeMode _parseMode(String? s) {
    switch (s) {
      case 'system':
        return ThemeMode.system;
      case 'light':
        return ThemeMode.light;
      default:
        return ThemeMode.dark;
    }
  }

  void setThemeMode(ThemeMode mode) {
    _prefs.setString('themeMode', mode.name);
    state = state.copyWith(themeMode: mode);
  }

  void setTheme(String name) {
    _prefs.setString('themeName', name);
    state = state.copyWith(themeName: name);
  }

  void setFontSize(double size) {
    _prefs.setDouble('fontSize', size);
    state = state.copyWith(fontSize: size);
  }

  void setCpuAlert(double v) {
    _prefs.setDouble('cpuAlert', v);
    state = state.copyWith(cpuAlert: v);
  }

  void setMemAlert(double v) {
    _prefs.setDouble('memAlert', v);
    state = state.copyWith(memAlert: v);
  }

  void setAutoCheckUpdates(bool v) {
    _prefs.setBool('autoCheckUpdates', v);
    state = state.copyWith(autoCheckUpdates: v);
  }

  /// Waktu pemeriksaan pembaruan otomatis terakhir (null = belum pernah).
  DateTime? get lastUpdateCheck {
    final ms = _prefs.getInt('lastUpdateCheck');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  void markUpdateChecked(DateTime when) =>
      _prefs.setInt('lastUpdateCheck', when.millisecondsSinceEpoch);

  void setDiskAlert(double v) {
    _prefs.setDouble('diskAlert', v);
    state = state.copyWith(diskAlert: v);
  }
}
