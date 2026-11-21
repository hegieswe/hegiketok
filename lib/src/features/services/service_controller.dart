import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../models/ssh_credentials.dart';
import '../../ssh/connection_progress.dart';
import '../../ssh/ssh_connector.dart';
import 'service_models.dart';
import 'service_service.dart';

/// Mengelola panel service systemd untuk satu server (via SSH).
class ServiceController extends ChangeNotifier {
  ServiceController(this.credentials);

  final SshCredentials credentials;

  /// Progres handshake koneksi (ditampilkan selama menyambung).
  final ConnectionProgress progress = ConnectionProgress();

  SshConnection? _conn;
  ServiceSnapshot? snapshot;
  bool loading = true;
  bool refreshing = false;
  bool autoRefresh = false;
  int intervalSeconds = 10;
  String? connectError;
  Timer? _timer;

  List<SystemdService> get services => snapshot?.services ?? const [];

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
      snapshot = await fetchServices(conn.client);
    } catch (e) {
      connectError = _friendly(e);
    } finally {
      loading = false;
      refreshing = false;
      notifyListeners();
    }
  }

  /// Jalankan aksi (start/stop/restart/enable/disable) lalu refresh.
  /// Kembalikan pesan error, atau null bila sukses.
  Future<String?> action(String act, SystemdService s) async {
    final conn = _conn;
    if (conn == null) return 'Tidak terhubung.';
    final err = await serviceAction(conn.client, act, s.unit);
    await refresh();
    return err.isEmpty ? null : err;
  }

  Future<String> logs(SystemdService s, {int lines = 200}) async {
    final conn = _conn;
    if (conn == null) return '(tidak terhubung)';
    return serviceLogs(conn.client, s.unit, lines: lines);
  }

  void toggleAutoRefresh() {
    autoRefresh = !autoRefresh;
    _restartTimer();
    notifyListeners();
  }

  void setInterval(int seconds) {
    intervalSeconds = seconds.clamp(2, 60);
    if (autoRefresh) _restartTimer();
    notifyListeners();
  }

  void _restartTimer() {
    _timer?.cancel();
    if (autoRefresh) {
      _timer =
          Timer.periodic(Duration(seconds: intervalSeconds), (_) => refresh());
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
    _conn?.close();
    super.dispose();
  }
}
