import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';

import 'service_models.dart';

/// Perintah gabungan: cek ketersediaan systemd + daftar unit + status enable.
const _servicesScript = r'''
export LANG=C
echo '@@HAS'; command -v systemctl >/dev/null 2>&1 && echo yes || echo no
echo '@@UNITS'; systemctl list-units --type=service --all --no-pager --no-legend --plain 2>&1
echo '@@FILES'; systemctl list-unit-files --type=service --no-pager --no-legend --plain 2>&1
echo '@@END'
''';

/// Ambil snapshot service systemd dari server lewat [client].
Future<ServiceSnapshot> fetchServices(SSHClient client) async {
  final out = await client.run(_servicesScript);
  return parseServicesOutput(utf8.decode(out, allowMalformed: true));
}

/// Parser murni (dapat diuji tanpa server).
ServiceSnapshot parseServicesOutput(String text) {
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

  // systemd tersedia?
  final has = sec('HAS').map((e) => e.trim()).firstWhere(
        (e) => e.isNotEmpty,
        orElse: () => '',
      );
  if (has == 'no') {
    return const ServiceSnapshot(
      services: [],
      error:
          'systemd tidak tersedia di server ini (bukan sistem berbasis systemd).',
    );
  }

  // Daftar unit aktif/terdaftar.
  final services = <SystemdService>[];
  final byUnit = <String, SystemdService>{};
  for (final raw in sec('UNITS')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final parts = line.split(RegExp(r'\s+'));
    if (parts.length < 4) continue;
    final unit = parts[0];
    if (!unit.endsWith('.service')) continue;
    final svc = SystemdService(
      unit: unit,
      load: parts[1],
      active: parts[2],
      sub: parts[3],
      description: parts.length > 4 ? parts.sublist(4).join(' ') : '',
    );
    services.add(svc);
    byUnit[unit] = svc;
  }

  // Status enable/disable dari list-unit-files.
  for (final raw in sec('FILES')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final parts = line.split(RegExp(r'\s+'));
    if (parts.length < 2) continue;
    final unit = parts[0];
    if (!unit.endsWith('.service')) continue;
    final state = parts[1];
    final existing = byUnit[unit];
    if (existing != null) {
      existing.enabledState = state;
    } else {
      // Unit terdaftar tapi tak muncul di list-units (mis. tak pernah dimuat).
      final svc = SystemdService(
        unit: unit,
        load: 'stub',
        active: 'inactive',
        sub: 'dead',
        description: '',
        enabledState: state,
      );
      services.add(svc);
      byUnit[unit] = svc;
    }
  }

  // Error autentikasi/akses walau systemd ada?
  String? error;
  if (services.isEmpty) {
    final low = text.toLowerCase();
    if (low.contains('permission denied') ||
        low.contains('access denied') ||
        low.contains('authentication required')) {
      error = 'Akses ditolak — perlu hak lebih tinggi untuk membaca service.';
    }
  }

  // Urutkan: gagal dulu, lalu berjalan, lalu nama.
  services.sort((a, b) {
    if (a.isFailed != b.isFailed) return a.isFailed ? -1 : 1;
    if (a.isRunning != b.isRunning) return a.isRunning ? -1 : 1;
    return a.unit.toLowerCase().compareTo(b.unit.toLowerCase());
  });

  return ServiceSnapshot(services: services, error: error);
}

const _actions = {'start', 'stop', 'restart', 'enable', 'disable'};

/// Jalankan aksi service: start | stop | restart | enable | disable.
/// Mengembalikan pesan error (atau string kosong bila sukses).
Future<String> serviceAction(
    SSHClient client, String action, String unit) async {
  if (!_actions.contains(action)) return 'Aksi tidak dikenal: $action';
  // systemctl non-root memicu polkit; tanpa TTY ia langsung mengembalikan
  // "Interactive authentication required" (tidak menggantung).
  final res = await client.run('systemctl $action $unit 2>&1');
  final msg = utf8.decode(res, allowMalformed: true).trim();
  final low = msg.toLowerCase();
  if (msg.isEmpty) return '';
  if (low.contains('authentication required')) {
    return 'Perlu hak root — jalankan aplikasi sebagai user dengan akses sudo/polkit.';
  }
  if (low.contains('permission denied') || low.contains('access denied')) {
    return 'Akses ditolak — user tidak punya hak mengelola service ini.';
  }
  if (low.contains('failed') ||
      low.contains('not found') ||
      low.contains('no such') ||
      low.contains('error')) {
    return msg;
  }
  return ''; // output lain (mis. peringatan symlink) dianggap sukses
}

/// Ambil log sebuah service (journalctl, fallback ke status).
Future<String> serviceLogs(SSHClient client, String unit,
    {int lines = 200}) async {
  final res = await client.run(
    'journalctl -u $unit -n $lines --no-pager --no-hostname 2>&1 '
    '|| systemctl status $unit --no-pager -n $lines 2>&1',
  );
  return utf8.decode(res, allowMalformed: true);
}
