import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_term/src/models/ssh_credentials.dart';
import 'package:nexus_term/src/ssh/ssh_errors.dart';

const _pw = SshCredentials(
    host: 'srv.test', port: 2200, username: 'deploy', password: 'x');
const _key = SshCredentials(
    host: 'srv.test', username: 'deploy', privateKey: 'KEY');

void main() {
  group('describeSshError', () {
    test('login ditolak menyebut username yang BENAR-BENAR dipakai', () {
      final f = describeSshError(
        Exception('SSHAuthFailError(All authentication methods failed)'),
        credentials: const SshCredentials(
            host: 'h', username: 'deploy!Rahasia1', password: 'x'),
      );
      expect(f.kind, SshFailureKind.auth);
      expect(f.message, 'Login ditolak untuk user "deploy!Rahasia1".');
      expect(f.hint, contains('username dan password'));
      expect(f.fixableByEditingHost, isTrue);
      // Tidak membocorkan nama kelas teknis.
      expect(f.full, isNot(contains('SSHAuthFailError')));
    });

    test('login key: saran menyebut public key di server', () {
      final f = describeSshError(Exception('SSHAuthFailError'),
          credentials: _key);
      expect(f.hint, contains('public key'));
    });

    test('tanpa kredensial tetap menghasilkan pesan yang utuh', () {
      final f = describeSshError(Exception('SSHAuthFailError'));
      expect(f.message, 'Login ditolak.');
    });

    test('server memutus sebelum login (blokir sementara) ≠ password salah',
        () {
      // Teks galat asli dartssh2 saat OpenSSH menjatuhkan penalti ke alamat
      // yang berkali-kali gagal login.
      final f = describeSshError(
          Exception('SSHAuthAbortError(Connection closed before authentication)'),
          credentials: _pw);
      expect(f.kind, SshFailureKind.serverClosed);
      expect(f.full, isNot(contains('Login ditolak')));
      expect(f.hint, contains('Tunggu'));
      // Mengedit host tidak akan membantu.
      expect(f.fixableByEditingHost, isFalse);
    });

    test('koneksi ditolak menyebut alamat & port', () {
      final f = describeSshError(
          Exception('SocketException: Connection refused (errno = 61)'),
          credentials: _pw);
      expect(f.kind, SshFailureKind.refused);
      expect(f.message, contains('srv.test:2200'));
      expect(f.fixableByEditingHost, isTrue);
    });

    test('timeout', () {
      final f = describeSshError(TimeoutException('Connection timed out'),
          credentials: _pw);
      expect(f.kind, SshFailureKind.timeout);
      expect(f.hint, contains('VPN'));
      // Mengedit host belum tentu membantu → tombol Edit tidak ditonjolkan.
      expect(f.fixableByEditingHost, isFalse);
    });

    test('host tidak ditemukan menyebut nama host', () {
      final f = describeSshError(
          Exception("SocketException: Failed host lookup: 'srv.test'"),
          credentials: _pw);
      expect(f.kind, SshFailureKind.hostNotFound);
      expect(f.message, contains('"srv.test"'));
    });

    test('host key ditolak', () {
      expect(
          describeSshError(Exception('SSHHostkeyError: Hostkey verification failed'))
              .kind,
          SshFailureKind.hostKey);
    });

    test('private key / passphrase bermasalah', () {
      expect(
          describeSshError(Exception('Invalid passphrase'), credentials: _key)
              .kind,
          SshFailureKind.badKey);
      expect(
          describeSshError(const FormatException('bad'), credentials: _key)
              .kind,
          SshFailureKind.badKey);
      // FormatException tanpa key bukan masalah key.
      expect(
          describeSshError(const FormatException('bad'), credentials: _pw).kind,
          SshFailureKind.other);
    });

    test('jaringan terputus', () {
      expect(describeSshError(Exception('Network is unreachable')).kind,
          SshFailureKind.network);
    });

    test('galat lain dipotong agar tidak membanjiri layar', () {
      final f = describeSshError(Exception('x' * 500));
      expect(f.kind, SshFailureKind.other);
      expect(f.message.length, lessThan(200));
    });
  });

  group('usernameWarning', () {
    test('username wajar → tanpa peringatan', () {
      for (final u in [
        'root', 'deploy', 'ec2-user', 'user.name', 'user_1', 'www-data',
        r'CORP\alice', 'alice@corp.example', r'machine$', '  root  ', '',
      ]) {
        expect(usernameWarning(u), isNull, reason: '"$u"');
      }
    });

    test('password yang ikut terketik di username terdeteksi', () {
      final w = usernameWarning('deploy!Rahasia1');
      expect(w, isNotNull);
      expect(w, contains('!'));
      expect(w, contains('password'));
    });

    test('spasi & karakter aneh lain', () {
      expect(usernameWarning('my user'), contains('spasi'));
      expect(usernameWarning('user#1'), contains('#'));
      expect(usernameWarning('user;rm'), isNotNull);
    });

    test('sangat panjang', () {
      expect(usernameWarning('a' * 40), contains('panjang'));
    });
  });

  group('hostAddressWarning', () {
    test('alamat wajar → tanpa peringatan', () {
      for (final h in [
        '192.168.1.10', 'srv.example.com', 'localhost', 'fe80::1', '::1', '',
      ]) {
        expect(hostAddressWarning(h), isNull, reason: '"$h"');
      }
    });

    test('user@host, skema, port tertempel, spasi', () {
      expect(hostAddressWarning('root@10.0.0.1'), contains('Username'));
      expect(hostAddressWarning('ssh://srv.test'), contains('awalan'));
      expect(hostAddressWarning('srv.test:2222'), contains('Port'));
      expect(hostAddressWarning('srv test'), contains('spasi'));
    });
  });
}
