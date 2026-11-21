import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';

import 'docker_models.dart';

/// Perintah gabungan: versi daemon + daftar container + stats (sekali jalan).
const _dockerScript = r'''
export LANG=C
echo '@@VER'; docker version --format '{{.Server.Version}}' 2>&1
echo '@@PS'; docker ps -a --no-trunc --format '{{json .}}' 2>&1
echo '@@STATS'; docker stats --no-stream --format '{{json .}}' 2>&1
echo '@@END'
''';

/// Ambil snapshot Docker dari server lewat [client].
Future<DockerSnapshot> fetchDocker(SSHClient client) async {
  final out = await client.run(_dockerScript);
  return parseDockerOutput(utf8.decode(out, allowMalformed: true));
}

/// Parser murni (dapat diuji tanpa server).
DockerSnapshot parseDockerOutput(String text) {
  final sections = <String, List<String>>{};
  var cur = '';
  for (final line in const LineSplitter().convert(text)) {
    if (line.startsWith('@@')) {
      cur = line.substring(2);
      sections.putIfAbsent(cur, () => []);
    } else {
      (sections[cur] ??= []).add(line);
    }
  }
  List<String> sec(String k) => sections[k] ?? const [];

  // Versi daemon
  var version = '';
  for (final l in sec('VER')) {
    final t = l.trim();
    if (t.isNotEmpty && RegExp(r'^\d').hasMatch(t)) {
      version = t;
      break;
    }
  }

  // Containers (ps)
  final containers = <DockerContainer>[];
  for (final l in sec('PS')) {
    final t = l.trim();
    if (t.isEmpty || !t.startsWith('{')) continue;
    try {
      final j = jsonDecode(t) as Map<String, dynamic>;
      containers.add(DockerContainer(
        id: (j['ID'] ?? '').toString(),
        name: (j['Names'] ?? '').toString(),
        image: (j['Image'] ?? '').toString(),
        state: (j['State'] ?? '').toString(),
        status: (j['Status'] ?? '').toString(),
        ports: (j['Ports'] ?? '').toString(),
      ));
    } catch (_) {}
  }

  // Stats → gabungkan ke container by ID prefix
  final byId = {for (final c in containers) c.id: c};
  for (final l in sec('STATS')) {
    final t = l.trim();
    if (t.isEmpty || !t.startsWith('{')) continue;
    try {
      final j = jsonDecode(t) as Map<String, dynamic>;
      final sid = (j['ID'] ?? j['Container'] ?? '').toString();
      DockerContainer? c = byId[sid];
      c ??= containers.firstWhere(
        (x) => x.id.startsWith(sid) || sid.startsWith(x.shortId),
        orElse: () => DockerContainer(
            id: '', name: '', image: '', state: '', status: '', ports: ''),
      );
      if (c.id.isEmpty) continue;
      c.cpuPerc = _pct(j['CPUPerc']);
      c.memPerc = _pct(j['MemPerc']);
      c.memUsage = (j['MemUsage'] ?? '').toString();
      c.netIO = (j['NetIO'] ?? '').toString();
      c.blockIO = (j['BlockIO'] ?? '').toString();
    } catch (_) {}
  }

  // Deteksi error bila tidak ada container terparse
  String? error;
  if (containers.isEmpty) {
    error = _detectError(text);
  }

  // Urutkan: running dulu, lalu nama
  containers.sort((a, b) {
    if (a.isRunning != b.isRunning) return a.isRunning ? -1 : 1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });

  return DockerSnapshot(
    containers: containers,
    serverVersion: version,
    error: error,
  );
}

double? _pct(dynamic v) {
  if (v == null) return null;
  final s = v.toString().replaceAll('%', '').trim();
  return double.tryParse(s);
}

String? _detectError(String text) {
  final t = text.toLowerCase();
  if (t.contains('cannot connect to the docker daemon') ||
      t.contains('is the docker daemon running')) {
    return 'Tidak bisa terhubung ke Docker daemon. Pastikan Docker berjalan di server.';
  }
  if (t.contains('permission denied')) {
    return 'Akses Docker ditolak — user perlu masuk grup "docker" (atau pakai sudo).';
  }
  if (t.contains('not found') || t.contains('command not found')) {
    return 'Docker tidak terpasang / tidak ditemukan di server ini.';
  }
  return null; // tidak ada error; memang 0 container
}

/// Jalankan aksi container: start | stop | restart | rm. Kembalikan pesan
/// error (atau string kosong bila sukses).
Future<String> dockerAction(
    SSHClient client, String action, String id) async {
  final res = await client.run('docker $action $id 2>&1');
  final msg = utf8.decode(res, allowMalformed: true).trim();
  // docker mencetak ID container saat sukses; anggap sukses bila tak ada kata error.
  final low = msg.toLowerCase();
  if (low.contains('error') ||
      low.contains('permission denied') ||
      low.contains('cannot') ||
      low.contains('no such')) {
    return msg;
  }
  return '';
}

/// Ambil log sebuah container.
Future<String> dockerLogs(SSHClient client, String id, {int tail = 200}) async {
  final res =
      await client.run('docker logs --tail $tail --timestamps $id 2>&1');
  return utf8.decode(res, allowMalformed: true);
}
