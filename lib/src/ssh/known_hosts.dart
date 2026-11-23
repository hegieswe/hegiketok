import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Status sebuah host key terhadap catatan tepercaya yang tersimpan.
enum HostKeyStatus {
  /// Host belum pernah terlihat → minta persetujuan (Trust On First Use).
  fresh,

  /// Fingerprint sama dengan yang tersimpan → aman, lanjut diam-diam.
  match,

  /// Fingerprint BERBEDA dari yang tersimpan → bahaya (indikasi MITM / server
  /// diganti). Minta persetujuan eksplisit dengan peringatan keras.
  changed,
}

/// Satu entri known-hosts: pemetaan `host:port` → fingerprint tepercaya.
///
/// Fingerprint host key bersifat **publik** (bukan rahasia), jadi disimpan
/// sebagai JSON biasa — transparan, mudah di-backup, tanpa lock-in. Sejalan
/// dengan `~/.ssh/known_hosts` milik OpenSSH.
class KnownHost {
  const KnownHost({
    required this.hostPort,
    required this.type,
    required this.fingerprint,
    required this.firstSeen,
  });

  /// Kunci penyimpanan, berformat `host:port` (mis. `1.2.3.4:22`).
  final String hostPort;

  /// Tipe host key, mis. `ssh-ed25519`, `rsa-sha2-512`.
  final String type;

  /// Fingerprint ala OpenSSH: `SHA256:<base64>`.
  final String fingerprint;

  /// Kapan kunci ini pertama dipercayai.
  final DateTime firstSeen;

  Map<String, dynamic> toJson() => {
        'hostPort': hostPort,
        'type': type,
        'fingerprint': fingerprint,
        'firstSeen': firstSeen.toIso8601String(),
      };

  factory KnownHost.fromJson(Map<String, dynamic> json) => KnownHost(
        hostPort: json['hostPort'] as String,
        type: (json['type'] as String?) ?? '',
        fingerprint: json['fingerprint'] as String,
        firstSeen: DateTime.tryParse(json['firstSeen'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}

/// Informasi yang dikirim ke UI agar pengguna bisa memutuskan kepercayaan.
class HostKeyPrompt {
  const HostKeyPrompt({
    required this.host,
    required this.port,
    required this.type,
    required this.fingerprint,
    required this.status,
    this.previousFingerprint,
  });

  final String host;
  final int port;
  final String type;
  final String fingerprint;

  /// [HostKeyStatus.fresh] atau [HostKeyStatus.changed] (yang `match` tak pernah
  /// sampai ke UI).
  final HostKeyStatus status;

  /// Fingerprint lama yang tersimpan — hanya terisi saat [status] `changed`.
  final String? previousFingerprint;

  String get hostPort => '$host:$port';
}

/// Callback UI: tampilkan prompt, kembalikan `true` bila pengguna mempercayai
/// kunci dan ingin melanjutkan. Mengembalikan `false` akan membatalkan koneksi.
typedef HostKeyVerifier = Future<bool> Function(HostKeyPrompt prompt);

/// Logika klasifikasi murni (mudah diuji, tanpa I/O).
HostKeyStatus classifyHostKey(KnownHost? known, String fingerprint) {
  if (known == null) return HostKeyStatus.fresh;
  return known.fingerprint == fingerprint
      ? HostKeyStatus.match
      : HostKeyStatus.changed;
}

/// Penyimpanan known-hosts berbasis file JSON di direktori dukungan aplikasi.
///
/// Thread-safe untuk pola pakai aplikasi (semua akses lewat `await`). Cache
/// di-muat sekali lalu dijaga sinkron dengan file.
class KnownHostsStore {
  KnownHostsStore({Directory? directory}) : _dirOverride = directory;

  /// Override direktori — dipakai pengujian agar tak bergantung path_provider.
  final Directory? _dirOverride;

  File? _cachedFile;
  final Map<String, KnownHost> _cache = {};
  bool _loaded = false;

  Future<File> _file() async {
    if (_cachedFile != null) return _cachedFile!;
    final dir = _dirOverride ?? await getApplicationSupportDirectory();
    final file = File('${dir.path}/known_hosts.json');
    if (!await file.exists()) {
      await file.create(recursive: true);
      await file.writeAsString('[]');
    }
    _cachedFile = file;
    return file;
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    try {
      final file = await _file();
      final content = await file.readAsString();
      if (content.trim().isNotEmpty) {
        final list = jsonDecode(content) as List<dynamic>;
        for (final e in list) {
          final kh = KnownHost.fromJson(e as Map<String, dynamic>);
          _cache[kh.hostPort] = kh;
        }
      }
    } catch (_) {
      // File rusak → mulai dari kosong agar app tetap jalan (aman: entri yang
      // hilang hanya memicu prompt TOFU ulang, bukan menerima kunci diam-diam).
      _cache.clear();
    }
    _loaded = true;
  }

  Future<void> _persist() async {
    final file = await _file();
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(
      encoder.convert(_cache.values.map((h) => h.toJson()).toList()),
    );
  }

  /// Cari entri tepercaya untuk `host:port`, atau null bila belum ada.
  Future<KnownHost?> lookup(String hostPort) async {
    await _ensureLoaded();
    return _cache[hostPort];
  }

  /// Simpan/perbarui kepercayaan terhadap sebuah host key (upsert).
  Future<void> trust(KnownHost host) async {
    await _ensureLoaded();
    _cache[host.hostPort] = host;
    await _persist();
  }

  /// Lupakan host (mis. server sengaja dibangun ulang). Koneksi berikutnya
  /// akan memicu TOFU lagi.
  Future<void> forget(String hostPort) async {
    await _ensureLoaded();
    _cache.remove(hostPort);
    await _persist();
  }

  /// Semua host tepercaya (untuk layar manajemen), terbaru dulu.
  Future<List<KnownHost>> all() async {
    await _ensureLoaded();
    final list = _cache.values.toList()
      ..sort((a, b) => b.firstSeen.compareTo(a.firstSeen));
    return list;
  }
}

/// Store bersama default untuk seluruh aplikasi.
final KnownHostsStore defaultKnownHosts = KnownHostsStore();

/// Verifier global yang dipasang saat startup (mis. menampilkan dialog).
/// Dibiarkan null pada konteks headless/test → koneksi ke host baru/berubah
/// ditolak demi keamanan (fail-closed).
HostKeyVerifier? globalHostKeyVerifier;
