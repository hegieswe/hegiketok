import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/host_credentials.dart';
import '../../data/host_providers.dart';
import '../../models/ssh_credentials.dart';
import '../../models/ssh_host.dart';
import '../../session/workspace_tab.dart';
import '../../theme/app_theme.dart';
import '../../theme/brand.dart';
import '../command_palette/command_palette.dart';
import '../cron/cron_tab.dart';
import '../docker/docker_tab.dart';
import '../hosts/host_editor.dart';
import '../hosts/host_sidebar.dart';
import '../hosts/hosts_home.dart';
import '../hosts/ssh_config_import.dart';
import '../server_info/server_info_tab.dart';
import '../snippets/snippets_dialog.dart';
import '../services/service_tab.dart';
import '../settings/settings_panel.dart';
import '../settings/settings_providers.dart';
import '../sftp/sftp_tab.dart';
import '../ssh/connection_form.dart';
import '../ssh/ssh_terminal_session.dart';
import '../ssh/tmux_control_tab.dart';
import '../terminal/local_terminal_session.dart';
import '../terminal/terminal_tab.dart';
import '../updates/update_ui.dart';
import '../users/user_tab.dart';
import 'split_tab.dart';

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

  /// Peta tab → id host yang diwakilinya. Sebuah host dianggap ONLINE hanya
  /// bila minimal satu tabnya benar-benar TERSAMBUNG saat ini (bukan sekadar
  /// terbuka): koneksi yang sedang menyambung, gagal, atau timeout → offline.
  final Map<WorkspaceTab, String> _tabHostId = {};

  /// Himpunan id host yang online = punya tab dengan koneksi hidup. Tab tanpa
  /// pelacakan koneksi (mis. panel SFTP) dianggap online selama terbuka.
  Set<String> get _onlineHosts {
    final online = <String>{};
    _tabHostId.forEach((tab, hostId) {
      final conn = tab.connection;
      if (conn == null || conn.value) online.add(hostId);
    });
    return online;
  }

  /// Dipanggil tiap status koneksi sebuah tab berubah → perbarui badge host.
  void _refreshOnline() {
    if (mounted) setState(() {});
  }

  /// Ikat sebuah tab ke host + pantau status koneksinya.
  void _bindHost(WorkspaceTab tab, String hostId) {
    _tabHostId[tab] = hostId;
    tab.connection?.addListener(_refreshOnline);
  }

  /// Lepas ikatan host sebuah tab; kembalikan id host sebelumnya (bila ada).
  String? _unbindHost(WorkspaceTab tab) {
    final hostId = _tabHostId.remove(tab);
    if (hostId != null) tab.connection?.removeListener(_refreshOnline);
    return hostId;
  }

  @override
  void initState() {
    super.initState();
    // Mendarat di grid host (home), bukan langsung terminal lokal — seperti
    // Termius. Terminal lokal dibuka lewat tombol saat dibutuhkan.

    // Cek pembaruan senyap (maks. sekali sehari; bisa dimatikan di Settings).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) maybeAutoCheckForUpdate(context, ref);
    });
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

  /// Tambah tab yang terikat ke sebuah host (statusnya mengikuti koneksi).
  void _addHostTab(WorkspaceTab tab, String hostId) {
    _bindHost(tab, hostId);
    _addTab(tab);
  }

  void _openLocal() => _addTab(TerminalTab(LocalTerminalSession()..start()));

  Future<void> _openSsh() async {
    final creds = await showSshConnectionForm(context);
    if (creds == null) return;
    _addTab(TerminalTab(SshTerminalSession(creds)..start()));
  }

  /// Kredensial lengkap sebuah host tersimpan (termasuk rantai bastion).
  Future<SshCredentials> _credentialsFor(SshHost host) => buildHostCredentials(
        host,
        loadSecret: ref.read(hostRepositoryProvider).loadSecret,
        allHosts: ref.read(hostsProvider).asData?.value ?? const <SshHost>[],
      );

  Future<void> _openSavedHost(SshHost host) async {
    final creds = await _credentialsFor(host);
    _addHostTab(
      TerminalTab(SshTerminalSession(
        creds,
        label: host.label,
        startupCommand: host.startupCommand,
        persistent: host.persistentSession,
      )..start()),
      host.id,
    );
  }

  Future<void> _openSftp(SshHost host) async {
    final creds = await _credentialsFor(host);
    _addHostTab(
      SftpTab(creds, label: host.label, resolveCreds: _credentialsFor),
      host.id,
    );
  }

  Future<void> _openInfo(SshHost host) async {
    final creds = await _credentialsFor(host);
    _addHostTab(ServerInfoTab(creds, label: host.label), host.id);
  }

  Future<void> _openDocker(SshHost host) async {
    final creds = await _credentialsFor(host);
    _addHostTab(DockerTab(creds, label: host.label), host.id);
  }

  Future<void> _openServices(SshHost host) async {
    final creds = await _credentialsFor(host);
    _addHostTab(ServiceTab(creds, label: host.label), host.id);
  }

  Future<void> _openCron(SshHost host) async {
    final creds = await _credentialsFor(host);
    _addHostTab(CronTab(creds, label: host.label), host.id);
  }

  Future<void> _openUsers(SshHost host) async {
    final creds = await _credentialsFor(host);
    _addHostTab(UserTab(creds, label: host.label), host.id);
  }

  Future<void> _openTmux(SshHost host) async {
    final creds = await _credentialsFor(host);
    _addHostTab(TmuxControlTab(creds, label: host.label), host.id);
  }

  void _close(int index) {
    final tab = _tabs[index];
    _unbindHost(tab); // host jadi offline bila ini tab terakhirnya
    tab.dispose();
    setState(() {
      _tabs.removeAt(index);
      if (_active >= _tabs.length) _active = _tabs.length - 1;
    });
  }

  /// Buat sesi kembar dari sebuah tab terminal (untuk panel split kedua).
  /// SSH → sambung ulang host yang sama; lokal → shell lokal baru.
  WorkspaceTab? _cloneTerminal(WorkspaceTab tab) {
    if (tab is! TerminalTab) return null;
    final s = tab.session;
    if (s is SshTerminalSession) {
      return TerminalTab(SshTerminalSession(
        s.credentials,
        label: s.label,
        startupCommand: s.startupCommand,
        persistent: s.persistent,
      )..start());
    }
    return TerminalTab(LocalTerminalSession()..start());
  }

  bool get _canSplitActive =>
      _tabs.isNotEmpty &&
      _active < _tabs.length &&
      _tabs[_active] is TerminalTab;

  /// Pecah tab aktif jadi dua panel berdampingan (panel kiri = sesi sekarang,
  /// panel kanan = sesi kembar). Panel kiri TIDAK tersambung ulang.
  void _splitActive(Axis direction) {
    if (!_canSplitActive) return;
    final current = _tabs[_active];
    final clone = _cloneTerminal(current);
    if (clone == null) return;
    final split = SplitTab(current, clone, direction: direction);
    split.onUnsplit = (keep, drop) => _unsplit(split, keep, drop);
    // Pindahkan ikatan host dari tab lama ke SplitTab (host yang sama).
    final hostId = _unbindHost(current);
    setState(() {
      _tabs[_active] = split;
      if (hostId != null) _bindHost(split, hostId);
    });
  }

  /// Tutup salah satu panel split: pertahankan [keep] sebagai tab tunggal,
  /// lepas [drop].
  void _unsplit(SplitTab split, WorkspaceTab keep, WorkspaceTab drop) {
    final index = _tabs.indexOf(split);
    if (index < 0) return;
    drop.dispose();
    final hostId = _unbindHost(split);
    split.releaseConnection(); // panel 'keep' tetap hidup, jangan ikut dilepas
    setState(() {
      _tabs[index] = keep;
      if (hostId != null) _bindHost(keep, hostId);
    });
  }

  void _openPalette() {
    showCommandPalette(
      context,
      onConnectHost: _openSavedHost,
      commands: [
        PaletteCommand(
            icon: Icons.terminal_rounded,
            label: 'Terminal Lokal',
            run: _openLocal),
        PaletteCommand(
            icon: Icons.cloud_outlined,
            label: 'Koneksi SSH baru',
            run: _openSsh),
        PaletteCommand(
            icon: Icons.code_rounded,
            label: 'Snippets',
            run: () => showSnippetsDialog(context)),
        PaletteCommand(
            icon: Icons.add_rounded,
            label: 'Host baru',
            run: () => showHostEditor(context)),
        PaletteCommand(
            icon: Icons.download_outlined,
            label: 'Import ~/.ssh/config',
            run: () => showSshConfigImport(context)),
        PaletteCommand(
            icon: Icons.tune_rounded,
            label: 'Pengaturan',
            run: () => _scaffoldKey.currentState?.openEndDrawer()),
      ],
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.keyK &&
        HardwareKeyboard.instance.isMetaPressed) {
      _openPalette();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
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
    // Pada mode "Sistem", OS bisa berganti terang/gelap tanpa mengubah
    // themeMode. Membaca platformBrightness mendaftarkan dependency MediaQuery
    // sehingga layar ikut rebuild saat OS beralih appearance — tanpa ini palet
    // facade (AppTheme.current) basi dan sebagian UI "nyangkut" di tema lama.
    if (mode == ThemeMode.system) {
      MediaQuery.platformBrightnessOf(context);
    }
    return Focus(
      onKeyEvent: _onKey,
      child: Scaffold(
      key: _scaffoldKey,
      endDrawer: const SettingsPanel(),
      body: Column(
        children: [
          _TitleBar(
            showSidebar: _showSidebar,
            sidebarToggleEnabled: _tabs.isNotEmpty,
            splitEnabled: _canSplitActive,
            themeMode: mode,
            onToggleSidebar: () =>
                setState(() => _showSidebar = !_showSidebar),
            onNewLocal: _openLocal,
            onNewSsh: _openSsh,
            onSplitRight: () => _splitActive(Axis.horizontal),
            onSplitDown: () => _splitActive(Axis.vertical),
            onCycleTheme: _cycleTheme,
            onOpenSettings: () => _scaffoldKey.currentState?.openEndDrawer(),
          ),
          Expanded(
            child: Row(
              children: [
                // Sidebar host hanya saat ada sesi terbuka (sebagai pengalih
                // cepat). Di home, grid sudah jadi daftar host-nya → tak perlu
                // daftar ganda.
                if (_showSidebar && _tabs.isNotEmpty)
                  HostSidebar(
                    onlineHostIds: _onlineHosts,
                    onConnect: _openSavedHost,
                    onOpenSftp: _openSftp,
                    onOpenInfo: _openInfo,
                    onOpenDocker: _openDocker,
                    onOpenServices: _openServices,
                    onOpenCron: _openCron,
                    onOpenUsers: _openUsers,
                    onOpenTmux: _openTmux,
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
                            ? HostsHome(
                                onlineHostIds: _onlineHosts,
                                onConnect: _openSavedHost,
                                onOpenSftp: _openSftp,
                                onOpenInfo: _openInfo,
                                onOpenDocker: _openDocker,
                                onOpenServices: _openServices,
                                onOpenCron: _openCron,
                                onOpenUsers: _openUsers,
                                onOpenTmux: _openTmux,
                                onNewLocal: _openLocal,
                              )
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
      ),
    );
  }
}

class _TitleBar extends StatelessWidget {
  const _TitleBar({
    required this.showSidebar,
    required this.sidebarToggleEnabled,
    required this.splitEnabled,
    required this.themeMode,
    required this.onToggleSidebar,
    required this.onNewLocal,
    required this.onNewSsh,
    required this.onSplitRight,
    required this.onSplitDown,
    required this.onCycleTheme,
    required this.onOpenSettings,
  });

  final bool showSidebar;
  final bool sidebarToggleEnabled;
  final bool splitEnabled;
  final ThemeMode themeMode;
  final VoidCallback onToggleSidebar;
  final VoidCallback onNewLocal;
  final VoidCallback onNewSsh;
  final VoidCallback onSplitRight;
  final VoidCallback onSplitDown;
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
          if (sidebarToggleEnabled) ...[
            _GhostIcon(
              icon: showSidebar
                  ? Icons.view_sidebar_outlined
                  : Icons.view_sidebar,
              tooltip: 'Tampilkan/sembunyikan daftar host',
              onTap: onToggleSidebar,
            ),
            const SizedBox(width: 6),
          ],
          const BrandLogo(),
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
          if (splitEnabled) ...[
            _GhostIcon(
              icon: Icons.vertical_split_rounded,
              tooltip: 'Split kiri|kanan (dua terminal berdampingan)',
              onTap: onSplitRight,
            ),
            _GhostIcon(
              icon: Icons.horizontal_split_rounded,
              tooltip: 'Split atas/bawah (dua terminal bertumpuk)',
              onTap: onSplitDown,
            ),
          ],
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
      cursor: SystemMouseCursors.click,
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
      cursor: SystemMouseCursors.click,
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
