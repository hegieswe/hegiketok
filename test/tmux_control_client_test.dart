// Menguji TmuxControlClient terhadap "tmux tiruan": perintah yang dikirim
// klien ditangkap, lalu keluaran control mode disuapkan lewat debugFeed.
// Ini memvalidasi bootstrap, korelasi balasan, isi awal panel, dan resize —
// tanpa server sungguhan.
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_term/src/models/ssh_credentials.dart';
import 'package:nexus_term/src/ssh/tmux_control.dart';
import 'package:nexus_term/src/ssh/tmux_control_client.dart';

const _creds = SshCredentials(host: 'example.test', username: 'u');

class _FakeTmux {
  _FakeTmux() {
    client = TmuxControlClient.forTest(_creds, sent.add);
  }

  final List<String> sent = [];
  late final TmuxControlClient client;
  int _n = 0;

  /// Perintah yang sudah dikirim klien (tanpa newline).
  List<String> get commands => sent.map((s) => s.trimRight()).toList();

  void feed(String s) => client.debugFeed(s);

  /// Blok balasan untuk perintah dari klien ini (flags = 1).
  void reply(List<String> lines, {bool error = false, int flags = 1}) {
    _n++;
    final end = error ? '%error' : '%end';
    feed('%begin 1700000000 $_n $flags\n');
    for (final l in lines) {
      feed('$l\n');
    }
    feed('$end 1700000000 $_n $flags\n');
  }

  /// Blok pembuka control mode + balasan list-windows satu jendela/panel.
  void bootOnePane({String layout = 'b25d,80x24,0,0,3'}) {
    reply(const [], flags: 0); // blok pembuka (bukan milik antrean kita)
    reply(['@1 $layout bash']); // balasan list-windows
  }

  String screen(int paneId) =>
      client.panes[paneId]!.terminal.buffer.getText();
}

