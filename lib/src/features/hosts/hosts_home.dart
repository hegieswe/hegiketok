import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/host_providers.dart';
import '../../models/ssh_host.dart';
import '../../theme/app_theme.dart';
import '../../theme/ui.dart';
import '../snippets/snippets_dialog.dart';
import 'host_editor.dart';
import 'host_sidebar.dart' show hostOsIcon, hostOsColor, OnlineBadge;
import 'ssh_config_import.dart';

/// Layar "home": grid semua host tersimpan ala Termius — kartu dengan ikon OS,
/// nama, alamat, dan tag; plus pencarian & filter tag. Tampil saat tak ada
/// sesi/tab terbuka.
class HostsHome extends ConsumerStatefulWidget {
  const HostsHome({
    super.key,
    required this.onConnect,
    required this.onOpenSftp,
    required this.onOpenInfo,
    required this.onOpenDocker,
    required this.onOpenServices,
    required this.onOpenCron,
    required this.onOpenUsers,
    required this.onOpenTmux,
    required this.onNewLocal,
    this.onlineHostIds = const {},
  });

  /// Id host yang sedang online (ada tab/sesi terbuka).
  final Set<String> onlineHostIds;

  final void Function(SshHost host) onConnect;
  final void Function(SshHost host) onOpenSftp;
  final void Function(SshHost host) onOpenInfo;
  final void Function(SshHost host) onOpenDocker;
  final void Function(SshHost host) onOpenServices;
  final void Function(SshHost host) onOpenCron;
  final void Function(SshHost host) onOpenUsers;
  final void Function(SshHost host) onOpenTmux;
  final VoidCallback onNewLocal;

  @override
  ConsumerState<HostsHome> createState() => _HostsHomeState();
}

class _HostsHomeState extends ConsumerState<HostsHome> {
  String _search = '';
  final Set<String> _activeTags = {};

