import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'features/settings/settings_providers.dart';
import 'features/workspace/workspace_screen.dart';
import 'ssh/host_key_dialog.dart';
import 'ssh/known_hosts.dart';
import 'theme/app_theme.dart';

/// Root aplikasi HegiKetok.
///
/// Local-first SSH & terminal client: data di perangkat, tanpa cloud wajib.
/// Nama "HegiKetok" dari bahasa Sunda *ketok* (mengetuk) — seperti mengetuk
/// pintu server untuk minta izin masuk.
class HegiKetokApp extends ConsumerWidget {
  const HegiKetokApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(settingsProvider.select((s) => s.themeMode));
    // Pasang verifier host key berbasis dialog (idempoten).
    globalHostKeyVerifier = hostKeyDialogVerifier;
    return MaterialApp(
      title: 'HegiKetok',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: mode,
      // Sinkronkan facade warna dengan brightness yang di-resolve Material,
      // termasuk saat OS berganti tema pada mode "system".
      builder: (context, child) {
        AppTheme.setPaletteFor(Theme.of(context).brightness);
        return child ?? const SizedBox.shrink();
      },
      home: const WorkspaceScreen(),
    );
  }
}
