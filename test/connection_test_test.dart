// "Tes koneksi": unit (konektor tiruan) + integrasi nyata ke container uji
// `nexus-ssh-test` (dilewati bila tidak berjalan).
//
// Catatan: OpenSSH memblokir sementara alamat yang gagal login ±4 kali
// berturut-turut. Karena itu hanya SATU tes di berkas ini yang benar-benar
// gagal login ke server; kasus gagal lainnya memakai konektor tiruan.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_term/src/models/ssh_credentials.dart';
import 'package:nexus_term/src/ssh/connection_test.dart';
import 'package:nexus_term/src/ssh/known_hosts.dart';
import 'package:nexus_term/src/ssh/ssh_connector.dart';
import 'package:nexus_term/src/ssh/ssh_errors.dart';

import 'support/test_server.dart';

const _good = SshCredentials(
    host: '127.0.0.1', port: 2222, username: 'nexus', password: 'nexus123');

Future<void> main() async {
  final skip = await integrationSkipReason();

  group('unit', () {
    test('galat konektor dikembalikan sebagai hasil, tidak dilempar', () async {
      final r = await testSshConnection(_good,
          connect: (_) async => throw Exception('SSHAuthFailError'));
      expect(r.ok, isFalse);
      expect(r.failure!.kind, SshFailureKind.auth);
      expect(r.failure!.message, contains('"nexus"'));
    });

    test('password terketik di username → pesan menunjukkan username itu',
        () async {
      final r = await testSshConnection(
        const SshCredentials(
            host: 'h', username: 'deploy!Rahasia1', password: 'Rahasia1'),
        connect: (_) async =>
            throw Exception('SSHAuthFailError(All authentication methods failed)'),
      );
      expect(r.failure!.message, contains('"deploy!Rahasia1"'));
    });

    test('konektor yang menggantung → timeout, bukan menunggu selamanya',
        () async {
      final r = await testSshConnection(
        _good,
        connect: (_) => Completer<SshConnection>().future,
        timeout: const Duration(milliseconds: 150),
      );
      expect(r.ok, isFalse);
      expect(r.failure!.kind, SshFailureKind.timeout);
    });
  });

  group('integrasi', () {
    late Directory tmp;
    late SshConnect connect;

    setUpAll(() async {
      if (skip != null) return;
      tmp = await Directory.systemTemp.createTemp('hegi_conntest_');
      final store = KnownHostsStore(directory: tmp);
      connect = (c) =>
          connectSsh(c, knownHosts: store, verifyHostKey: (_) async => true);
    });
    tearDownAll(() async {
      if (skip != null) return;
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('kredensial benar → berhasil + info sistem server', () async {
      final r = await testSshConnection(_good, connect: connect);
      expect(r.ok, isTrue, reason: '${r.failure}');
      expect(r.detail, startsWith('Linux'));
    }, skip: skip);

    test('password salah → login ditolak, menyebut username', () async {
      final r = await testSshConnection(
        const SshCredentials(
            host: '127.0.0.1', port: 2222, username: 'nexus', password: 'salah'),
        connect: connect,
      );
      expect(r.ok, isFalse);
      expect(r.failure!.kind, SshFailureKind.auth);
      expect(r.failure!.message, 'Login ditolak untuk user "nexus".');
    }, skip: skip);

    test('port salah → koneksi ditolak, menyebut alamat:port', () async {
      final r = await testSshConnection(
        const SshCredentials(
            host: '127.0.0.1', port: 2, username: 'nexus', password: 'x'),
        connect: connect,
      );
      expect(r.ok, isFalse);
      expect(r.failure!.kind, SshFailureKind.refused);
      expect(r.failure!.message, contains('127.0.0.1:2'));
    }, skip: skip);

    test('host key ditolak pengguna → gagal dengan jenis hostKey', () async {
      final dir = await Directory.systemTemp.createTemp('hegi_conntest_hk_');
      addTearDown(() => dir.delete(recursive: true));
      final r = await testSshConnection(
        _good,
        connect: (c) => connectSsh(c,
            knownHosts: KnownHostsStore(directory: dir),
            verifyHostKey: (_) async => false),
      );
      expect(r.ok, isFalse);
      expect(r.failure!.kind, SshFailureKind.hostKey);
      // Regresi: dulu tampil sebagai "Login ditolak" (menyalahkan password).
      expect(r.failure!.full, isNot(contains('Login ditolak')));
    }, skip: skip);

    test('host key BERUBAH lalu ditolak → peringatan yang lebih keras',
        () async {
      final dir = await Directory.systemTemp.createTemp('hegi_conntest_chg_');
      addTearDown(() => dir.delete(recursive: true));
      final store = KnownHostsStore(directory: dir);
      await store.trust(KnownHost(
        hostPort: '127.0.0.1:2222',
        type: 'ssh-ed25519',
        fingerprint: 'SHA256:bukan-key-yang-sebenarnya',
        firstSeen: DateTime(2026),
      ));
      final r = await testSshConnection(
        _good,
        connect: (c) => connectSsh(c,
            knownHosts: store, verifyHostKey: (_) async => false),
      );
      expect(r.failure!.kind, SshFailureKind.hostKey);
      expect(r.failure!.message, contains('BERUBAH'));
    }, skip: skip);
  });
}
