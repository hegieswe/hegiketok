import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_term/src/models/ssh_host.dart';

void main() {
  group('SshHost tags', () {
    test('toJson/fromJson menjaga tags', () {
      const host = SshHost(
        id: 'a',
        label: 'web-01',
        host: '192.168.1.10',
        port: 2222,
        username: 'deploy',
        tags: ['web', 'runner', 'dev'],
      );
      final back = SshHost.fromJson(host.toJson());
      expect(back.tags, ['web', 'runner', 'dev']);
      expect(back.port, 2222);
    });

    test('JSON lama tanpa field tags → list kosong (kompatibel mundur)', () {
      final back = SshHost.fromJson({
        'id': 'b',
        'label': 'old',
        'host': 'h',
        'port': 22,
        'username': 'u',
        'authMethod': 'password',
      });
      expect(back.tags, isEmpty);
    });

    test('copyWith mengganti tags, default mempertahankan', () {
      const host = SshHost(
        id: 'c',
        label: 'x',
        host: 'h',
        username: 'u',
        tags: ['a'],
      );
      expect(host.copyWith().tags, ['a']);
      expect(host.copyWith(tags: ['b', 'c']).tags, ['b', 'c']);
    });
  });

  group('SshHost persistentSession (tmux)', () {
    test('default false, toJson/fromJson menjaga nilai', () {
      const host = SshHost(
        id: 'p',
        label: 'prod',
        host: 'h',
        username: 'u',
        persistentSession: true,
      );
      expect(host.persistentSession, isTrue);
      final back = SshHost.fromJson(host.toJson());
      expect(back.persistentSession, isTrue);
    });

    test('JSON lama tanpa field → false (kompatibel mundur)', () {
      final back = SshHost.fromJson({
        'id': 'q',
        'label': 'old',
        'host': 'h',
        'port': 22,
        'username': 'u',
        'authMethod': 'password',
      });
      expect(back.persistentSession, isFalse);
    });

    test('copyWith mengganti & mempertahankan', () {
      const host = SshHost(id: 'r', label: 'x', host: 'h', username: 'u');
      expect(host.copyWith().persistentSession, isFalse);
      expect(host.copyWith(persistentSession: true).persistentSession, isTrue);
    });
  });
}
