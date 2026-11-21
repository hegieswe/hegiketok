import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/ssh_credentials.dart';
import 'server_info.dart';
import 'server_info_collector.dart';

/// Mengelola koneksi SSH untuk mengambil info sistem server secara berkala.
class ServerInfoController extends ChangeNotifier {
  ServerInfoController(this.credentials);

  final SshCredentials credentials;

  SSHClient? _client;
  ServerInfo? info;
  bool loading = true;
  bool refreshing = false;
  bool autoRefresh = false;
  int intervalSeconds = 5;
  String? error;
  Timer? _timer;

  Future<void> connect() async {
    try {
      final socket = await SSHSocket.connect(
        credentials.host,
        credentials.port,
        timeout: const Duration(seconds: 10),
      );
      final identities = credentials.usesKey
          ? SSHKeyPair.fromPem(credentials.privateKey!, credentials.passphrase)
          : null;
      final client = SSHClient(
        socket,
        username: credentials.username,
        identities: identities,
        onPasswordRequest:
            credentials.usesKey ? null : () => credentials.password,
      );
      await client.authenticated;
      _client = client;
      await refresh();
    } catch (e) {
      error = _friendly(e);
      loading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    if (_client == null) return;
    refreshing = true;
    notifyListeners();
    try {
      info = await collectServerInfo(_client!);
      error = null;
    } catch (e) {
      error = _friendly(e);
    } finally {
      loading = false;
      refreshing = false;
      notifyListeners();
    }
  }

  void toggleAutoRefresh() {
    autoRefresh = !autoRefresh;
    _restartTimer();
    notifyListeners();
  }

  void setInterval(int seconds) {
    intervalSeconds = seconds.clamp(1, 60);
    if (autoRefresh) _restartTimer();
    notifyListeners();
  }

  void _restartTimer() {
    _timer?.cancel();
    if (autoRefresh) {
      _timer = Timer.periodic(
          Duration(seconds: intervalSeconds), (_) => refresh());
    }
  }

  /// Kirim sinyal kill ke sebuah proses. [force] = SIGKILL (-9).
  /// Mengembalikan pesan error, atau null bila berhasil.
  Future<String?> killProcess(int pid, {bool force = false}) async {
    if (_client == null) return 'Tidak terhubung.';
    try {
      final flag = force ? '-9 ' : '';
      final res = await _client!.run('kill $flag$pid 2>&1');
      final msg = utf8.decode(res, allowMalformed: true).trim();
      await refresh();
      if (msg.isEmpty) return null;
      if (msg.toLowerCase().contains('permission')) {
        return 'Akses ditolak — perlu hak lebih tinggi (sudo).';
      }
      if (msg.toLowerCase().contains('no such')) {
        return 'Proses sudah tidak ada.';
      }
      return msg;
    } catch (e) {
      return 'Gagal: $e';
    }
  }

  String _friendly(Object e) {
    final t = e.toString().toLowerCase();
    if (t.contains('auth')) return 'Autentikasi gagal.';
    if (t.contains('timed out') || t.contains('timeout')) {
      return 'Koneksi timeout — server tidak merespons.';
    }
    if (t.contains('refused')) return 'Koneksi ditolak.';
    return 'Gagal: $e';
  }

  @override
  void dispose() {
    _timer?.cancel();
    _client?.close();
    super.dispose();
  }
}
