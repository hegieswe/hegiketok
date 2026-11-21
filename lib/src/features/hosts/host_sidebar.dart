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
  });

  /// Dipanggil saat pengguna memilih sebuah host untuk dikoneksikan (terminal).
  final void Function(SshHost host) onConnect;

  /// Dipanggil saat pengguna ingin membuka browser SFTP untuk sebuah host.
  final void Function(SshHost host) onOpenSftp;

  /// Dipanggil saat pengguna ingin membuka dashboard info server.
  final void Function(SshHost host) onOpenInfo;

  /// Dipanggil saat pengguna ingin membuka panel Docker.
  final void Function(SshHost host) onOpenDocker;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hostsAsync = ref.watch(hostsProvider);

    return Container(
      width: 240,
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(right: BorderSide(color: AppTheme.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 10, 8),
            child: Row(
              children: [
                const Icon(Icons.dns_outlined,
                    size: 15, color: AppTheme.textMuted),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'SAVED HOSTS',
                    style: TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                _IconBtn(
                  icon: Icons.download_outlined,
                  tooltip: 'Import dari ~/.ssh/config',
                  onTap: () => showSshConfigImport(context),
                ),
                _IconBtn(
                  icon: Icons.add,
                  tooltip: 'Tambah host',
                  onTap: () => showHostEditor(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppTheme.border),
          Expanded(
            child: hostsAsync.when(
              loading: () => const Center(
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
                    style: const TextStyle(
                        color: Color(0xFFFF7B72), fontSize: 12)),
              ),
              data: (hosts) => hosts.isEmpty
                  ? _empty(context)
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: hosts.length,
                      itemBuilder: (_, i) => _HostTile(
                        host: hosts[i],
                        onConnect: () => onConnect(hosts[i]),
                        onOpenSftp: () => onOpenSftp(hosts[i]),
                        onOpenInfo: () => onOpenInfo(hosts[i]),
                        onOpenDocker: () => onOpenDocker(hosts[i]),
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

  Widget _empty(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inbox_outlined,
                size: 32, color: AppTheme.border),
            const SizedBox(height: 10),
            const Text(
              'Belum ada host tersimpan',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => showHostEditor(context),
              icon: const Icon(Icons.add, size: 15),
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
        backgroundColor: AppTheme.surface,
        title: const Text('Hapus host?',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
        content: Text(
          'Host "${host.label}" dan rahasianya akan dihapus permanen.',
          style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal',
                style: TextStyle(color: AppTheme.textMuted)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF7B72)),
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

class _HostTile extends StatefulWidget {
  const _HostTile({
    required this.host,
    required this.onConnect,
    required this.onOpenSftp,
    required this.onOpenInfo,
    required this.onOpenDocker,
    required this.onEdit,
    required this.onDelete,
  });

  final SshHost host;
  final VoidCallback onConnect;
  final VoidCallback onOpenSftp;
  final VoidCallback onOpenInfo;
  final VoidCallback onOpenDocker;
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
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: InkWell(
        onTap: widget.onConnect,
        child: Container(
          color: _hover ? AppTheme.bg : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            children: [
              Icon(
                host.authMethod == SshAuthMethod.key
                    ? Icons.vpn_key_outlined
                    : Icons.dns_outlined,
                size: 15,
                color: AppTheme.accent,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      host.label,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            host.subtitle,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: AppTheme.textMuted, fontSize: 11),
                          ),
                        ),
                        if (host.jumpHostId != null) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.alt_route,
                              size: 11, color: AppTheme.accent),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (_hover) ...[
                _IconBtn(
                  icon: Icons.monitor_heart_outlined,
                  tooltip: 'Info server (CPU, RAM, disk…)',
                  onTap: widget.onOpenInfo,
                ),
                _IconBtn(
                  icon: Icons.directions_boat_filled_outlined,
                  tooltip: 'Docker (container, logs…)',
                  onTap: widget.onOpenDocker,
                ),
                _IconBtn(
                  icon: Icons.folder_outlined,
                  tooltip: 'Buka SFTP (file manager)',
                  onTap: widget.onOpenSftp,
                ),
                _IconBtn(
                  icon: Icons.edit_outlined,
                  tooltip: 'Edit',
                  onTap: widget.onEdit,
                ),
                _IconBtn(
                  icon: Icons.delete_outline,
                  tooltip: 'Hapus',
                  onTap: widget.onDelete,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 15, color: AppTheme.textMuted),
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      onPressed: onTap,
    );
  }
}
