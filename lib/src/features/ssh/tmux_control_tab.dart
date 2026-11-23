import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/ssh_credentials.dart';
import '../../session/workspace_tab.dart';
import '../../ssh/tmux_control_client.dart';
import 'tmux_control_view.dart';

/// Tab workspace yang menampung sesi **tmux control mode** (`tmux -CC`):
/// jendela tmux remote tampil sebagai tab internal & panel sebagai split native.
class TmuxControlTab implements WorkspaceTab {
  TmuxControlTab(SshCredentials credentials, {this.label})
      : client = TmuxControlClient(credentials, label: label)..start();

  final TmuxControlClient client;
  final String? label;

  @override
  String get title => 'tmux · ${label ?? 'sesi'}';

  @override
  IconData get icon => Icons.grid_view_rounded;

  @override
  ValueListenable<bool> get connection => client.online;

  @override
  Widget build(BuildContext context) => TmuxControlView(client: client);

  @override
  void dispose() => client.dispose();
}
