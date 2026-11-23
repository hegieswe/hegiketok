import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/ssh_credentials.dart';
import '../../session/workspace_tab.dart';
import 'server_info_controller.dart';
import 'server_info_view.dart';

/// Tab workspace yang menampilkan dashboard informasi server.
class ServerInfoTab implements WorkspaceTab {
  ServerInfoTab(SshCredentials credentials, {required this.label})
      : controller = ServerInfoController(credentials) {
    controller.connect();
  }

  final ServerInfoController controller;
  final String label;

  @override
  String get title => 'Info · $label';

  @override
  IconData get icon => Icons.monitor_heart_outlined;

  @override
  ValueListenable<bool>? get connection => null;

  @override
  Widget build(BuildContext context) =>
      ServerInfoView(controller: controller);

  @override
  void dispose() => controller.dispose();
}