void main() {
  group('bootstrap & korelasi balasan', () {
    test('tidak mengirim apa pun sebelum control mode siap', () {
      final t = _FakeTmux();
      expect(t.sent, isEmpty);
      t.client.dispose();
    });

    test('blok pembuka memicu list-windows; balasannya membangun jendela', () {
      final t = _FakeTmux();
      t.reply(const [], flags: 0);
      expect(t.commands.single, startsWith('list-windows -F'));

      t.reply(['@1 b25d,80x24,0,0,3 bash']);
      expect(t.client.windowOrder, [1]);
      expect(t.client.windows[1]!.name, 'bash');
      expect(t.client.activeWindow, 1);
      expect(t.client.panes.keys, [3]);
      t.client.dispose();
    });

    test('blok pembuka ber-flag 1 (tmux lama) tetap dianggap penanda siap', () {
      final t = _FakeTmux();
      t.reply(const [], flags: 1);
      expect(t.commands.single, startsWith('list-windows -F'));
      t.reply(['@7 b25d,80x24,0,0,9 zsh']);
      expect(t.client.windowOrder, [7]);
      t.client.dispose();
    });

    test('blok tak diminta (flags 0) di tengah jalan tidak menggeser antrean',
        () {
      final t = _FakeTmux();
      t.reply(const [], flags: 0);
      // Blok asing tiba SEBELUM balasan list-windows.
      t.reply(['noise'], flags: 0);
      expect(t.client.windows, isEmpty);
      t.reply(['@1 b25d,80x24,0,0,3 bash']);
      expect(t.client.windowOrder, [1]);
      t.client.dispose();
    });

    test('balasan %error untuk list-windows tidak membuat jendela', () {
      final t = _FakeTmux();
      t.reply(const [], flags: 0);
      t.reply(['no server running'], error: true);
      expect(t.client.windows, isEmpty);
      t.client.dispose();
    });
  });

  group('panel: ukuran & isi awal', () {
    test('terminal panel disetel ke ukuran yang ditetapkan tmux', () {
      final t = _FakeTmux()..bootOnePane(layout: 'b25d,132x43,0,0,3');
      final term = t.client.panes[3]!.terminal;
      expect(term.viewWidth, 132);
      expect(term.viewHeight, 43);
      t.client.dispose();
    });

    test('panel baru meminta capture-pane lalu posisi kursor', () {
      final t = _FakeTmux()..bootOnePane();
      expect(t.commands, contains('capture-pane -p -e -t %3'));
      expect(
        t.commands.last,
        "display-message -p -t %3 '#{cursor_x},#{cursor_y}'",
      );
      t.client.dispose();
    });

    test('isi awal ditulis; output lama dibuang, output baru tidak hilang', () {
      final t = _FakeTmux()..bootOnePane();

      // Tiba sebelum balasan capture → sudah tercakup capture → dibuang.
      t.feed('%output %3 BASI\n');
      t.reply(['user@host:~\$ ls', 'file-a  file-b', 'user@host:~\$ ']);
      // Tiba setelah capture, sebelum kursor diketahui → ditahan.
      t.feed('%output %3 BARU\n');
      expect(t.screen(3), isNot(contains('file-a')));

      t.reply(['13,2']); // kursor di kolom 13, baris 2 (0-based)

      final text = t.screen(3);
      expect(text, contains('user@host:~\$ ls'));
      expect(text, contains('file-a  file-b'));
      expect(text, contains('BARU'));
      expect(text, isNot(contains('BASI')));

      // Setelah selesai, output langsung mengalir.
      t.feed('%output %3 !\n');
      expect(t.screen(3), contains('BARU!'));
      t.client.dispose();
    });

    test('kursor dikembalikan ke posisi yang dilaporkan tmux', () {
      final t = _FakeTmux()..bootOnePane();
      t.reply(['abc', 'def']);
      t.reply(['1,0']);
      final term = t.client.panes[3]!.terminal;
      expect(term.buffer.cursorX, 1);
      expect(term.buffer.cursorY, 0);
      t.client.dispose();
    });

    test('capture gagal (%error) tetap melepas output yang ditahan', () {
      final t = _FakeTmux()..bootOnePane();
      t.reply(["can't find pane"], error: true);
      t.feed('%output %3 hidup\n');
      t.reply(['0,0'], error: true);
      expect(t.screen(3), contains('hidup'));
      t.feed('%output %3 -terus\n');
      expect(t.screen(3), contains('hidup-terus'));
      t.client.dispose();
    });

    test('karakter multi-byte yang terpotong antar-%output tetap utuh', () {
      final t = _FakeTmux()..bootOnePane();
      t.reply(const []);
      t.reply(['0,0']);
      // "é" = C3 A9, dipecah ke dua notifikasi; "🚀" = F0 9F 9A 80 dipecah 3.
      t.feed('%output %3 caf\\303\n');
      expect(t.screen(3), contains('caf'));
      expect(t.screen(3), isNot(contains('\u{FFFD}')));
      t.feed('%output %3 \\251 \\360\\237\n');
      t.feed('%output %3 \\232\n');
      t.feed('%output %3 \\200!\n');
      expect(t.screen(3), contains('café 🚀!'));
      t.client.dispose();
    });

    test('UTF-8 mentah di %output dan nama jendela non-ASCII', () {
      final t = _FakeTmux()..bootOnePane();
      t.reply(const []);
      t.reply(['0,0']);
      t.feed('%output %3 naïve ✓ 日本\n');
      expect(t.screen(3), contains('naïve ✓ 日本'));
      t.feed('%window-renamed @1 kerja-日本\n');
      expect(t.client.windows[1]!.name, 'kerja-日本');
      t.client.dispose();
    });

    test('layout-change: panel baru dibuat, panel hilang dibersihkan', () {
      final t = _FakeTmux()..bootOnePane();
      t.reply(const []); // capture %3
      t.reply(['0,0']); // kursor %3

      // Split kiri|kanan: %3 dan %4.
      t.feed('%layout-change @1 abcd,80x24,0,0{40x24,0,0,3,39x24,41,0,4}\n');
      expect(t.client.panes.keys.toSet(), {3, 4});
      expect(t.client.panes[3]!.terminal.viewWidth, 40);
      expect(t.client.panes[4]!.terminal.viewWidth, 39);

      // %3 ditutup → tinggal %4 selebar penuh.
      t.feed('%layout-change @1 abcd,80x24,0,0,4\n');
      expect(t.client.panes.keys.toSet(), {4});
      expect(t.client.panes[4]!.terminal.viewWidth, 80);
      t.client.dispose();
    });

    test('ketikan panel dikirim sebagai send-keys heksadesimal', () {
      final t = _FakeTmux()..bootOnePane();
      t.client.panes[3]!.terminal.onOutput!('ls\r');
      expect(t.commands.last, 'send-keys -t %3 -H 6c 73 0d');
      t.client.dispose();
    });
  });

  group('ukuran klien → tmux', () {
    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 220));

    test('ukuran yang diset sebelum siap dikirim saat bootstrap', () async {
      final t = _FakeTmux();
      t.client.setClientSize(const TmuxGridSize(120, 40));
      await settle();
      expect(t.sent, isEmpty, reason: 'control mode belum siap');
      t.reply(const [], flags: 0);
      expect(t.commands.first, 'refresh-client -C 120,40');
      expect(t.commands[1], startsWith('list-windows -F'));
      t.client.dispose();
    });

    test('perubahan beruntun di-debounce; ukuran sama tidak dikirim ulang',
        () async {
      final t = _FakeTmux()..bootOnePane();
      t.reply(const []);
      t.reply(['0,0']);
      final before = t.sent.length;

      t.client.setClientSize(const TmuxGridSize(100, 30));
      t.client.setClientSize(const TmuxGridSize(101, 30));
      t.client.setClientSize(const TmuxGridSize(102, 31));
      await settle();
      expect(t.commands.sublist(before), ['refresh-client -C 102,31']);
      expect(t.client.sentSize, const TmuxGridSize(102, 31));

      t.client.setClientSize(const TmuxGridSize(102, 31));
      await settle();
      expect(t.sent.length, before + 1);
      t.client.dispose();
    });

    test('balasan refresh-client tidak mengacaukan balasan berikutnya',
        () async {
      final t = _FakeTmux()..bootOnePane();
      t.reply(const []);
      t.reply(['0,0']);
      t.client.setClientSize(const TmuxGridSize(90, 20));
      await settle();
      t.reply(const []); // balasan refresh-client
      t.client.newWindow();
      t.reply(const []); // balasan new-window
      t.feed('%window-add @2\n'); // memicu list-windows lagi
      t.reply([
        '@1 b25d,90x20,0,0,3 bash',
        '@2 c11e,90x20,0,0,5 vim',
      ]);
      expect(t.client.windowOrder, [1, 2]);
      expect(t.client.windows[2]!.name, 'vim');
      expect(t.client.panes.keys.toSet(), {3, 5});
      t.client.dispose();
    });
  });

  group('status', () {
    test('%exit menandai offline dan mengisi error', () {
      final t = _FakeTmux()..bootOnePane();
      expect(t.client.online.value, isTrue);
      t.feed('%exit detached\n');
      expect(t.client.connected, isFalse);
      expect(t.client.error, contains('detached'));
      t.client.dispose();
    });
  });
}
