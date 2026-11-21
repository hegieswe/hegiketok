/// Satu entri cron (baris crontab yang berupa jadwal + perintah).
class CronJob {
  CronJob({
    required this.lineIndex,
    required this.schedule,
    required this.command,
    required this.enabled,
    required this.raw,
  });

  /// Indeks baris pada crontab mentah (sumber kebenaran untuk edit/hapus).
  final int lineIndex;
  final String schedule; // mis. "*/5 * * * *" atau "@reboot"
  final String command;
  final bool enabled; // false = baris di-comment ("# …")
  final String raw;
}

/// Snapshot crontab pengguna: daftar job + seluruh baris mentah.
class CronSnapshot {
  const CronSnapshot({
    required this.jobs,
    required this.lines,
    this.error,
  });

  final List<CronJob> jobs;

  /// Seluruh baris crontab apa adanya — dipakai untuk menulis ulang dengan
  /// tetap mempertahankan komentar & variabel lingkungan (SHELL, PATH, dll).
  final List<String> lines;

  final String? error;
}
