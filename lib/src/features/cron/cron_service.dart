import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';

import 'cron_models.dart';

/// Ambil crontab pengguna dari server lewat [client].
Future<CronSnapshot> fetchCron(SSHClient client) async {
  final res = await client.run('crontab -l 2>&1');
  return parseCron(utf8.decode(res, allowMalformed: true));
}

/// Parser murni crontab (dapat diuji tanpa server).
CronSnapshot parseCron(String text) {
  final low = text.toLowerCase();
  if (low.contains('no crontab for')) {
    return const CronSnapshot(jobs: [], lines: []);
  }
  if (low.contains('not allowed') || low.contains('permission denied')) {
    return const CronSnapshot(
        jobs: [], lines: [], error: 'Akses crontab ditolak untuk user ini.');
  }
  if (low.contains('command not found')) {
    return const CronSnapshot(
        jobs: [], lines: [], error: 'cron tidak tersedia di server ini.');
  }

  final lines = const LineSplitter().convert(text);
  // Buang baris kosong di ujung agar tidak menumpuk saat ditulis ulang.
  while (lines.isNotEmpty && lines.last.trim().isEmpty) {
    lines.removeLast();
  }

  final jobs = <CronJob>[];
  for (var i = 0; i < lines.length; i++) {
    final job = _parseLine(lines[i], i);
    if (job != null) jobs.add(job);
  }
  return CronSnapshot(jobs: jobs, lines: lines);
}

final _special = RegExp(
    r'^(@(?:reboot|yearly|annually|monthly|weekly|daily|midnight|hourly))\s+(.+)$');
final _fiveField = RegExp(r'^(\S+\s+\S+\s+\S+\s+\S+\s+\S+)\s+(.+)$');
final _envAssign = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*\s*=');

/// Pecah sebuah baris jadwal menjadi [schedule, command], atau null.
List<String>? splitCronLine(String line) {
  final l = line.trim();
  if (l.isEmpty) return null;
  final sp = _special.firstMatch(l);
  if (sp != null) return [sp.group(1)!, sp.group(2)!.trim()];
  final m = _fiveField.firstMatch(l);
  if (m == null) return null;
  return [m.group(1)!.replaceAll(RegExp(r'\s+'), ' '), m.group(2)!.trim()];
}

CronJob? _parseLine(String line, int index) {
  var l = line.trim();
  if (l.isEmpty) return null;

  var enabled = true;
  if (l.startsWith('#')) {
    // Mungkin job yang di-disable (di-comment). Kupas tanda pagar.
    final body = l.replaceFirst(RegExp(r'^#+\s*'), '');
    if (splitCronLine(body) == null) return null; // komentar biasa
    l = body;
    enabled = false;
  }

  // Lewati variabel lingkungan (SHELL=…, PATH=…, MAILTO=…).
  if (_envAssign.hasMatch(l)) return null;

  final parts = splitCronLine(l);
  if (parts == null) return null;
  return CronJob(
    lineIndex: index,
    schedule: parts[0],
    command: parts[1],
    enabled: enabled,
    raw: line,
  );
}

/// Tulis ulang crontab dari [lines]. Memakai base64 agar aman dari masalah
/// kutip/escape shell. Mengembalikan pesan error, atau '' bila sukses.
Future<String> writeCron(SSHClient client, List<String> lines) async {
  final content = '${lines.join('\n')}\n';
  final b64 = base64.encode(utf8.encode(content));
  final res = await client.run('echo $b64 | base64 -d | crontab - 2>&1');
  final msg = utf8.decode(res, allowMalformed: true).trim();
  if (msg.isEmpty) return '';
  final low = msg.toLowerCase();
  if (low.contains('errors in crontab') || low.contains('error')) return msg;
  if (low.contains('not allowed') || low.contains('permission')) {
    return 'Akses ditolak — tidak boleh mengubah crontab.';
  }
  return msg;
}

/// Deskripsi ramah untuk jadwal cron umum (best-effort).
String describeCron(String schedule) {
  switch (schedule) {
    case '@reboot':
      return 'Saat server boot';
    case '@hourly':
      return 'Tiap jam';
    case '@daily':
    case '@midnight':
      return 'Tiap hari (00:00)';
    case '@weekly':
      return 'Tiap minggu';
    case '@monthly':
      return 'Tiap bulan';
    case '@yearly':
    case '@annually':
      return 'Tiap tahun';
  }
  final f = schedule.split(RegExp(r'\s+'));
  if (f.length != 5) return schedule;
  final min = f[0], hour = f[1], dom = f[2], mon = f[3], dow = f[4];
  if (schedule == '* * * * *') return 'Tiap menit';
  if (min.startsWith('*/') && hour == '*' && dom == '*' && mon == '*' && dow == '*') {
    return 'Tiap ${min.substring(2)} menit';
  }
  if (RegExp(r'^\d+$').hasMatch(min) &&
      hour == '*' &&
      dom == '*' &&
      mon == '*' &&
      dow == '*') {
    return 'Tiap jam pada menit ke-$min';
  }
  if (RegExp(r'^\d+$').hasMatch(min) &&
      RegExp(r'^\d+$').hasMatch(hour) &&
      dom == '*' &&
      mon == '*' &&
      dow == '*') {
    final h = hour.padLeft(2, '0');
    final m = min.padLeft(2, '0');
    return 'Tiap hari pukul $h:$m';
  }
  return schedule;
}
