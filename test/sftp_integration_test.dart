// Tes integrasi SSH/SFTP NYATA terhadap server uji coba Docker.
//
// Membutuhkan container `nexus-ssh-test` berjalan di 127.0.0.1:2222
// (user: nexus / pass: nexus123). Jika server tidak terjangkau, seluruh
// grup di-skip agar tidak menggagalkan CI tanpa container.
//
// Menguji JALUR INTI yang sama dengan yang dipakai aplikasi (dartssh2):
// eksekusi perintah SSH, serta operasi SFTP lengkap (list, mkdir, tulis,
// baca/verifikasi, rename, hapus).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';

const _host = '127.0.0.1';
const _port = 2222;
const _user = 'nexus';
const _pass = 'nexus123';
const _workDir = '/config'; // direktori yang bisa ditulis user nexus

Future<bool> _reachable() async {
  try {
    final socket = await SSHSocket.connect(_host, _port)
        .timeout(const Duration(seconds: 4));
    final client = SSHClient(socket,
        username: _user, onPasswordRequest: () => _pass);
    await client.authenticated;
    client.close();
    return true;
  } catch (_) {
    return false;
  }
}

void main() {
  late bool serverUp;

  setUpAll(() async {
    serverUp = await _reachable();
    if (!serverUp) {
      // ignore: avoid_print
      print('⚠️  Server uji coba tidak terjangkau — grup di-skip.');
    }
  });

  group('SSH/SFTP integration', () {
    late SSHClient client;

    setUp(() async {
      if (!serverUp) return;
      final socket = await SSHSocket.connect(_host, _port);
      client = SSHClient(socket,
          username: _user, onPasswordRequest: () => _pass);
      await client.authenticated;
    });

    tearDown(() {
      if (serverUp) client.close();
    });

    test('SSH: eksekusi perintah "whoami" mengembalikan user', () async {
      if (!serverUp) return;
      final out = await client.run('whoami');
      expect(utf8.decode(out).trim(), _user);
    });

    test('SFTP: list direktori home mengembalikan daftar', () async {
      if (!serverUp) return;
      final sftp = await client.sftp();
      final items = await sftp.listdir(_workDir);
      expect(items, isNotEmpty);
      // '.' dan '..' selalu ada di listing SFTP.
      expect(items.map((e) => e.filename), contains('.'));
    });

    test('SFTP: siklus penuh mkdir → tulis → baca → rename → hapus',
        () async {
      if (!serverUp) return;
      final sftp = await client.sftp();
      final dir = '$_workDir/nexus_it_${DateTime.now().millisecondsSinceEpoch}';
      const payload = 'Halo dari tes integrasi HegiKetok 🎉';

      // 1. mkdir
      await sftp.mkdir(dir);

      // 2. tulis file (upload)
      final filePath = '$dir/catatan.txt';
      final wf = await sftp.open(
        filePath,
        mode: SftpFileOpenMode.create |
            SftpFileOpenMode.write |
            SftpFileOpenMode.truncate,
      );
      await wf.writeBytes(Uint8List.fromList(utf8.encode(payload)));
      await wf.close();

      // 3. baca kembali (download) & verifikasi isi identik
      final rf = await sftp.open(filePath, mode: SftpFileOpenMode.read);
      final data = await rf.readBytes();
      await rf.close();
      expect(utf8.decode(data), payload);

      // 4. rename
      final renamed = '$dir/catatan-renamed.txt';
      await sftp.rename(filePath, renamed);
      final afterRename = await sftp.listdir(dir);
      final names = afterRename.map((e) => e.filename).toList();
      expect(names, contains('catatan-renamed.txt'));
      expect(names, isNot(contains('catatan.txt')));

      // 5. hapus file lalu direktori
      await sftp.remove(renamed);
      await sftp.rmdir(dir);

      // 6. pastikan direktori sudah tidak ada (listdir melempar error)
      await expectLater(sftp.listdir(dir), throwsA(anything));
    });
  });

  // Menguji jalur kode yang sama dengan fitur SSH-key app (SSHKeyPair.fromPem).
  // Prasyarat: keypair uji terdaftar di server, private key di
  // ~/.ssh/hegiketok_test_ed25519. Jika tidak ada, tes di-skip.
  group('SSH key auth', () {
    test('autentikasi via private key (OpenSSH ed25519)', () async {
      if (!serverUp) return;
      final keyPath =
          '${Platform.environment['HOME']}/.ssh/hegiketok_test_ed25519';
      final keyFile = File(keyPath);
      if (!await keyFile.exists()) {
        // ignore: avoid_print
        print('⚠️  Key uji tidak ada ($keyPath) — tes key di-skip.');
        return;
      }
      final pem = await keyFile.readAsString();

      final socket = await SSHSocket.connect(_host, _port);
      final client = SSHClient(
        socket,
        username: _user,
        identities: SSHKeyPair.fromPem(pem), // persis seperti di app
      );
      await client.authenticated; // melempar bila auth gagal
      final out = await client.run('whoami');
      expect(utf8.decode(out).trim(), _user);
      client.close();
    });
  });

  // Regresi untuk TC-SSH-05: host tak terjangkau harus MELEMPAR (timeout),
  // bukan menggantung tanpa batas. Tidak perlu server uji coba.
  group('Ketahanan koneksi', () {
    test('connect ke host tak terjangkau melempar dalam batas timeout',
        () async {
      await expectLater(
        SSHSocket.connect('10.255.255.1', 22,
            timeout: const Duration(seconds: 2)),
        throwsA(anything),
      );
    }, timeout: const Timeout(Duration(seconds: 15)));
  });
}