  bool _matches(SshHost h) {
    if (_activeTags.isNotEmpty &&
        !_activeTags.any((t) => h.tags.contains(t))) {
      return false;
    }
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return true;
    final hay =
        '${h.label} ${h.host} ${h.username} ${h.tags.join(' ')}'.toLowerCase();
    return hay.contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final hostsAsync = ref.watch(hostsProvider);

    return Container(
      color: AppTheme.bg,
      child: hostsAsync.when(
        loading: () => Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppTheme.accent),
          ),
        ),
        error: (e, _) => PanelMessage(
          icon: Icons.error_outline_rounded,
          iconColor: AppTheme.danger,
          title: 'Gagal memuat host',
          message: '$e',
        ),
        data: (hosts) {
          if (hosts.isEmpty) return _empty();
          final allTags = <String>{for (final h in hosts) ...h.tags}.toList()
            ..sort();
          final filtered = hosts.where(_matches).toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(hosts.length),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
                child: SizedBox(
                  width: 420,
                  child: SearchField(
                    hint: 'Cari host, alamat, atau tag…',
                    onChanged: (v) => setState(() => _search = v),
                  ),
                ),
              ),
              if (allTags.isNotEmpty) _tagBar(allTags),
              Expanded(
                child: filtered.isEmpty
                    ? PanelMessage(
                        icon: Icons.search_off_rounded,
                        message: 'Tak ada host yang cocok dengan filter.',
                        actionLabel: 'Reset filter',
                        onAction: () => setState(() {
                          _search = '';
                          _activeTags.clear();
                        }),
                      )
                    : _grid(filtered),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _header(int total) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 14),
      child: Row(
        children: [
          Text('Hosts',
              style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4)),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppTheme.surfaceInput,
              borderRadius: BorderRadius.circular(AppTheme.rPill),
            ),
            child: Text('$total',
                style: TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
          const Spacer(),
          ToolButton(
            icon: Icons.terminal_rounded,
            label: 'Terminal Lokal',
            onTap: widget.onNewLocal,
          ),
          const SizedBox(width: 8),
          ToolButton(
            icon: Icons.code_rounded,
            label: 'Snippets',
            onTap: () => showSnippetsDialog(context),
          ),
          const SizedBox(width: 8),
          ToolButton(
            icon: Icons.download_outlined,
            label: 'Import',
            onTap: () => showSshConfigImport(context),
          ),
          const SizedBox(width: 8),
          ToolButton(
            icon: Icons.add_rounded,
            label: 'Host baru',
            color: AppTheme.accent,
            onTap: () => showHostEditor(context),
          ),
        ],
      ),
    );
  }

  Widget _tagBar(List<String> tags) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 14),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilterTab(
            label: 'Semua',
            active: _activeTags.isEmpty,
            onTap: () => setState(() => _activeTags.clear()),
          ),
          for (final t in tags)
            FilterTab(
              label: t,
              active: _activeTags.contains(t),
              onTap: () => setState(() {
                if (!_activeTags.remove(t)) _activeTags.add(t);
              }),
            ),
        ],
      ),
    );
  }

  Widget _grid(List<SshHost> hosts) {
    return LayoutBuilder(
      builder: (context, c) {
        const gap = 14.0;
        final w = c.maxWidth - 48; // dikurangi padding kiri-kanan
        // Target lebar kartu ~320px; batasi 1..5 kolom agar tak melar di layar
        // lebar maupun terlalu sempit.
        var cols = (w / 320).floor();
        cols = cols.clamp(1, 5);
        final cardW = (w - gap * (cols - 1)) / cols;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final h in hosts)
                SizedBox(
                  width: cardW,
                  child: _HostGridCard(
                    host: h,
                    online: widget.onlineHostIds.contains(h.id),
                    onConnect: () => widget.onConnect(h),
                    onOpenSftp: () => widget.onOpenSftp(h),
                    onOpenInfo: () => widget.onOpenInfo(h),
                    onOpenDocker: () => widget.onOpenDocker(h),
                    onOpenServices: () => widget.onOpenServices(h),
                    onOpenCron: () => widget.onOpenCron(h),
                    onOpenUsers: () => widget.onOpenUsers(h),
                    onOpenTmux: () => widget.onOpenTmux(h),
                    onEdit: () => showHostEditor(context, existing: h),
                    onDelete: () => _confirmDelete(h),
                    onTapTag: (t) => setState(() {
                      _activeTags
                        ..clear()
                        ..add(t);
                    }),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _empty() {
    return Center(
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
            child: Icon(Icons.dns_outlined, size: 32, color: AppTheme.textFaint),
          ),
          const SizedBox(height: 20),
          Text('Belum ada host tersimpan',
              style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text('Tambahkan server untuk mulai, atau import dari ~/.ssh/config.',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
          const SizedBox(height: 22),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                onPressed: () => showSshConfigImport(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.textPrimary,
                  side: BorderSide(color: AppTheme.border),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                icon: const Icon(Icons.download_outlined, size: 16),
                label: const Text('Import config'),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: () => showHostEditor(context),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: AppTheme.onAccent,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Host Baru'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(SshHost host) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Hapus host?',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
        content: Text(
          'Host "${host.label}" dan rahasianya akan dihapus permanen.',
          style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Batal', style: TextStyle(color: AppTheme.textMuted)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(hostsProvider.notifier).delete(host.id);
    }
  }
}

class _HostGridCard extends StatefulWidget {
  const _HostGridCard({
    required this.host,
    required this.online,
    required this.onConnect,
    required this.onOpenSftp,
    required this.onOpenInfo,
    required this.onOpenDocker,
    required this.onOpenServices,
    required this.onOpenCron,
    required this.onOpenUsers,
    required this.onOpenTmux,
    required this.onEdit,
    required this.onDelete,
    required this.onTapTag,
  });

  final SshHost host;
  final bool online;
  final VoidCallback onConnect;
  final VoidCallback onOpenSftp;
  final VoidCallback onOpenInfo;
  final VoidCallback onOpenDocker;
  final VoidCallback onOpenServices;
  final VoidCallback onOpenCron;
  final VoidCallback onOpenUsers;
  final VoidCallback onOpenTmux;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final void Function(String tag) onTapTag;

  @override
  State<_HostGridCard> createState() => _HostGridCardState();
}

class _HostGridCardState extends State<_HostGridCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final host = widget.host;
    final isKey = host.authMethod == SshAuthMethod.key;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: AppTheme.fast,
        height: 112,
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.rLg),
          border: Border.all(
              color: _hover ? AppTheme.borderStrong : AppTheme.border),
          boxShadow: _hover ? AppTheme.softShadow(AppTheme.current) : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onConnect,
            borderRadius: BorderRadius.circular(AppTheme.rLg),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: hostOsColor(host).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(AppTheme.rMd),
                            ),
                            child: Icon(hostOsIcon(host),
                                size: 20, color: hostOsColor(host)),
                          ),
                          Positioned(
                            right: -3,
                            bottom: -3,
                            child: OnlineBadge(online: widget.online),
                          ),
                        ],
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    host.label,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: AppTheme.textPrimary,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                if (host.jumpHostId != null) ...[
                                  const SizedBox(width: 6),
                                  Icon(Icons.alt_route,
                                      size: 13, color: AppTheme.violet),
                                ],
                              ],
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Icon(
                                    isKey
                                        ? Icons.vpn_key_rounded
                                        : Icons.password_rounded,
                                    size: 11,
                                    color: AppTheme.textFaint),
                                const SizedBox(width: 5),
                                Flexible(
                                  child: Text(
                                    host.subtitle,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: AppTheme.textMuted,
                                        fontSize: 11.5),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      _menu(),
                    ],
                  ),
                  const Spacer(),
                  _tagRow(host.tags),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tagRow(List<String> tags) {
    if (tags.isEmpty) return const SizedBox.shrink();
    final shown = tags.take(3).toList();
    final extra = tags.length - shown.length;
    return SizedBox(
      height: 22,
      child: ClipRect(
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          clipBehavior: Clip.hardEdge,
          children: [
            for (final t in shown) _tagChip(t),
            if (extra > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppTheme.rPill),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Text('+$extra',
                    style: TextStyle(
                        color: AppTheme.textFaint,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _tagChip(String t) {
    return InkWell(
      onTap: () => widget.onTapTag(t),
      borderRadius: BorderRadius.circular(AppTheme.rPill),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: AppTheme.surfaceInput,
          borderRadius: BorderRadius.circular(AppTheme.rPill),
          border: Border.all(color: AppTheme.border),
        ),
        child: Text(
          t,
          style: TextStyle(
            color: AppTheme.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _menu() {
    return AnimatedOpacity(
      opacity: _hover ? 1 : 0.35,
      duration: AppTheme.fast,
      child: PopupMenuButton<String>(
        tooltip: 'Aksi',
        padding: EdgeInsets.zero,
        position: PopupMenuPosition.under,
        constraints: const BoxConstraints(minWidth: 180),
        icon:
            Icon(Icons.more_horiz_rounded, size: 18, color: AppTheme.textMuted),
        onSelected: (v) {
          switch (v) {
            case 'terminal':
              widget.onConnect();
            case 'info':
              widget.onOpenInfo();
            case 'sftp':
              widget.onOpenSftp();
            case 'docker':
              widget.onOpenDocker();
            case 'services':
              widget.onOpenServices();
            case 'cron':
              widget.onOpenCron();
            case 'users':
              widget.onOpenUsers();
            case 'tmux':
              widget.onOpenTmux();
            case 'edit':
              widget.onEdit();
            case 'delete':
              widget.onDelete();
          }
        },
        itemBuilder: (_) => [
          _item('terminal', Icons.terminal_rounded, 'Buka Terminal'),
          _item('info', Icons.monitor_heart_outlined, 'Info Server'),
          _item('sftp', Icons.folder_outlined, 'SFTP (file)'),
          _item('docker', Icons.directions_boat_filled_outlined, 'Docker'),
          _item('services', Icons.settings_suggest_outlined, 'Services'),
          _item('cron', Icons.schedule, 'Cron'),
          _item('users', Icons.group_outlined, 'Users'),
          _item('tmux', Icons.grid_view_rounded, 'tmux (control mode)'),
          const PopupMenuDivider(),
          _item('edit', Icons.edit_outlined, 'Edit'),
          _item('delete', Icons.delete_outline, 'Hapus', danger: true),
        ],
      ),
    );
  }

  PopupMenuItem<String> _item(String value, IconData icon, String label,
      {bool danger = false}) {
    final color = danger ? AppTheme.danger : AppTheme.textMuted;
    return PopupMenuItem<String>(
      value: value,
      height: 38,
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Text(label,
              style: TextStyle(
                  color: danger ? AppTheme.danger : AppTheme.textPrimary,
                  fontSize: 13)),
        ],
      ),
    );
  }
}
