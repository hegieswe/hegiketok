import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';

import '../models/ssh_credentials.dart';
import 'connection_progress.dart';
import 'ssh_connector.dart';
import 'ssh_errors.dart';
import 'tmux_control.dart';

/// Satu jendela tmux (ditampilkan sebagai tab di dalam view control-mode).
class TmuxWindowState {
  TmuxWindowState(this.id, this.name, this.layout);
  final int id;
  String name;

  /// String layout tmux terakhir (menentukan susunan panel).
  String? layout;

  /// Pohon layout hasil parse (null bila belum ada/invalid).
  TmuxLayoutNode? get tree =>
      layout == null ? null : parseTmuxLayout(layout!);
}

/// Satu panel tmux — memiliki [Terminal] xterm sendiri yang diisi dari
/// notifikasi `%output`.
class TmuxPaneState {
  TmuxPaneState(this.id) : terminal = Terminal(maxLines: 10000);
  final int id;
  final Terminal terminal;

  /// Tahap pengambilan isi awal panel saat attach.
  _CaptureStage _stage = _CaptureStage.done;

  /// Hasil `capture-pane` (menunggu posisi kursor sebelum ditulis).
  List<String>? _captured;

  /// `%output` yang datang SETELAH capture tapi sebelum kursor diketahui.
  final StringBuffer _held = StringBuffer();

  /// Dekoder UTF-8 bertahap untuk keluaran panel ini.
  final Utf8Carry _utf8 = Utf8Carry();
}

/// Tahap isi awal panel:
/// - [waitingCapture]: `%output` yang tiba sekarang sudah termasuk dalam hasil
///   capture → dibuang agar tidak dobel.
/// - [waitingCursor]: capture sudah diterima; `%output` baru ditahan dulu.
/// - [done]: `%output` langsung ditulis ke terminal.
enum _CaptureStage { waitingCapture, waitingCursor, done }

enum _ReplyKind { other, listWindows, capture, cursor }

class _Pending {
  const _Pending(this.kind, [this.paneId]);
  final _ReplyKind kind;
  final int? paneId;
}

/// Fungsi pembuka koneksi untuk [TmuxControlClient].
typedef TmuxConnect = Future<SshConnection> Function(
    SshCredentials credentials, ConnectionProgress progress);

/// Klien **tmux control mode** (`tmux -CC`) di atas satu koneksi SSH.
///
/// EKSPERIMENTAL: menerjemahkan jendela/panel tmux remote menjadi tab & split
/// native HegiKetok (seperti iTerm2 `-CC`), sekaligus memberi persistensi sesi
/// tmux. Butuh tmux terpasang di server.
class TmuxControlClient extends ChangeNotifier {
  TmuxControlClient(
    this.credentials, {
    this.label,
    String? sessionName,
    TmuxConnect? connect,
  })  : sessionName = sessionName ?? 'hegi',
        _connect = connect ?? _defaultConnect,
        _testSink = null;

  /// Klien tanpa SSH untuk pengujian: perintah yang dikirim ditulis ke [sink],
  /// dan keluaran tmux disuapkan lewat [debugFeed].
  @visibleForTesting
  TmuxControlClient.forTest(
    this.credentials,
    void Function(String data) sink, {
    this.label,
    String? sessionName,
  })  : sessionName = sessionName ?? 'hegi',
        _connect = _defaultConnect,
        _testSink = sink {
    _setConnected(true);
  }

  final void Function(String data)? _testSink;

  /// Pembuka koneksi SSH (bisa diganti pengujian integrasi).
  final TmuxConnect _connect;

  static Future<SshConnection> _defaultConnect(
          SshCredentials creds, ConnectionProgress progress) =>
      connectSsh(creds, progress: progress);

  bool get _canSend => _shell != null || _testSink != null;

  /// Suapkan teks mentah seolah datang dari tmux (khusus pengujian).
  @visibleForTesting
  void debugFeed(String chunk) =>
      _onData(const Latin1Decoder().convert(utf8.encode(chunk)));

  final SshCredentials credentials;
  final String? label;
  final String sessionName;

  final ConnectionProgress progress = ConnectionProgress();
  final TmuxControlParser _parser = TmuxControlParser();

  final Map<int, TmuxWindowState> windows = {};
  final List<int> windowOrder = [];
  final Map<int, TmuxPaneState> panes = {};
  int? activeWindow;

