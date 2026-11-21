import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/host_providers.dart';
import '../../models/ssh_credentials.dart';
import '../../models/ssh_host.dart';
import '../../session/workspace_tab.dart';
import '../../theme/app_theme.dart';
import '../cron/cron_tab.dart';
import '../docker/docker_tab.dart';
import '../hosts/host_sidebar.dart';
import '../server_info/server_info_tab.dart';
import '../services/service_tab.dart';
import '../settings/settings_panel.dart';
import '../settings/settings_providers.dart';
import '../sftp/sftp_tab.dart';
import '../ssh/connection_form.dart';
import '../ssh/ssh_terminal_session.dart';
import '../terminal/local_terminal_session.dart';
import '../terminal/terminal_tab.dart';
import '../users/user_tab.dart';

/// Layar utama: sidebar host tersimpan + workspace ber-tab yang menampung
/// terminal lokal, koneksi SSH, dan panel-panel server sekaligus.
class WorkspaceScreen extends ConsumerStatefulWidget {
  const WorkspaceScreen({super.key});

  @override
  ConsumerState<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends ConsumerState<WorkspaceScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
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

  Future<SshCredentials> _credentialsFor(SshHost host) =>
      _buildCreds(host, <String>{});

  /// Bangun kredensial lengkap termasuk rantai jump-host (bastion), dengan
  /// perlindungan terhadap siklus referensi lewat [visited].
  Future<SshCredentials> _buildCreds(SshHost host, Set<String> visited) async {
    visited.add(host.id);
    final secret = await ref.read(hostRepositoryProvider).loadSecret(host.id);

    final jumps = <SshCredentials>[];
    final jid = host.jumpHostId;
    if (jid != null && !visited.contains(jid)) {
      final hosts = ref.read(hostsProvider).asData?.value ?? const <SshHost>[];
      SshHost? jump;
      for (final h in hosts) {
        if (h.id == jid) {
          jump = h;
          break;
        }
      }
      if (jump != null) {
        final jumpCreds = await _buildCreds(jump, visited);
        jumps
          ..addAll(jumpCreds.jumpHosts)
          ..add(SshCredentials(
            host: jumpCreds.host,
            port: jumpCreds.port,
            username: jumpCreds.username,
            password: jumpCreds.password,
            privateKey: jumpCreds.privateKey,
            passphrase: jumpCreds.passphrase,
          ));
      }
    }

    return SshCredentials(
      host: host.host,
      port: host.port,
      username: host.username,
      password:
          host.authMethod == SshAuthMethod.password ? secret.password : null,
      privateKey:
          host.authMethod == SshAuthMethod.key ? secret.privateKey : null,
      passphrase: secret.passphrase,
      jumpHosts: jumps,
    );
  }

  Future<void> _openSavedHost(SshHost host) async {
    final creds = await _credentialsFor(host);
    _addTab(TerminalTab(SshTerminalSession(creds)..start()));
  }

  Future<void> _openSftp(SshHost host) async {
    final creds = await _credentialsFor(host);
    _addTab(SftpTab(creds, label: host.label));
  }

  Future<void> _openInfo(SshHost host) async {
    final creds = await _credentialsFor(host);
    _addTab(ServerInfoTab(creds, label: host.label));
  }

  Future<void> _openDocker(SshHost host) async {
    final creds = await _credentialsFor(host);
    _addTab(DockerTab(creds, label: host.label));
  }

  Future<void> _openServices(SshHost host) async {
    final creds = await _credentialsFor(host);
    _addTab(ServiceTab(creds, label: host.label));
  }

  Future<void> _openCron(SshHost host) async {
    final creds = await _credentialsFor(host);
    _addTab(CronTab(creds, label: host.label));
  }

  Future<void> _openUsers(SshHost host) async {
    final creds = await _credentialsFor(host);
    _addTab(UserTab(creds, label: host.label));
  }

  void _close(int index) {
    _tabs[index].dispose();
    setState(() {
      _tabs.removeAt(index);
      if (_active >= _tabs.length) _active = _tabs.length - 1;
    });
  }

  void _cycleTheme() {
    final cur = ref.read(settingsProvider).themeMode;
    final next = switch (cur) {
      ThemeMode.dark => ThemeMode.light,
      ThemeMode.light => ThemeMode.system,
      ThemeMode.system => ThemeMode.dark,
    };
    ref.read(settingsProvider.notifier).setThemeMode(next);
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(settingsProvider.select((s) => s.themeMode));
    return Scaffold(
      key: _scaffoldKey,
      endDrawer: const SettingsPanel(),
      body: Column(
        children: [
          _TitleBar(
            showSidebar: _showSidebar,
            themeMode: mode,
            onToggleSidebar: () =>
                setState(() => _showSidebar = !_showSidebar),
            onNewLocal: _openLocal,
            onNewSsh: _openSsh,
            onCycleTheme: _cycleTheme,
            onOpenSettings: () => _scaffoldKey.currentState?.openEndDrawer(),
          ),
          Expanded(
            child: Row(
              children: [
                if (_showSidebar)
                  HostSidebar(
                    onConnect: _openSavedHost,
                    onOpenSftp: _openSftp,
                    onOpenInfo: _openInfo,
                    onOpenDocker: _openDocker,
                    onOpenServices: _openServices,
                    onOpenCron: _openCron,
                    onOpenUsers: _openUsers,
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
    required this.themeMode,
    required this.onToggleSidebar,
    required this.onNewLocal,
    required this.onNewSsh,
    required this.onCycleTheme,
    required this.onOpenSettings,
  });

  final bool showSidebar;
  final ThemeMode themeMode;
  final VoidCallback onToggleSidebar;
  final VoidCallback onNewLocal;
  final VoidCallback onNewSsh;
  final VoidCallback onCycleTheme;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          _GhostIcon(
            icon: showSidebar
                ? Icons.view_sidebar_outlined
                : Icons.view_sidebar,
            tooltip: 'Tampilkan/sembunyikan daftar host',
            onTap: onToggleSidebar,
          ),
          const SizedBox(width: 6),
          _brand(),
          const Spacer(),
          _NewButton(
            icon: Icons.add_rounded,
            label: 'Local',
            onTap: onNewLocal,
          ),
          const SizedBox(width: 8),
          _NewButton(
            icon: Icons.cloud_outlined,
            label: 'SSH',
            primary: true,
            onTap: onNewSsh,
          ),
          const SizedBox(width: 10),
          Container(width: 1, height: 22, color: AppTheme.border),
          const SizedBox(width: 6),
          _GhostIcon(
            icon: switch (themeMode) {
              ThemeMode.dark => Icons.dark_mode_outlined,
              ThemeMode.light => Icons.light_mode_outlined,
              ThemeMode.system => Icons.brightness_auto_outlined,
            },
            tooltip: 'Tema: ${switch (themeMode) {
              ThemeMode.dark => 'Gelap',
              ThemeMode.light => 'Terang',
              ThemeMode.system => 'Ikuti sistem',
            }}',
            onTap: onCycleTheme,
          ),
          _GhostIcon(
            icon: Icons.tune_rounded,
            tooltip: 'Pengaturan tampilan',
            onTap: onOpenSettings,
          ),
        ],
      ),
    );
  }

