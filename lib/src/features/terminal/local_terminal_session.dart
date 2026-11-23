import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
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

  /// Shell lokal selalu "tersambung" (berjalan di mesin ini, tanpa jaringan).
  final ValueNotifier<bool> _connected = ValueNotifier(true);

  @override
  ValueListenable<bool> get connected => _connected;

  /// Keran input synchronized-input (di-set oleh split pane).
  void Function(String data)? _onUserInput;

  @override
  set onUserInput(void Function(String data)? cb) => _onUserInput = cb;

  @override
  void writeInput(String data) {
    if (data.isEmpty) return;
    _pty?.write(const Utf8Encoder().convert(data));
  }

  @override
  bool get isLocal => true;

  @override
  String get title => 'Local';

  @override
  void start() {
    // PENTING: shell TIDAK diluncurkan di sini. Pada saat start() dipanggil
    // (ketika tab dibuat), [TerminalView] belum di-layout sehingga ukuran
    // sebenarnya belum diketahui — [Terminal] masih memakai default 80×24.
    // Kalau shell diluncurkan dengan ukuran itu lalu diubah belakangan, zsh
    // sudah terlanjur mencetak prompt pertamanya memakai lebar yang salah,
    // dan penanda akhir-baris "%" (PROMPT_EOL_MARK) tak ikut terhapus →
    // tersisa sebagai "%" terbalik di pojok kiri atas.
    //
    // Solusi: tunda peluncuran sampai onResize pertama dari layout memberi
    // ukuran nyata, sehingga zsh memakai lebar yang benar sejak prompt
    // pertama. `Terminal.resize()` selalu memanggil onResize (tanpa guard),
    // jadi callback ini dijamin terpicu saat view di-layout.
    terminal.onResize = _handleResize;
  }

  void _handleResize(int width, int height, int pixelWidth, int pixelHeight) {
    final pty = _pty;
    if (pty == null) {
      _spawn(width, height);
    } else {
      pty.resize(height, width);
    }
  }

  void _spawn(int columns, int rows) {
    final pty = Pty.start(
      _resolveShell(),
      columns: columns,
      rows: rows,
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

    // terminal -> shell (sambil menyalurkan ke keran synchronized-input)
    terminal.onOutput = (data) {
      _onUserInput?.call(data);
      pty.write(const Utf8Encoder().convert(data));
    };

    pty.exitCode.then((code) {
      terminal.write('\r\n\x1b[90m[sesi berakhir — kode $code]\x1b[0m\r\n');
    });
  }

  @override
  void dispose() {
    _pty?.kill();
    _pty = null;
    _connected.value = false;
    _connected.dispose();
  }

  static String _resolveShell() {
    if (Platform.isWindows) {
      return Platform.environment['COMSPEC'] ?? r'C:\Windows\System32\cmd.exe';
    }
    return Platform.environment['SHELL'] ?? '/bin/zsh';
  }
}