  /// Error fatal (koneksi gagal / tmux keluar). null = sehat.
  String? error;

  /// Petunjuk lunak (mis. tmux belum merespons) — tidak fatal.
  String? hint;

  bool _connected = false;
  bool get connected => _connected;

  /// Status koneksi langsung (untuk badge online/offline host).
  final ValueNotifier<bool> online = ValueNotifier(false);

  void _setConnected(bool v) {
    _connected = v;
    online.value = v;
  }

  bool _disposed = false;

  SshConnection? _conn;
  SSHSession? _shell;
  final Queue<_Pending> _pending = Queue<_Pending>();
  Timer? _bootstrapTimer;

  // Ukuran klien (sel) yang diinginkan UI vs yang terakhir dikirim ke tmux.
  TmuxGridSize? _wantedSize;
  TmuxGridSize? _sentSize;
  Timer? _resizeDebounce;

  /// Ukuran klien terakhir yang dikirim ke tmux (untuk diagnosa/tes).
  @visibleForTesting
  TmuxGridSize? get sentSize => _sentSize;

  static const _fmt =
      r"list-windows -F '#{window_id} #{window_layout} #{window_name}'";

  void start() => unawaited(_run());

  Future<void> _run() async {
    try {
      progress.reset();
      final conn = await _connect(credentials, progress);
      if (_disposed) {
        conn.close();
        return;
      }
      _conn = conn;
      final shell = await conn.client.shell(
        pty: const SSHPtyConfig(width: 220, height: 50),
      );
      _shell = shell;
      progress.finish();

      // Dibaca sebagai byte (latin1 = satu unit kode per byte): data panel
      // bisa terpotong di tengah karakter UTF-8, jadi decoding dilakukan
      // per panel (lihat [Utf8Carry]), bukan pada aliran gabungan.
      shell.stdout
          .cast<List<int>>()
          .transform(const Latin1Decoder(allowInvalid: true))
          .listen(_onData, onDone: _onClosed);

      // Masuk control mode (attach-or-create sesi stabil).
      _write('tmux -CC new-session -A -s $sessionName\n');
      _setConnected(true);
      _safeNotify();

      // Bootstrap dipicu oleh blok pembuka control mode (lihat [_onReply]).
      // Cadangan: bila blok itu tak kunjung datang, mulai sendiri.
      Future<void>.delayed(const Duration(milliseconds: 1500), _bootstrap);
      _bootstrapTimer = Timer(const Duration(seconds: 3), () {
        if (windows.isEmpty && !_disposed) {
          _queryWindows();
          hint = 'Menunggu tmux… pastikan tmux terpasang di server.';
          _safeNotify();
        }
      });
    } catch (e) {
      error = describeSshError(e, credentials: credentials).full;
      _setConnected(false);
      _safeNotify();
    }
  }

  bool _bootstrapped = false;

  /// Langkah awal setelah control mode aktif: kirim ukuran klien (bila UI
  /// sudah mengukur) lalu minta daftar jendela + layout. Idempoten.
  void _bootstrap() {
    if (_disposed || _bootstrapped) return;
    _bootstrapped = true;
    _flushClientSize();
    _queryWindows();
  }

  void _queryWindows() {
    if (_disposed) return;
    _send(_fmt, kind: _ReplyKind.listWindows);
  }

  // ───────────────────── Event handling ──────────────────────

  void _onData(String chunk) {
    for (final ev in _parser.feed(chunk)) {
      _handle(ev);
    }
  }

  void _handle(TmuxEvent ev) {
    switch (ev) {
      case TmuxOutput o:
        _onPaneOutput(o);
      case TmuxCommandReply r:
        _onReply(r);
      case TmuxLayoutChange l:
        _ingestLayout(l.windowId, l.layout);
        _prunePanes();
        _safeNotify();
      case TmuxWindowAdd _:
        _queryWindows();
      case TmuxWindowClose c:
        windows.remove(c.windowId);
        windowOrder.remove(c.windowId);
        if (activeWindow == c.windowId) {
          activeWindow = windowOrder.isEmpty ? null : windowOrder.first;
        }
        _prunePanes();
        _safeNotify();
      case TmuxWindowRenamed rn:
        windows[rn.windowId]?.name = rn.name;
        _safeNotify();
      case TmuxWindowPaneChanged _:
        break;
      case TmuxSessionChanged _:
        break;
      case TmuxExit e:
        error = e.reason == null ? 'tmux keluar' : 'tmux keluar: ${e.reason}';
        _setConnected(false);
        _safeNotify();
      case TmuxUnknown _:
        break;
    }
  }

