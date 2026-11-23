import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/ssh_credentials.dart';
import '../../models/ssh_host.dart';
import '../../session/workspace_tab.dart';
import 'sftp_browser_controller.dart';
import 'sftp_dual_view.dart';

/// Tab workspace: browser file SFTP dua-panel untuk sebuah host (panel kiri),
/// dengan panel kanan opsional untuk transfer antar-server.
class SftpTab implements WorkspaceTab {
  SftpTab(
    SshCredentials credentials, {
    required this.label,
    required this.resolveCreds,
  }) : controller = SftpBrowserController(credentials) {
    controller.connect();
  }

  final SftpBrowserController controller;
  final String label;

  /// Resolver kredensial (termasuk rantai bastion) untuk membuka panel kanan.
  final Future<SshCredentials> Function(SshHost host) resolveCreds;

  @override
  String get title => 'SFTP · $label';

  @override
  IconData get icon => Icons.folder_outlined;

  @override
  ValueListenable<bool>? get connection => null;

  @override
  Widget build(BuildContext context) => SftpDualView(
        left: controller,
        leftLabel: label,
        resolveCreds: resolveCreds,
      );

  @override
  void dispose() => controller.dispose();
}
