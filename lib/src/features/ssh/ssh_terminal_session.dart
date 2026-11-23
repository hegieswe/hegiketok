import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';

import '../../models/ssh_credentials.dart';
import '../../session/terminal_session.dart';
import '../../ssh/connection_progress.dart';
import '../../ssh/port_forward.dart';
import '../../ssh/ssh_connector.dart';

/// Sesi terminal SSH: membuka koneksi ke server remote dengan [dartssh2]
/// (SSH murni Dart, tanpa binary eksternal) dan menyalurkan shell-nya ke
/// [Terminal] xterm.
///
/// Juga menyediakan:
/// - progres handshake berlangkah ([progress]),
/// - jump-host/bastion (lewat [SshCredentials.jumpHosts]),
/// - deteksi port listening dari output + manajemen port-forward ([forwards]).
class SshTerminalSession implements TerminalSession {
  SshTerminalSession(
    this.credentials, {
    this.label,
    this.startupCommand,
    this.persistent = false,
  });

  final SshCredentials credentials;

  /// Nama tampilan tab — biasanya label host tersimpan agar dua koneksi ke
  /// alamat yang sama (mis. lewat bastion berbeda) tetap bisa dibedakan.
  final String? label;

  /// Perintah yang dijalankan otomatis setiap kali shell terbuka (startup
  /// snippet). Kosong/null = tidak ada.
  final String? startupCommand;

  /// Bungkus sesi dengan tmux agar tahan putus (ala tmux `new-session -A`):
  /// program tetap hidup di server, sambung-ulang MELANJUTKAN sesi yang sama.
  final bool persistent;

  /// Keran input synchronized-input (di-set oleh split pane).
  void Function(String data)? _onUserInput;

  @override
  set onUserInput(void Function(String data)? cb) => _onUserInput = cb;

  /// Nama sesi tmux yang stabil per host (hanya karakter aman untuk tmux).
  String get _tmuxName => persistentSessionName(label ?? credentials.label);

  @override
  final Terminal terminal = Terminal(maxLines: 10000);

  /// Progres koneksi (ditampilkan oleh UI sebagai handshake stepper).
  final ConnectionProgress progress = ConnectionProgress();

  /// Saran port yang terdeteksi dari output (belum ditindak pengguna).
  final ValueNotifier<List<PortSuggestion>> suggestions = ValueNotifier([]);

  /// Status koneksi langsung: true hanya saat shell benar-benar terbuka.
  /// Jadi false saat menyambung, gagal, atau terputus — menggerakkan tanda
  /// online/offline host.
  final ValueNotifier<bool> _connected = ValueNotifier(false);

  @override
  ValueListenable<bool> get connected => _connected;

  /// Manajer port-forward aktif; tersedia setelah terhubung.
  PortForwardManager? forwards;

  SshConnection? _conn;
  SSHSession? _session;
  final Set<int> _handledPorts = {};

  bool _disposed = false;
  bool _everConnected = false;
  static const int _maxReconnect = 6;

  @override
  bool get isLocal => false;

  @override
  String get title => label ?? credentials.label;

  @override
  void start() {
    _maintain();
  }

  /// Loop pemeliharaan koneksi: buka sesi, dan bila putus tak terduga, coba
  /// sambung ulang dengan backoff (sampai [_maxReconnect] kali). Kegagalan
  /// koneksi PERTAMA (mis. salah password) tidak di-loop — langsung lapor.
  Future<void> _maintain() async {
    var attempt = 0;
    while (!_disposed) {
      try {
        final established = await _runSession();
        if (_disposed) break;
        if (established) {
          attempt = 0; // sesi sempat hidup → reset hitungan untuk putus berikutnya
          _status('Koneksi terputus.', ansi: 33);
        }
      } catch (e) {
        if (_disposed) break;
        if (!_everConnected) {
          // Belum pernah berhasil → jangan coba terus (kemungkinan kredensial/alamat salah).
          _error(_friendlyError(e));
          break;
        }
        _status('Koneksi terputus: ${_friendlyError(e)}', ansi: 33);
      }

      _cleanupConn();
      if (_disposed) break;

      attempt++;
      if (attempt > _maxReconnect) {
        _error('Gagal menyambung ulang setelah $_maxReconnect percobaan. '
            'Tutup tab lalu buka lagi untuk mencoba manual.');
        break;
      }
      final secs = _backoffSeconds(attempt);
      _status('Menyambung ulang ($attempt/$_maxReconnect) dalam ${secs}s…',
          ansi: 33);
      await Future<void>.delayed(Duration(seconds: secs));
    }
  }

