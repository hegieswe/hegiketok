import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_term/src/ssh/known_hosts.dart';

void main() {
  group('classifyHostKey', () {
    final known = KnownHost(
      hostPort: '10.0.0.1:22',
      type: 'ssh-ed25519',
      fingerprint: 'SHA256:AAAA',
      firstSeen: DateTime(2026, 1, 1),
    );

    test('host belum dikenal → fresh', () {
      expect(classifyHostKey(null, 'SHA256:AAAA'), HostKeyStatus.fresh);
    });

    test('fingerprint sama → match', () {
      expect(classifyHostKey(known, 'SHA256:AAAA'), HostKeyStatus.match);
    });

    test('fingerprint beda → changed', () {
      expect(classifyHostKey(known, 'SHA256:BBBB'), HostKeyStatus.changed);
    });
  });

  group('KnownHost JSON', () {
    test('round-trip menjaga semua field', () {
      final kh = KnownHost(
        hostPort: 'host:2222',
        type: 'rsa-sha2-512',
        fingerprint: 'SHA256:ZZZ',
        firstSeen: DateTime(2026, 11, 22, 10, 30),
      );
      final back = KnownHost.fromJson(kh.toJson());
      expect(back.hostPort, kh.hostPort);
      expect(back.type, kh.type);
      expect(back.fingerprint, kh.fingerprint);
      expect(back.firstSeen, kh.firstSeen);
    });
  });

  group('KnownHostsStore', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('known_hosts_test');
    });

    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('lookup kosong → null', () async {
      final store = KnownHostsStore(directory: dir);
      expect(await store.lookup('a:22'), isNull);
    });

    test('trust lalu lookup mengembalikan entri', () async {
      final store = KnownHostsStore(directory: dir);
      await store.trust(KnownHost(
        hostPort: 'a:22',
        type: 'ssh-ed25519',
        fingerprint: 'SHA256:AAAA',
        firstSeen: DateTime(2026, 1, 1),
      ));
      final got = await store.lookup('a:22');
      expect(got, isNotNull);
      expect(got!.fingerprint, 'SHA256:AAAA');
    });

    test('persisten lintas instance (dibaca dari file)', () async {
      final store1 = KnownHostsStore(directory: dir);
      await store1.trust(KnownHost(
        hostPort: 'b:22',
        type: 'ssh-ed25519',
        fingerprint: 'SHA256:BBBB',
        firstSeen: DateTime(2026, 2, 2),
      ));
      final store2 = KnownHostsStore(directory: dir);
      final got = await store2.lookup('b:22');
      expect(got?.fingerprint, 'SHA256:BBBB');
    });

    test('trust ulang meng-upsert (server dibangun ulang)', () async {
      final store = KnownHostsStore(directory: dir);
      await store.trust(KnownHost(
        hostPort: 'c:22',
        type: 'ssh-ed25519',
        fingerprint: 'SHA256:OLD',
        firstSeen: DateTime(2026, 1, 1),
      ));
      await store.trust(KnownHost(
        hostPort: 'c:22',
        type: 'ssh-ed25519',
        fingerprint: 'SHA256:NEW',
        firstSeen: DateTime(2026, 1, 1),
      ));
      final got = await store.lookup('c:22');
      expect(got?.fingerprint, 'SHA256:NEW');
      expect((await store.all()).length, 1);
    });

    test('forget menghapus entri', () async {
      final store = KnownHostsStore(directory: dir);
      await store.trust(KnownHost(
        hostPort: 'd:22',
        type: 'ssh-ed25519',
        fingerprint: 'SHA256:DDDD',
        firstSeen: DateTime(2026, 1, 1),
      ));
      await store.forget('d:22');
      expect(await store.lookup('d:22'), isNull);
    });
  });
}
