import 'dart:async';
import 'dart:convert';

import '../models/ssh_credentials.dart';
import 'ssh_connector.dart';
import 'ssh_errors.dart';

/// Hasil "Tes koneksi".
class ConnectionTestResult {
  const ConnectionTestResult.success(this.detail)
      : ok = true,
        failure = null;
  const ConnectionTestResult.failed(SshFailure this.failure)
      : ok = false,
        detail = null;

  final bool ok;

  /// Saat berhasil: info singkat server (mis. `Linux 6.8.0` / nama host).
  final String? detail;
  final SshFailure? failure;
}

/// Pembuka koneksi (bisa diganti pengujian).
typedef SshConnect = Future<SshConnection> Function(SshCredentials credentials);

/// Coba login ke [credentials] lalu langsung putuskan. Tidak mengubah apa pun
/// di server: hanya menjalankan `uname` untuk memastikan sesi benar-benar
/// bisa dipakai. Tidak pernah melempar — galat dikembalikan sebagai hasil.
Future<ConnectionTestResult> testSshConnection(
  SshCredentials credentials, {
  SshConnect? connect,
  Duration timeout = const Duration(seconds: 20),
}) async {
  SshConnection? conn;
  try {
    conn = await (connect ?? connectSsh)(credentials).timeout(timeout);
    String? detail;
    try {
      final out = await conn.client
          .run('uname -sr 2>/dev/null || ver', stderr: false)
          .timeout(const Duration(seconds: 8));
      final text = utf8.decode(out, allowMalformed: true).trim();
      if (text.isNotEmpty) detail = text.split('\n').first.trim();
    } catch (_) {
      // Login berhasil; info server hanya pelengkap.
    }
    return ConnectionTestResult.success(detail);
  } on TimeoutException {
    return ConnectionTestResult.failed(describeSshError(
        TimeoutException('timeout'),
        credentials: credentials));
  } catch (e) {
    return ConnectionTestResult.failed(
        describeSshError(e, credentials: credentials));
  } finally {
    conn?.close();
  }
}
