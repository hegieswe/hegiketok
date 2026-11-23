// Tes integrasi NYATA tmux control mode (`tmux -CC`) terhadap container uji
// `nexus-ssh-test` (127.0.0.1:2222). Butuh tmux terpasang di container;
// bila server mati atau tmux tak ada, tes dilaporkan dilewati.
//
// Menguji jalur yang sama dengan app: TmuxControlClient di atas SSH sungguhan.
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_term/src/models/ssh_credentials.dart';
import 'package:nexus_term/src/ssh/known_hosts.dart';
import 'package:nexus_term/src/ssh/ssh_connector.dart';
import 'package:nexus_term/src/ssh/tmux_control.dart';
import 'package:nexus_term/src/ssh/tmux_control_client.dart';

const _host = '127.0.0.1';
const _port = 2222;
const _user = 'nexus';
const _pass = 'nexus123';
const _session = 'hegi-it';
const _creds =
    SshCredentials(host: _host, port: _port, username: _user, password: _pass);

Future<SSHClient> _raw() async {
  final socket = await SSHSocket.connect(_host, _port)
      .timeout(const Duration(seconds: 4));
  final c = SSHClient(socket, username: _user, onPasswordRequest: () => _pass);
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

/// Tunggu sampai [cond] benar (maks [seconds] detik).
Future<void> _until(bool Function() cond, String what,
    {int seconds = 12}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (!cond()) {
    if (DateTime.now().isAfter(end)) fail('timeout menunggu: $what');
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

Future<void> main() async {
  String? skip;
  try {
    final probe = await _sh('command -v tmux >/dev/null 2>&1 && echo ADA');
    if (!probe.contains('ADA')) skip = 'tmux tidak terpasang di container uji.';
  } catch (_) {
    skip = 'Server uji (nexus-ssh-test di 127.0.0.1:2222) tidak berjalan.';
  }

  late Directory tmp;
  late TmuxControlClient client;
  var disposed = false;

  String screen(int pane) => client.panes[pane]!.terminal.buffer.getText();
  int firstPane() => client.panes.keys.reduce((a, b) => a < b ? a : b);

  setUpAll(() async {
    if (skip != null) return; // server/tmux tak ada → tak ada yang disiapkan
    tmp = await Directory.systemTemp.createTemp('hegi_tmux_it_');
    // Sesi yang SUDAH berjalan dengan isi layar, sebelum klien kita attach.
    await _sh('tmux kill-session -t $_session 2>/dev/null; '
        'tmux new-session -d -s $_session -x 80 -y 24 && '
        "tmux send-keys -t $_session 'echo HALO_AWAL' Enter && sleep 0.4");
    final store = KnownHostsStore(directory: tmp);
    client = TmuxControlClient(
      _creds,
      sessionName: _session,
      connect: (creds, progress) => connectSsh(creds,
          progress: progress,
          knownHosts: store,
          verifyHostKey: (_) async => true),
    )..start();
  });

  tearDownAll(() async {
    if (skip != null) return;
    if (!disposed) client.dispose();
    await _sh('tmux kill-session -t $_session 2>/dev/null; true');
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('attach: jendela & panel terbaca, isi layar lama langsung tampil',
      () async {
    await _until(() => client.windows.isNotEmpty && client.panes.isNotEmpty,
        'jendela & panel dari tmux');
    expect(client.error, isNull);
    expect(client.connected, isTrue);
    expect(client.windowOrder, hasLength(1));
    expect(client.activeWindow, client.windowOrder.single);
    await _until(() => screen(firstPane()).contains('HALO_AWAL'),
        'isi awal panel (capture-pane)');
  }, skip: skip);

  test('ketikan sampai ke shell dan keluarannya tampil di panel', () async {
    final pane = firstPane();
    // Hasil aritmetika membuktikan perintah benar-benar DIEKSEKUSI di server,
    // bukan sekadar gema ketikan.
    client.panes[pane]!.terminal.onOutput!('echo KETIK_\$((40+2))\r');
    await _until(() => screen(pane).contains('KETIK_42'), 'keluaran perintah');
  }, skip: skip);

  test('UTF-8 multi-byte utuh lewat send-keys heksadesimal', () async {
    final pane = firstPane();
    client.panes[pane]!.terminal.onOutput!("printf 'caf\\303\\251-%s\\n' ok\r");
    await _until(() => screen(pane).contains('café-ok'), 'teks UTF-8');
  }, skip: skip);

  test('resize klien → tmux mengubah ukuran panel', () async {
    final pane = firstPane();
    client.setClientSize(const TmuxGridSize(100, 30));
    await _until(
        () => client.panes[pane]!.terminal.viewWidth == 100,
        'lebar panel 100 kolom '
        '(sekarang ${client.panes[pane]!.terminal.viewWidth})');
    expect(client.panes[pane]!.terminal.viewHeight, 30);
    // Server sendiri melaporkan ukuran yang sama.
    final server = await _sh(
        "tmux display-message -p -t $_session '#{window_width}x#{window_height}'");
    expect(server.trim(), '100x30');
  }, skip: skip);

  test('split panel → dua panel berdampingan dengan ukuran dari tmux',
      () async {
    final pane = firstPane();
    client.splitPane(pane, horizontal: true);
    await _until(() => client.panes.length == 2, 'panel kedua');
    final tree = client.windows[client.activeWindow]!.tree!;
    expect(tree.dir, TmuxSplitDir.leftRight);
    expect(tree.children, hasLength(2));
    final widths =
        client.panes.values.map((p) => p.terminal.viewWidth).toList();
    // Dua panel + 1 kolom pembatas = lebar jendela.
    expect(widths[0] + widths[1] + 1, 100);
    // Panel baru menerima ketikan sendiri.
    final second = client.panes.keys.firstWhere((id) => id != pane);
    client.panes[second]!.terminal.onOutput!('echo PANEL_DUA\r');
    await _until(() => screen(second).contains('PANEL_DUA'),
        'keluaran di panel kedua');
    expect(screen(pane), isNot(contains('PANEL_DUA')));
  }, skip: skip);

  test('jendela baru muncul sebagai tab; menutupnya menghapus tab', () async {
    client.newWindow();
    await _until(() => client.windowOrder.length == 2, 'jendela kedua');
    final second = client.windowOrder.last;
    await _until(() => client.windows[second]!.tree != null, 'layout jendela');
    await _sh('tmux kill-window -t $_session:@$second');
    await _until(() => client.windowOrder.length == 1, 'jendela ditutup');
    expect(client.windows.containsKey(second), isFalse);
    // Panel milik jendela yang ditutup ikut dibersihkan.
    expect(client.panes.length, 2);
  }, skip: skip);

  test('rename jendela dari server tercermin di klien', () async {
    final win = client.windowOrder.single;
    await _sh('tmux rename-window -t $_session:@$win nama-baru');
    await _until(() => client.windows[win]!.name == 'nama-baru', 'nama baru');
  }, skip: skip);

  test('menutup klien hanya detach — sesi & program tetap hidup di server',
      () async {
    client.dispose();
    disposed = true;
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final out = await _sh(
        'tmux has-session -t $_session 2>/dev/null && echo MASIH_HIDUP; '
        "tmux list-panes -s -t $_session -F '#{pane_id}' | wc -l");
    expect(out, contains('MASIH_HIDUP'));
    expect(out.trim().split('\n').last.trim(), '2');
  }, skip: skip);
}
