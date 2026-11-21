import 'package:material_ui/material_ui.dart';

import '../../models/ssh_credentials.dart';
import '../../ssh/connection_progress.dart';
import '../../ssh/ssh_connector.dart';
import 'cron_models.dart';
import 'cron_service.dart';

/// Mengelola crontab satu server (via SSH): list + tambah/edit/hapus/toggle.
class CronController extends ChangeNotifier {
  CronController(this.credentials);

  final SshCredentials credentials;

  final ConnectionProgress progress = ConnectionProgress();

  SshConnection? _conn;
  CronSnapshot? snapshot;
  List<String> _lines = [];
  bool loading = true;
  bool refreshing = false;
  String? connectError;

  List<CronJob> get jobs => snapshot?.jobs ?? const [];

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
      final snap = await fetchCron(conn.client);
      snapshot = snap;
      _lines = List.of(snap.lines);
    } catch (e) {
      connectError = _friendly(e);
    } finally {
      loading = false;
      refreshing = false;
      notifyListeners();
    }
  }

  Future<String?> addJob(String schedule, String command) =>
      _write([..._lines, '$schedule $command']);

  Future<String?> updateJob(CronJob job, String schedule, String command) {
    final lines = List.of(_lines);
    if (job.lineIndex < 0 || job.lineIndex >= lines.length) {
      return Future.value('Baris tidak ditemukan — muat ulang dulu.');
    }
    lines[job.lineIndex] =
        job.enabled ? '$schedule $command' : '# $schedule $command';
    return _write(lines);
  }

  Future<String?> deleteJob(CronJob job) {
    final lines = List.of(_lines);
    if (job.lineIndex < 0 || job.lineIndex >= lines.length) {
      return Future.value('Baris tidak ditemukan — muat ulang dulu.');
    }
    lines.removeAt(job.lineIndex);
    return _write(lines);
  }

  Future<String?> toggleJob(CronJob job) {
    final lines = List.of(_lines);
    if (job.lineIndex < 0 || job.lineIndex >= lines.length) {
      return Future.value('Baris tidak ditemukan — muat ulang dulu.');
    }
    lines[job.lineIndex] = job.enabled
        ? '# ${job.schedule} ${job.command}'
        : '${job.schedule} ${job.command}';
    return _write(lines);
  }

  Future<String?> _write(List<String> lines) async {
    final conn = _conn;
    if (conn == null) return 'Tidak terhubung.';
    final err = await writeCron(conn.client, lines);
    await refresh();
    return err.isEmpty ? null : err;
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
