import 'package:material_ui/material_ui.dart';

import '../../ssh/handshake_stepper.dart';
import '../../theme/app_theme.dart';
import '../../theme/ui.dart';
import 'service_controller.dart';
import 'service_models.dart';

enum _Filter { all, running, failed }

/// Panel service systemd: daftar unit, status, dan aksi start/stop/restart/
/// enable/disable + logs (journalctl).
class ServiceView extends StatefulWidget {
  const ServiceView({super.key, required this.controller});

  final ServiceController controller;

  @override
  State<ServiceView> createState() => _ServiceViewState();
}

class _ServiceViewState extends State<ServiceView> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  _Filter _filter = _Filter.all;

  ServiceController get c => widget.controller;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<SystemdService> _visible() {
    return c.services.where((s) {
      switch (_filter) {
        case _Filter.running:
          if (!s.isRunning) return false;
          break;
        case _Filter.failed:
          if (!s.isFailed) return false;
          break;
        case _Filter.all:
          break;
      }
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return s.unit.toLowerCase().contains(q) ||
          s.description.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        if (c.loading && c.snapshot == null && !c.progress.finished) {
          return HandshakeLoading(
            progress: c.progress,
            title: 'Menyambungkan ke ${c.credentials.label}…',
          );
        }
        if (c.connectError != null && c.snapshot == null) {
          return PanelMessage(
            icon: Icons.settings_suggest_outlined,
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
        final snap = c.snapshot!;
        if (snap.error != null && c.services.isEmpty) {
          return PanelMessage(
            icon: Icons.settings_suggest_outlined,
            iconColor: AppTheme.warning,
            message: snap.error!,
            onAction: c.refresh,
          );
        }
        return Container(
          color: AppTheme.bg,
          child: Column(
            children: [
              _header(),
              _filterBar(),
              Expanded(child: _list()),
            ],
          ),
        );
      },
    );
  }

  Widget _header() {
    final running = c.services.where((s) => s.isRunning).length;
    final failed = c.services.where((s) => s.isFailed).length;
    return PanelHeader(
      icon: Icons.settings_suggest_outlined,
      title: 'Services',
      meta: '${c.services.length} unit · $running aktif'
          '${failed > 0 ? " · $failed gagal" : ""}',
      actions: [
        RefreshControls(
          auto: c.autoRefresh,
          interval: c.intervalSeconds,
          onToggleAuto: c.toggleAutoRefresh,
          onInterval: c.setInterval,
          onRefresh: c.refresh,
          busy: c.refreshing,
          options: const [5, 10, 30, 60],
        ),
      ],
    );
  }

  Widget _filterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: AppTheme.bg,
      child: Row(
        children: [
          Expanded(
            child: SearchField(
              hint: 'Cari service…',
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          const SizedBox(width: 10),
          FilterTab(
            label: 'Semua',
            active: _filter == _Filter.all,
            onTap: () => setState(() => _filter = _Filter.all),
          ),
          const SizedBox(width: 6),
          FilterTab(
            label: 'Berjalan',
            active: _filter == _Filter.running,
            onTap: () => setState(() => _filter = _Filter.running),
          ),
          const SizedBox(width: 6),
          FilterTab(
            label: 'Gagal',
            active: _filter == _Filter.failed,
            onTap: () => setState(() => _filter = _Filter.failed),
            color: AppTheme.danger,
          ),
        ],
      ),
    );
  }

  Widget _list() {
    final items = _visible();
    if (items.isEmpty) {
      return PanelMessage(
        icon: Icons.inbox_outlined,
        message: 'Tidak ada service yang cocok.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      itemCount: items.length,
      itemBuilder: (_, i) => _ServiceCard(service: items[i], controller: c),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({required this.service, required this.controller});

  final SystemdService service;
  final ServiceController controller;

  Color get _statusColor {
    if (service.isFailed) return AppTheme.danger;
    if (service.isRunning) return AppTheme.success;
    if (service.active == 'activating') return AppTheme.warning;
    return AppTheme.textMuted;
  }

  Future<void> _run(BuildContext context, String act, String verb) async {
    final err = await controller.action(act, service);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: err == null ? AppTheme.success : AppTheme.danger,
      duration: const Duration(seconds: 2),
      content: Text(err ?? '$verb: ${service.name}',
          style: const TextStyle(color: Colors.white)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = service;
    return AppCard(
      danger: s.isFailed,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: StatusDot(_statusColor),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(s.name,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600)),
                        ),
                        if (s.enabledState != null) ...[
                          const SizedBox(width: 8),
                          Pill(s.enabledState!,
                              color: s.isEnabled
                                  ? AppTheme.success
                                  : AppTheme.textMuted),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      s.description.isEmpty
                          ? '${s.active} · ${s.sub}'
                          : s.description,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: AppTheme.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Pill('${s.active} (${s.sub})', color: _statusColor),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (s.isActive) ...[
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
              if (s.canToggleEnable)
                s.isEnabled
                    ? ToolButton(
                        icon: Icons.link_off_rounded,
                        label: 'Disable',
                        onTap: () => _run(context, 'disable', 'Di-disable'))
                    : ToolButton(
                        icon: Icons.link_rounded,
                        label: 'Enable',
                        color: AppTheme.accent,
                        onTap: () => _run(context, 'enable', 'Di-enable')),
            ],
          ),
        ],
      ),
    );
  }

  void _showLogs(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => _LogsDialog(controller: controller, service: service),
    );
  }
}

class _LogsDialog extends StatefulWidget {
  const _LogsDialog({required this.controller, required this.service});
  final ServiceController controller;
  final SystemdService service;

  @override
  State<_LogsDialog> createState() => _LogsDialogState();
}

class _LogsDialogState extends State<_LogsDialog> {
  String _logs = '';
  bool _loading = true;
  int _lines = 200;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final l = await widget.controller.logs(widget.service, lines: _lines);
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
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 560),
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
                    child: Text('Logs · ${widget.service.name}',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                  ),
                  PopupMenuButton<int>(
                    initialValue: _lines,
                    tooltip: 'Jumlah baris',
                    position: PopupMenuPosition.under,
                    onSelected: (v) {
                      _lines = v;
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
                      child: Text('$_lines baris',
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
