import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_term/src/features/users/user_service.dart';

void main() {
  group('parseUsers', () {
    test('parse passwd + who + grup sudo', () {
      const out = '''
@@PASSWD
root:x:0:0:root:/root:/bin/bash
daemon:x:1:1:daemon:/usr/sbin:/usr/sbin/nologin
nexus:x:1000:1000:Nexus User,,,:/home/nexus:/bin/bash
deploy:x:1001:1001::/home/deploy:/bin/bash
@@WHO
nexus pts/0 2026-11-21 10:00
@@SUDO
sudo:x:27:nexus,deploy
@@END
''';
      final snap = parseUsers(out);
      expect(snap.error, isNull);
      expect(snap.users, hasLength(4));

      // urutan: root → manusia (uid asc) → sistem
      expect(snap.users.first.name, 'root');
      expect(snap.users.first.isRoot, isTrue);
      expect(snap.users.last.name, 'daemon'); // sistem terakhir

      final nexus = snap.users.firstWhere((u) => u.name == 'nexus');
      expect(nexus.gecos, 'Nexus User');
      expect(nexus.loggedIn, isTrue);
      expect(nexus.isSudoer, isTrue);
      expect(nexus.canLogin, isTrue);

      final deploy = snap.users.firstWhere((u) => u.name == 'deploy');
      expect(deploy.isSudoer, isTrue);
      expect(deploy.loggedIn, isFalse);

      final daemon = snap.users.firstWhere((u) => u.name == 'daemon');
      expect(daemon.isSystem, isTrue);
      expect(daemon.canLogin, isFalse);
    });

    test('akses ditolak → error', () {
      const out = '@@PASSWD\nPermission denied\n@@WHO\n@@SUDO\n@@END\n';
      final snap = parseUsers(out);
      expect(snap.users, isEmpty);
      expect(snap.error, isNotNull);
    });
  });
}
