import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/ssh_credentials.dart';
import 'docker_models.dart';
import 'docker_service.dart';

/// Mengelola panel Docker untuk satu server (via SSH).
class DockerController extends ChangeNotifier {
  DockerController(this.credentials);

  final SshCredentials credentials;

  SSHClient? _client;
  DockerSnapshot? snapshot;
  bool loading = true;
  bool refreshing = false;
  bool autoRefresh = false;
  int intervalSeconds = 5;
  String? connectError;
  Timer? _timer;

  List<DockerContainer> get containers => snapshot?.containers ?? const [];

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
      connectError = _friendly(e);
      loading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    if (_client == null) return;
    refreshing = true;
    notifyListeners();
    try {
      snapshot = await fetchDocker(_client!);
    } catch (e) {
      connectError = _friendly(e);
    } finally {
      loading = false;
      refreshing = false;
      notifyListeners();
    }
  }

  /// Jalankan aksi (start/stop/restart/rm) lalu refresh. Kembalikan error/null.
  Future<String?> action(String act, DockerContainer c) async {
    if (_client == null) return 'Tidak terhubung.';
    final err = await dockerAction(_client!, act, c.id);
    await refresh();
    return err.isEmpty ? null : err;
  }

  Future<String> logs(DockerContainer c, {int tail = 200}) async {
    if (_client == null) return '(tidak terhubung)';
    return dockerLogs(_client!, c.id, tail: tail);
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
