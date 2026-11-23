// Mesin protokol **tmux control mode** (`tmux -CC`).
//
// Dalam control mode, tmux membungkus semua sesi/jendela/panel di SATU koneksi
// dan mengalirkan "notifikasi" berbasis baris yang diawali `%`. Ini memungkinkan
// klien (seperti iTerm2 — dan kini HegiKetok) menampilkan jendela & panel tmux
// remote sebagai TAB & SPLIT native, sekaligus mendapat persistensi sesi tmux.
//
// File ini MURNI (tanpa I/O): ia mengubah teks mentah control-mode menjadi
// event bertipe, meng-unescape data `%output`, dan mem-parse string layout
// panel. Bagian hidup (SSH, UI) dibangun di atasnya.

import 'dart:convert';
import 'dart:typed_data';

// ───────────────────────────── Events ──────────────────────────────

/// Satu notifikasi control-mode tmux yang sudah diparse.
sealed class TmuxEvent {
  const TmuxEvent();
}

/// `%output %<pane> <data>` — keluaran dari sebuah panel. [bytes] adalah byte
/// mentah setelah escape oktal dibuka; bisa berakhir di tengah karakter
/// multi-byte (lanjutannya datang di `%output` berikutnya), jadi konsumen
/// streaming sebaiknya memakai [Utf8Carry].
class TmuxOutput extends TmuxEvent {
  const TmuxOutput(this.paneId, this.bytes);
  final int paneId;
  final Uint8List bytes;

  /// [bytes] di-decode UTF-8 apa adanya (toleran byte rusak).
  String get data => utf8.decode(bytes, allowMalformed: true);
}

/// Balasan sebuah perintah yang kita kirim: isi di antara `%begin`..`%end`.
/// [error] true bila diakhiri `%error`.
class TmuxCommandReply extends TmuxEvent {
  const TmuxCommandReply({
    required this.number,
    required this.lines,
    required this.error,
    this.fromClient = true,
  });
  final int number;
  final List<String> lines;
  final bool error;

  /// false bila blok ini BUKAN balasan atas perintah yang kita kirim (flag
  /// ketiga `%begin` = 0), mis. blok pembuka saat control mode baru mulai.
  /// Blok seperti itu tidak boleh dicocokkan dengan antrean perintah kita.
  final bool fromClient;

  String get body => lines.join('\n');
}

/// `%window-add @<id>`
class TmuxWindowAdd extends TmuxEvent {
  const TmuxWindowAdd(this.windowId);
  final int windowId;
}

/// `%window-close @<id>` / `%unlinked-window-close @<id>`
class TmuxWindowClose extends TmuxEvent {
  const TmuxWindowClose(this.windowId);
  final int windowId;
}

/// `%window-renamed @<id> <name>`
class TmuxWindowRenamed extends TmuxEvent {
  const TmuxWindowRenamed(this.windowId, this.name);
  final int windowId;
  final String name;
}

/// `%layout-change @<id> <layout> [<visible-layout> <flags>]`
class TmuxLayoutChange extends TmuxEvent {
  const TmuxLayoutChange(this.windowId, this.layout);
  final int windowId;
  final String layout;
}

/// `%session-changed $<id> <name>`
class TmuxSessionChanged extends TmuxEvent {
  const TmuxSessionChanged(this.sessionId, this.name);
  final int sessionId;
  final String name;
}

/// `%window-pane-changed @<win> %<pane>` — panel aktif jendela berubah.
class TmuxWindowPaneChanged extends TmuxEvent {
  const TmuxWindowPaneChanged(this.windowId, this.paneId);
  final int windowId;
  final int paneId;
}

/// `%exit [reason]` — tmux keluar dari control mode (sesi detach/berakhir).
class TmuxExit extends TmuxEvent {
  const TmuxExit(this.reason);
  final String? reason;
}

/// Notifikasi lain yang belum ditangani khusus (disimpan apa adanya).
class TmuxUnknown extends TmuxEvent {
  const TmuxUnknown(this.line);
  final String line;
}

// ───────────────────────────── Parser ──────────────────────────────

/// Parser stateful: umpankan teks mentah via [feed]; ia mengurai baris lengkap
/// dan mengembalikan event yang terbentuk. Baris parsial ditahan sampai `\n`.
class TmuxControlParser {
  final StringBuffer _buffer = StringBuffer();

