// Kesiapan server uji untuk tes integrasi: container `nexus-ssh-test` di
// 127.0.0.1:2222 (user nexus / nexus123 — kredensial container lokal saja).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';

const testHost = '127.0.0.1';
const testPort = 2222;
const testUser = 'nexus';
const testPass = 'nexus123';

/// Klien SSH terautentikasi ke server uji.
Future<SSHClient> testServerClient() async {
  final socket = await SSHSocket.connect(testHost, testPort)
      .timeout(const Duration(seconds: 4));
  final client = SSHClient(socket,
      username: testUser, onPasswordRequest: () => testPass);
  try {
    await client.authenticated;
  } catch (_) {
    client.close();
    rethrow;
  }
  return client;
}

/// Alasan melewati tes integrasi, atau null bila server siap.
///
/// OpenSSH memblokir sementara (±20 detik) alamat yang beberapa kali gagal
/// login — dan beberapa tes memang sengaja gagal login. Bila server sedang
/// dalam masa blokir itu, fungsi ini MENUNGGU sampai login berhasil lagi,
/// supaya menjalankan suite berulang-ulang tidak menghasilkan kegagalan palsu.
Future<String?> integrationSkipReason({bool needTmux = false}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 45));
  while (true) {
    SSHClient? client;
    try {
      client = await testServerClient();
      if (needTmux) {
        final out = utf8.decode(
            await client.run('command -v tmux >/dev/null 2>&1 && echo ADA'));
        if (!out.contains('ADA')) return 'tmux tidak terpasang di server uji.';
      }
      return null;
    } on SocketException {
      return 'Server uji (nexus-ssh-test di $testHost:$testPort) tidak berjalan.';
    } on TimeoutException {
      return 'Server uji ($testHost:$testPort) tidak merespons.';
    } catch (_) {
      // Tersambung tapi diputus/ditolak → kemungkinan masa blokir; tunggu.
      if (DateTime.now().isAfter(deadline)) {
        return 'Server uji menolak login (masih memblokir setelah 45 detik).';
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    } finally {
      client?.close();
    }
  }
}
