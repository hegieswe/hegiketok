import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../models/ssh_host.dart';

/// Menyimpan & memuat daftar host SSH.
///
/// Pembagian penyimpanan yang disengaja:
/// - **Metadata non-sensitif** (label, host, port, user) → file JSON biasa di
///   direktori dukungan aplikasi. Transparan & mudah di-backup/ekspor → tanpa
///   vendor lock-in.
/// - **Rahasia** (password, private key, passphrase) → [FlutterSecureStorage]
///   yang memakai **Keychain** macOS. Tidak pernah ditulis ke disk sebagai
///   teks biasa.
class HostRepository {
  HostRepository({
    FlutterSecureStorage? secureStorage,
    Directory? directory,
    DateTime Function()? clock,
  })  : _dirOverride = directory,
        _clock = clock ?? DateTime.now,
        _secure = secureStorage ??
            const FlutterSecureStorage(
              // Keychain legacy (file-based) di macOS: tidak memerlukan
              // entitlement keychain-access-groups maupun Apple Developer
              // certificate, sehingga berjalan di build lokal/dev.
              mOptions: MacOsOptions(
                usesDataProtectionKeychain: false,
              ),
            );

  final FlutterSecureStorage _secure;

  /// Override direktori — dipakai pengujian agar tak bergantung path_provider.
  final Directory? _dirOverride;

  /// Sumber waktu (diganti pengujian agar nama cadangan deterministik).
  final DateTime Function() _clock;

  /// Jumlah cadangan `hosts.json` yang disimpan; yang lebih lama dibuang.
  static const int maxBackups = 15;

  File? _cachedFile;

  Future<File> _hostsFile() async {
    if (_cachedFile != null) return _cachedFile!;
    final dir = _dirOverride ?? await getApplicationSupportDirectory();
    final file = File('${dir.path}/hosts.json');
    if (!await file.exists()) {
      await file.create(recursive: true);
      await file.writeAsString('[]');
    }
    _cachedFile = file;
    return file;
  }

