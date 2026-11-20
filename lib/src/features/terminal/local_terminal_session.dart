import 'dart:convert';
import 'dart:io';

import 'package:flutter_pty/flutter_pty.dart';
import 'package:xterm/xterm.dart';

import '../../session/terminal_session.dart';

/// Sesi terminal LOKAL: menjalankan shell asli pengguna (zsh/bash di
/// macOS/Linux, cmd di Windows) dan menyambungkannya ke [Terminal] xterm.
///
/// Fondasi "local-first": berjalan di mesin pengguna, tanpa server.
class LocalTerminalSession implements TerminalSession {
  @override
  final Terminal terminal = Terminal(maxLines: 10000);

  Pty? _pty;

  @override
  bool get isLocal => true;

  @override
  String get title => 'Local';

  @override
  void start() {
    final pty = Pty.start(
      _resolveShell(),
      columns: terminal.viewWidth > 0 ? terminal.viewWidth : 80,
      rows: terminal.viewHeight > 0 ? terminal.viewHeight : 25,
      environment: {
        ...Platform.environment,
        'TERM': 'xterm-256color',
      },
    );
    _pty = pty;

    // shell -> terminal
    pty.output
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(terminal.write);

    // terminal -> shell
    terminal.onOutput = (data) => pty.write(const Utf8Encoder().convert(data));

    // resize jendela -> beri tahu shell
    terminal.onResize = (width, height, pixelWidth, pixelHeight) =>
        pty.resize(height, width);

    pty.exitCode.then((code) {
      terminal.write('\r\n\x1b[90m[sesi berakhir — kode $code]\x1b[0m\r\n');
    });
  }

  @override
  void dispose() {
    _pty?.kill();
    _pty = null;
  }

  static String _resolveShell() {
    if (Platform.isWindows) {
      return Platform.environment['COMSPEC'] ?? r'C:\Windows\System32\cmd.exe';
    }
    return Platform.environment['SHELL'] ?? '/bin/zsh';
  }
}
