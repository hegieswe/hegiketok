import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:material_ui/material_ui.dart';
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
  SshTerminalSession(this.credentials);

  final SshCredentials credentials;

  @override
  final Terminal terminal = Terminal(maxLines: 10000);

  /// Progres koneksi (ditampilkan oleh UI sebagai handshake stepper).
  final ConnectionProgress progress = ConnectionProgress();

  /// Saran port yang terdeteksi dari output (belum ditindak pengguna).
  final ValueNotifier<List<PortSuggestion>> suggestions = ValueNotifier([]);

  /// Manajer port-forward aktif; tersedia setelah terhubung.
  PortForwardManager? forwards;

  SshConnection? _conn;
  SSHSession? _session;
  final Set<int> _handledPorts = {};

  @override
  bool get isLocal => false;

  @override
  String get title => credentials.label;

  @override
  void start() {
    _connect();
  }

  Future<void> _connect() async {
    try {
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

      // terminal -> server
      terminal.onOutput =
          (data) => session.write(Uint8List.fromList(utf8.encode(data)));
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

      await session.done;
      _status('Koneksi ditutup.');
    } catch (e) {
      _error(_friendlyError(e));
    }
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
    _session?.close();
    forwards?.dispose();
    _conn?.close();
    suggestions.dispose();
    progress.dispose();
    _session = null;
    _conn = null;
  }
}
