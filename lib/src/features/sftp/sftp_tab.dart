import 'package:material_ui/material_ui.dart';

import '../../models/ssh_credentials.dart';
import '../../session/workspace_tab.dart';
import 'sftp_browser_controller.dart';
import 'sftp_browser_view.dart';

/// Tab workspace yang menampilkan browser file SFTP untuk sebuah host.
class SftpTab implements WorkspaceTab {
  SftpTab(SshCredentials credentials, {required this.label})
      : controller = SftpBrowserController(credentials) {
    controller.connect();
  }

  final SftpBrowserController controller;
  final String label;

  @override
  String get title => 'SFTP · $label';

  @override
  IconData get icon => Icons.folder_outlined;

  @override
  Widget build(BuildContext context) =>
      SftpBrowserView(controller: controller);

  @override
  void dispose() => controller.dispose();
}
