import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/host_providers.dart';
import '../../models/ssh_host.dart';
import '../../theme/app_theme.dart';
import 'host_editor.dart';
import 'ssh_config_import.dart';

/// Panel kiri berisi daftar host SSH tersimpan.
class HostSidebar extends ConsumerWidget {
  const HostSidebar({
    super.key,
    required this.onConnect,
    required this.onOpenSftp,
    required this.onOpenInfo,
    required this.onOpenDocker,
    required this.onOpenServices,
    required this.onOpenCron,
    required this.onOpenUsers,
  });

  final void Function(SshHost host) onConnect;
  final void Function(SshHost host) onOpenSftp;
  final void Function(SshHost host) onOpenInfo;
  final void Function(SshHost host) onOpenDocker;
  final void Function(SshHost host) onOpenServices;
  final void Function(SshHost host) onOpenCron;
  final void Function(SshHost host) onOpenUsers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hostsAsync = ref.watch(hostsProvider);

    return Container(
      width: 256,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(right: BorderSide(color: AppTheme.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 12, 10),
            child: Row(
              children: [
                Text(
                  'HOSTS',
                  style: TextStyle(
                    color: AppTheme.textFaint,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(width: 8),
                hostsAsync.maybeWhen(
                  data: (h) => h.isEmpty
                      ? const SizedBox.shrink()
                      : _countPill(h.length),
                  orElse: () => const SizedBox.shrink(),
                ),
                const Spacer(),
                _HeaderBtn(
                  icon: Icons.download_outlined,
                  tooltip: 'Import dari ~/.ssh/config',
                  onTap: () => showSshConfigImport(context),
                ),
                _HeaderBtn(
                  icon: Icons.add_rounded,
                  tooltip: 'Tambah host',
                  onTap: () => showHostEditor(context),
                ),
              ],
            ),
          ),
          Expanded(
            child: hostsAsync.when(
              loading: () => Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppTheme.accent),
                ),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Gagal memuat host:\n$e',
                    style: TextStyle(color: AppTheme.danger, fontSize: 12)),
              ),
              data: (hosts) => hosts.isEmpty
                  ? _empty(context)
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(10, 2, 10, 12),
                      itemCount: hosts.length,
                      itemBuilder: (_, i) => _HostTile(
                        host: hosts[i],
                        onConnect: () => onConnect(hosts[i]),
                        onOpenSftp: () => onOpenSftp(hosts[i]),
                        onOpenInfo: () => onOpenInfo(hosts[i]),
                        onOpenDocker: () => onOpenDocker(hosts[i]),
                        onOpenServices: () => onOpenServices(hosts[i]),
                        onOpenCron: () => onOpenCron(hosts[i]),
                        onOpenUsers: () => onOpenUsers(hosts[i]),
                        onEdit: () =>
                            showHostEditor(context, existing: hosts[i]),
                        onDelete: () => _confirmDelete(context, ref, hosts[i]),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _countPill(int n) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
        decoration: BoxDecoration(
          color: AppTheme.surfaceInput,
          borderRadius: BorderRadius.circular(AppTheme.rPill),
        ),
        child: Text('$n',
            style: TextStyle(
                color: AppTheme.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600)),
      );

  Widget _empty(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppTheme.surfaceInput,
                borderRadius: BorderRadius.circular(AppTheme.rLg),
              ),
              child: Icon(Icons.dns_outlined, size: 24, color: AppTheme.textFaint),
            ),
            const SizedBox(height: 14),
            Text(
              'Belum ada host tersimpan',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              'Tambahkan server untuk mulai.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textFaint, fontSize: 12),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () => showHostEditor(context),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: AppTheme.onAccent,
              ),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Tambah Host'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, SshHost host) async {
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

/// Pilih ikon berdasarkan tebakan OS dari label/host (best-effort).
IconData _osIcon(SshHost host) {
  final t = '${host.label} ${host.host}'.toLowerCase();
  if (t.contains('ubuntu') ||
      t.contains('debian') ||
      t.contains('linux') ||
      t.contains('centos') ||
      t.contains('fedora') ||
      t.contains('arch')) {
    return Icons.terminal_rounded;
  }
  if (t.contains('mac') || t.contains('darwin')) return Icons.laptop_mac;
  if (t.contains('win')) return Icons.window;
  if (t.contains('db') || t.contains('sql') || t.contains('postgres')) {
    return Icons.storage_rounded;
  }
  if (t.contains('web') || t.contains('nginx') || t.contains('app')) {
    return Icons.public;
  }
  return Icons.dns_rounded;
}

class _HostTile extends StatefulWidget {
  const _HostTile({
    required this.host,
    required this.onConnect,
    required this.onOpenSftp,
    required this.onOpenInfo,
    required this.onOpenDocker,
    required this.onOpenServices,
    required this.onOpenCron,
    required this.onOpenUsers,
    required this.onEdit,
    required this.onDelete,
  });

  final SshHost host;
  final VoidCallback onConnect;
  final VoidCallback onOpenSftp;
  final VoidCallback onOpenInfo;
  final VoidCallback onOpenDocker;
  final VoidCallback onOpenServices;
  final VoidCallback onOpenCron;
  final VoidCallback onOpenUsers;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  State<_HostTile> createState() => _HostTileState();
}

class _HostTileState extends State<_HostTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final host = widget.host;
    final isKey = host.authMethod == SshAuthMethod.key;
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedContainer(
          duration: AppTheme.fast,
          decoration: BoxDecoration(
            color: _hover ? AppTheme.surfaceInput : Colors.transparent,
            borderRadius: BorderRadius.circular(AppTheme.rMd),
            border: Border.all(
                color: _hover ? AppTheme.border : Colors.transparent),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onConnect,
              borderRadius: BorderRadius.circular(AppTheme.rMd),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 9, 6, 9),
                child: Row(
                  children: [
                    _avatar(host),
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
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (host.jumpHostId != null) ...[
                                const SizedBox(width: 6),
                                Icon(Icons.alt_route,
                                    size: 12, color: AppTheme.violet),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(
                                  isKey
                                      ? Icons.vpn_key_rounded
                                      : Icons.password_rounded,
                                  size: 10,
                                  color: AppTheme.textFaint),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  host.subtitle,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: AppTheme.textMuted, fontSize: 11),
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
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _avatar(SshHost host) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: AppTheme.accentSoft,
        borderRadius: BorderRadius.circular(AppTheme.rSm),
      ),
      child: Icon(_osIcon(host), size: 17, color: AppTheme.accent),
    );
  }

  Widget _menu() {
    return AnimatedOpacity(
      opacity: _hover ? 1 : 0,
      duration: AppTheme.fast,
      child: PopupMenuButton<String>(
        tooltip: 'Aksi',
        padding: EdgeInsets.zero,
        position: PopupMenuPosition.under,
        constraints: const BoxConstraints(minWidth: 180),
        icon: Icon(Icons.more_horiz_rounded, size: 17, color: AppTheme.textMuted),
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

class _HeaderBtn extends StatelessWidget {
  const _HeaderBtn({required this.icon, required this.onTap, this.tooltip});

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 17, color: AppTheme.textMuted),
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
      onPressed: onTap,
    );
  }
}
