import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ssh_host.dart';
import 'host_repository.dart';

/// Penyedia instance repository (satu untuk seluruh app).
final hostRepositoryProvider = Provider<HostRepository>(
  (ref) => HostRepository(),
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

  Future<void> delete(String id) async {
    await _repo.deleteHost(id);
    state = AsyncData(await _repo.loadHosts());
  }
}
