import 'package:material_ui/material_ui.dart';

import '../../ssh/handshake_stepper.dart';
import '../../theme/app_theme.dart';
import 'service_controller.dart';
import 'service_models.dart';

const _red = Color(0xFFFF7B72);
const _green = Color(0xFF3FB950);
const _amber = Color(0xFFD29922);

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
          return _errorState(c.connectError!, c.connect);
        }
        if (c.loading && c.snapshot == null) {
          return const _Centered(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppTheme.accent),
            ),
          );
        }
        final snap = c.snapshot!;
        if (snap.error != null && c.services.isEmpty) {
          return _errorState(snap.error!, c.refresh,
              icon: Icons.settings_suggest_outlined);
        }
        return Container(
          color: AppTheme.bg,
          child: Column(
            children: [
              _header(),
              const Divider(height: 1, color: AppTheme.border),
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
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: AppTheme.surface,
      child: Row(
        children: [
          const Icon(Icons.settings_suggest_outlined,
              size: 20, color: AppTheme.accent),
          const SizedBox(width: 10),
          const Text('Services',
              style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          const SizedBox(width: 10),
          Text(
            '${c.services.length} unit · $running aktif'
            '${failed > 0 ? " · $failed gagal" : ""}',
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
          ),
          const Spacer(),
          if (c.autoRefresh) _intervalSelector(),
          const SizedBox(width: 8),
          _toggleChip(
              label: 'Auto', active: c.autoRefresh, onTap: c.toggleAutoRefresh),
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
                : const Icon(Icons.refresh, size: 18, color: AppTheme.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _filterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: AppTheme.bg,
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 34,
              child: TextField(
                controller: _searchCtrl,
                style:
                    const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: AppTheme.surface,
                  hintText: 'Cari service…',
                  hintStyle:
                      const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                  prefixIcon: const Icon(Icons.search,
                      size: 16, color: AppTheme.textMuted),
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppTheme.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppTheme.accent),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _filterChip('Semua', _Filter.all),
          const SizedBox(width: 6),
          _filterChip('Berjalan', _Filter.running),
          const SizedBox(width: 6),
          _filterChip('Gagal', _Filter.failed),
        ],
      ),
    );
  }

  Widget _filterChip(String label, _Filter f) {
    final active = _filter == f;
    final isFail = f == _Filter.failed;
    final color = isFail ? _red : AppTheme.accent;
    return InkWell(
      onTap: () => setState(() => _filter = f),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: active ? color : AppTheme.border),
        ),
        child: Text(label,
            style: TextStyle(
                color: active ? color : AppTheme.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w500)),
      ),
    );
  }

  Widget _list() {
    final items = _visible();
    if (items.isEmpty) {
      return const _Centered(
        child: Text('Tidak ada service yang cocok.',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      itemCount: items.length,
      itemBuilder: (_, i) => _ServiceCard(service: items[i], controller: c),
    );
  }

  Widget _intervalSelector() {
    return PopupMenuButton<int>(
      initialValue: c.intervalSeconds,
      tooltip: 'Interval refresh',
      onSelected: c.setInterval,
      color: AppTheme.surface,
      itemBuilder: (_) => [5, 10, 30, 60]
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
            const Icon(Icons.timer_outlined, size: 13, color: AppTheme.textMuted),
            const SizedBox(width: 5),
            Text('${c.intervalSeconds}s',
                style:
                    const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
            const Icon(Icons.arrow_drop_down, size: 16, color: AppTheme.textMuted),
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
                    color: active ? _green : AppTheme.textMuted, fontSize: 11)),
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
            width: 360,
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

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({required this.service, required this.controller});

  final SystemdService service;
  final ServiceController controller;

  Color get _statusColor {
    if (service.isFailed) return _red;
    if (service.isRunning) return _green;
    if (service.active == 'activating') return _amber;
    return AppTheme.textMuted;
  }

  Future<void> _run(BuildContext context, String act, String verb) async {
    final err = await controller.action(act, service);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: err == null ? _green : _red,
      duration: const Duration(seconds: 2),
      content: Text(err ?? '$verb: ${service.name}',
          style: const TextStyle(color: Colors.white)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = service;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: s.isFailed ? _red.withValues(alpha: 0.5) : AppTheme.border),
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
                    Row(
                      children: [
                        Flexible(
                          child: Text(s.name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600)),
                        ),
                        if (s.enabledState != null) ...[
                          const SizedBox(width: 8),
                          _enabledBadge(s),
                        ],
                      ],
                    ),
                    const SizedBox(height: 1),
                    Text(
                      s.description.isEmpty
                          ? '${s.active} · ${s.sub}'
                          : s.description,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppTheme.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              _statePill(s),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (s.isActive) ...[
                _action(context, Icons.stop, 'Stop',
                    () => _run(context, 'stop', 'Dihentikan')),
                _action(context, Icons.restart_alt, 'Restart',
                    () => _run(context, 'restart', 'Direstart')),
              ] else
                _action(context, Icons.play_arrow, 'Start',
                    () => _run(context, 'start', 'Dijalankan'),
                    color: _green),
              _action(context, Icons.article_outlined, 'Logs',
                  () => _showLogs(context)),
              const Spacer(),
              if (s.canToggleEnable)
                s.isEnabled
                    ? _action(context, Icons.link_off, 'Disable',
                        () => _run(context, 'disable', 'Di-disable'))
                    : _action(context, Icons.link, 'Enable',
                        () => _run(context, 'enable', 'Di-enable'),
                        color: AppTheme.accent),
            ],
          ),
        ],
      ),
    );
  }

  Widget _enabledBadge(SystemdService s) {
    final enabled = s.isEnabled;
    final color = enabled ? _green : AppTheme.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(s.enabledState!,
          style: TextStyle(color: color, fontSize: 10)),
    );
  }

  Widget _statePill(SystemdService s) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text('${s.active} (${s.sub})',
          style: TextStyle(
              color: _statusColor, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  void _showLogs(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => _LogsDialog(controller: controller, service: service),
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
                    child: Text('Logs · ${widget.service.name}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600)),
                  ),
                  PopupMenuButton<int>(
                    initialValue: _lines,
                    tooltip: 'Jumlah baris',
                    color: AppTheme.surface,
                    onSelected: (v) {
                      _lines = v;
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
                      child: Text('$_lines baris',
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