  // Saat berada di dalam blok %begin..%end, baris mentah diakumulasi di sini.
  bool _inBlock = false;
  int _blockNumber = 0;
  bool _blockFromClient = true;
  final List<String> _blockLines = [];

  /// Umpan teks mentah dari koneksi. Mengembalikan semua event dari baris yang
  /// sudah lengkap pada umpan ini.
  List<TmuxEvent> feed(String chunk) {
    _buffer.write(chunk);
    final text = _buffer.toString();
    final events = <TmuxEvent>[];

    var start = 0;
    while (true) {
      final nl = text.indexOf('\n', start);
      if (nl < 0) break;
      var line = text.substring(start, nl);
      if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
      start = nl + 1;
      final ev = _line(line);
      if (ev != null) events.add(ev);
    }

    // Sisakan baris yang belum lengkap di buffer.
    _buffer
      ..clear()
      ..write(text.substring(start));
    return events;
  }

  // Aliran control mode dibaca sebagai BYTE (tiap unit kode = satu byte,
  // alias latin1) supaya data panel tidak rusak. Baris non-%output (nama
  // jendela, isi balasan perintah) adalah teks UTF-8 → decode di sini.
  static String _text(String raw) {
    for (var i = 0; i < raw.length; i++) {
      final c = raw.codeUnitAt(i);
      if (c > 0xFF) return raw; // sudah teks Unicode (mis. dari pengujian)
      if (c > 0x7F) {
        return utf8.decode(latin1.encode(raw), allowMalformed: true);
      }
    }
    return raw; // ASCII murni
  }

  TmuxEvent? _line(String rawLine) {
    // Data %output tetap byte mentah; baris lain diperlakukan sebagai teks.
    final line = (!_inBlock && rawLine.startsWith('%output '))
        ? rawLine
        : _text(rawLine);
    if (_inBlock) {
      if (line.startsWith('%end ') || line.startsWith('%error ')) {
        final error = line.startsWith('%error ');
        final num = _firstIntAfter(line, error ? '%error ' : '%end ');
        if (num == _blockNumber) {
          final reply = TmuxCommandReply(
            number: _blockNumber,
            lines: List<String>.from(_blockLines),
            error: error,
            fromClient: _blockFromClient,
          );
          _inBlock = false;
          _blockLines.clear();
          return reply;
        }
      }
      // Baris isi perintah (verbatim).
      _blockLines.add(line);
      return null;
    }

    if (line.startsWith('%begin ')) {
      _inBlock = true;
      _blockNumber = _firstIntAfter(line, '%begin ') ?? 0;
      // Format: `%begin <waktu> <nomor> <flags>`; flags 1 = dari klien ini.
      // Bila kolom flags tak ada (tmux lama), anggap balasan milik kita.
      final fields = line.split(' ');
      _blockFromClient = fields.length < 4 || fields[3].trim() != '0';
      _blockLines.clear();
      return null;
    }

    if (!line.startsWith('%')) {
      // Di luar blok, baris non-% tak diharapkan — abaikan diam-diam.
      return line.isEmpty ? null : TmuxUnknown(line);
    }

    return _notification(line);
  }

  TmuxEvent _notification(String line) {
    // %output %<pane> <data>
    if (line.startsWith('%output ')) {
      final rest = line.substring('%output '.length);
      final sp = rest.indexOf(' ');
      final paneTok = sp < 0 ? rest : rest.substring(0, sp);
      final data = sp < 0 ? '' : rest.substring(sp + 1);
      final pane = _paneId(paneTok);
      return TmuxOutput(pane ?? -1, tmuxUnescapeBytes(data));
    }

    final parts = line.split(' ');
    switch (parts.first) {
      case '%window-add':
        return TmuxWindowAdd(_winId(_at(parts, 1)) ?? -1);
      case '%window-close':
      case '%unlinked-window-close':
        return TmuxWindowClose(_winId(_at(parts, 1)) ?? -1);
      case '%window-renamed':
        return TmuxWindowRenamed(
          _winId(_at(parts, 1)) ?? -1,
          parts.skip(2).join(' '),
        );
      case '%layout-change':
        return TmuxLayoutChange(
          _winId(_at(parts, 1)) ?? -1,
          _at(parts, 2) ?? '',
        );
      case '%session-changed':
        return TmuxSessionChanged(
          _sessionId(_at(parts, 1)) ?? -1,
          parts.skip(2).join(' '),
        );
      case '%window-pane-changed':
        return TmuxWindowPaneChanged(
          _winId(_at(parts, 1)) ?? -1,
          _paneId(_at(parts, 2)) ?? -1,
        );
      case '%exit':
        final reason = parts.skip(1).join(' ').trim();
        return TmuxExit(reason.isEmpty ? null : reason);
      default:
        return TmuxUnknown(line);
    }
  }

