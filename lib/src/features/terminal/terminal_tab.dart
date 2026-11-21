import 'package:material_ui/material_ui.dart';

import '../../session/terminal_session.dart';
import '../../session/workspace_tab.dart';
import '../ssh/ssh_session_view.dart';
import '../ssh/ssh_terminal_session.dart';
import 'session_view.dart';

/// Membungkus sebuah [TerminalSession] (lokal atau SSH) sebagai [WorkspaceTab].
class TerminalTab implements WorkspaceTab {
  TerminalTab(this.session);

  final TerminalSession session;

  @override
  String get title => session.title;

  @override
  IconData get icon =>
      session.isLocal ? Icons.terminal_rounded : Icons.cloud_outlined;

  @override
  Widget build(BuildContext context) {
    final s = session;
    if (s is SshTerminalSession) return SshSessionView(session: s);
    return SessionView(session.terminal);
  }

  @override
  void dispose() => session.dispose();
}