  /// Muat semua host tersimpan (tanpa rahasia).
  Future<List<SshHost>> loadHosts() async {
    try {
      final file = await _hostsFile();
      final content = await file.readAsString();
      if (content.trim().isEmpty) return [];
      final list = jsonDecode(content) as List<dynamic>;
      return list
          .map((e) => SshHost.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      // File rusak/tidak terbaca → kembalikan kosong agar app tetap jalan.
      return [];
    }
  }

  /// Tulis daftar host. Sebelum menimpa, isi lama disalin ke folder
  /// `backups/` (lihat [listBackups]); penulisan dilakukan ke berkas sementara
  /// lalu di-rename, sehingga `hosts.json` tidak pernah setengah tertulis.
  Future<void> _writeHosts(List<SshHost> hosts) async {
    final file = await _hostsFile();
    const encoder = JsonEncoder.withIndent('  ');
    final next = encoder.convert(hosts.map((h) => h.toJson()).toList());

    String current = '';
    try {
      current = await file.readAsString();
    } catch (_) {
      // Berkas lama tak terbaca → tak ada yang bisa dicadangkan.
    }
    if (current == next) return; // tak ada perubahan
    await _backup(current);

    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(next, flush: true);
    await tmp.rename(file.path);
  }

  Future<Directory> _backupDir() async {
    final file = await _hostsFile();
    return Directory('${file.parent.path}/backups');
  }

  // Simpan [content] (isi hosts.json sebelum ditimpa) sebagai cadangan.
  // Daftar kosong tidak dicadangkan — tak ada yang perlu diselamatkan, dan
  // itu akan menggeser cadangan yang berisi. Kegagalan mencadangkan tidak
  // boleh menggagalkan penyimpanan.
  Future<void> _backup(String content) async {
    try {
      final trimmed = content.trim();
      if (trimmed.isEmpty || trimmed == '[]') return;
      final dir = await _backupDir();
      await dir.create(recursive: true);

      final existing = await _backupFiles(dir);
      if (existing.isNotEmpty &&
          await existing.first.readAsString() == content) {
        return; // sama dengan cadangan terbaru
      }

      final t = _clock().toUtc();
      String two(int n) => n.toString().padLeft(2, '0');
      final stamp = '${t.year}${two(t.month)}${two(t.day)}-'
          '${two(t.hour)}${two(t.minute)}${two(t.second)}-'
          '${t.millisecond.toString().padLeft(3, '0')}';
      await File('${dir.path}/hosts-$stamp.json')
          .writeAsString(content, flush: true);

      final all = await _backupFiles(dir);
      for (final old in all.skip(maxBackups)) {
        try {
          await old.delete();
        } catch (_) {}
      }
    } catch (_) {
      // Lihat komentar di atas: terbaik-usaha.
    }
  }

  // Berkas cadangan, terbaru lebih dulu (nama berisi cap waktu → urut nama).
  Future<List<File>> _backupFiles(Directory dir) async {
    if (!await dir.exists()) return [];
    final files = <File>[];
    await for (final e in dir.list()) {
      final name = e.uri.pathSegments.last;
      if (e is File && name.startsWith('hosts-') && name.endsWith('.json')) {
        files.add(e);
      }
    }
    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  /// Cadangan daftar host yang tersedia, terbaru lebih dulu. Cadangan yang
  /// rusak dilewati.
  Future<List<HostBackup>> listBackups() async {
    final out = <HostBackup>[];
    for (final f in await _backupFiles(await _backupDir())) {
      try {
        final list = jsonDecode(await f.readAsString()) as List<dynamic>;
        final hosts = list
            .map((e) => SshHost.fromJson(e as Map<String, dynamic>))
            .toList();
        final time = _parseBackupTime(f.uri.pathSegments.last) ??
            (await f.lastModified());
        out.add(HostBackup(file: f, time: time, hosts: hosts));
      } catch (_) {
        // Cadangan rusak → tidak ditawarkan.
      }
    }
    return out;
  }

  static DateTime? _parseBackupTime(String name) {
    final m = RegExp(r'^hosts-(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})(\d{2})-(\d{3})\.json$')
        .firstMatch(name);
    if (m == null) return null;
    int g(int i) => int.parse(m.group(i)!);
    return DateTime.utc(g(1), g(2), g(3), g(4), g(5), g(6), g(7)).toLocal();
  }

  /// Ganti daftar host dengan isi [backup]. Daftar yang sekarang dicadangkan
  /// lebih dulu, jadi pemulihan ini sendiri bisa dibatalkan. Rahasia di
  /// Keychain tidak disentuh: host yang ID-nya sama mendapat kembali
  /// password/key-nya. Mengembalikan jumlah host yang dipulihkan.
  Future<int> restoreBackup(HostBackup backup) async {
    final content = await backup.file.readAsString();
    final list = jsonDecode(content) as List<dynamic>;
    final hosts =
        list.map((e) => SshHost.fromJson(e as Map<String, dynamic>)).toList();
    await _writeHosts(hosts);
    return hosts.length;
  }

  /// Baca daftar host untuk DITULIS ULANG. Berbeda dari [loadHosts], berkas
  /// yang rusak di sini melempar galat — kalau dianggap kosong, penyimpanan
  /// berikutnya akan menimpa (menghapus) semua host yang ada.
  Future<List<SshHost>> _readHostsForWrite() async {
    final file = await _hostsFile();
    final content = await file.readAsString();
    if (content.trim().isEmpty) return [];
    final list = jsonDecode(content) as List<dynamic>;
    return list
        .map((e) => SshHost.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Tambah/perbarui host beserta rahasianya.
  ///
  /// Rahasia yang bernilai null TIDAK diubah (berguna saat mengedit host tanpa
  /// mengganti password/key).
  ///
  /// Rahasia ditulis ke Keychain LEBIH DULU; daftar host baru diperbarui bila
  /// itu berhasil. Dengan begitu kegagalan Keychain tidak meninggalkan host
  /// "yatim" tanpa password di daftar. Untuk host baru, rahasia yang sempat
  /// tertulis dibersihkan lagi bila langkah berikutnya gagal.
  Future<void> saveHost(
    SshHost host, {
    String? password,
    String? privateKey,
    String? passphrase,
  }) async {
    final hosts = await _readHostsForWrite();
    final index = hosts.indexWhere((h) => h.id == host.id);
    final isNew = index < 0;

    try {
      if (password != null) {
        await _secure.write(key: _pwKey(host.id), value: password);
      }
      if (privateKey != null) {
        await _secure.write(key: _keyKey(host.id), value: privateKey);
      }
      if (passphrase != null) {
        await _secure.write(key: _passKey(host.id), value: passphrase);
      }

      if (isNew) {
        hosts.add(host);
      } else {
        hosts[index] = host;
      }
      await _writeHosts(hosts);
    } catch (_) {
      if (isNew) await _deleteSecretsQuietly(host.id);
      rethrow;
    }
  }

  Future<void> _deleteSecretsQuietly(String id) async {
    for (final key in [_pwKey(id), _keyKey(id), _passKey(id)]) {
      try {
        await _secure.delete(key: key);
      } catch (_) {
        // Pembersihan terbaik-usaha; galat aslinya yang dilempar ke pemanggil.
      }
    }
  }

  /// Hapus host beserta semua rahasianya.
  Future<void> deleteHost(String id) async {
    final hosts = await _readHostsForWrite();
    hosts.removeWhere((h) => h.id == id);
    await _writeHosts(hosts);
    await _secure.delete(key: _pwKey(id));
    await _secure.delete(key: _keyKey(id));
    await _secure.delete(key: _passKey(id));
  }

  /// Baca rahasia sebuah host dari Keychain.
  Future<HostSecret> loadSecret(String id) async {
    return HostSecret(
      password: await _secure.read(key: _pwKey(id)),
      privateKey: await _secure.read(key: _keyKey(id)),
      passphrase: await _secure.read(key: _passKey(id)),
    );
  }

  String _pwKey(String id) => 'host_${id}_password';
  String _keyKey(String id) => 'host_${id}_privateKey';
  String _passKey(String id) => 'host_${id}_passphrase';
}

/// Satu cadangan otomatis daftar host.
class HostBackup {
  const HostBackup({required this.file, required this.time, required this.hosts});

  final File file;

  /// Saat cadangan dibuat (= saat daftar itu digantikan).
  final DateTime time;
  final List<SshHost> hosts;
}
