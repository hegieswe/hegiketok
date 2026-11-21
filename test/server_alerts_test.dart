import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_term/src/features/server_info/server_alerts.dart';
import 'package:nexus_term/src/features/server_info/server_info.dart';

ServerInfo _info({
  required double cpuUsage,
  required int memTotalKb,
  required int memUsedKb,
  List<DiskInfo> disks = const [],
}) {
  return ServerInfo(
    hostname: 'h',
    os: 'o',
    kernel: 'k',
    uptime: 'u',
    cpuModel: 'c',
    cpuCores: 4,
    loadAvg: const [0, 0, 0],
    cpuUsage: cpuUsage,
    perCore: const [],
    cpuBreakdown: const CpuBreakdown(),
    cpuTemp: null,
    memTotalKb: memTotalKb,
    memUsedKb: memUsedKb,
    memCacheKb: 0,
    memFreeKb: memTotalKb - memUsedKb,
    swapTotalKb: 0,
    swapUsedKb: 0,
    disks: disks,
    networks: const [],
    usersLoggedIn: 1,
    processes: 100,
    topProcesses: const [],
    collectedAt: DateTime(2026),
  );
}

DiskInfo _disk(String mount, int usePercent) => DiskInfo(
      filesystem: '/dev/x',
      mount: mount,
      sizeKb: 1000,
      usedKb: usePercent * 10,
      availKb: 1000 - usePercent * 10,
      usePercent: usePercent,
    );

void main() {
  group('computeAlerts', () {
    test('tidak ada peringatan saat di bawah ambang', () {
      final a = computeAlerts(
        _info(cpuUsage: 50, memTotalKb: 1000, memUsedKb: 500),
        cpu: 90,
        mem: 90,
        disk: 90,
      );
      expect(a, isEmpty);
    });

    test('CPU & memory melampaui ambang', () {
      final a = computeAlerts(
        _info(cpuUsage: 95, memTotalKb: 1000, memUsedKb: 950),
        cpu: 90,
        mem: 90,
        disk: 90,
      );
      expect(a, hasLength(2));
      expect(a[0].label, 'CPU');
      expect(a[1].label, 'Memory');
    });

    test('disk per-mount dicek, hanya yang lewat ambang', () {
      final a = computeAlerts(
        _info(
          cpuUsage: 10,
          memTotalKb: 1000,
          memUsedKb: 100,
          disks: [_disk('/', 95), _disk('/data', 40)],
        ),
        cpu: 90,
        mem: 90,
        disk: 90,
      );
      expect(a, hasLength(1));
      expect(a.first.label, 'Disk /');
      expect(a.first.message, contains('95%'));
    });

    test('tepat di ambang memicu (>=)', () {
      final a = computeAlerts(
        _info(cpuUsage: 90, memTotalKb: 1000, memUsedKb: 100),
        cpu: 90,
        mem: 90,
        disk: 90,
      );
      expect(a, hasLength(1));
      expect(a.first.label, 'CPU');
    });
  });
}
