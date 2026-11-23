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
    this.jumpHosts = const [],
    this.forwardAgent = false,
  });

  final String host;
  final int port;
  final String username;

  final String? password;
  final String? privateKey;
  final String? passphrase;

  /// Rantai jump-host (bastion) yang harus dilewati sebelum mencapai host ini,
  /// urut dari yang paling luar. Kosong = koneksi langsung.
  final List<SshCredentials> jumpHosts;

  /// Teruskan agen SSH ke host ini: server bisa memakai key ini untuk
  /// menyambung ke server lain (mis. `git pull`, `ssh` lanjutan) tanpa key
  /// disalin ke sana. Hanya berlaku bila login memakai key.
  final bool forwardAgent;

  bool get usesKey => privateKey != null && privateKey!.trim().isNotEmpty;

  String get label => '$username@$host';
}
