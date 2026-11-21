import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_term/src/features/hosts/ssh_config_parser.dart';

void main() {
  group('parseSshConfig', () {
    test('mem-parse blok host dasar', () {
      const config = '''
Host produksi
  HostName 203.0.113.10
  User deploy
  Port 2222
  IdentityFile ~/.ssh/id_ed25519
''';
      final entries = parseSshConfig(config);
      expect(entries, hasLength(1));
      final e = entries.first;
      expect(e.alias, 'produksi');
      expect(e.hostName, '203.0.113.10');
      expect(e.user, 'deploy');
      expect(e.port, 2222);
      expect(e.usesKey, isTrue);
    });

    test('default port 22 & hostName = alias bila tak ada', () {
      const config = 'Host staging\n  User admin\n';
      final e = parseSshConfig(config).single;
      expect(e.port, 22);
      expect(e.hostName, 'staging');
      expect(e.usesKey, isFalse);
    });

    test('melewati entri wildcard', () {
      const config = '''
Host *
  User root
Host web
  HostName example.com
''';
      final entries = parseSshConfig(config);
      expect(entries, hasLength(1));
      expect(entries.first.alias, 'web');
    });

    test('mengabaikan komentar & baris kosong, mendukung key=value', () {
      const config = '''
# komentar
Host db
  HostName=10.0.0.5
  Port=5432
''';
      final e = parseSshConfig(config).single;
      expect(e.hostName, '10.0.0.5');
      expect(e.port, 5432);
    });

    test('mem-parse banyak host', () {
      const config = '''
Host a
  HostName a.com
Host b
  HostName b.com
''';
      final entries = parseSshConfig(config);
      expect(entries.map((e) => e.alias), ['a', 'b']);
    });
  });
}
