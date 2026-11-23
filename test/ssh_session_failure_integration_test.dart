// Integrasi NYATA: kegagalan koneksi pertama pada SshTerminalSession, tombol
// "Coba lagi", dan sesi yang berhasil — terhadap container `nexus-ssh-test`.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_term/src/features/ssh/ssh_terminal_session.dart';
import 'package:nexus_term/src/models/ssh_credentials.dart';
import 'package:nexus_term/src/ssh/known_hosts.dart';
import 'package:nexus_term/src/ssh/ssh_connector.dart';
import 'package:nexus_term/src/ssh/ssh_errors.dart';

import 'support/test_server.dart';

Future<void> _until(bool Function() cond, String what, {int seconds = 12}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (!cond()) {
    if (DateTime.now().isAfter(end)) fail('timeout menunggu: $what');
    await Future<void>.delayed(const Duration(milliseconds: 80));
  }
}

Future<void> main() async {
  final skip = await integrationSkipReason();

  late Directory tmp;
  late KnownHostsStore store;
  var attempts = 0;

  // OpenSSH memblokir sementara alamat yang gagal login ±4 kali beruntun,
  // dan itu akan merusak tes integrasi lain. Jadi penolakan di berkas ini
  // disimulasikan dengan galat yang sama persis seperti yang dilempar
  // pustaka SSH; yang nyata di sini adalah jalur BERHASIL.
  var simulateRejections = 0;

  SshTerminalSession session(String user, String password) =>
      SshTerminalSession(
        SshCredentials(
            host: '127.0.0.1', port: 2222, username: user, password: password),
        connect: (c, progress) {
          attempts++;
          if (simulateRejections > 0) {
            simulateRejections--;
            final step = progress.begin('Autentikasi ${c.username}@${c.host}');
            final e =
                Exception('SSHAuthFailError(All authentication methods failed)');
            progress.fail(step, describeSshError(e, credentials: c).message);
            throw e;
          }
          return connectSsh(c,
              progress: progress,
              knownHosts: store,
              verifyHostKey: (_) async => true);
        },
      );

  setUpAll(() async {
    if (skip != null) return;
    tmp = await Directory.systemTemp.createTemp('hegi_session_it_');
    store = KnownHostsStore(directory: tmp);
  });
  tearDownAll(() async {
    if (skip != null) return;
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });
  setUp(() {
    attempts = 0;
    simulateRejections = 0;
  });

  test('login ditolak → failure terisi, offline, TIDAK mencoba berulang',
      () async {
    // Penolakan disimulasikan (lihat catatan di atas); penolakan oleh server
    // sungguhan diuji sekali di connection_test_test.dart.
    simulateRejections = 1;
    final s = session('nexus', 'salah')..start();
    addTearDown(s.dispose);
    await _until(() => s.failure.value != null, 'failure');

    final f = s.failure.value!;
    expect(f.kind, SshFailureKind.auth);
    expect(f.message, 'Login ditolak untuk user "nexus".');
    expect(s.connected.value, isFalse);
    expect(s.terminal.buffer.getText(), contains('Login ditolak'));

    // Tidak ada percobaan otomatis (mencegah akun/alamat diblokir).
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(attempts, 1);
  }, skip: skip);

  test('"Coba lagi": sekali per klik; berhasil begitu masalahnya hilang',
      () async {
    simulateRejections = 2;
    final s = session('nexus', 'nexus123')..start();
    addTearDown(s.dispose);
    await _until(() => s.failure.value != null, 'failure pertama');
    expect(attempts, 1);

    // Klik ganda tidak menjalankan dua percobaan paralel.
    s.retry();
    s.retry();
    expect(s.failure.value, isNull, reason: 'banner hilang selama mencoba');
    await _until(() => s.failure.value != null, 'failure kedua');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(attempts, 2);

    // Percobaan berikutnya sampai ke server sungguhan dan berhasil.
    s.retry();
    await _until(
        () => s.connected.value || s.failure.value != null, 'hasil retry');
    expect(s.connected.value, isTrue, reason: 'gagal: ${s.failure.value}');
    expect(s.failure.value, isNull);
    expect(attempts, 3);

    s.sendCommand('echo SESI_\$((20+3))');
    await _until(() => s.terminal.buffer.getText().contains('SESI_23'),
        'keluaran perintah');
  }, skip: skip);
}
