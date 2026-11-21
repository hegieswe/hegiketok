import 'package:material_ui/material_ui.dart';

import '../../theme/app_theme.dart';
import 'server_info.dart';
import 'server_info_controller.dart';

const _red = Color(0xFFFF7B72);
const _amber = Color(0xFFD29922);
const _purple = Color(0xFFBC8CFF);

Color _usageColor(double pct) {
  if (pct >= 90) return _red;
  if (pct >= 70) return _amber;
  return AppTheme.success;
}

String _kb(int kb) {
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(0)} MB';
  final gb = mb / 1024;
  if (gb < 1024) return '${gb.toStringAsFixed(gb < 10 ? 1 : 0)} GB';
  return '${(gb / 1024).toStringAsFixed(1)} TB';
}

/// Dashboard informasi server: CPU, memory, disk, jaringan, proses, dll.
class ServerInfoView extends StatelessWidget {
  const ServerInfoView({super.key, required this.controller});

  final ServerInfoController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        if (c.loading && c.info == null) {
          return const _Centered(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppTheme.accent),
                ),
                SizedBox(height: 14),
                Text('Mengambil informasi server…',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
              ],
            ),
          );
        }
        if (c.error != null && c.info == null) {
          return _Centered(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: _red, size: 36),
                const SizedBox(height: 12),
                Text(c.error!,
                    style: const TextStyle(color: _red, fontSize: 13)),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: c.connect,
                  icon: const Icon(Icons.refresh, size: 15),
                  label: const Text('Coba lagi'),
                ),
              ],
            ),
          );
        }
        return _Dashboard(controller: c);
      },
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

class _Dashboard extends StatelessWidget {
  const _Dashboard({required this.controller});
  final ServerInfoController controller;

  @override
  Widget build(BuildContext context) {
    final info = controller.info!;
    return Container(
      color: AppTheme.bg,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _header(context, info),
          const SizedBox(height: 18),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              _CpuCard(info),
              _MemoryCard(info),
              if (info.swapTotalKb > 0)
                _SimpleMeter(
                  icon: Icons.swap_horiz,
                  title: 'Swap',
                  percent: info.swapPercent,
                  subtitle:
                      '${_kb(info.swapUsedKb)} / ${_kb(info.swapTotalKb)}',
                ),
            ],
          ),
          const SizedBox(height: 22),
          _sectionTitle('Sistem'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _InfoTile(Icons.dns_outlined, 'Hostname', info.hostname),
              _InfoTile(Icons.terminal, 'OS', info.os),
              _InfoTile(Icons.settings_suggest_outlined, 'Kernel', info.kernel),
              _InfoTile(Icons.schedule, 'Uptime', info.uptime),
              _InfoTile(
                  Icons.developer_board,
                  'CPU',
                  info.cpuModel.isEmpty
                      ? '${info.cpuCores} core'
                      : info.cpuModel),
              _InfoTile(
                  Icons.show_chart,
                  'Load (1·5·15m)',
                  info.loadAvg.isEmpty
                      ? '-'
                      : info.loadAvg
                          .map((e) => e.toStringAsFixed(2))
                          .join('  ')),
              _InfoTile(Icons.people_outline, 'Users login',
                  '${info.usersLoggedIn}'),
              _InfoTile(Icons.account_tree_outlined, 'Processes',
                  '${info.processes}'),
            ],
          ),
          const SizedBox(height: 22),
          _sectionTitle('Proses'),
          const SizedBox(height: 10),
          _ProcessTable(
            procs: info.topProcesses,
            onKill: controller.killProcess,
          ),
          const SizedBox(height: 22),
          _sectionTitle('Penyimpanan'),
          const SizedBox(height: 10),
          if (info.disks.isEmpty)
            const Text('Tidak ada data disk.',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 13))
          else
            ...info.disks.map((d) => _DiskRow(d)),
          const SizedBox(height: 22),
          _sectionTitle('Jaringan'),
          const SizedBox(height: 10),
          if (info.networks.isEmpty)
            const Text('Tidak ada interface.',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 13))
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: info.networks.map((n) => _NetChip(n)).toList(),
            ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, ServerInfo info) {
    final c = controller;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.monitor_heart_outlined,
                color: AppTheme.accent, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  info.hostname.isEmpty ? c.credentials.host : info.hostname,
                  style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  '${info.os.isEmpty ? "" : "${info.os} · "}${c.credentials.username}@${c.credentials.host}:${c.credentials.port}',
                  style: const TextStyle(
                      color: AppTheme.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          if (c.autoRefresh) _intervalSelector(c),
          const SizedBox(width: 8),
          _toggleChip(
            label: 'Auto',
            active: c.autoRefresh,
            onTap: c.toggleAutoRefresh,
          ),
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

  Widget _intervalSelector(ServerInfoController c) {
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
                style: const TextStyle(
                    color: AppTheme.textMuted, fontSize: 12)),
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
          color: active
              ? AppTheme.success.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border:
              Border.all(color: active ? AppTheme.success : AppTheme.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(active ? Icons.sync : Icons.sync_disabled,
                size: 13,
                color: active ? AppTheme.success : AppTheme.textMuted),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    color: active ? AppTheme.success : AppTheme.textMuted,
                    fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String t) => Text(
        t,
        style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600),
      );
}

