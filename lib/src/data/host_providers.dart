import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ssh_credentials.dart';
import '../models/ssh_host.dart';
import '../ssh/connection_test.dart';
import 'host_repository.dart';

/// Penyedia instance repository (satu untuk seluruh app).
final hostRepositoryProvider = Provider<HostRepository>(
  (ref) => HostRepository(),
);

/// Fungsi "Tes koneksi" (dipisah sebagai provider agar bisa diganti pengujian).
final connectionTesterProvider =
    Provider<Future<ConnectionTestResult> Function(SshCredentials)>(
  (ref) => testSshConnection,
);

/// State daftar host tersimpan. Memuat dari disk saat pertama dibutuhkan,
/// lalu menyediakan aksi tambah/hapus yang menyinkronkan UI & penyimpanan.
final hostsProvider =
    AsyncNotifierProvider<HostsNotifier, List<SshHost>>(HostsNotifier.new);

class HostsNotifier extends AsyncNotifier<List<SshHost>> {
  HostRepository get _repo => ref.read(hostRepositoryProvider);

  @override
  Future<List<SshHost>> build() => _repo.loadHosts();

  Future<void> save(
    SshHost host, {
    String? password,
    String? privateKey,
    String? passphrase,
  }) async {
    await _repo.saveHost(
      host,
      password: password,
      privateKey: privateKey,
      passphrase: passphrase,
    );
    state = AsyncData(await _repo.loadHosts());
  }

  /// Pulihkan daftar host dari sebuah cadangan otomatis.
  Future<int> restoreBackup(HostBackup backup) async {
    final count = await _repo.restoreBackup(backup);
    state = AsyncData(await _repo.loadHosts());
    return count;
  }

  Future<void> delete(String id) async {
    await _repo.deleteHost(id);
    state = AsyncData(await _repo.loadHosts());
  }
}
