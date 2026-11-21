import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_term/src/features/services/service_service.dart';

void main() {
  group('parseServicesOutput', () {
    test('parse unit + status enable, urut gagal dulu', () {
      const out = '''
@@HAS
yes
@@UNITS
nginx.service loaded active running A high performance web server
cron.service loaded active running Regular background program processing daemon
bad.service loaded failed failed Some Broken Service
@@FILES
nginx.service enabled enabled
cron.service enabled enabled
bad.service disabled disabled
ssh.service static -
@@END
''';
      final snap = parseServicesOutput(out);
      expect(snap.error, isNull);
      // 3 dari UNITS + 1 stub (ssh) dari FILES
      expect(snap.services, hasLength(4));

      // gagal harus pertama
      final first = snap.services.first;
      expect(first.unit, 'bad.service');
      expect(first.isFailed, isTrue);

      final nginx =
          snap.services.firstWhere((s) => s.unit == 'nginx.service');
      expect(nginx.isRunning, isTrue);
      expect(nginx.isEnabled, isTrue);
      expect(nginx.description, 'A high performance web server');
      expect(nginx.name, 'nginx');

      final ssh = snap.services.firstWhere((s) => s.unit == 'ssh.service');
      expect(ssh.isRunning, isFalse);
      expect(ssh.enabledState, 'static');
      expect(ssh.canToggleEnable, isFalse);
    });

    test('deteksi bukan sistem systemd', () {
      const out = '@@HAS\nno\n@@UNITS\n@@FILES\n@@END\n';
      final snap = parseServicesOutput(out);
      expect(snap.services, isEmpty);
      expect(snap.error, isNotNull);
      expect(snap.error!.toLowerCase(), contains('systemd'));
    });

    test('akses ditolak saat daftar kosong', () {
      const out =
          '@@HAS\nyes\n@@UNITS\nFailed to list units: Access denied\n@@FILES\n@@END\n';
      final snap = parseServicesOutput(out);
      expect(snap.services, isEmpty);
      expect(snap.error, isNotNull);
      expect(snap.error!.toLowerCase(), contains('akses'));
    });
  });
}
