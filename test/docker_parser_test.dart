import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_term/src/features/docker/docker_service.dart';

void main() {
  group('parseDockerOutput', () {
    test('mem-parse container + stats + versi', () {
      const out = '''
@@VER
24.0.5
@@PS
{"ID":"abc123def456","Names":"web","Image":"nginx:latest","State":"running","Status":"Up 2 hours","Ports":"0.0.0.0:80->80/tcp"}
{"ID":"def456ghi789","Names":"db","Image":"postgres:15","State":"exited","Status":"Exited (0) 1 hour ago","Ports":""}
@@STATS
{"ID":"abc123def456","CPUPerc":"1.50%","MemUsage":"50MiB / 7.9GiB","MemPerc":"0.62%","NetIO":"1kB / 2kB","BlockIO":"0B / 0B"}
@@END
''';
      final snap = parseDockerOutput(out);
      expect(snap.error, isNull);
      expect(snap.serverVersion, '24.0.5');
      expect(snap.containers, hasLength(2));

      // running harus di urutan pertama
      final first = snap.containers.first;
      expect(first.name, 'web');
      expect(first.isRunning, isTrue);
      expect(first.cpuPerc, 1.5);
      expect(first.memPerc, closeTo(0.62, 0.001));
      expect(first.memUsage, '50MiB / 7.9GiB');

      final db = snap.containers[1];
      expect(db.name, 'db');
      expect(db.isRunning, isFalse);
      expect(db.cpuPerc, isNull); // tidak berjalan → tanpa stats
    });

    test('deteksi Docker tidak terpasang', () {
      const out = '''
@@VER
sh: docker: not found
@@PS
sh: docker: not found
@@STATS
sh: docker: not found
@@END
''';
      final snap = parseDockerOutput(out);
      expect(snap.containers, isEmpty);
      expect(snap.error, isNotNull);
      expect(snap.error!.toLowerCase(), contains('tidak'));
    });

    test('deteksi daemon tidak berjalan', () {
      const out = '''
@@VER
Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?
@@PS
Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?
@@STATS
@@END
''';
      final snap = parseDockerOutput(out);
      expect(snap.containers, isEmpty);
      expect(snap.error, isNotNull);
      expect(snap.error!.toLowerCase(), contains('daemon'));
    });

    test('0 container tanpa error (Docker sehat, kosong)', () {
      const out = '@@VER\n24.0.5\n@@PS\n@@STATS\n@@END\n';
      final snap = parseDockerOutput(out);
      expect(snap.containers, isEmpty);
      expect(snap.error, isNull);
      expect(snap.serverVersion, '24.0.5');
    });
  });
}