  void _onPaneOutput(TmuxOutput o) {
    final pane = panes[o.paneId];
    if (pane == null) return;
    if (pane._stage == _CaptureStage.waitingCapture) {
      // Sudah tercakup dalam hasil capture-pane yang sedang ditunggu.
      return;
    }
    final text = pane._utf8.add(o.bytes);
    if (text.isEmpty) return; // baru separuh karakter multi-byte
    if (pane._stage == _CaptureStage.waitingCursor) {
      pane._held.write(text);
    } else {
      pane.terminal.write(text);
    }
  }

  void _onReply(TmuxCommandReply r) {
    // Blok yang bukan balasan perintah kita (mis. blok pembuka control mode)
    // tidak boleh menggeser antrean korelasi.
    if (!r.fromClient) {
      _bootstrap();
      return;
    }
    // tmux membuka control mode dengan satu blok %begin/%end untuk perintah
    // awal (`new-session`). Itu penanda "siap" — bukan balasan antrean kita.
    if (!_bootstrapped) {
      _bootstrap();
      return;
    }
    final p = _pending.isNotEmpty
        ? _pending.removeFirst()
        : const _Pending(_ReplyKind.other);
    switch (p.kind) {
      case _ReplyKind.listWindows:
        if (!r.error) _ingestWindows(r.lines);
      case _ReplyKind.capture:
        final pane = panes[p.paneId];
        if (pane == null) return;
        pane._captured = r.error ? null : r.lines;
        pane._stage = _CaptureStage.waitingCursor;
      case _ReplyKind.cursor:
        final pane = panes[p.paneId];
        if (pane == null) return;
        _finishCapture(pane, r.error ? null : parseTmuxCursor(r.lines));
      case _ReplyKind.other:
        break;
    }
  }

  /// Tulis isi awal panel (bila ada) lalu lepaskan `%output` yang ditahan.
  void _finishCapture(TmuxPaneState pane, ({int x, int y})? cursor) {
    final captured = pane._captured;
    pane._captured = null;
    if (captured != null && captured.any((l) => l.trim().isNotEmpty)) {
      pane.terminal.write(buildTmuxCaptureWrite(captured, cursor: cursor));
    }
    if (pane._held.isNotEmpty) {
      pane.terminal.write(pane._held.toString());
      pane._held.clear();
    }
    pane._stage = _CaptureStage.done;
  }

  void _ingestWindows(List<String> lines) {
    hint = null;
    for (final line in lines) {
      final t = line.trim();
      if (!t.startsWith('@')) continue;
      final firstSp = t.indexOf(' ');
      if (firstSp < 0) continue;
      final idTok = t.substring(0, firstSp);
      final rest = t.substring(firstSp + 1);
      final secondSp = rest.indexOf(' ');
      final layout = secondSp < 0 ? rest : rest.substring(0, secondSp);
      final name = secondSp < 0 ? '' : rest.substring(secondSp + 1);
      final id = int.tryParse(idTok.substring(1));
      if (id == null) continue;

      final w = windows.putIfAbsent(id, () {
        windowOrder.add(id);
        return TmuxWindowState(id, name.isEmpty ? 'win$id' : name, null);
      });
      if (name.isNotEmpty) w.name = name;
      _ingestLayout(id, layout);
    }
    activeWindow ??= windowOrder.isEmpty ? null : windowOrder.first;
    _prunePanes();
    _safeNotify();
  }

  void _ingestLayout(int windowId, String layout) {
    final w = windows.putIfAbsent(windowId, () {
      windowOrder.add(windowId);
      return TmuxWindowState(windowId, 'win$windowId', null);
    });
    w.layout = layout;
    final tree = parseTmuxLayout(layout);
    if (tree != null) _syncPanes(tree);
  }

  /// Pastikan tiap panel daun punya terminal dan berukuran sama dengan yang
  /// ditetapkan tmux (agar pembungkusan baris identik dengan di server).
  void _syncPanes(TmuxLayoutNode node) {
    if (node.isLeaf) {
      final id = node.paneId;
      if (id == null || id < 0) return;
      final pane = _ensurePane(id);
      final t = pane.terminal;
      if (node.width > 0 &&
          node.height > 0 &&
          (t.viewWidth != node.width || t.viewHeight != node.height)) {
        t.resize(node.width, node.height);
      }
      return;
    }
    for (final c in node.children) {
      _syncPanes(c);
    }
  }

