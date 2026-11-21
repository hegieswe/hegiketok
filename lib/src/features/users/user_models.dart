/// Satu akun pengguna sistem (dari /etc/passwd).
class SystemUser {
  SystemUser({
    required this.name,
    required this.uid,
    required this.gid,
    required this.gecos,
    required this.home,
    required this.shell,
    this.loggedIn = false,
    this.isSudoer = false,
  });

  final String name;
  final int uid;
  final int gid;
  final String gecos; // nama lengkap / deskripsi
  final String home;
  final String shell;

  bool loggedIn;
  bool isSudoer;

  bool get isRoot => uid == 0;
  bool get isSystem => uid != 0 && uid < 1000;
  bool get isHuman => uid == 0 || uid >= 1000;

  bool get canLogin {
    final s = shell.trim();
    if (s.isEmpty) return false;
    return !(s.endsWith('nologin') || s.endsWith('false') || s.endsWith('sync'));
  }
}

/// Hasil pengambilan daftar user.
class UserSnapshot {
  const UserSnapshot({required this.users, this.error});

  final List<SystemUser> users;
  final String? error;
}
