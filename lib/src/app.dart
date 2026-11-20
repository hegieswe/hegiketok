import 'package:material_ui/material_ui.dart';

import 'features/workspace/workspace_screen.dart';
import 'theme/app_theme.dart';

/// Root aplikasi Nexus Terminal.
///
/// Local-first SSH & terminal client: data di perangkat, tanpa cloud wajib.
class NexusApp extends StatelessWidget {
  const NexusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nexus Terminal',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const WorkspaceScreen(),
    );
  }
}