// ---------------- CPU card ----------------

class _CpuCard extends StatelessWidget {
  const _CpuCard(this.info);
  final ServerInfo info;

  @override
  Widget build(BuildContext context) {
    final color = _usageColor(info.cpuUsage);
    final bd = info.cpuBreakdown;
    return Container(
      width: 340,
      padding: const EdgeInsets.all(16),
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
              const Icon(Icons.memory, size: 16, color: AppTheme.textMuted),
              const SizedBox(width: 6),
              const Text('CPU',
                  style: TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              Text('${info.cpuCores} core',
                  style: const TextStyle(
                      color: AppTheme.textMuted, fontSize: 11)),
              const Spacer(),
              if (info.cpuTemp != null) ...[
                Icon(Icons.thermostat,
                    size: 14, color: _usageColor(info.cpuTemp!)),
                const SizedBox(width: 2),
                Text('${info.cpuTemp!.toStringAsFixed(0)}°C',
                    style: TextStyle(
                        color: _usageColor(info.cpuTemp!),
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
                const SizedBox(width: 10),
              ],
              Text('${info.cpuUsage.toStringAsFixed(0)}%',
                  style: TextStyle(
                      color: color,
                      fontSize: 20,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (info.cpuUsage / 100).clamp(0, 1),
              minHeight: 8,
              backgroundColor: AppTheme.bg,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(height: 10),
          // Breakdown
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              _legend('usr', bd.user, AppTheme.accent),
              _legend('sys', bd.system, _purple),
              _legend('io', bd.iowait, _amber),
              _legend('steal', bd.steal, _red),
            ],
          ),
          if (info.perCore.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('Per-core',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 10.5)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 0; i < info.perCore.length; i++)
                  _CoreBar(index: i, percent: info.perCore[i]),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _legend(String label, double pct, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 8,
            height: 8,
            decoration:
                BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 5),
        Text('$label ${pct.toStringAsFixed(0)}%',
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
      ],
    );
  }
}

class _CoreBar extends StatelessWidget {
  const _CoreBar({required this.index, required this.percent});
  final int index;
  final double percent;

  @override
  Widget build(BuildContext context) {
    final color = _usageColor(percent);
    return Tooltip(
      message: 'core $index: ${percent.toStringAsFixed(0)}%',
      child: SizedBox(
        width: 40,
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: (percent / 100).clamp(0, 1),
                minHeight: 6,
                backgroundColor: AppTheme.bg,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
            const SizedBox(height: 2),
            Text('$index',
                style:
                    const TextStyle(color: AppTheme.textMuted, fontSize: 9)),
          ],
        ),
      ),
    );
  }
}

// ---------------- Memory card ----------------

class _MemoryCard extends StatelessWidget {
  const _MemoryCard(this.info);
  final ServerInfo info;

