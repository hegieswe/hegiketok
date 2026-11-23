import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../models/ssh_credentials.dart';
import '../../ssh/connection_progress.dart';
import '../../ssh/ssh_connector.dart';
import 'docker_models.dart';
import 'docker_service.dart';
import '../../ssh/ssh_errors.dart';

/// Mengelola panel Docker untuk satu server (via SSH).
class DockerController extends ChangeNotifier {
  DockerController(this.credentials);

  final SshCredentials credentials;

  /// Progres handshake koneksi (ditampilkan selama menyambung).
  final ConnectionProgress progress = ConnectionProgress();

  SshConnection? _conn;
  DockerSnapshot? snapshot;
  bool loading = true;
  bool refreshing = false;
  bool autoRefresh = false;
  int intervalSeconds = 5;
  String? connectError;
  Timer? _timer;

  List<DockerContainer> get containers => snapshot?.containers ?? const [];

  Future<void> connect() async {
    connectError = null;
    loading = true;
    notifyListeners();
    try {
      progress.reset();
      _conn = await connectSsh(credentials, progress: progress);
      await refresh();
    } catch (e) {
      connectError = _friendly(e);
      loading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    final conn = _conn;
    if (conn == null) return;
    refreshing = true;
    notifyListeners();
    try {
      snapshot = await fetchDocker(conn.client);
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
    final conn = _conn;
    if (conn == null) return 'Tidak terhubung.';
    final err = await dockerAction(conn.client, act, c.id);
    await refresh();
    return err.isEmpty ? null : err;
  }

  Future<String> logs(DockerContainer c, {int tail = 200}) async {
    final conn = _conn;
    if (conn == null) return '(tidak terhubung)';
    return dockerLogs(conn.client, c.id, tail: tail);
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

  String _friendly(Object e) =>
      describeSshError(e, credentials: credentials).full;

  @override
  void dispose() {
    _timer?.cancel();
    _conn?.close();
    super.dispose();
  }
}
