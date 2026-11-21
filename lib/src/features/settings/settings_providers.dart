import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'terminal_themes.dart';

/// Preferensi tampilan aplikasi.
class AppSettings {
  const AppSettings({
    this.themeName = kDefaultThemeName,
    this.fontSize = 14,
  });

  final String themeName;
  final double fontSize;

  AppSettings copyWith({String? themeName, double? fontSize}) => AppSettings(
        themeName: themeName ?? this.themeName,
        fontSize: fontSize ?? this.fontSize,
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
      themeName: _prefs.getString('themeName') ?? kDefaultThemeName,
      fontSize: _prefs.getDouble('fontSize') ?? 14,
    );
  }

  void setTheme(String name) {
    _prefs.setString('themeName', name);
    state = state.copyWith(themeName: name);
  }

  void setFontSize(double size) {
    _prefs.setDouble('fontSize', size);
    state = state.copyWith(fontSize: size);
  }
}