  @override
  Widget build(BuildContext context) {
    final color = _usageColor(info.memPercent);
    final total = info.memTotalKb == 0 ? 1 : info.memTotalKb;
    final usedF = info.memUsedKb / total;
    final cacheF = info.memCacheKb / total;
    final freeF = (1 - usedF - cacheF).clamp(0.0, 1.0);
    return Container(
      width: 300,
      padding: const EdgeInsets.all(16),
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
              const Icon(Icons.sd_storage_outlined,
                  size: 16, color: AppTheme.textMuted),
              const SizedBox(width: 6),
              const Text('Memory',
                  style: TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('${info.memPercent.toStringAsFixed(0)}%',
                  style: TextStyle(
                      color: color,
                      fontSize: 20,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 10),
          // Stacked bar: used | cache | free
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 8,
              child: Row(
                children: [
                  Expanded(
                      flex: (usedF * 1000).round().clamp(0, 1000),
                      child: Container(color: color)),
                  Expanded(
                      flex: (cacheF * 1000).round().clamp(0, 1000),
                      child: Container(
                          color: color.withValues(alpha: 0.35))),
                  Expanded(
                      flex: (freeF * 1000).round().clamp(0, 1000),
                      child: Container(color: AppTheme.bg)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              _legend('Used', info.memUsedKb, color),
              _legend('Cache', info.memCacheKb, color.withValues(alpha: 0.5)),
              _legend('Free', info.memFreeKb, AppTheme.textMuted),
            ],
          ),
          const SizedBox(height: 8),
          Text('Total ${_kb(info.memTotalKb)}',
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _legend(String label, int kb, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 5),
        Text('$label ${_kb(kb)}',
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
      ],
    );
  }
}

// ---------------- Simple meter (swap) ----------------

class _SimpleMeter extends StatelessWidget {
  const _SimpleMeter({
    required this.icon,
    required this.title,
    required this.percent,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final double percent;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final color = _usageColor(percent);
    return Container(
      width: 220,
      padding: const EdgeInsets.all(16),
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
              Icon(icon, size: 16, color: AppTheme.textMuted),
              const SizedBox(width: 6),
              Text(title,
                  style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('${percent.toStringAsFixed(0)}%',
                  style: TextStyle(
                      color: color,
                      fontSize: 20,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (percent / 100).clamp(0, 1),
              minHeight: 8,
              backgroundColor: AppTheme.bg,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(height: 8),
          Text(subtitle,
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
        ],
      ),
    );
  }
}

// ---------------- Info tile / disk / net ----------------

class _InfoTile extends StatelessWidget {
  const _InfoTile(this.icon, this.label, this.value);
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: AppTheme.textMuted, fontSize: 11)),
                const SizedBox(height: 1),
                Text(
                  value.isEmpty ? '-' : value,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DiskRow extends StatelessWidget {
  const _DiskRow(this.disk);
  final DiskInfo disk;

  @override
  Widget build(BuildContext context) {
    final color = _usageColor(disk.usePercent.toDouble());
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.storage, size: 15, color: AppTheme.textMuted),
              const SizedBox(width: 8),
              Text(disk.mount,
                  style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(disk.filesystem,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppTheme.textMuted, fontSize: 11)),
              ),
              Text('${disk.usePercent}%',
                  style: TextStyle(
                      color: color,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (disk.usePercent / 100).clamp(0, 1),
              minHeight: 7,
              backgroundColor: AppTheme.bg,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(height: 7),
          Text(
              '${_kb(disk.usedKb)} terpakai · ${_kb(disk.availKb)} bebas · total ${_kb(disk.sizeKb)}',
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
        ],
      ),
    );
  }
}

class _NetChip extends StatelessWidget {
  const _NetChip(this.net);
  final NetInterface net;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lan_outlined, size: 15, color: AppTheme.accent),
          const SizedBox(width: 8),
          Text(net.name,
              style: const TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Text(net.address,
              style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 12,
                  fontFamily: 'Menlo')),
        ],
      ),
    );
  }
}

// ---------------- Process table (search + sort + kill) ----------------

enum _ProcSort { cpu, mem }

class _ProcessTable extends StatefulWidget {
  const _ProcessTable({required this.procs, required this.onKill});
  final List<ProcessInfo> procs;
  final Future<String?> Function(int pid, {bool force}) onKill;

