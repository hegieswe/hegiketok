import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_term/src/ssh/tmux_control.dart';

void main() {
  group('TmuxControlParser — notifikasi', () {
    test('%output di-unescape & dipetakan ke pane id', () {
      final p = TmuxControlParser();
      final ev = p.feed('%output %3 hello\\040world\r\n');
      expect(ev, hasLength(1));
      final o = ev.first as TmuxOutput;
      expect(o.paneId, 3);
      expect(o.data, 'hello world'); // \040 = spasi
    });

    test('%output mempertahankan escape ANSI (ESC via \\033)', () {
      final p = TmuxControlParser();
      final ev = p.feed('%output %1 \\033[31mred\\033[0m\n');
      final o = ev.first as TmuxOutput;
      expect(o.data, '\x1b[31mred\x1b[0m');
    });

    test('window add/close/renamed', () {
      final p = TmuxControlParser();
      expect((p.feed('%window-add @5\n').single as TmuxWindowAdd).windowId, 5);
      expect((p.feed('%window-close @5\n').single as TmuxWindowClose).windowId,
          5);
      final r = p.feed('%window-renamed @2 build server\n').single
          as TmuxWindowRenamed;
      expect(r.windowId, 2);
      expect(r.name, 'build server');
    });

    test('layout-change membawa string layout', () {
      final p = TmuxControlParser();
      final ev = p.feed('%layout-change @1 bc62,80x24,0,0,0\n').single
          as TmuxLayoutChange;
      expect(ev.windowId, 1);
      expect(ev.layout, 'bc62,80x24,0,0,0');
    });

    test('session-changed & exit', () {
      final p = TmuxControlParser();
      final s =
          p.feed('%session-changed \$1 main\n').single as TmuxSessionChanged;
      expect(s.sessionId, 1);
      expect(s.name, 'main');
      final e = p.feed('%exit \n').single as TmuxExit;
      expect(e.reason, isNull);
      final e2 = p.feed('%exit server exited\n').single as TmuxExit;
      expect(e2.reason, 'server exited');
    });
  });

  group('TmuxControlParser — blok perintah', () {
    test('%begin..%end mengumpulkan isi sebagai satu balasan', () {
      final p = TmuxControlParser();
      final ev = p.feed(
        '%begin 123 0 1\n'
        '@1 main\n'
        '@2 logs\n'
        '%end 123 0 1\n',
      );
      expect(ev, hasLength(1));
      final r = ev.single as TmuxCommandReply;
      expect(r.number, 123);
      expect(r.error, isFalse);
      expect(r.lines, ['@1 main', '@2 logs']);
    });

    test('%error menandai balasan gagal', () {
      final p = TmuxControlParser();
      final r = p.feed('%begin 9 0 1\nno such window\n%error 9 0 1\n').single
          as TmuxCommandReply;
      expect(r.error, isTrue);
      expect(r.body, 'no such window');
    });

    test('baris %output DI DALAM blok tidak salah tafsir', () {
      // tmux menaruh output verbatim; baris literal diperlakukan sbg isi blok.
      final p = TmuxControlParser();
      final ev = p.feed('%begin 1 0 1\nliteral line\n%end 1 0 1\n');
      final r = ev.single as TmuxCommandReply;
      expect(r.lines, ['literal line']);
    });
  });

  group('TmuxControlParser — framing', () {
    test('chunk terpotong ditahan sampai newline', () {
      final p = TmuxControlParser();
      expect(p.feed('%window-ad'), isEmpty);
      expect(p.feed('d @7\n'), hasLength(1));
      expect((p.feed('').isEmpty), isTrue);
    });

    test('beberapa event dalam satu umpan', () {
      final p = TmuxControlParser();
      final ev = p.feed('%window-add @1\n%window-add @2\n%output %1 hi\n');
      expect(ev, hasLength(3));
      expect(ev.whereType<TmuxWindowAdd>(), hasLength(2));
      expect((ev.last as TmuxOutput).data, 'hi');
    });
  });

  group('tmuxUnescapeOutput', () {
    test('byte oktal → karakter; UTF-8 multi-byte utuh', () {
      // 'é' UTF-8 = 0xC3 0xA9 = \303\251
      expect(tmuxUnescapeOutput('caf\\303\\251'), 'café');
    });
    test('teks biasa tak berubah', () {
      expect(tmuxUnescapeOutput('plain text 123'), 'plain text 123');
    });
    test('backslash tunggal bukan oktal dibiarkan', () {
      expect(tmuxUnescapeOutput(r'a\b'), r'a\b');
    });
  });

  group('parseTmuxLayout', () {
    test('panel tunggal', () {
      final n = parseTmuxLayout('bc62,80x24,0,0,0')!;
      expect(n.isLeaf, isTrue);
      expect(n.paneId, 0);
      expect(n.width, 80);
      expect(n.height, 24);
      expect(n.paneIds, [0]);
    });

    test('split kiri-kanan {} → dua daun', () {
      final n = parseTmuxLayout('cafe,80x24,0,0{40x24,0,0,1,39x24,41,0,2}')!;
      expect(n.isLeaf, isFalse);
      expect(n.dir, TmuxSplitDir.leftRight);
      expect(n.children, hasLength(2));
      expect(n.children[0].paneId, 1);
      expect(n.children[1].paneId, 2);
      expect(n.children[1].x, 41);
      expect(n.paneIds, [1, 2]);
    });

    test('split atas-bawah [] ', () {
      final n = parseTmuxLayout('f00d,80x24,0,0[80x12,0,0,3,80x11,0,13,4]')!;
      expect(n.dir, TmuxSplitDir.topBottom);
      expect(n.paneIds, [3, 4]);
      expect(n.children[1].y, 13);
    });

    test('split bersarang', () {
      // kiri satu panel, kanan terbagi atas-bawah
      final n = parseTmuxLayout(
          '1234,80x24,0,0{40x24,0,0,1,39x24,41,0[39x12,41,0,2,39x11,41,13,3]}')!;
      expect(n.dir, TmuxSplitDir.leftRight);
      expect(n.children[0].paneId, 1);
      expect(n.children[1].isLeaf, isFalse);
      expect(n.children[1].dir, TmuxSplitDir.topBottom);
      expect(n.paneIds, [1, 2, 3]);
    });

    test('tanpa checksum tetap terparse', () {
      final n = parseTmuxLayout('80x24,0,0,5')!;
      expect(n.paneId, 5);
    });

    test('string malformed → null', () {
      expect(parseTmuxLayout('bukan-layout'), isNull);
    });
  });
}
