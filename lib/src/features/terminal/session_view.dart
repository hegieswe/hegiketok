import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xterm/xterm.dart';

import '../settings/settings_providers.dart';
import '../settings/terminal_themes.dart';

/// Menampilkan satu [Terminal] dengan tema & ukuran font dari pengaturan.
/// Dipakai ulang oleh sesi lokal maupun SSH; berubah langsung saat tema diganti.
class SessionView extends ConsumerWidget {
  const SessionView(this.terminal, {super.key});

  final Terminal terminal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final preset = themeByName(settings.themeName);

    return Container(
      color: preset.background,
      padding: const EdgeInsets.all(8),
      child: TerminalView(
        terminal,
        autofocus: true,
        padding: const EdgeInsets.all(8),
        theme: preset.theme,
        textStyle: TerminalStyle(
          fontSize: settings.fontSize,
          fontFamily: 'Menlo',
        ),
      ),
    );
  }
}
