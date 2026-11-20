/// Kredensial lengkap untuk membuka satu koneksi SSH.
///
/// Mendukung dua metode autentikasi:
/// - Password: isi [password].
/// - SSH key: isi [privateKey] (PEM/OpenSSH) dan opsional [passphrase].
class SshCredentials {
  const SshCredentials({
    required this.host,
    this.port = 22,
    required this.username,
    this.password,
    this.privateKey,
    this.passphrase,
  });

  final String host;
  final int port;
  final String username;

  final String? password;
  final String? privateKey;
  final String? passphrase;

  bool get usesKey => privateKey != null && privateKey!.trim().isNotEmpty;

  String get label => '$username@$host';
}
