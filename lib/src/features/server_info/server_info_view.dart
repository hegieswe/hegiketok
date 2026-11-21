import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../ssh/handshake_stepper.dart';
import '../../theme/app_theme.dart';
import '../../theme/ui.dart';
import '../settings/settings_providers.dart';
import 'server_alerts.dart';
import 'server_info.dart';
import 'server_info_controller.dart';

Color _usageColor(double pct) {
  if (pct >= 90) return AppTheme.danger;
  if (pct >= 70) return AppTheme.warning;
  return AppTheme.success;
}

String _kb(int kb) {
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(0)} MB';
  final gb = mb / 1024;
  if (gb < 1024) return '${gb.toStringAsFixed(gb < 10 ? 1 : 0)} GB';
  return '${(gb / 1024).toStringAsFixed(1)} TB';
}

/// Container permukaan standar (dengan bayangan lembut di mode terang).
Widget _panel({
  double? width,
  required Widget child,
  EdgeInsetsGeometry padding = const EdgeInsets.all(16),
}) {
  final p = AppTheme.current;
  return Container(
    width: width,
    padding: padding,
    decoration: BoxDecoration(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(AppTheme.rLg),
      border: Border.all(color: AppTheme.border),
      boxShadow: p.isDark ? null : AppTheme.softShadow(p),
    ),
    child: child,
  );
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
        if (c.loading && c.info == null && !c.progress.finished) {
          return HandshakeLoading(
            progress: c.progress,
            title: 'Menyambungkan ke ${c.credentials.label}…',
          );
        }
        if (c.loading && c.info == null && c.error == null) {
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
        if (c.error != null && c.info == null) {
          return PanelMessage(
            icon: Icons.error_outline,
            iconColor: AppTheme.danger,
            title: 'Gagal mengambil info',
            message: c.error!,
            onAction: c.connect,
          );
        }
        return _Dashboard(controller: c);
      },
    );
  }
}