  static String? _at(List<String> parts, int i) =>
      i < parts.length ? parts[i] : null;

  static int? _firstIntAfter(String line, String prefix) {
    final rest = line.substring(prefix.length).trim();
    final tok = rest.split(' ').first;
    return int.tryParse(tok);
  }

  // Token id tmux: pane `%12`, window `@3`, session `$1`.
  static int? _paneId(String? t) =>
      (t != null && t.startsWith('%')) ? int.tryParse(t.substring(1)) : null;
  static int? _winId(String? t) =>
      (t != null && t.startsWith('@')) ? int.tryParse(t.substring(1)) : null;
  static int? _sessionId(String? t) =>
      (t != null && t.startsWith('\$')) ? int.tryParse(t.substring(1)) : null;
}

// ─────────────────────────── Unescaping ────────────────────────────

bool _isOctal(int c) => c >= 0x30 && c <= 0x37; // '0'..'7'

/// Buka escape data `%output` menjadi byte mentah. tmux mengirim byte
/// non-cetak dan backslash sebagai `\ooo` (oktal 3 digit); byte lain — termasuk
/// UTF-8 multi-byte pada tmux modern — dikirim apa adanya.
///
/// [s] adalah "string byte": tiap unit kode ≤ 0xFF mewakili satu byte. Unit di
/// atas itu (teks Unicode asli, mis. dari pengujian) di-encode UTF-8.
Uint8List tmuxUnescapeBytes(String s) {
  final out = BytesBuilder(copy: false);
  final units = s.codeUnits;
  var i = 0;
  while (i < units.length) {
    final c = units[i];
    if (c == 0x5C /* \ */ &&
        i + 3 < units.length &&
        _isOctal(units[i + 1]) &&
        _isOctal(units[i + 2]) &&
        _isOctal(units[i + 3])) {
      final value = (units[i + 1] - 0x30) * 64 +
          (units[i + 2] - 0x30) * 8 +
          (units[i + 3] - 0x30);
      out.addByte(value & 0xFF);
      i += 4;
    } else if (c <= 0xFF) {
      out.addByte(c);
      i += 1;
    } else {
      // Unit > 0xFF: karakter Unicode asli (bisa pasangan surrogate).
      var end = i + 1;
      if (c >= 0xD800 && c <= 0xDBFF && end < units.length) end++;
      out.add(utf8.encode(String.fromCharCodes(units.sublist(i, end))));
      i = end;
    }
  }
  return out.toBytes();
}

/// Seperti [tmuxUnescapeBytes] lalu di-decode UTF-8 (toleran byte rusak).
String tmuxUnescapeOutput(String s) =>
    utf8.decode(tmuxUnescapeBytes(s), allowMalformed: true);

/// Dekoder UTF-8 bertahap: menahan byte di ujung yang baru separuh karakter
/// multi-byte sampai lanjutannya tiba, sehingga karakter yang terpotong di
/// antara dua potongan data tidak berubah menjadi `�`.
class Utf8Carry {
  Uint8List _tail = Uint8List(0);

  /// Decode [chunk] (digabung sisa sebelumnya) dan kembalikan teks yang sudah
  /// lengkap. Byte yang benar-benar rusak tetap menjadi U+FFFD.
  String add(List<int> chunk) {
    if (chunk.isEmpty && _tail.isEmpty) return '';
    final all = Uint8List(_tail.length + chunk.length)
      ..setRange(0, _tail.length, _tail)
      ..setRange(_tail.length, _tail.length + chunk.length, chunk);
    final cut = all.length - _incompleteTail(all);
    _tail = Uint8List.sublistView(all, cut);
    if (cut == 0) return '';
    return utf8.decode(Uint8List.sublistView(all, 0, cut),
        allowMalformed: true);
  }

  /// Keluarkan sisa yang tertahan (dipakai saat aliran berakhir).
  String flush() {
    if (_tail.isEmpty) return '';
    final s = utf8.decode(_tail, allowMalformed: true);
    _tail = Uint8List(0);
    return s;
  }

