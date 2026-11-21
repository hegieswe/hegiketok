import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:material_ui/material_ui.dart';

/// Hasil deteksi "ada server yang listening di port X" dari output terminal.
class PortSuggestion {
  const PortSuggestion(this.port, this.raw);

  final int port;

  /// Baris output yang memicu deteksi (untuk ditampilkan ke pengguna).
  final String raw;
}

// Pola umum saat sebuah proses mengumumkan dirinya siap menerima koneksi.
final List<RegExp> _patterns = [
  // http://localhost:3000 · http://127.0.0.1:8080 · http://0.0.0.0:5173
  RegExp(r'https?://(?:localhost|127\.0\.0\.1|0\.0\.0\.0):(\d{2,5})'),
  // "Listening on port 3000" · "listening on :3000" · "server started on 8000"
  RegExp(
    r'(?:listening|running|serving|started|server|bound|listen)\b[^\d]{0,24}?(?:port\s+|:)?(\d{2,5})\b',
    caseSensitive: false,
  ),
  // "0.0.0.0:8000" / "127.0.0.1:8000" di tengah baris
  RegExp(r'(?:0\.0\.0\.0|127\.0\.0\.1|localhost):(\d{2,5})'),
];

// Port yang hampir selalu noise, bukan server aplikasi yang ingin di-forward.
const _ignore = {22, 25, 53, 80, 443, 0};

/// Pindai satu baris output; kembalikan saran port bila terdeteksi, else null.
PortSuggestion? detectListeningPort(String line) {
  for (final re in _patterns) {
    final m = re.firstMatch(line);
    if (m == null) continue;
    final p = int.tryParse(m.group(1) ?? '');
    if (p == null || p < 1 || p > 65535) continue;
    if (_ignore.contains(p)) continue;
    return PortSuggestion(p, line.trim());
  }
  return null;
}

/// Satu port-forward lokal aktif (setara `ssh -L localPort:remoteHost:remotePort`).
class ActiveForward {
  ActiveForward({
    required this.localPort,
    required this.remoteHost,
    required this.remotePort,
    required this.server,
  });

  final int localPort;
  final String remoteHost;
  final int remotePort;
  final ServerSocket server;
  int connections = 0;

  String get label => 'localhost:$localPort → $remoteHost:$remotePort';
}

/// Mengelola port-forward lokal untuk satu sesi SSH. Membuka [ServerSocket]
/// lokal, lalu menyalurkan tiap koneksi masuk lewat channel direct-tcpip SSH
/// ([SSHClient.forwardLocal]). Tidak butuh biner `ssh` eksternal.
class PortForwardManager extends ChangeNotifier {
  PortForwardManager(this._client);

  final SSHClient _client;
  final List<ActiveForward> forwards = [];

  bool isForwarded(int remotePort) =>
      forwards.any((f) => f.remotePort == remotePort);

  /// Mulai forward. [localPort] 0 = coba port yang sama dengan remote, lalu
  /// jatuh ke port lokal bebas pilihan OS bila sudah terpakai.
  /// Mengembalikan forward yang dibuat, atau melempar bila gagal bind.
  Future<ActiveForward> start(
    int remotePort, {
    String remoteHost = 'localhost',
    int localPort = 0,
  }) async {
    ServerSocket server;
    try {
      server = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        localPort == 0 ? remotePort : localPort,
      );
    } on SocketException {
      // Port lokal terpakai → minta OS pilihkan port bebas (0).
      server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    }
    final fwd = ActiveForward(
      localPort: server.port,
      remoteHost: remoteHost,
      remotePort: remotePort,
      server: server,
    );
    forwards.add(fwd);
    notifyListeners();

    server.listen(
      (socket) => _handle(socket, fwd),
      onError: (_) {},
      cancelOnError: false,
    );
    return fwd;
  }

  Future<void> _handle(Socket socket, ActiveForward fwd) async {
    try {
      final channel = await _client.forwardLocal(fwd.remoteHost, fwd.remotePort);
      fwd.connections++;
      notifyListeners();
      // lokal → remote
      socket.cast<List<int>>().pipe(channel.sink).catchError((_) {});
      // remote → lokal
      channel.stream.cast<List<int>>().pipe(socket).catchError((_) {});
    } catch (_) {
      socket.destroy();
    }
  }

  Future<void> stop(ActiveForward fwd) async {
    await fwd.server.close();
    forwards.remove(fwd);
    notifyListeners();
  }

  @override
  void dispose() {
    for (final f in forwards) {
      f.server.close();
    }
    forwards.clear();
    super.dispose();
  }
}
