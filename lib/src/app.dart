import 'package:material_ui/material_ui.dart';

import 'features/workspace/workspace_screen.dart';
import 'theme/app_theme.dart';

/// Root aplikasi HegiKetok.
///
/// Local-first SSH & terminal client: data di perangkat, tanpa cloud wajib.
/// Nama "HegiKetok" dari bahasa Sunda *ketok* (mengetuk) — seperti mengetuk
/// pintu server untuk minta izin masuk.
class HegiKetokApp extends StatelessWidget {
  const HegiKetokApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HegiKetok',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const WorkspaceScreen(),
    );
  }
}
