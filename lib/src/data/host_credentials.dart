import '../models/ssh_credentials.dart';
import '../models/ssh_host.dart';

/// Pembaca rahasia sebuah host (biasanya `HostRepository.loadSecret`).
typedef SecretLoader = Future<HostSecret> Function(String hostId);

/// Bangun kredensial lengkap untuk [host], termasuk rantai jump-host
/// (bastion) dari [allHosts]. Referensi melingkar (A → B → A) diputus lewat
/// [visited]; bastion yang sudah dihapus dilewati.
Future<SshCredentials> buildHostCredentials(
  SshHost host, {
  required SecretLoader loadSecret,
  required List<SshHost> allHosts,
  Set<String>? visited,
}) async {
  final seen = visited ?? <String>{};
  seen.add(host.id);
  final secret = await loadSecret(host.id);
  final jumps = await resolveJumpChain(
    host.jumpHostId,
    loadSecret: loadSecret,
    allHosts: allHosts,
    visited: seen,
  );
  final usesKey = host.authMethod == SshAuthMethod.key;
  return SshCredentials(
    host: host.host,
    port: host.port,
    username: host.username,
    password: usesKey ? null : secret.password,
    privateKey: usesKey ? secret.privateKey : null,
    passphrase: secret.passphrase,
    jumpHosts: jumps,
    forwardAgent: usesKey && host.forwardAgent,
  );
}

/// Rantai bastion (urut dari yang paling luar) untuk mencapai sebuah host yang
/// jump-host-nya [jumpHostId]. Kosong bila koneksi langsung.
Future<List<SshCredentials>> resolveJumpChain(
  String? jumpHostId, {
  required SecretLoader loadSecret,
  required List<SshHost> allHosts,
  Set<String>? visited,
}) async {
  final seen = visited ?? <String>{};
  if (jumpHostId == null || seen.contains(jumpHostId)) return const [];
  SshHost? jump;
  for (final h in allHosts) {
    if (h.id == jumpHostId) {
      jump = h;
      break;
    }
  }
  if (jump == null) return const [];
  final jumpCreds = await buildHostCredentials(
    jump,
    loadSecret: loadSecret,
    allHosts: allHosts,
    visited: seen,
  );
  return [
    ...jumpCreds.jumpHosts,
    // Bastion sendiri: tanpa rantai bersarang, dan TANPA agent forwarding —
    // agen hanya diteruskan ke host tujuan akhir.
    SshCredentials(
      host: jumpCreds.host,
      port: jumpCreds.port,
      username: jumpCreds.username,
      password: jumpCreds.password,
      privateKey: jumpCreds.privateKey,
      passphrase: jumpCreds.passphrase,
    ),
  ];
}
