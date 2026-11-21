import 'package:material_ui/material_ui.dart';

import '../../models/ssh_credentials.dart';
import '../../ssh/connection_progress.dart';
import '../../ssh/ssh_connector.dart';
import 'user_models.dart';
import 'user_service.dart';

/// Mengelola panel daftar user sistem (read-only) untuk satu server via SSH.
class UserController extends ChangeNotifier {
  UserController(this.credentials);

  final SshCredentials credentials;

  final ConnectionProgress progress = ConnectionProgress();

  SshConnection? _conn;
  UserSnapshot? snapshot;
  bool loading = true;
  bool refreshing = false;
  String? connectError;

  List<SystemUser> get users => snapshot?.users ?? const [];

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
      snapshot = await fetchUsers(conn.client);
    } catch (e) {
      connectError = _friendly(e);
    } finally {
      loading = false;
      refreshing = false;
      notifyListeners();
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
    _conn?.close();
    super.dispose();
  }
}