  @override
  State<_ProcessTable> createState() => _ProcessTableState();
}

class _ProcessTableState extends State<_ProcessTable> {
  _ProcSort _key = _ProcSort.cpu;
  bool _desc = true;
  String _query = '';
  static const _limit = 15;

  List<ProcessInfo> get _filteredSorted {
    final q = _query.trim().toLowerCase();
    var list = widget.procs.where((p) {
      if (q.isEmpty) return true;
      return p.command.toLowerCase().contains(q) ||
          p.user.toLowerCase().contains(q) ||
          '${p.pid}'.contains(q);
    }).toList();
    list.sort((a, b) {
      final v = _key == _ProcSort.cpu
          ? a.cpu.compareTo(b.cpu)
          : a.mem.compareTo(b.mem);
      return _desc ? -v : v;
    });
    return list.take(_limit).toList();
  }

  void _sortBy(_ProcSort k) {
    setState(() {
      if (_key == k) {
        _desc = !_desc;
      } else {
        _key = k;
        _desc = true;
      }
    });
  }

  Future<void> _confirmKill(ProcessInfo p) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Hentikan proses?',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
        content: Text(
          'PID ${p.pid} · ${p.command}\nKirim sinyal untuk menghentikan proses ini?',
          style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal',
                style: TextStyle(color: AppTheme.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'term'),
            child: const Text('Kill (TERM)',
                style: TextStyle(color: _amber)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'force'),
            style: FilledButton.styleFrom(backgroundColor: _red),
            child: const Text('Force (-9)'),
          ),
        ],
      ),
    );
    if (choice == null) return;
    final err = await widget.onKill(p.pid, force: choice == 'force');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: err == null ? AppTheme.success : _red,
        duration: const Duration(seconds: 2),
        content: Text(
          err ?? 'Proses ${p.pid} dihentikan.',
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.procs.isEmpty) {
      return const Text('Tidak ada data proses.',
          style: TextStyle(color: AppTheme.textMuted, fontSize: 13));
    }
    final rows = _filteredSorted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _toolbar(),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _headerRow(),
              if (rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Tidak ada proses cocok.',
                      style: TextStyle(
                          color: AppTheme.textMuted, fontSize: 12)),
                )
              else
                for (var i = 0; i < rows.length; i++)
                  _dataRow(rows[i], alt: i.isOdd),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text('Menampilkan ${rows.length} dari ${widget.procs.length} proses',
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
      ],
    );
  }

  Widget _toolbar() {
    return Row(
      children: [
        SizedBox(
          width: 220,
          height: 34,
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Cari nama / user / PID…',
              hintStyle:
                  const TextStyle(color: AppTheme.textMuted, fontSize: 12.5),
              isDense: true,
              filled: true,
              fillColor: AppTheme.surface,
              prefixIcon: const Icon(Icons.search,
                  size: 15, color: AppTheme.textMuted),
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
        const SizedBox(width: 14),
        const Text('Urutkan:',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
        const SizedBox(width: 8),
        _sortChip('CPU', _ProcSort.cpu),
        const SizedBox(width: 8),
        _sortChip('Memory', _ProcSort.mem),
        const Spacer(),
        InkWell(
          onTap: () => setState(() => _desc = !_desc),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_desc ? Icons.arrow_downward : Icons.arrow_upward,
                    size: 13, color: AppTheme.textMuted),
                const SizedBox(width: 5),
                Text(_desc ? 'Tertinggi' : 'Terendah',
                    style: const TextStyle(
                        color: AppTheme.textMuted, fontSize: 12)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _sortChip(String label, _ProcSort k) {
    final active = _key == k;
    return InkWell(
      onTap: () => _sortBy(k),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active
              ? AppTheme.accent.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: active ? AppTheme.accent : AppTheme.border),
        ),
        child: Text(label,
            style: TextStyle(
              color: active ? AppTheme.accent : AppTheme.textMuted,
              fontSize: 12,
              fontWeight: active ? FontWeight.w600 : FontWeight.w500,
            )),
      ),
    );
  }

  Widget _headerRow() {
    Widget sortableHeader(String text, _ProcSort k, double width) {
      final active = _key == k;
      return SizedBox(
        width: width,
        child: InkWell(
          onTap: () => _sortBy(k),
          child: Row(
            children: [
              Text(text,
                  style: TextStyle(
                    color: active ? AppTheme.accent : AppTheme.textMuted,
                    fontSize: 11,
                    fontFamily: 'Menlo',
                    fontWeight: FontWeight.w700,
                  )),
              if (active)
                Icon(_desc ? Icons.arrow_drop_down : Icons.arrow_drop_up,
                    size: 14, color: AppTheme.accent),
            ],
          ),
        ),
      );
    }

    const headStyle = TextStyle(
      color: AppTheme.textMuted,
      fontSize: 11,
      fontFamily: 'Menlo',
      fontWeight: FontWeight.w700,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: AppTheme.bg,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 52, child: Text('PID', style: headStyle)),
          const SizedBox(width: 92, child: Text('USER', style: headStyle)),
          sortableHeader('CPU%', _ProcSort.cpu, 54),
          sortableHeader('MEM%', _ProcSort.mem, 54),
          const Expanded(child: Text('COMMAND', style: headStyle)),
          const SizedBox(width: 32),
        ],
      ),
    );
  }

  Widget _dataRow(ProcessInfo p, {required bool alt}) {
    const base = TextStyle(
        color: AppTheme.textPrimary, fontSize: 12.5, fontFamily: 'Menlo');
    Color heat(double v) => v >= 50
        ? _red
        : v >= 15
            ? _amber
            : AppTheme.textPrimary;
    return _HoverKillRow(
      alt: alt,
      onKill: () => _confirmKill(p),
      child: Row(
        children: [
          SizedBox(width: 52, child: Text('${p.pid}', style: base)),
          SizedBox(
            width: 92,
            child: Text(p.user,
                overflow: TextOverflow.ellipsis,
                style: base.copyWith(color: AppTheme.textMuted)),
          ),
          SizedBox(
              width: 54,
              child: Text(p.cpu.toStringAsFixed(1),
                  style: base.copyWith(color: heat(p.cpu)))),
          SizedBox(
              width: 54,
              child: Text(p.mem.toStringAsFixed(1),
                  style: base.copyWith(color: heat(p.mem)))),
          Expanded(
            child:
                Text(p.command, overflow: TextOverflow.ellipsis, style: base),
          ),
        ],
      ),
    );
  }
}

class _HoverKillRow extends StatefulWidget {
  const _HoverKillRow(
      {required this.child, required this.onKill, required this.alt});
  final Widget child;
  final VoidCallback onKill;
  final bool alt;

  @override
  State<_HoverKillRow> createState() => _HoverKillRowState();
}

class _HoverKillRowState extends State<_HoverKillRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: widget.alt
            ? AppTheme.bg.withValues(alpha: 0.4)
            : Colors.transparent,
        child: Row(
          children: [
            Expanded(child: widget.child),
            SizedBox(
              width: 32,
              child: _hover
                  ? IconButton(
                      icon: const Icon(Icons.stop_circle_outlined,
                          size: 16, color: _red),
                      tooltip: 'Hentikan proses',
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: widget.onKill,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
