import 'package:xterm/xterm.dart';

/// Kontrak umum untuk satu sesi terminal — baik shell LOKAL maupun SSH remote.
///
/// Dengan antarmuka yang sama, lapisan UI (tab workspace) tidak perlu peduli
/// apakah sebuah tab menjalankan shell lokal atau koneksi SSH.
abstract class TerminalSession {
  /// Buffer & state terminal (dari paket xterm) yang ditampilkan widget.
  Terminal get terminal;

  /// Label untuk tab, mis. "Local" atau "user@host".
  String get title;

  /// true bila ini shell lokal; false bila koneksi SSH.
  bool get isLocal;

  /// Mulai sesi (spawn shell / buka koneksi).
  void start();

  /// Hentikan sesi dan lepaskan sumber daya.
  void dispose();
}
