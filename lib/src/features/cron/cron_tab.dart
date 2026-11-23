import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/ssh_credentials.dart';
import '../../session/workspace_tab.dart';
import 'cron_controller.dart';
import 'cron_view.dart';

/// Tab workspace yang menampilkan penjadwal cron sebuah server.
class CronTab implements WorkspaceTab {
  CronTab(SshCredentials credentials, {required this.label})
      : controller = CronController(credentials) {
    controller.connect();
  }

  final CronController controller;
  final String label;

  @override
  String get title => 'Cron · $label';

  @override
  IconData get icon => Icons.schedule;

  @override
  ValueListenable<bool>? get connection => null;

  @override
  Widget build(BuildContext context) => CronView(controller: controller);

  @override
  void dispose() => controller.dispose();
}
