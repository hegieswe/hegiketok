import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/host_providers.dart';
import '../../models/ssh_credentials.dart';
import '../../models/ssh_host.dart';
import '../../session/workspace_tab.dart';
import '../../theme/app_theme.dart';
import '../hosts/host_sidebar.dart';
import '../sftp/sftp_tab.dart';
import '../ssh/connection_form.dart';
import '../ssh/ssh_terminal_session.dart';
import '../terminal/local_terminal_session.dart';
import '../terminal/terminal_tab.dart';

/// Layar utama: sidebar host tersimpan + workspace ber-tab yang menampung
/// terminal lokal, koneksi SSH, dan browser file SFTP sekaligus.
class WorkspaceScreen extends ConsumerStatefulWidget {
  const WorkspaceScreen({super.key});

  @override
  ConsumerState<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends ConsumerState<WorkspaceScreen> {
  final List<WorkspaceTab> _tabs = [];
  int _active = 0;
  bool _showSidebar = true;

  @override
  void initState() {
    super.initState();
    _openLocal();
  }

  @override
  void dispose() {
    for (final t in _tabs) {
      t.dispose();
    }
    super.dispose();
  }

  void _addTab(WorkspaceTab tab) {
    setState(() {
      _tabs.add(tab);
      _active = _tabs.length - 1;
    });
  }

  void _openLocal() => _addTab(TerminalTab(LocalTerminalSession()..start()));

  Future<void> _openSsh() async {
    final creds = await showSshConnectionForm(context);
    if (creds == null) return;
    _addTab(TerminalTab(SshTerminalSession(creds)..start()));
  }

  Future<SshCredentials> _credentialsFor(SshHost host) async {
    final secret = await ref.read(hostRepositoryProvider).loadSecret(host.id);
    return SshCredentials(
      host: host.host,
      port: host.port,
      username: host.username,
      password:
          host.authMethod == SshAuthMethod.password ? secret.password : null,
      privateKey:
          host.authMethod == SshAuthMethod.key ? secret.privateKey : null,
      passphrase: secret.passphrase,
    );
  }

  /// Buka terminal SSH dari host tersimpan.
  Future<void> _openSavedHost(SshHost host) async {
    final creds = await _credentialsFor(host);
    _addTab(TerminalTab(SshTerminalSession(creds)..start()));
  }

  /// Buka browser SFTP dari host tersimpan.
  Future<void> _openSftp(SshHost host) async {
    final creds = await _credentialsFor(host);
    _addTab(SftpTab(creds, label: host.label));
  }

  void _close(int index) {
    _tabs[index].dispose();
    setState(() {
      _tabs.removeAt(index);
      if (_active >= _tabs.length) _active = _tabs.length - 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _TitleBar(
            showSidebar: _showSidebar,
            onToggleSidebar: () =>
                setState(() => _showSidebar = !_showSidebar),
            onNewLocal: _openLocal,
            onNewSsh: _openSsh,
          ),
          Expanded(
            child: Row(
              children: [
                if (_showSidebar)
                  HostSidebar(
                    onConnect: _openSavedHost,
                    onOpenSftp: _openSftp,
                  ),
                Expanded(
                  child: Column(
                    children: [
                      _TabBar(
                        tabs: _tabs,
                        active: _active,
                        onSelect: (i) => setState(() => _active = i),
                        onClose: _close,
                        onNewLocal: _openLocal,
                      ),
                      Expanded(
                        child: _tabs.isEmpty
                            ? _EmptyState(
                                onNewLocal: _openLocal, onNewSsh: _openSsh)
                            : IndexedStack(
                                index: _active,
                                children: [
                                  for (final t in _tabs) t.build(context),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TitleBar extends StatelessWidget {
  const _TitleBar({
    required this.showSidebar,
    required this.onToggleSidebar,
    required this.onNewLocal,
    required this.onNewSsh,
  });

  final bool showSidebar;
  final VoidCallback onToggleSidebar;
  final VoidCallback onNewLocal;
  final VoidCallback onNewSsh;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          IconButton(
            icon: Icon(showSidebar ? Icons.menu_open : Icons.menu,
                size: 18, color: AppTheme.textMuted),
            tooltip: 'Tampilkan/sembunyikan daftar host',
            onPressed: onToggleSidebar,
          ),
          const SizedBox(width: 4),
          const Icon(Icons.terminal_rounded, size: 18, color: AppTheme.accent),
          const SizedBox(width: 8),
          const Text(
            'Nexus Terminal',
            style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          _ActionButton(icon: Icons.add, label: 'Local', onTap: onNewLocal),
          const SizedBox(width: 8),
          _ActionButton(
              icon: Icons.cloud_outlined,
              label: 'SSH',
              primary: true,
              onTap: onNewSsh),
          const SizedBox(width: 12),
          const Text('local-first · tanpa cloud',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: primary
              ? AppTheme.accent.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border:
              Border.all(color: primary ? AppTheme.accent : AppTheme.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 15,
                color: primary ? AppTheme.accent : AppTheme.textMuted),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    color: primary ? AppTheme.accent : AppTheme.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({
    required this.tabs,
    required this.active,
    required this.onSelect,
    required this.onClose,
    required this.onNewLocal,
  });

  final List<WorkspaceTab> tabs;
  final int active;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onClose;
  final VoidCallback onNewLocal;

  @override
  Widget build(BuildContext context) {
    if (tabs.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 38,
      decoration: const BoxDecoration(
        color: AppTheme.bg,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: tabs.length,
              itemBuilder: (_, i) => _TabItem(
                tab: tabs[i],
                selected: i == active,
                onTap: () => onSelect(i),
                onClose: () => onClose(i),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add, size: 16, color: AppTheme.textMuted),
            tooltip: 'Tab lokal baru',
            onPressed: onNewLocal,
          ),
        ],
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.tab,
    required this.selected,
    required this.onTap,
    required this.onClose,
  });

  final WorkspaceTab tab;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minWidth: 120, maxWidth: 240),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? AppTheme.surface : Colors.transparent,
          border: Border(
            bottom: BorderSide(
                color: selected ? AppTheme.accent : Colors.transparent,
                width: 2),
            right: const BorderSide(color: AppTheme.border),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(tab.icon,
                size: 13,
                color: selected ? AppTheme.accent : AppTheme.textMuted),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                tab.title,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color:
                        selected ? AppTheme.textPrimary : AppTheme.textMuted,
                    fontSize: 12),
              ),
            ),
            const SizedBox(width: 6),
            InkWell(
              onTap: onClose,
              borderRadius: BorderRadius.circular(4),
              child:
                  const Icon(Icons.close, size: 13, color: AppTheme.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onNewLocal, required this.onNewSsh});

  final VoidCallback onNewLocal;
  final VoidCallback onNewSsh;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.terminal_rounded, size: 48, color: AppTheme.border),
          const SizedBox(height: 16),
          const Text('Tidak ada sesi terbuka',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 14)),
          const SizedBox(height: 20),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                onPressed: onNewLocal,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Terminal Lokal'),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: onNewSsh,
                style: FilledButton.styleFrom(backgroundColor: AppTheme.accent),
                icon: const Icon(Icons.cloud_outlined, size: 16),
                label: const Text('Koneksi SSH'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