/// Banner daftar peringatan ambang yang terlampaui.
class _AlertsBanner extends StatelessWidget {
  const _AlertsBanner({required this.alerts});
  final List<ServerAlert> alerts;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppTheme.rLg),
        border: Border.all(color: AppTheme.danger.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 18, color: AppTheme.danger),
              const SizedBox(width: 8),
              Text(
                '${alerts.length} peringatan ambang terlampaui',
                style: TextStyle(
                    color: AppTheme.danger,
                    fontSize: 13,
                    fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final a in alerts)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(AppTheme.rSm),
                    border:
                        Border.all(color: AppTheme.danger.withValues(alpha: 0.4)),
                  ),
                  child: Text(a.message,
                      style: TextStyle(color: AppTheme.danger, fontSize: 12)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Dialog pengaturan ambang peringatan CPU/Memory/Disk (persisten via settings).
class _ThresholdDialog extends ConsumerWidget {
  const _ThresholdDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    Widget slider(String label, double value, ValueChanged<double> onChanged) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label,
                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
              const Spacer(),
              Text('${value.toStringAsFixed(0)}%',
                  style: TextStyle(
                      color: AppTheme.accent,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          Slider(
            value: value,
            min: 50,
            max: 99,
            divisions: 49,
            onChanged: onChanged,
          ),
        ],
      );
    }

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.notifications_active_rounded,
                      size: 20, color: AppTheme.accent),
                  const SizedBox(width: 8),
                  Text('Ambang Peringatan',
                      style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Peringatan muncul di dashboard saat pemakaian melampaui ambang.',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 16),
              slider('CPU', s.cpuAlert, notifier.setCpuAlert),
              slider('Memory', s.memAlert, notifier.setMemAlert),
              slider('Disk', s.diskAlert, notifier.setDiskAlert),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      foregroundColor: AppTheme.onAccent),
                  child: const Text('Selesai'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dashboard extends ConsumerWidget {
  const _Dashboard({required this.controller});
  final ServerInfoController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = controller.info!;
    final settings = ref.watch(settingsProvider);
    final alerts = computeAlerts(
      info,
      cpu: settings.cpuAlert,
      mem: settings.memAlert,
      disk: settings.diskAlert,
    );
    return Container(
      color: AppTheme.bg,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _header(context, ref, info, alerts.length),
          if (alerts.isNotEmpty) ...[
            const SizedBox(height: 14),
            _AlertsBanner(alerts: alerts),
          ],
          const SizedBox(height: 18),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              _CpuCard(info),
              _MemoryCard(info),
              if (info.swapTotalKb > 0)
                _SimpleMeter(
                  icon: Icons.swap_horiz_rounded,
                  title: 'Swap',
                  percent: info.swapPercent,
                  subtitle:
                      '${_kb(info.swapUsedKb)} / ${_kb(info.swapTotalKb)}',
                ),
            ],
          ),
          const SizedBox(height: 24),
          const SectionLabel('Sistem'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _InfoTile(Icons.dns_outlined, 'Hostname', info.hostname),
              _InfoTile(Icons.terminal_rounded, 'OS', info.os),
              _InfoTile(Icons.settings_suggest_outlined, 'Kernel', info.kernel),
              _InfoTile(Icons.schedule_rounded, 'Uptime', info.uptime),
              _InfoTile(
                  Icons.developer_board_rounded,
                  'CPU',
                  info.cpuModel.isEmpty
                      ? '${info.cpuCores} core'
                      : info.cpuModel),
              _InfoTile(
                  Icons.show_chart_rounded,
                  'Load (1·5·15m)',
                  info.loadAvg.isEmpty
                      ? '-'
                      : info.loadAvg
                          .map((e) => e.toStringAsFixed(2))
                          .join('  ')),
              _InfoTile(Icons.people_outline_rounded, 'Users login',
                  '${info.usersLoggedIn}'),
              _InfoTile(Icons.account_tree_outlined, 'Processes',
                  '${info.processes}'),
            ],
          ),
          const SizedBox(height: 24),
          const SectionLabel('Proses'),
          const SizedBox(height: 12),
          _ProcessTable(
            procs: info.topProcesses,
            onKill: controller.killProcess,
          ),
          const SizedBox(height: 24),
          const SectionLabel('Penyimpanan'),
          const SizedBox(height: 12),
          if (info.disks.isEmpty)
            Text('Tidak ada data disk.',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 13))
          else
            ...info.disks.map((d) => _DiskRow(d)),
          const SizedBox(height: 24),
          const SectionLabel('Jaringan'),
          const SizedBox(height: 12),
          if (info.networks.isEmpty)
            Text('Tidak ada interface.',
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

  Widget _header(
      BuildContext context, WidgetRef ref, ServerInfo info, int alertCount) {
    final c = controller;
    return _panel(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.accentSoft,
              borderRadius: BorderRadius.circular(AppTheme.rMd),
            ),
            child: Icon(Icons.monitor_heart_outlined,
                color: AppTheme.accent, size: 23),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  info.hostname.isEmpty ? c.credentials.host : info.hostname,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  '${info.os.isEmpty ? "" : "${info.os} · "}${c.credentials.username}@${c.credentials.host}:${c.credentials.port}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _alertBell(context, ref, alertCount),
          const SizedBox(width: 4),
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
    );
  }

  Widget _alertBell(BuildContext context, WidgetRef ref, int alertCount) {
    return IconButton(
      onPressed: () =>
          showDialog(context: context, builder: (_) => const _ThresholdDialog()),
      tooltip: 'Ambang peringatan',
      visualDensity: VisualDensity.compact,
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(
            alertCount > 0
                ? Icons.notifications_active_rounded
                : Icons.notifications_none_rounded,
            size: 19,
            color: alertCount > 0 ? AppTheme.danger : AppTheme.textMuted,
          ),
          if (alertCount > 0)
            Positioned(
              right: -3,
              top: -3,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration:
                    BoxDecoration(color: AppTheme.danger, shape: BoxShape.circle),
                constraints:
                    const BoxConstraints(minWidth: 14, minHeight: 14),
                child: Text('$alertCount',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w700)),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------- CPU card ----------------

class _CpuCard extends StatelessWidget {
  const _CpuCard(this.info);
  final ServerInfo info;

  @override
  Widget build(BuildContext context) {
    final color = _usageColor(info.cpuUsage);
    final bd = info.cpuBreakdown;
    return _panel(
      width: 340,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.memory_rounded, size: 16, color: AppTheme.textMuted),
              const SizedBox(width: 6),
              Text('CPU',
                  style: TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              Text('${info.cpuCores} core',
                  style: TextStyle(color: AppTheme.textFaint, fontSize: 11)),
              const Spacer(),
              if (info.cpuTemp != null) ...[
                Icon(Icons.thermostat_rounded,
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
          const SizedBox(height: 12),
          _bar(info.cpuUsage / 100, color),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              _legend('usr', bd.user, AppTheme.accent),
              _legend('sys', bd.system, AppTheme.violet),
              _legend('io', bd.iowait, AppTheme.warning),
              _legend('steal', bd.steal, AppTheme.danger),
            ],
          ),
          if (info.perCore.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('PER-CORE',
                style: TextStyle(
                    color: AppTheme.textFaint,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8)),
            const SizedBox(height: 8),
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
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 5),
        Text('$label ${pct.toStringAsFixed(0)}%',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
      ],
    );
  }
}

Widget _bar(double value, Color color) {
  return ClipRRect(
    borderRadius: BorderRadius.circular(AppTheme.rPill),
    child: LinearProgressIndicator(
      value: value.clamp(0, 1),
      minHeight: 8,
      backgroundColor: AppTheme.surfaceInput,
      valueColor: AlwaysStoppedAnimation(color),
    ),
  );
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
              borderRadius: BorderRadius.circular(AppTheme.rPill),
              child: LinearProgressIndicator(
                value: (percent / 100).clamp(0, 1),
                minHeight: 6,
                backgroundColor: AppTheme.surfaceInput,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
            const SizedBox(height: 2),
            Text('$index',
                style: TextStyle(color: AppTheme.textFaint, fontSize: 9)),
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
    return _panel(
      width: 300,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.sd_storage_outlined,
                  size: 16, color: AppTheme.textMuted),
              const SizedBox(width: 6),
              Text('Memory',
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
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.rPill),
            child: SizedBox(
              height: 8,
              child: Row(
                children: [
                  Expanded(
                      flex: (usedF * 1000).round().clamp(0, 1000),
                      child: Container(color: color)),
                  Expanded(
                      flex: (cacheF * 1000).round().clamp(0, 1000),
                      child: Container(color: color.withValues(alpha: 0.35))),
                  Expanded(
                      flex: (freeF * 1000).round().clamp(0, 1000),
                      child: Container(color: AppTheme.surfaceInput)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              _legend('Used', info.memUsedKb, color),
              _legend('Cache', info.memCacheKb, color.withValues(alpha: 0.5)),
              _legend('Free', info.memFreeKb, AppTheme.textFaint),
            ],
          ),
          const SizedBox(height: 8),
          Text('Total ${_kb(info.memTotalKb)}',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
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
            style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
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
    return _panel(
      width: 220,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppTheme.textMuted),
              const SizedBox(width: 6),
              Text(title,
                  style: TextStyle(
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
          const SizedBox(height: 12),
          _bar(percent / 100, color),
          const SizedBox(height: 8),
          Text(subtitle,
              style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
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
    return _panel(
      width: 250,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(color: AppTheme.textFaint, fontSize: 11)),
                const SizedBox(height: 1),
                Text(
                  value.isEmpty ? '-' : value,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _panel(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.storage_rounded, size: 15, color: AppTheme.textMuted),
                const SizedBox(width: 8),
                Text(disk.mount,
                    style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(disk.filesystem,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppTheme.textFaint, fontSize: 11)),
                ),
                Text('${disk.usePercent}%',
                    style: TextStyle(
                        color: color,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 10),
            _bar(disk.usePercent / 100, color),
            const SizedBox(height: 8),
            Text(
                '${_kb(disk.usedKb)} terpakai · ${_kb(disk.availKb)} bebas · total ${_kb(disk.sizeKb)}',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _NetChip extends StatelessWidget {
  const _NetChip(this.net);
  final NetInterface net;

  @override
  Widget build(BuildContext context) {
    return _panel(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lan_outlined, size: 15, color: AppTheme.accent),
          const SizedBox(width: 8),
          Text(net.name,
              style: TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Text(net.address,
              style: TextStyle(
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
        title: Text('Hentikan proses?',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
        content: Text(
          'PID ${p.pid} · ${p.command}\nKirim sinyal untuk menghentikan proses ini?',
          style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Batal', style: TextStyle(color: AppTheme.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'term'),
            child: Text('Kill (TERM)', style: TextStyle(color: AppTheme.warning)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'force'),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
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
        backgroundColor: err == null ? AppTheme.success : AppTheme.danger,
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
      return Text('Tidak ada data proses.',
          style: TextStyle(color: AppTheme.textMuted, fontSize: 13));
    }
    final rows = _filteredSorted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _toolbar(),
        const SizedBox(height: 12),
        _panel(
          padding: EdgeInsets.zero,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.rLg),
            child: Column(
              children: [
                _headerRow(),
                if (rows.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Tidak ada proses cocok.',
                        style:
                            TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                  )
                else
                  for (var i = 0; i < rows.length; i++)
                    _dataRow(rows[i], alt: i.isOdd),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text('Menampilkan ${rows.length} dari ${widget.procs.length} proses',
            style: TextStyle(color: AppTheme.textFaint, fontSize: 11)),
      ],
    );
  }

  Widget _toolbar() {
    return Row(
      children: [
        SizedBox(
          width: 240,
          child: SearchField(
            hint: 'Cari nama / user / PID…',
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        const SizedBox(width: 14),
        Text('Urutkan:',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
        const SizedBox(width: 8),
        FilterTab(
            label: 'CPU',
            active: _key == _ProcSort.cpu,
            onTap: () => _sortBy(_ProcSort.cpu)),
        const SizedBox(width: 6),
        FilterTab(
            label: 'Memory',
            active: _key == _ProcSort.mem,
            onTap: () => _sortBy(_ProcSort.mem)),
        const Spacer(),
        GestureDetector(
          onTap: () => setState(() => _desc = !_desc),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.rSm),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                    _desc
                        ? Icons.arrow_downward_rounded
                        : Icons.arrow_upward_rounded,
                    size: 13,
                    color: AppTheme.textMuted),
                const SizedBox(width: 5),
                Text(_desc ? 'Tertinggi' : 'Terendah',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
              ],
            ),
          ),
        ),
      ],
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
                Icon(
                    _desc
                        ? Icons.arrow_drop_down
                        : Icons.arrow_drop_up,
                    size: 14,
                    color: AppTheme.accent),
            ],
          ),
        ),
      );
    }

    final headStyle = TextStyle(
      color: AppTheme.textFaint,
      fontSize: 11,
      fontFamily: 'Menlo',
      fontWeight: FontWeight.w700,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppTheme.surfaceInput,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          SizedBox(width: 52, child: Text('PID', style: headStyle)),
          SizedBox(width: 92, child: Text('USER', style: headStyle)),
          sortableHeader('CPU%', _ProcSort.cpu, 54),
          sortableHeader('MEM%', _ProcSort.mem, 54),
          Expanded(child: Text('COMMAND', style: headStyle)),
          const SizedBox(width: 32),
        ],
      ),
    );
  }

  Widget _dataRow(ProcessInfo p, {required bool alt}) {
    final base = TextStyle(
        color: AppTheme.textPrimary, fontSize: 12.5, fontFamily: 'Menlo');
    Color heat(double v) => v >= 50
        ? AppTheme.danger
        : v >= 15
            ? AppTheme.warning
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
        color: _hover
            ? AppTheme.surfaceInput
            : (widget.alt
                ? AppTheme.surfaceInput.withValues(alpha: 0.4)
                : Colors.transparent),
        child: Row(
          children: [
            Expanded(child: widget.child),
            SizedBox(
              width: 32,
              child: _hover
                  ? IconButton(
                      icon: Icon(Icons.stop_circle_outlined,
                          size: 16, color: AppTheme.danger),
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