  TmuxPaneState _ensurePane(int paneId) {
    return panes.putIfAbsent(paneId, () {
      final pane = TmuxPaneState(paneId);
      // Ketikan panel → kirim ke tmux via send-keys (hex, aman untuk semua byte).
      pane.terminal.onOutput = (data) => _sendKeys(paneId, data);
      // Isi awal: ambil layar panel yang sudah berjalan + posisi kursornya.
      // (Tanpa shell perintahnya tak terkirim → jangan menahan output.)
      if (!_canSend) return pane;
      pane._stage = _CaptureStage.waitingCapture;
      _send(tmuxCapturePaneCommand(paneId),
          kind: _ReplyKind.capture, paneId: paneId);
      _send(tmuxCursorQueryCommand(paneId),
          kind: _ReplyKind.cursor, paneId: paneId);
      return pane;
    });
  }

  /// Buang state panel yang sudah tidak ada di layout jendela mana pun.
  void _prunePanes() {
    final alive = <int>{};
    for (final w in windows.values) {
      final tree = w.tree;
      if (tree != null) alive.addAll(tree.paneIds);
    }
    // Belum ada layout sama sekali → jangan buang apa pun.
    if (alive.isEmpty) return;
    panes.removeWhere((id, _) => !alive.contains(id));
  }

  // ───────────────────── Ukuran klien ──────────────────────

  /// Beri tahu tmux ukuran area tampilan (dalam sel). Dipanggil UI tiap kali
  /// ukuran berubah; pengiriman di-debounce agar seret-ubah-ukuran jendela
  /// tidak membanjiri server.
  void setClientSize(TmuxGridSize size) {
    if (_disposed || size == _wantedSize) return;
    _wantedSize = size;
    _resizeDebounce?.cancel();
    _resizeDebounce =
        Timer(const Duration(milliseconds: 140), _flushClientSize);
  }

  void _flushClientSize() {
    final size = _wantedSize;
    if (_disposed || size == null || size == _sentSize) return;
    // Sebelum control mode siap, jangan kirim: balasannya akan tertukar dengan
    // blok pembuka. [_bootstrap] memanggil ulang fungsi ini begitu siap.
    if (!_canSend || !_bootstrapped) return;
    _sentSize = size;
    _send(tmuxClientSizeCommand(size));
  }

  // ───────────────────── Output & input ──────────────────────

  void _sendKeys(int paneId, String data) {
    if (data.isEmpty) return;
    final hex = utf8
        .encode(data)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(' ');
    _send('send-keys -t %$paneId -H $hex');
  }

  /// Pilih jendela tmux aktif (dipakai dari UI) + beri tahu pendengar.
  void setActiveWindow(int id) {
    if (!windows.containsKey(id)) return;
    activeWindow = id;
    _safeNotify();
  }

  /// Buat jendela tmux baru (akan muncul sebagai tab baru).
  void newWindow() => _send('new-window');

  /// Pecah panel aktif (butuh id panel; dipakai dari UI).
  void splitPane(int paneId, {required bool horizontal}) =>
      _send('split-window ${horizontal ? '-h' : '-v'} -t %$paneId');

  /// Kirim perintah tmux (control mode) + catat urutan untuk korelasi balasan.
  /// Tidak mengantre apa pun bila shell belum/tidak tersedia — kalau tidak,
  /// antrean akan bergeser dan balasan berikutnya salah alamat.
  void _send(String command,
      {_ReplyKind kind = _ReplyKind.other, int? paneId}) {
    if (!_canSend) return;
    _pending.add(_Pending(kind, paneId));
    _write('$command\n');
  }

  void _write(String data) {
    final sink = _testSink;
    if (sink != null) {
      sink(data);
      return;
    }
    final s = _shell;
    if (s == null) return;
    s.write(Uint8List.fromList(utf8.encode(data)));
  }

  void _onClosed() {
    if (_disposed) return;
    _setConnected(false);
    error ??= 'Koneksi tmux tertutup.';
    _safeNotify();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _bootstrapTimer?.cancel();
    _resizeDebounce?.cancel();
    try {
      // Detach control client dengan sopan (program tetap hidup di server).
      _shell?.close();
    } catch (_) {}
    _conn?.close();
    progress.dispose();
    online.dispose();
    super.dispose();
  }
}
