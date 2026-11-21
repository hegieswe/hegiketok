import 'dart:convert';
import 'dart:math' as math;

import 'package:dartssh2/dartssh2.dart';

import 'server_info.dart';

/// Satu perintah gabungan yang mengeluarkan semua metrik dengan penanda @@.
/// Mengambil dua sampel /proc/stat (jeda 1 dtk) untuk menghitung %CPU per-core.
const _collectScript = r'''
export LANG=C
echo '@@HOST'; hostname 2>/dev/null
echo '@@OS'; (. /etc/os-release 2>/dev/null; printf '%s\n' "$PRETTY_NAME")
echo '@@KERNEL'; uname -sr 2>/dev/null
echo '@@UPTIMEP'; uptime -p 2>/dev/null
echo '@@UPTIMES'; cut -d' ' -f1 /proc/uptime 2>/dev/null
echo '@@CORES'; nproc 2>/dev/null
echo '@@CPUMODEL'; grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed 's/^ *//'
echo '@@LOAD'; cut -d' ' -f1-3 /proc/loadavg 2>/dev/null
echo '@@TEMP'; cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | sort -rn | head -1
echo '@@CPU1'; grep '^cpu' /proc/stat 2>/dev/null
sleep 1
echo '@@CPU2'; grep '^cpu' /proc/stat 2>/dev/null
echo '@@MEM'; grep -E 'MemTotal|MemFree|MemAvailable|Buffers|Cached|SReclaimable|SwapTotal|SwapFree' /proc/meminfo 2>/dev/null
echo '@@DISK'; df -P -k 2>/dev/null | tail -n +2
echo '@@NET'; ip -o -4 addr show 2>/dev/null | awk '{print $2"="$4}'
echo '@@USERS'; who 2>/dev/null | wc -l
echo '@@PROCS'; ps -e 2>/dev/null | wc -l
echo '@@PROCLIST'; ps -eo pid,user,pcpu,pmem,comm --sort=-pcpu 2>/dev/null | head -n 101
echo '@@END'
''';

