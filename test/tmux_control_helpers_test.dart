import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_term/src/ssh/tmux_control.dart';

void main() {
  group('computeTmuxGrid', () {
    test('membagi area dengan ukuran sel (dibulatkan ke bawah)', () {
      final g = computeTmuxGrid(
          width: 845, height: 505, cellWidth: 8.4, cellHeight: 16.8);
      expect(g, const TmuxGridSize(100, 30));
    });

    test('masukan tak valid → null (tidak mengirim apa pun)', () {
      expect(
          computeTmuxGrid(width: 0, height: 0, cellWidth: 8, cellHeight: 16),
          isNull);
      expect(
          computeTmuxGrid(
              width: double.infinity, height: 400, cellWidth: 8, cellHeight: 16),
          isNull);
      expect(
          computeTmuxGrid(width: 800, height: 400, cellWidth: 0, cellHeight: 16),
          isNull);
      expect(
          computeTmuxGrid(width: -50, height: 400, cellWidth: 8, cellHeight: 16),
          isNull);
    });

    test('dijepit ke rentang wajar', () {
      final small = computeTmuxGrid(
          width: 40, height: 40, cellWidth: 8, cellHeight: 16);
      expect(small, const TmuxGridSize(20, 5));
      final huge = computeTmuxGrid(
          width: 100000, height: 100000, cellWidth: 8, cellHeight: 16);
      expect(huge, const TmuxGridSize(500, 300));
    });
  });

  group('perintah', () {
    test('ukuran klien memakai bentuk lebar,tinggi', () {
      expect(tmuxClientSizeCommand(const TmuxGridSize(120, 40)),
          'refresh-client -C 120,40');
    });

    test('capture & kursor menarget panel', () {
      expect(tmuxCapturePaneCommand(7), 'capture-pane -p -e -t %7');
      expect(tmuxCursorQueryCommand(7),
          "display-message -p -t %7 '#{cursor_x},#{cursor_y}'");
    });
  });

  group('parseTmuxCursor', () {
    test('x,y valid', () {
      expect(parseTmuxCursor(['13,2']), (x: 13, y: 2));
      expect(parseTmuxCursor(['', ' 0,0 ']), (x: 0, y: 0));
    });

    test('tak valid → null', () {
      expect(parseTmuxCursor([]), isNull);
      expect(parseTmuxCursor(['abc']), isNull);
      expect(parseTmuxCursor(['1,2,3']), isNull);
      expect(parseTmuxCursor(['-1,2']), isNull);
    });
  });

  group('buildTmuxCaptureWrite', () {
    test('bersihkan layar, tulis baris dengan CRLF, pulihkan kursor', () {
      final s = buildTmuxCaptureWrite(['a', 'b'], cursor: (x: 4, y: 1));
      expect(s, '\x1b[0m\x1b[H\x1b[2Ja\r\nb\x1b[0m\x1b[2;5H');
    });

    test('baris kosong di akhir dibuang; tanpa kursor tak ada CUP', () {
      final s = buildTmuxCaptureWrite(['a', '', '  ', '']);
      expect(s, '\x1b[0m\x1b[H\x1b[2Ja\x1b[0m');
    });
  });

  group('parser: flag fromClient', () {
    test('flags 0 → bukan balasan perintah kita', () {
      final r = TmuxControlParser()
          .feed('%begin 1700 1 0\n%end 1700 1 0\n')
          .single as TmuxCommandReply;
      expect(r.fromClient, isFalse);
    });

    test('flags 1 atau tanpa kolom flags → milik kita', () {
      final a = TmuxControlParser()
          .feed('%begin 1700 2 1\nx\n%end 1700 2 1\n')
          .single as TmuxCommandReply;
      expect(a.fromClient, isTrue);
      final b = TmuxControlParser()
          .feed('%begin 1700 3\n%end 1700 3\n')
          .single as TmuxCommandReply;
      expect(b.fromClient, isTrue);
    });
  });

  // Aliran nyata dibaca sebagai byte (latin1). Fungsi bantu: teks → string-byte.
  String wire(String text) => latin1.decode(utf8.encode(text));

  group('tmuxUnescapeBytes / tmuxUnescapeOutput', () {
    test('UTF-8 mentah (tmux modern, tanpa escape oktal) tetap utuh', () {
      // Regresi: dulu tiap karakter dipotong ke 1 byte → "café" jadi rusak.
      expect(tmuxUnescapeOutput(wire('café-ok')), 'café-ok');
      expect(tmuxUnescapeOutput(wire('日本語 ✓ 🚀')), '日本語 ✓ 🚀');
      expect(tmuxUnescapeOutput(wire('┌─┐│└┘')), '┌─┐│└┘');
    });

    test('campuran escape oktal + UTF-8 mentah', () {
      expect(tmuxUnescapeOutput('${wire('é')}\\015\\012\\033[0m'),
          'é\r\n\x1b[0m');
    });

    test('backslash ter-escape (\\134) kembali jadi satu backslash', () {
      expect(tmuxUnescapeOutput(r'a\134n'), r'a\n');
    });

    test('teks Unicode asli (unit > 0xFF) di-encode, tidak dipotong', () {
      expect(utf8.decode(tmuxUnescapeBytes('日🚀')), '日🚀');
    });
  });

  group('Utf8Carry', () {
    List<int> b(String s) => utf8.encode(s);

    test('karakter 2/3/4-byte yang terpotong disambung kembali', () {
      for (final ch in ['é', '日', '🚀']) {
        final bytes = b('a${ch}b');
        for (var cut = 1; cut < bytes.length; cut++) {
          final c = Utf8Carry();
          final out = c.add(bytes.sublist(0, cut)) + c.add(bytes.sublist(cut));
          expect(out, 'a${ch}b', reason: '$ch dipotong di byte $cut');
          expect(c.flush(), isEmpty);
        }
      }
    });

    test('potongan yang hanya berisi awal karakter → belum mengeluarkan apa pun',
        () {
      final c = Utf8Carry();
      expect(c.add([0xF0]), '');
      expect(c.add([0x9F, 0x9A]), '');
      expect(c.add([0x80, 0x21]), '🚀!');
    });

    test('ASCII & karakter lengkap langsung keluar', () {
      final c = Utf8Carry();
      expect(c.add(b('halo ')), 'halo ');
      expect(c.add(b('café')), 'café');
    });

    test('byte rusak tidak menahan aliran selamanya', () {
      final c = Utf8Carry();
      // 0xFF bukan pembuka sah; byte lanjutan yatim juga tidak ditahan.
      expect(c.add([0x61, 0xFF, 0x62]), 'a\u{FFFD}b');
      expect(c.add([0x80, 0x80, 0x80, 0x80, 0x63]), endsWith('c'));
      expect(c.flush(), isEmpty);
    });

    test('flush mengeluarkan sisa yang tak pernah lengkap', () {
      final c = Utf8Carry();
      expect(c.add([0x61, 0xE6]), 'a');
      expect(c.flush(), '\u{FFFD}');
      expect(c.flush(), isEmpty);
    });
  });

  group('parser atas aliran byte (latin1)', () {
    test('nama jendela non-ASCII terbaca benar', () {
      final ev = TmuxControlParser()
          .feed(wire('%window-renamed @3 café-日本\n'))
          .single as TmuxWindowRenamed;
      expect(ev.name, 'café-日本');
    });

    test('isi balasan perintah (mis. capture-pane) di-decode UTF-8', () {
      final r = TmuxControlParser()
          .feed(wire('%begin 1 2 1\n┌─ status ─┐ ✓\n%end 1 2 1\n'))
          .single as TmuxCommandReply;
      expect(r.lines.single, '┌─ status ─┐ ✓');
    });

    test('%output menyimpan byte mentah, .data men-decode-nya', () {
      final o = TmuxControlParser().feed(wire('%output %1 naïve\n')).single
          as TmuxOutput;
      expect(o.bytes, utf8.encode('naïve'));
      expect(o.data, 'naïve');
    });
  });
}
