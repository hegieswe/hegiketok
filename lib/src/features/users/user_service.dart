import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';

import 'user_models.dart';

const _usersScript = r'''
export LANG=C
echo '@@PASSWD'; getent passwd 2>/dev/null || cat /etc/passwd 2>/dev/null
echo '@@WHO'; who 2>/dev/null
echo '@@SUDO'; getent group sudo wheel admin 2>/dev/null
echo '@@END'
''';

/// Ambil daftar user sistem dari server lewat [client].
Future<UserSnapshot> fetchUsers(SSHClient client) async {
  final out = await client.run(_usersScript);
  return parseUsers(utf8.decode(out, allowMalformed: true));
}

/// Parser murni (dapat diuji tanpa server).
UserSnapshot parseUsers(String text) {
  final sections = <String, List<String>>{};
  var cur = '';
  for (final line in const LineSplitter().convert(text)) {
    if (line.startsWith('@@')) {
      cur = line.substring(2);
      sections.putIfAbsent(cur, () => []);
    } else {
      (sections[cur] ??= []).add(line);
    }
  }
  List<String> sec(String k) => sections[k] ?? const [];

  final users = <SystemUser>[];
  final byName = <String, SystemUser>{};
  for (final raw in sec('PASSWD')) {
    final line = raw.trim();
    if (line.isEmpty || !line.contains(':')) continue;
    final f = line.split(':');
    if (f.length < 7) continue;
    final uid = int.tryParse(f[2]);
    final gid = int.tryParse(f[3]);
    if (uid == null || gid == null) continue;
    final u = SystemUser(
      name: f[0],
      uid: uid,
      gid: gid,
      gecos: f[4].split(',').first, // buang info kantor/telepon
      home: f[5],
      shell: f[6],
    );
    users.add(u);
    byName[u.name] = u;
  }

  if (users.isEmpty) {
    final low = text.toLowerCase();
    if (low.contains('permission denied') || low.contains('denied')) {
      return const UserSnapshot(
          users: [], error: 'Akses ditolak membaca daftar user.');
    }
    return const UserSnapshot(
        users: [], error: 'Tidak bisa membaca daftar user dari server.');
  }

  // Siapa yang sedang login.
  for (final raw in sec('WHO')) {
    final name = raw.trim().split(RegExp(r'\s+')).first;
    if (name.isEmpty) continue;
    byName[name]?.loggedIn = true;
  }

  // Keanggotaan grup sudo/wheel/admin.
  for (final raw in sec('SUDO')) {
    final line = raw.trim();
    if (line.isEmpty || !line.contains(':')) continue;
    final f = line.split(':');
    if (f.length < 4) continue;
    for (final m in f[3].split(',')) {
      final name = m.trim();
      if (name.isNotEmpty) byName[name]?.isSudoer = true;
    }
  }

  // Urutkan: root → manusia (uid asc) → sistem (uid asc).
  int rank(SystemUser u) {
    if (u.isRoot) return 0;
    if (u.uid >= 1000) return 1;
    return 2;
  }

  users.sort((a, b) {
    final r = rank(a).compareTo(rank(b));
    if (r != 0) return r;
    return a.uid.compareTo(b.uid);
  });

  return UserSnapshot(users: users);
}