/// Kumpulkan informasi sistem dari server lewat [client].
Future<ServerInfo> collectServerInfo(SSHClient client) async {
  final out = await client.run(_collectScript);
  final text = utf8.decode(out, allowMalformed: true);

  final sections = <String, List<String>>{};
  var cur = '';
  for (final line in const LineSplitter().convert(text)) {
    if (line.startsWith('@@')) {
      cur = line.substring(2);
      sections.putIfAbsent(cur, () => []);
    } else {
      (sections[cur] ??= []).add(line);
    }
  }

  List<String> sec(String k) => sections[k] ?? const [];
  String first(String k) {
    for (final l in sec(k)) {
      if (l.trim().isNotEmpty) return l.trim();
    }
    return '';
  }

  int toInt(String s) => int.tryParse(s.trim()) ?? 0;

  // Load average
  final load = first('LOAD')
      .split(RegExp(r'\s+'))
      .where((s) => s.isNotEmpty)
      .map((s) => double.tryParse(s) ?? 0.0)
      .toList();

  // --- CPU: parse semua baris cpu / cpuN dari dua sampel ---
  Map<String, List<int>> cpuMap(List<String> lines) {
    final m = <String, List<int>>{};
    for (final l in lines) {
      final p = l.trim().split(RegExp(r'\s+'));
      if (p.isEmpty || !p[0].startsWith('cpu')) continue;
      m[p[0]] = p.skip(1).map((s) => int.tryParse(s) ?? 0).toList();
    }
    return m;
  }

  double usageDelta(List<int> a, List<int> b) {
    if (a.length < 5 || b.length < 5) return 0;
    int sum(List<int> x) => x.fold(0, (p, e) => p + e);
    final idleA = a[3] + a[4], idleB = b[3] + b[4];
    final totD = sum(b) - sum(a), idleD = idleB - idleA;
    if (totD <= 0) return 0;
    return (100 * (totD - idleD) / totD).clamp(0, 100).toDouble();
  }

  final c1 = cpuMap(sec('CPU1'));
  final c2 = cpuMap(sec('CPU2'));

  double cpuUsage = 0;
  var breakdown = const CpuBreakdown();
  final a = c1['cpu'], b = c2['cpu'];
  if (a != null && b != null) {
    cpuUsage = usageDelta(a, b);
    try {
      final d = List.generate(
          math.max(a.length, b.length),
          (i) =>
              (i < b.length ? b[i] : 0) - (i < a.length ? a[i] : 0));
      final tot = d.fold(0, (p, e) => p + e);
      double pct(int v) => tot > 0 ? (v / tot * 100) : 0;
      double at(int i) => i < d.length ? d[i].toDouble() : 0;
      breakdown = CpuBreakdown(
        user: pct(at(0).toInt()),
        nice: pct(at(1).toInt()),
        system: pct((at(2) + at(5) + at(6)).toInt()),
        idle: pct(at(3).toInt()),
        iowait: pct(at(4).toInt()),
        steal: pct(at(7).toInt()),
      );
    } catch (_) {}
  }

  // Per-core (cpu0, cpu1, ...) terurut
  final perCore = <double>[];
  final coreKeys = c1.keys
      .where((k) => RegExp(r'^cpu\d+$').hasMatch(k))
      .toList()
    ..sort((x, y) => int.parse(x.substring(3)).compareTo(int.parse(y.substring(3))));
  for (final k in coreKeys) {
    final x = c1[k], y = c2[k];
    if (x != null && y != null) perCore.add(usageDelta(x, y));
  }

  // Suhu (milli-degree -> Celsius)
  double? temp;
  final tRaw = first('TEMP');
  if (tRaw.isNotEmpty) {
    final v = int.tryParse(tRaw);
    if (v != null && v > 0) temp = v > 1000 ? v / 1000.0 : v.toDouble();
  }

  // --- Memory ---
  final mem = <String, int>{};
  for (final l in sec('MEM')) {
    final m = RegExp(r'(\w+):\s+(\d+)').firstMatch(l);
    if (m != null) mem[m.group(1)!] = int.parse(m.group(2)!);
  }
  final memTotal = mem['MemTotal'] ?? 0;
  final memFree = mem['MemFree'] ?? 0;
  final cache =
      (mem['Cached'] ?? 0) + (mem['Buffers'] ?? 0) + (mem['SReclaimable'] ?? 0);
  final memUsed = (memTotal - memFree - cache).clamp(0, memTotal);
  final swapTotal = mem['SwapTotal'] ?? 0;
  final swapFree = mem['SwapFree'] ?? 0;
  final swapUsed = (swapTotal - swapFree).clamp(0, swapTotal);

  // --- Disk ---
  final disks = <DiskInfo>[];
  final skip = RegExp(r'tmpfs|devtmpfs|overlay|udev|loop|squashfs|^none$');
  for (final l in sec('DISK')) {
    final p = l.trim().split(RegExp(r'\s+'));
    if (p.length < 6) continue;
    if (skip.hasMatch(p[0])) continue;
    disks.add(DiskInfo(
      filesystem: p[0],
      sizeKb: toInt(p[1]),
      usedKb: toInt(p[2]),
      availKb: toInt(p[3]),
      usePercent: toInt(p[4].replaceAll('%', '')),
      mount: p.sublist(5).join(' '),
    ));
  }

  // --- Network ---
  final nets = <NetInterface>[];
  for (final l in sec('NET')) {
    final i = l.indexOf('=');
    if (i < 0) continue;
    final name = l.substring(0, i).trim();
    final addr = l.substring(i + 1).trim();
    if (name == 'lo' || addr.isEmpty) continue;
    nets.add(NetInterface(name, addr));
  }

  // --- Uptime ---
  var uptime = first('UPTIMEP').replaceFirst(RegExp(r'^up '), '');
  if (uptime.isEmpty) {
    final secs = double.tryParse(first('UPTIMES')) ?? 0;
    uptime = _formatUptime(secs.toInt());
  }

  final procs = (toInt(first('PROCS')) - 1).clamp(0, 1 << 30);

  // --- Top processes ---
  final topProcs = <ProcessInfo>[];
  for (final l in sec('PROCLIST')) {
    final line = l.trim();
    if (line.isEmpty || line.startsWith('PID')) continue;
    final p = line.split(RegExp(r'\s+'));
    if (p.length < 5) continue;
    topProcs.add(ProcessInfo(
      pid: int.tryParse(p[0]) ?? 0,
      user: p[1],
      cpu: double.tryParse(p[2]) ?? 0,
      mem: double.tryParse(p[3]) ?? 0,
      command: p.sublist(4).join(' '),
    ));
  }

  return ServerInfo(
    hostname: first('HOST'),
    os: first('OS'),
    kernel: first('KERNEL'),
    uptime: uptime,
    cpuModel: first('CPUMODEL'),
    cpuCores: toInt(first('CORES')),
    loadAvg: load,
    cpuUsage: cpuUsage,
    perCore: perCore,
    cpuBreakdown: breakdown,
    cpuTemp: temp,
    memTotalKb: memTotal,
    memUsedKb: memUsed,
    memCacheKb: cache,
    memFreeKb: memFree,
    swapTotalKb: swapTotal,
    swapUsedKb: swapUsed,
    disks: disks,
    networks: nets,
    usersLoggedIn: toInt(first('USERS')),
    processes: procs,
    topProcesses: topProcs,
    collectedAt: DateTime.now(),
  );
}

String _formatUptime(int seconds) {
  final d = seconds ~/ 86400;
  final h = (seconds % 86400) ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final parts = <String>[];
  if (d > 0) parts.add('$d hari');
  if (h > 0) parts.add('$h jam');
  if (m > 0 || parts.isEmpty) parts.add('$m menit');
  return parts.join(' ');
}
