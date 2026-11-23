import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_term/src/features/hosts/host_os.dart';
import 'package:nexus_term/src/models/ssh_host.dart';

SshHost h({String label = '', String host = '', HostOs os = HostOs.auto}) =>
    SshHost(id: '1', label: label, host: host, username: 'u', os: os);

void main() {
  group('resolveHostOs', () {
    test('menghormati pilihan eksplisit (bukan auto)', () {
      expect(resolveHostOs(h(label: 'ubuntu box', os: HostOs.windows)),
          HostOs.windows);
    });

    test('auto menebak dari label/host', () {
      expect(resolveHostOs(h(label: 'Ubuntu Prod')), HostOs.ubuntu);
      expect(resolveHostOs(h(label: 'db', host: 'debian-01')), HostOs.debian);
      expect(resolveHostOs(h(label: 'My Mac', host: 'darwin')), HostOs.macos);
      expect(resolveHostOs(h(label: 'winserver')), HostOs.windows);
      expect(resolveHostOs(h(label: 'raspberry pi 4')), HostOs.raspberryPi);
      expect(resolveHostOs(h(label: 'freebsd gw')), HostOs.freebsd);
    });

    test('default ke linux bila tak dikenali', () {
      expect(resolveHostOs(h(label: 'myserver', host: '10.0.0.1')),
          HostOs.linux);
    });

    test('setiap OS punya ikon & warna', () {
      for (final o in HostOs.values) {
        expect(o.label, isNotEmpty);
        expect(o.icon, isNotNull);
        expect(o.color, isNotNull);
      }
    });
  });

  group('SshHost.os JSON', () {
    test('round-trip menyimpan os', () {
      final host = h(label: 'x', os: HostOs.alpine);
      final back = SshHost.fromJson(host.toJson());
      expect(back.os, HostOs.alpine);
    });

    test('JSON lama tanpa os → auto (backward-compat)', () {
      final json = {
        'id': '1',
        'label': 'old',
        'host': 'h',
        'port': 22,
        'username': 'u',
        'authMethod': 'password',
      };
      expect(SshHost.fromJson(json).os, HostOs.auto);
    });
  });
}