  /// Satu siklus koneksi. Mengembalikan true bila shell sempat terbuka
  /// (koneksi hidup), false tak akan terjadi — melempar bila gagal konek.
  Future<bool> _runSession() async {
    progress.reset();
    final conn = await connectSsh(credentials, progress: progress);
    _conn = conn;
    forwards = PortForwardManager(conn.client);

    final shellStep = progress.begin('Membuka shell');
    final session = await conn.client.shell(
      pty: SSHPtyConfig(
        width: terminal.viewWidth > 0 ? terminal.viewWidth : 80,
        height: terminal.viewHeight > 0 ? terminal.viewHeight : 25,
      ),
    );
    _session = session;
    progress.complete(shellStep);
    progress.finish();
    _everConnected = true;
    _connected.value = true; // shell terbuka → host ONLINE (hijau)

    // terminal -> server (sambil menyalurkan ke keran synchronized-input)
    terminal.onOutput = (data) {
      _onUserInput?.call(data);
      session.write(Uint8List.fromList(utf8.encode(data)));
    };
    terminal.onResize =
        (width, height, pw, ph) => session.resizeTerminal(width, height);

    // server -> terminal (stdout & stderr), sambil memindai saran port.
    session.stdout
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen((data) {
      terminal.write(data);
      _scan(data);
    });
    session.stderr
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen((data) {
      terminal.write(data);
      _scan(data);
    });

    // Sesi persisten: ganti shell dengan tmux bila tersedia (attach-or-create
    // ke sesi stabil). Tanpa tmux di server, perintah gagal dengan tenang dan
    // shell biasa tetap jalan — TIDAK memutus koneksi.
    if (persistent) {
      sendCommand(persistentSessionCommand(_tmuxName));
    }

    // Startup snippet: jalankan otomatis setelah shell siap (di dalam tmux
    // bila sesi persisten — beri jeda singkat agar tmux sempat attach).
    final startup = startupCommand?.trim();
    if (startup != null && startup.isNotEmpty) {
      if (persistent) {
        await Future<void>.delayed(const Duration(milliseconds: 450));
      }
      sendCommand(startup);
    }

    await session.done;
    return true;
  }

  /// Kirim perintah ke shell aktif. [run] true menambah newline (langsung
  /// dieksekusi); false hanya mengetik tanpa menjalankan.
  void sendCommand(String command, {bool run = true}) {
    final s = _session;
    if (s == null) return;
    final text = run ? '$command\n' : command;
    s.write(Uint8List.fromList(utf8.encode(text)));
  }

  @override
  void writeInput(String data) {
    final s = _session;
    if (s == null || data.isEmpty) return;
    s.write(Uint8List.fromList(utf8.encode(data)));
  }

  int _backoffSeconds(int attempt) {
    const steps = [1, 2, 4, 8, 15];
    return steps[(attempt - 1).clamp(0, steps.length - 1)];
  }

  /// Tutup sumber daya koneksi saat ini (sebelum menyambung ulang).
  void _cleanupConn() {
    _connected.value = false; // koneksi tak lagi hidup → host OFFLINE (merah)
    try {
      _session?.close();
    } catch (_) {}
    forwards?.dispose();
    try {
      _conn?.close();
    } catch (_) {}
    _session = null;
    _conn = null;
    forwards = null;
    suggestions.value = [];
    _handledPorts.clear();
  }

  /// Pindai output untuk pola "server listening di port X" dan tawarkan forward.
  void _scan(String chunk) {
    final mgr = forwards;
    if (mgr == null) return;
    for (final line in const LineSplitter().convert(chunk)) {
      final s = detectListeningPort(line);
      if (s == null) continue;
      if (_handledPorts.contains(s.port)) continue;
      if (mgr.isForwarded(s.port)) continue;
      if (suggestions.value.any((e) => e.port == s.port)) continue;
      suggestions.value = [...suggestions.value, s];
    }
  }

  /// Terima sebuah saran: mulai port-forward lokal.
  Future<String?> acceptSuggestion(PortSuggestion s) async {
    _handledPorts.add(s.port);
    dismissSuggestion(s);
    try {
      final fwd = await forwards!.start(s.port);
      _status('Port-forward aktif: ${fwd.label}', ansi: 32);
      return null;
    } catch (e) {
      return 'Gagal forward port ${s.port}: $e';
    }
  }

  /// Abaikan sebuah saran port (tanpa membuka forward).
  void dismissSuggestion(PortSuggestion s) {
    _handledPorts.add(s.port);
    suggestions.value =
        suggestions.value.where((e) => e.port != s.port).toList();
  }

  void _status(String msg, {int ansi = 90}) {
    terminal.write('\x1b[${ansi}m$msg\x1b[0m\r\n');
  }

  void _error(String msg) {
    terminal.write('\r\n\x1b[31m$msg\x1b[0m\r\n');
  }

  /// Ubah exception teknis jadi pesan yang mudah dipahami.
  String _friendlyError(Object e) {
    final text = e.toString().toLowerCase();
    if (text.contains('auth')) {
      return 'Autentikasi gagal — periksa username & kredensial.';
    }
    if (text.contains('refused')) {
      return 'Koneksi ditolak — pastikan server & port benar, serta SSH aktif.';
    }
    if (text.contains('timed out') || text.contains('timeout')) {
      return 'Koneksi timeout — server tidak merespons.';
    }
    if (text.contains('failed host lookup') || text.contains('nodename')) {
      return 'Host tidak ditemukan — periksa alamat server.';
    }
    return 'Gagal konek: $e';
  }

  @override
  void dispose() {
    _disposed = true; // hentikan loop reconnect
    _connected.value = false;
    _session?.close();
    forwards?.dispose();
    _conn?.close();
    suggestions.dispose();
    progress.dispose();
    _connected.dispose();
    _session = null;
    _conn = null;
  }
}

/// Nama sesi tmux yang stabil untuk sebuah host: `hegi-<label>` dengan hanya
/// huruf, angka, `_` dan `-` (aman untuk shell & tmux).
String persistentSessionName(String label) {
  final safe = label
      .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  return 'hegi-${safe.isEmpty ? 'session' : safe}';
}

/// Perintah yang membungkus shell dengan tmux (attach bila sesi sudah ada,
/// buat bila belum). Bila tmux tidak terpasang, perintah ini tidak melakukan
/// apa-apa dan shell biasa tetap dipakai.
String persistentSessionCommand(String sessionName) =>
    'command -v tmux >/dev/null 2>&1 && '
    'exec tmux new-session -A -s "$sessionName"';
