import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/ssh_credentials.dart';
import '../../session/workspace_tab.dart';
import 'user_controller.dart';
import 'user_view.dart';

/// Tab workspace yang menampilkan daftar user sistem sebuah server.
class UserTab implements WorkspaceTab {
  UserTab(SshCredentials credentials, {required this.label})
      : controller = UserController(credentials) {
    controller.connect();
  }

  final UserController controller;
  final String label;

  @override
  String get title => 'Users · $label';

  @override
  IconData get icon => Icons.group_outlined;

  @override
  ValueListenable<bool>? get connection => null;

  @override
  Widget build(BuildContext context) => UserView(controller: controller);

  @override
  void dispose() => controller.dispose();
}
