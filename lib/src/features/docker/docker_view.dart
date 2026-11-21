import 'package:material_ui/material_ui.dart';

import '../../ssh/handshake_stepper.dart';
import '../../theme/app_theme.dart';
import '../../theme/ui.dart';
import 'docker_controller.dart';
import 'docker_models.dart';

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
        if (c.loading && c.snapshot == null && !c.progress.finished) {
          return HandshakeLoading(
            progress: c.progress,
            title: 'Menyambungkan Docker ke ${c.credentials.label}…',
          );
        }
        if (c.connectError != null && c.snapshot == null) {
          return PanelMessage(
            icon: Icons.directions_boat_filled_outlined,
            iconColor: AppTheme.warning,
            title: 'Gagal terhubung',
            message: c.connectError!,
            onAction: c.connect,
          );
        }
        if (c.loading && c.snapshot == null) {
          return Container(
            color: AppTheme.bg,
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppTheme.accent),
              ),
            ),
          );
        }
        return Container(
          color: AppTheme.bg,
          child: Column(
            children: [
              PanelHeader(
                icon: Icons.directions_boat_filled_outlined,
                title: 'Docker',
                meta: (c.snapshot?.serverVersion ?? '').isEmpty
                    ? null
                    : 'v${c.snapshot!.serverVersion}',
                actions: [
                  RefreshControls(
                    auto: c.autoRefresh,
                    interval: c.intervalSeconds,
                    onToggleAuto: c.toggleAutoRefresh,
                    onInterval: c.setInterval,
                    onRefresh: c.refresh,
                    busy: c.refreshing,
                  ),
                ],
              ),
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
      return PanelMessage(
        icon: Icons.dock,
        iconColor: AppTheme.warning,
        message: snap.error!,
        onAction: c.refresh,
      );
    }
    if (snap.containers.isEmpty) {
      return PanelMessage(
        icon: Icons.inbox_outlined,
        message: 'Tidak ada container di server ini.',
      );
    }
    final running = snap.containers.where((e) => e.isRunning).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      children: [
        Row(
          children: [
            Pill('$running berjalan', color: AppTheme.success),
            const SizedBox(width: 8),
            Pill('${snap.containers.length} total', color: AppTheme.textMuted),
          ],
        ),
        const SizedBox(height: 14),
        ...snap.containers
            .map((e) => _ContainerCard(container: e, controller: c)),
      ],
    );
  }
}

class _ContainerCard extends StatelessWidget {
  const _ContainerCard({required this.container, required this.controller});

  final DockerContainer container;
  final DockerController controller;

  Color get _statusColor {
    switch (container.state) {
      case 'running':
        return AppTheme.success;
      case 'paused':
      case 'restarting':
        return AppTheme.warning;
      default:
        return AppTheme.textFaint;
    }
  }

  Future<void> _run(BuildContext context, String act, String verb) async {
    final err = await controller.action(act, container);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: err == null ? AppTheme.success : AppTheme.danger,
      duration: const Duration(seconds: 2),
      content: Text(err ?? '$verb: ${container.name}',
          style: const TextStyle(color: Colors.white)),
    ));
  }

  Future<void> _confirmRemove(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Hapus container?',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
        content: Text(
          '"${container.name}" akan dihapus permanen (force). Lanjutkan?',
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
    if (ok == true && context.mounted) {
      await _run(context, 'rm -f', 'Dihapus');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = container;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: StatusDot(_statusColor),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.name,
                        style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text('${c.shortId} · ${c.image}',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 11,
                            fontFamily: 'Menlo')),
                  ],
                ),
              ),
              if (c.isRunning) ...[
                Tag('CPU ${c.cpuPerc?.toStringAsFixed(1) ?? "-"}%', mono: true),
                const SizedBox(width: 6),
                Tag('MEM ${c.memUsage?.split(' / ').first ?? '-'}', mono: true),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Pill(c.isRunning ? 'running' : c.state,
                  color: _statusColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  c.ports.isEmpty ? c.status : '${c.status}  ·  ${c.ports}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (c.isRunning) ...[
                ToolButton(
                    icon: Icons.stop_rounded,
                    label: 'Stop',
                    onTap: () => _run(context, 'stop', 'Dihentikan')),
                ToolButton(
                    icon: Icons.restart_alt_rounded,
                    label: 'Restart',
                    onTap: () => _run(context, 'restart', 'Direstart')),
              ] else
                ToolButton(
                    icon: Icons.play_arrow_rounded,
                    label: 'Start',
                    color: AppTheme.success,
                    onTap: () => _run(context, 'start', 'Dijalankan')),
              ToolButton(
                  icon: Icons.article_outlined,
                  label: 'Logs',
                  onTap: () => _showLogs(context)),
              const Spacer(),
              ToolButton(
                  icon: Icons.delete_outline_rounded,
                  label: 'Hapus',
                  color: AppTheme.danger,
                  onTap: () => _confirmRemove(context)),
            ],
          ),
        ],
      ),
    );
  }

  void _showLogs(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) =>
          _LogsDialog(controller: controller, container: container),
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
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780, maxHeight: 580),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 10, 10),
              child: Row(
                children: [
                  Icon(Icons.article_outlined, size: 18, color: AppTheme.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Logs · ${widget.container.name}',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                  ),
                  PopupMenuButton<int>(
                    initialValue: _tail,
                    tooltip: 'Jumlah baris',
                    position: PopupMenuPosition.under,
                    onSelected: (v) {
                      _tail = v;
                      _load();
                    },
                    itemBuilder: (_) => [100, 200, 500, 1000]
                        .map((v) => PopupMenuItem(
                            value: v,
                            height: 38,
                            child: Text('$v baris',
                                style: TextStyle(
                                    color: AppTheme.textPrimary, fontSize: 13))))
                        .toList(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppTheme.rSm),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Text('$_tail baris',
                          style: TextStyle(
                              color: AppTheme.textMuted, fontSize: 12)),
                    ),
                  ),
                  GhostIconButton(
                      icon: Icons.refresh_rounded,
                      tooltip: 'Muat ulang',
                      onTap: _load),
                  GhostIconButton(
                      icon: Icons.close_rounded,
                      onTap: () => Navigator.pop(context)),
                ],
              ),
            ),
            Divider(height: 1, color: AppTheme.border),
            Flexible(
              child: _loading
                  ? Padding(
                      padding: const EdgeInsets.all(40),
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
                          style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 12,
                              fontFamily: 'Menlo',
                              height: 1.45),
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
