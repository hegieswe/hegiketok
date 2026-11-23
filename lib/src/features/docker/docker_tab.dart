import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/ssh_credentials.dart';
import '../../session/workspace_tab.dart';
import 'docker_controller.dart';
import 'docker_view.dart';

/// Tab workspace yang menampilkan panel Docker sebuah server.
class DockerTab implements WorkspaceTab {
  DockerTab(SshCredentials credentials, {required this.label})
      : controller = DockerController(credentials) {
    controller.connect();
  }

  final DockerController controller;
  final String label;

  @override
  String get title => 'Docker · $label';

  @override
  IconData get icon => Icons.directions_boat_filled_outlined;

  @override
  ValueListenable<bool>? get connection => null;

  @override
  Widget build(BuildContext context) => DockerView(controller: controller);

  @override
  void dispose() => controller.dispose();
}
