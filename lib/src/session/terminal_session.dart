import 'package:flutter/foundation.dart';
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

  /// Status koneksi LANGSUNG (live): true bila sesi benar-benar tersambung
  /// saat ini, false saat sedang menyambung, gagal, atau sudah terputus.
  /// Dipakai indikator online/offline host — jadi hijau hanya saat koneksi
  /// nyata, bukan sekadar tab terbuka.
  ValueListenable<bool> get connected;

  /// Mulai sesi (spawn shell / buka koneksi).
  void start();

  /// Tulis input MENTAH (byte ketikan) langsung ke shell/sesi — tanpa menambah
  /// newline. Dipakai mode synchronized-input untuk menyalurkan ketikan ke
  /// sesi lain. Aman dipanggil walau sesi belum/ tak lagi tersambung (no-op).
  void writeInput(String data);

  /// Pasang "keran" input: callback yang dipanggil tiap PENGGUNA mengetik di
  /// sesi ini (bukan saat [writeInput] dari luar). Dipakai split-pane untuk
  /// broadcast ke pane lain. null = nonaktif.
  set onUserInput(void Function(String data)? cb);

  /// Hentikan sesi dan lepaskan sumber daya.
  void dispose();
}