  // Jumlah byte di akhir [b] yang merupakan AWAL karakter multi-byte tapi
  // belum lengkap (0..3).
  static int _incompleteTail(Uint8List b) {
    final n = b.length;
    for (var back = 1; back <= 3 && back <= n; back++) {
      final c = b[n - back];
      if (c & 0xC0 == 0x80) continue; // byte lanjutan → cari pembukanya
      final need = c >= 0xF0 && c <= 0xF4
          ? 4
          : c >= 0xE0
              ? 3
              : c >= 0xC2 && c < 0xE0
                  ? 2
                  : 1;
      // Pembuka multi-byte yang lanjutannya belum cukup → tahan.
      return (need > 1 && back < need) ? back : 0;
    }
    return 0;
  }
}

// ───────────────────────── Layout parsing ──────────────────────────

/// Arah pembagian dalam sebuah node layout tmux.
enum TmuxSplitDir { leftRight, topBottom }

/// Satu node dalam pohon layout tmux. Daun memiliki [paneId]; node bercabang
/// memiliki [dir] + [children].
class TmuxLayoutNode {
  TmuxLayoutNode({
    required this.width,
    required this.height,
    required this.x,
    required this.y,
    this.paneId,
    this.dir,
    this.children = const [],
  });

  final int width;
  final int height;
  final int x;
  final int y;

  /// Id panel bila ini daun; null bila node bercabang.
  final int? paneId;

  /// Arah split bila bercabang; null bila daun.
  final TmuxSplitDir? dir;
  final List<TmuxLayoutNode> children;

  bool get isLeaf => paneId != null;

  /// Semua id panel di bawah node ini (urut kiri→kanan / atas→bawah).
  List<int> get paneIds {
    if (isLeaf) return [paneId!];
    return [for (final c in children) ...c.paneIds];
  }
}

/// Parse string layout tmux (mis. `bc62,80x24,0,0,0` atau dengan split
/// `..{40x24,0,0,1,39x24,41,0,2}`). Mengembalikan null bila malformed.
///
/// Format: `<checksum>,<node>` di mana node = `WxH,X,Y` diikuti salah satu:
///  - `,<pane-id>`        → daun,
///  - `{child,child,...}` → split kiri-kanan,
///  - `[child,child,...]` → split atas-bawah.
TmuxLayoutNode? parseTmuxLayout(String layout) {
  var s = layout.trim();
  final comma = s.indexOf(',');
  if (comma < 0) return null;
  // Buang checksum di depan (4 hex). Bila bagian pertama bukan checksum (sudah
  // berupa WxH), jangan buang.
  final head = s.substring(0, comma);
  if (RegExp(r'^[0-9a-fA-F]{4}$').hasMatch(head)) {
    s = s.substring(comma + 1);
  }
  final parser = _LayoutParser(s);
  final node = parser._node();
  if (node == null || !parser._atEnd) return node; // toleran sisa
  return node;
}

class _LayoutParser {
  _LayoutParser(this._s);
  final String _s;
  int _i = 0;

  bool get _atEnd => _i >= _s.length;
  String? get _peek => _atEnd ? null : _s[_i];

  TmuxLayoutNode? _node() {
    final w = _int('x');
    if (w == null) return null;
    _expect('x');
    final h = _int(',');
    if (h == null) return null;
    _expect(',');
    final x = _int(',');
    if (x == null) return null;
    _expect(',');
    final y = _int2(); // diikuti ',' (daun) atau '{'/'[' (cabang) atau akhir
    if (y == null) return null;

    final p = _peek;
    if (p == '{' || p == '[') {
      final dir = p == '{' ? TmuxSplitDir.leftRight : TmuxSplitDir.topBottom;
      final close = p == '{' ? '}' : ']';
      _i++; // lewati pembuka
      final children = <TmuxLayoutNode>[];
      while (true) {
        final c = _node();
        if (c == null) return null;
        children.add(c);
        if (_peek == ',') {
          _i++;
          continue;
        }
        break;
      }
      if (_peek != close) return null;
      _i++; // lewati penutup
      return TmuxLayoutNode(
        width: w,
        height: h,
        x: x,
        y: y,
        dir: dir,
        children: children,
      );
    }

    // Daun: ',' lalu pane-id.
    if (_peek == ',') {
      _i++;
      final pane = _int2();
      if (pane == null) return null;
      return TmuxLayoutNode(
          width: w, height: h, x: x, y: y, paneId: pane);
    }

    // Tanpa pane-id eksplisit (jarang) — anggap daun tanpa id.
    return TmuxLayoutNode(width: w, height: h, x: x, y: y, paneId: -1);
  }

