import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_term/src/features/cron/cron_service.dart';

void main() {
  group('parseCron', () {
    test('parse job + env + komentar + job nonaktif', () {
      const out = '''
SHELL=/bin/bash
PATH=/usr/bin:/bin
# Ini komentar biasa
*/5 * * * * /usr/bin/backup.sh
0 2 * * * /usr/bin/cleanup
# 30 4 * * * /usr/bin/disabled.sh
@reboot /opt/startup.sh
''';
      final snap = parseCron(out);
      expect(snap.error, isNull);
      expect(snap.lines, hasLength(7)); // env + komentar dipertahankan
      expect(snap.jobs, hasLength(4));

      final first = snap.jobs.first;
      expect(first.schedule, '*/5 * * * *');
      expect(first.command, '/usr/bin/backup.sh');
      expect(first.enabled, isTrue);

      final disabled = snap.jobs.firstWhere((j) => !j.enabled);
      expect(disabled.command, '/usr/bin/disabled.sh');
      expect(disabled.lineIndex, 5);

      expect(snap.jobs.any((j) => j.schedule == '@reboot'), isTrue);
    });

    test('tidak ada crontab → kosong tanpa error', () {
      final snap = parseCron('no crontab for nexus\n');
      expect(snap.jobs, isEmpty);
      expect(snap.lines, isEmpty);
      expect(snap.error, isNull);
    });

    test('akses ditolak → error', () {
      final snap = parseCron('crontab: you are not allowed to use this program\n');
      expect(snap.error, isNotNull);
    });
  });

  group('splitCronLine', () {
    test('special @reboot', () {
      expect(splitCronLine('@reboot /opt/x'), ['@reboot', '/opt/x']);
    });
    test('5 kolom', () {
      expect(splitCronLine('*/5 * * * * echo hi'), ['*/5 * * * *', 'echo hi']);
    });
    test('tidak valid', () {
      expect(splitCronLine('cuma teks biasa'), isNull);
    });
  });

  group('describeCron', () {
    test('pola umum', () {
      expect(describeCron('* * * * *'), 'Tiap menit');
      expect(describeCron('*/5 * * * *'), 'Tiap 5 menit');
      expect(describeCron('0 * * * *'), 'Tiap jam pada menit ke-0');
      expect(describeCron('0 2 * * *'), 'Tiap hari pukul 02:00');
      expect(describeCron('@reboot'), 'Saat server boot');
    });
  });
}
