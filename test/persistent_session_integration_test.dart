// Tes integrasi NYATA "sesi persisten (tmux)" terhadap container uji
// `nexus-ssh-test`: perintah yang sama persis dengan yang dikirim app.
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_term/src/features/ssh/ssh_terminal_session.dart';

import 'support/test_server.dart';

Future<SSHClient> _raw() async {
  final socket = await SSHSocket.connect('127.0.0.1', 2222)
      .timeout(const Duration(seconds: 4));
  final c = SSHClient(socket,
      username: 'nexus', onPasswordRequest: () => 'nexus123');
  await c.authenticated;
  return c;
}

Future<String> _sh(String cmd) async {
  final c = await _raw();
  try {
    return utf8.decode(await c.run(cmd), allowMalformed: true);
  } finally {
    c.close();
  }
}

/// Buka shell interaktif seperti app, kirim [lines], kumpulkan keluaran
/// sampai [marker] muncul (atau timeout), lalu PUTUSKAN koneksi mendadak.
Future<String> _session(List<String> lines, String marker) async {
  final c = await _raw();
  final sh = await c.shell(pty: const SSHPtyConfig(width: 100, height: 30));
  final buf = StringBuffer();
  sh.stdout
      .cast<List<int>>()
      .transform(const Utf8Decoder(allowMalformed: true))
      .listen(buf.write);
  for (final l in lines) {
    sh.write(utf8.encode('$l\n'));
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  final end = DateTime.now().add(const Duration(seconds: 8));
  while (!buf.toString().contains(marker) && DateTime.now().isBefore(end)) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  c.close(); // koneksi putus tanpa pamit — seperti jaringan mati
  return buf.toString();
}

Future<void> main() async {
  final skip = await integrationSkipReason(needTmux: true);

  test('nama sesi aman untuk shell', () {
    expect(persistentSessionName('Server Produksi #1'), 'hegi-Server-Produksi-1');
    expect(persistentSessionName('a"; rm -rf ~ #'), 'hegi-a-rm-rf');
    expect(persistentSessionName('***'), 'hegi-session');
    expect(persistentSessionName('web_01-a'), 'hegi-web_01-a');
  });

  final name = persistentSessionName('uji persisten');
  final cmd = persistentSessionCommand(name);

  tearDownAll(() async {
    if (skip == null) await _sh('tmux kill-session -t $name 2>/dev/null; true');
  });

  test('program tetap hidup saat koneksi putus; sambung ulang melanjutkan',
      () async {
    await _sh('tmux kill-session -t $name 2>/dev/null; true');

    // Sesi 1: masuk tmux, jalankan proses panjang, lalu koneksi diputus.
    await _session([
      cmd,
      'echo MULAI_\$((1+1)); sleep 300',
    ], 'MULAI_2');

    await Future<void>.delayed(const Duration(milliseconds: 500));
    final alive = await _sh('tmux has-session -t $name && echo SESI_ADA; '
        "tmux list-panes -t $name -F '#{pane_current_command}'");
    expect(alive, contains('SESI_ADA'));
    expect(alive, contains('sleep'), reason: 'proses harus masih berjalan');

    // Sesi 2: perintah yang sama meng-attach sesi lama — layar lama terlihat.
    final second = await _session([cmd], 'MULAI_2');
    expect(second, contains('MULAI_2'));

    // Tetap satu sesi (attach, bukan membuat baru).
    final count = await _sh("tmux list-sessions -F '#{session_name}' | grep -c '^$name\$'");
    expect(count.trim(), '1');
  }, skip: skip, timeout: const Timeout(Duration(seconds: 60)));
}