  Widget _brand() {
    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppTheme.accent, AppTheme.violet],
            ),
            borderRadius: BorderRadius.circular(AppTheme.rSm),
          ),
          child: const Icon(Icons.terminal_rounded, size: 15, color: Colors.white),
        ),
        const SizedBox(width: 9),
        Text(
          'HegiKetok',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: AppTheme.surfaceInput,
            borderRadius: BorderRadius.circular(AppTheme.rPill),
          ),
          child: Text('local-first',
              style: TextStyle(color: AppTheme.textFaint, fontSize: 10.5)),
        ),
      ],
    );
  }
}

class _GhostIcon extends StatelessWidget {
  const _GhostIcon(
      {required this.icon, required this.onTap, required this.tooltip});

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 18, color: AppTheme.textMuted),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      onPressed: onTap,
    );
  }
}

class _NewButton extends StatefulWidget {
  const _NewButton({
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
  State<_NewButton> createState() => _NewButtonState();
}

class _NewButtonState extends State<_NewButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final primary = widget.primary;
    final Color fg = primary ? AppTheme.onAccent : AppTheme.textMuted;
    final Color bg = primary
        ? (_hover ? AppTheme.accentHover : AppTheme.accent)
        : (_hover ? AppTheme.surfaceInput : Colors.transparent);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppTheme.fast,
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppTheme.rSm),
            border: Border.all(
              color: primary ? Colors.transparent : AppTheme.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 15, color: fg),
              const SizedBox(width: 6),
              Text(widget.label,
                  style: TextStyle(
                      color: fg,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600)),
            ],
          ),
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
      height: 44,
      decoration: BoxDecoration(
        color: AppTheme.bg,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: tabs.length,
              padding: const EdgeInsets.symmetric(vertical: 6),
              separatorBuilder: (_, _) => const SizedBox(width: 4),
              itemBuilder: (_, i) => _TabItem(
                tab: tabs[i],
                selected: i == active,
                onTap: () => onSelect(i),
                onClose: () => onClose(i),
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: Icon(Icons.add_rounded, size: 18, color: AppTheme.textMuted),
            tooltip: 'Tab lokal baru',
            visualDensity: VisualDensity.compact,
            onPressed: onNewLocal,
          ),
        ],
      ),
    );
  }
}

class _TabItem extends StatefulWidget {
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
  State<_TabItem> createState() => _TabItemState();
}

class _TabItemState extends State<_TabItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppTheme.fast,
          constraints: const BoxConstraints(minWidth: 118, maxWidth: 220),
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.surface
                : (_hover ? AppTheme.surfaceInput : Colors.transparent),
            borderRadius: BorderRadius.circular(AppTheme.rSm),
            border: Border.all(
              color: selected ? AppTheme.border : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.tab.icon,
                  size: 13,
                  color: selected ? AppTheme.accent : AppTheme.textFaint),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  widget.tab.title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color:
                        selected ? AppTheme.textPrimary : AppTheme.textMuted,
                    fontSize: 12.5,
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 7),
              _closeBtn(selected),
            ],
          ),
        ),
      ),
    );
  }

  Widget _closeBtn(bool selected) {
    final visible = _hover || selected;
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: AppTheme.fast,
      child: InkWell(
        onTap: widget.onClose,
        borderRadius: BorderRadius.circular(5),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(Icons.close_rounded, size: 14, color: AppTheme.textMuted),
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
    return Container(
      color: AppTheme.bg,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(AppTheme.rXl),
                border: Border.all(color: AppTheme.border),
              ),
              child: Icon(Icons.terminal_rounded,
                  size: 32, color: AppTheme.textFaint),
            ),
            const SizedBox(height: 20),
            Text('Tidak ada sesi terbuka',
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text('Mulai terminal lokal atau sambungkan ke server.',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
            const SizedBox(height: 22),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  onPressed: onNewLocal,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.textPrimary,
                    side: BorderSide(color: AppTheme.border),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Terminal Lokal'),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: onNewSsh,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: AppTheme.onAccent,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                  ),
                  icon: const Icon(Icons.cloud_outlined, size: 16),
                  label: const Text('Koneksi SSH'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
