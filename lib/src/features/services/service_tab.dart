import 'package:material_ui/material_ui.dart';

import '../../models/ssh_credentials.dart';
import '../../session/workspace_tab.dart';
import 'service_controller.dart';
import 'service_view.dart';

/// Tab workspace yang menampilkan panel service systemd sebuah server.
class ServiceTab implements WorkspaceTab {
  ServiceTab(SshCredentials credentials, {required this.label})
      : controller = ServiceController(credentials) {
    controller.connect();
  }

  final ServiceController controller;
  final String label;

  @override
  String get title => 'Services · $label';

  @override
  IconData get icon => Icons.settings_suggest_outlined;

  @override
  Widget build(BuildContext context) => ServiceView(controller: controller);

  @override
  void dispose() => controller.dispose();
}
