import 'package:material_ui/material_ui.dart';

import '../../theme/app_theme.dart';
import 'docker_controller.dart';
import 'docker_models.dart';

const _red = Color(0xFFFF7B72);
const _green = Color(0xFF3FB950);
const _amber = Color(0xFFD29922);

/// Panel Docker: daftar container, stats, logs, dan aksi start/stop/restart/remove.
class DockerView extends StatelessWidget {
  const DockerView({super.key, required this.controller});

  final DockerController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        if (c.loading && c.snapshot == null) {
          return const _Centered(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppTheme.accent)),
                SizedBox(height: 14),
                Text('Memuat Docker…',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
              ],
            ),
          );
        }
        if (c.connectError != null && c.snapshot == null) {
          return _errorState(c.connectError!, c.connect);
        }
        return Container(
          color: AppTheme.bg,
          child: Column(
            children: [
              _header(context, c),
              const Divider(height: 1, color: AppTheme.border),
              Expanded(child: _body(context, c)),
            ],
          ),
        );
      },
    );
  }

  Widget _body(BuildContext context, DockerController c) {
    final snap = c.snapshot!;
    if (snap.error != null) {
      return _errorState(snap.error!, c.refresh, icon: Icons.dock);
    }
    if (snap.containers.isEmpty) {
      return const _Centered(
        child: Text('Tidak ada container.',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
      );
    }
    final running = snap.containers.where((e) => e.isRunning).length;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          '${snap.containers.length} container · $running berjalan',
          style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
        ),
        const SizedBox(height: 12),
        ...snap.containers.map((e) => _ContainerCard(
              container: e,
              controller: c,
            )),
      ],
    );
  }

  Widget _header(BuildContext context, DockerController c) {
    final ver = c.snapshot?.serverVersion ?? '';
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: AppTheme.surface,
      child: Row(
        children: [
          const Icon(Icons.directions_boat_filled_outlined,
              size: 20, color: AppTheme.accent),
          const SizedBox(width: 10),
          const Text('Docker',
              style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          if (ver.isNotEmpty) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.bg,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text('v$ver',
                  style: const TextStyle(
                      color: AppTheme.textMuted, fontSize: 11)),
            ),
          ],
          const Spacer(),
          if (c.autoRefresh) _intervalSelector(c),
          const SizedBox(width: 8),
          _toggleChip(
              label: 'Auto',
              active: c.autoRefresh,
              onTap: c.toggleAutoRefresh),
          const SizedBox(width: 8),
          IconButton(
            onPressed: c.refreshing ? null : c.refresh,
            tooltip: 'Perbarui',
            icon: c.refreshing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppTheme.accent))
                : const Icon(Icons.refresh,
                    size: 18, color: AppTheme.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _intervalSelector(DockerController c) {
    return PopupMenuButton<int>(
      initialValue: c.intervalSeconds,
      tooltip: 'Interval refresh',
      onSelected: c.setInterval,
      color: AppTheme.surface,
      itemBuilder: (_) => [2, 5, 10, 30, 60]
          .map((s) => PopupMenuItem(
                value: s,
                child: Text('$s detik',
                    style: const TextStyle(
                        color: AppTheme.textPrimary, fontSize: 13)),
              ))
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.timer_outlined,
                size: 13, color: AppTheme.textMuted),
            const SizedBox(width: 5),
            Text('${c.intervalSeconds}s',
                style:
                    const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
            const Icon(Icons.arrow_drop_down,
                size: 16, color: AppTheme.textMuted),
          ],
        ),
      ),
    );
  }

  Widget _toggleChip({
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? _green.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: active ? _green : AppTheme.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(active ? Icons.sync : Icons.sync_disabled,
                size: 13, color: active ? _green : AppTheme.textMuted),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    color: active ? _green : AppTheme.textMuted,
                    fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _errorState(String msg, VoidCallback onRetry,
      {IconData icon = Icons.error_outline}) {
    return _Centered(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: _amber, size: 38),
          const SizedBox(height: 12),
          SizedBox(
            width: 340,
            child: Text(msg,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 15),
            label: const Text('Coba lagi'),
          ),
        ],
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      Container(color: AppTheme.bg, child: Center(child: child));
}

class _ContainerCard extends StatelessWidget {
  const _ContainerCard({required this.container, required this.controller});

  final DockerContainer container;
  final DockerController controller;

  Color get _statusColor {
    switch (container.state) {
      case 'running':
        return _green;
      case 'paused':
        return _amber;
      case 'restarting':
        return _amber;
      default:
        return AppTheme.textMuted;
    }
  }

  Future<void> _run(BuildContext context, String act, String verb) async {
    final err = await controller.action(act, container);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: err == null ? _green : _red,
      duration: const Duration(seconds: 2),
      content: Text(err ?? '$verb: ${container.name}',
          style: const TextStyle(color: Colors.white)),
    ));
  }

  Future<void> _confirmRemove(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Hapus container?',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
        content: Text(
          '"${container.name}" akan dihapus permanen (force). Lanjutkan?',
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
            style: FilledButton.styleFrom(backgroundColor: _red),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await _run(context, 'rm -f', 'Dihapus');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = container;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                margin: const EdgeInsets.only(top: 2),
                decoration:
                    BoxDecoration(color: _statusColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.name,
                        style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 1),
                    Text('${c.shortId} · ${c.image}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 11,
                            fontFamily: 'Menlo')),
                  ],
                ),
              ),
              if (c.isRunning) ...[
                _statChip('CPU', '${c.cpuPerc?.toStringAsFixed(1) ?? "-"}%'),
                const SizedBox(width: 6),
                _statChip('MEM', c.memUsage?.split(' / ').first ?? '-'),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                c.isRunning
                    ? Icons.play_circle_fill
                    : Icons.stop_circle_outlined,
                size: 13,
                color: _statusColor,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  c.ports.isEmpty ? c.status : '${c.status}  ·  ${c.ports}',
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (c.isRunning) ...[
                _action(context, Icons.stop, 'Stop', () =>
                    _run(context, 'stop', 'Dihentikan')),
                _action(context, Icons.restart_alt, 'Restart', () =>
                    _run(context, 'restart', 'Direstart')),
              ] else
                _action(context, Icons.play_arrow, 'Start',
                    () => _run(context, 'start', 'Dijalankan'),
                    color: _green),
              _action(context, Icons.article_outlined, 'Logs',
                  () => _showLogs(context)),
              const Spacer(),
              _action(context, Icons.delete_outline, 'Hapus',
                  () => _confirmRemove(context),
                  color: _red),
            ],
          ),
        ],
      ),
    );
  }

  void _showLogs(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => _LogsDialog(controller: controller, container: container),
    );
  }

  Widget _statChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label ',
              style:
                  const TextStyle(color: AppTheme.textMuted, fontSize: 10)),
          Text(value,
              style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Menlo')),
        ],
      ),
    );
  }

  Widget _action(BuildContext context, IconData icon, String label,
      VoidCallback onTap,
      {Color color = AppTheme.textMuted}) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 5),
              Text(label, style: TextStyle(color: color, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

class _LogsDialog extends StatefulWidget {
  const _LogsDialog({required this.controller, required this.container});
  final DockerController controller;
  final DockerContainer container;

  @override
  State<_LogsDialog> createState() => _LogsDialogState();
}

class _LogsDialogState extends State<_LogsDialog> {
  String _logs = '';
  bool _loading = true;
  int _tail = 200;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final l = await widget.controller.logs(widget.container, tail: _tail);
    if (!mounted) return;
    setState(() {
      _logs = l.trim().isEmpty ? '(tidak ada log)' : l;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppTheme.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 10, 10),
              child: Row(
                children: [
                  const Icon(Icons.article_outlined,
                      size: 18, color: AppTheme.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Logs · ${widget.container.name}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600)),
                  ),
                  PopupMenuButton<int>(
                    initialValue: _tail,
                    tooltip: 'Jumlah baris',
                    color: AppTheme.surface,
                    onSelected: (v) {
                      _tail = v;
                      _load();
                    },
                    itemBuilder: (_) => [100, 200, 500, 1000]
                        .map((v) => PopupMenuItem(
                            value: v,
                            child: Text('$v baris',
                                style: const TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontSize: 13))))
                        .toList(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Text('$_tail baris',
                          style: const TextStyle(
                              color: AppTheme.textMuted, fontSize: 12)),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh,
                        size: 18, color: AppTheme.textMuted),
                    tooltip: 'Muat ulang',
                    onPressed: _load,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close,
                        size: 18, color: AppTheme.textMuted),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppTheme.border),
            Flexible(
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(
                        child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppTheme.accent)),
                      ),
                    )
                  : Container(
                      width: double.infinity,
                      color: AppTheme.bg,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(14),
                        child: SelectableText(
                          _logs,
                          style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 12,
                              fontFamily: 'Menlo',
                              height: 1.4),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