  // Baca integer sampai bertemu [terminator]; tidak mengonsumsi terminator.
  int? _int(String terminator) {
    final startIdx = _i;
    while (!_atEnd && _s[_i] != terminator) {
      _i++;
    }
    return int.tryParse(_s.substring(startIdx, _i));
  }

  // Baca integer sampai bertemu salah satu pemisah struktural atau akhir.
  int? _int2() {
    final startIdx = _i;
    while (!_atEnd && !',{}[]'.contains(_s[_i])) {
      _i++;
    }
    return int.tryParse(_s.substring(startIdx, _i));
  }

  void _expect(String ch) {
    if (_peek == ch) _i++;
  }
}

// ───────────────────── Ukuran klien & isi awal panel ─────────────────────

/// Ukuran klien control mode dalam sel karakter.
class TmuxGridSize {
  const TmuxGridSize(this.cols, this.rows);
  final int cols;
  final int rows;

  @override
  bool operator ==(Object other) =>
      other is TmuxGridSize && other.cols == cols && other.rows == rows;

  @override
  int get hashCode => Object.hash(cols, rows);

  @override
  String toString() => '${cols}x$rows';
}

/// Hitung berapa kolom × baris yang muat pada area [width]×[height] piksel
/// untuk sel berukuran [cellWidth]×[cellHeight]. Mengembalikan null bila
/// masukan belum valid (mis. layout belum punya ukuran) — pemanggil cukup
/// melewatkan pengiriman. Hasil dijepit ke rentang yang wajar untuk tmux.
TmuxGridSize? computeTmuxGrid({
  required double width,
  required double height,
  required double cellWidth,
  required double cellHeight,
}) {
  if (!width.isFinite || !height.isFinite) return null;
  if (cellWidth <= 0 || cellHeight <= 0) return null;
  final cols = (width / cellWidth).floor();
  final rows = (height / cellHeight).floor();
  if (cols < 2 || rows < 2) return null;
  return TmuxGridSize(cols.clamp(20, 500), rows.clamp(5, 300));
}

/// Perintah control mode untuk memberi tahu tmux ukuran klien. Bentuk
/// `lebar,tinggi` dipakai karena diterima tmux lama (2.x) maupun baru.
String tmuxClientSizeCommand(TmuxGridSize size) =>
    'refresh-client -C ${size.cols},${size.rows}';

/// Perintah mengambil isi layar panel yang sudah ada (dengan escape warna,
/// `-e`) agar tampil saat kita baru attach ke sesi yang sedang berjalan.
String tmuxCapturePaneCommand(int paneId) => 'capture-pane -p -e -t %$paneId';

/// Perintah menanyakan posisi kursor panel (0-based) → balasan `x,y`.
String tmuxCursorQueryCommand(int paneId) =>
    "display-message -p -t %$paneId '#{cursor_x},#{cursor_y}'";

/// Urai balasan [tmuxCursorQueryCommand] (`x,y`, 0-based). null bila tak valid.
({int x, int y})? parseTmuxCursor(List<String> lines) {
  for (final raw in lines) {
    final parts = raw.trim().split(',');
    if (parts.length != 2) continue;
    final x = int.tryParse(parts[0]);
    final y = int.tryParse(parts[1]);
    if (x == null || y == null || x < 0 || y < 0) continue;
    return (x: x, y: y);
  }
  return null;
}

/// Ubah hasil `capture-pane` menjadi urutan byte terminal: bersihkan layar,
/// tulis tiap baris, lalu (bila diketahui) kembalikan kursor ke posisinya.
/// Baris kosong di akhir dibuang supaya layar tidak tergulir sia-sia.
String buildTmuxCaptureWrite(List<String> lines, {({int x, int y})? cursor}) {
  var end = lines.length;
  while (end > 0 && lines[end - 1].trim().isEmpty) {
    end--;
  }
  final sb = StringBuffer('\x1b[0m\x1b[H\x1b[2J');
  for (var i = 0; i < end; i++) {
    if (i > 0) sb.write('\r\n');
    sb.write(lines[i]);
  }
  sb.write('\x1b[0m');
  if (cursor != null) {
    sb.write('\x1b[${cursor.y + 1};${cursor.x + 1}H');
  }
  return sb.toString();
}
