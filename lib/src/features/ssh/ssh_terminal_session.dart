import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:xterm/xterm.dart';

import '../../models/ssh_credentials.dart';
import '../../session/terminal_session.dart';

/// Sesi terminal SSH: membuka koneksi ke server remote dengan [dartssh2]
/// (SSH murni Dart, tanpa binary eksternal) dan menyalurkan shell-nya ke
/// [Terminal] xterm.
class SshTerminalSession implements TerminalSession {
  SshTerminalSession(this.credentials);

  final SshCredentials credentials;

  @override
  final Terminal terminal = Terminal(maxLines: 10000);

  SSHClient? _client;
  SSHSession? _session;

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
      _status('Menghubungkan ke ${credentials.host}:${credentials.port} …');

      final socket = await SSHSocket.connect(
        credentials.host,
        credentials.port,
        timeout: const Duration(seconds: 10),
      );

      // Siapkan identitas key bila metode autentikasi memakai SSH key.
      final identities = credentials.usesKey
          ? SSHKeyPair.fromPem(
              credentials.privateKey!,
              credentials.passphrase,
            )
          : null;

      final client = SSHClient(
        socket,
        username: credentials.username,
        identities: identities,
        onPasswordRequest:
            credentials.usesKey ? null : () => credentials.password,
      );
      _client = client;

      final session = await client.shell(
        pty: SSHPtyConfig(
          width: terminal.viewWidth > 0 ? terminal.viewWidth : 80,
          height: terminal.viewHeight > 0 ? terminal.viewHeight : 25,
        ),
      );
      _session = session;

      // terminal -> server
      terminal.onOutput =
          (data) => session.write(Uint8List.fromList(utf8.encode(data)));
      terminal.onResize =
          (width, height, pw, ph) => session.resizeTerminal(width, height);

      // server -> terminal (stdout & stderr)
      session.stdout
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(terminal.write);
      session.stderr
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(terminal.write);

      _status('Terhubung ✓', ansi: 32); // hijau

      await session.done;
      _status('Koneksi ditutup.');
    } catch (e) {
      _error(_friendlyError(e));
    }
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
      return 'Autentikasi gagal — periksa username & password.';
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
    _client?.close();
    _session = null;
    _client = null;
  }
}
