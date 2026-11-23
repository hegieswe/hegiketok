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
  HostRepository({FlutterSecureStorage? secureStorage, Directory? directory})
      : _dirOverride = directory,
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

  Future<void> _writeHosts(List<SshHost> hosts) async {
    final file = await _hostsFile();
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(
      encoder.convert(hosts.map((h) => h.toJson()).toList()),
    );
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
