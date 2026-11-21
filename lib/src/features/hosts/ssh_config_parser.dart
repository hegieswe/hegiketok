/// Satu entri hasil parse dari `~/.ssh/config`.
class SshConfigEntry {
  const SshConfigEntry({
    required this.alias,
    required this.hostName,
    this.port = 22,
    this.user,
    this.identityFile,
  });

  final String alias;
  final String hostName;
  final int port;
  final String? user;
  final String? identityFile;

  bool get usesKey => identityFile != null && identityFile!.isNotEmpty;
}

/// Parser sederhana untuk format OpenSSH `~/.ssh/config`.
///
/// Menangani blok `Host <alias>` dengan kunci HostName, Port, User, dan
/// IdentityFile. Entri dengan wildcard (`*` / `?`) dilewati karena bukan host
/// konkret. Nilai bisa dipisah spasi maupun `=`.
List<SshConfigEntry> parseSshConfig(String content) {
  final entries = <SshConfigEntry>[];

  String? alias;
  String? hostName;
  int port = 22;
  String? user;
  String? identityFile;

  void flush() {
    final a = alias;
    if (a == null || a.contains('*') || a.contains('?')) return;
    final h = hostName;
    entries.add(SshConfigEntry(
      alias: a,
      hostName: (h == null || h.isEmpty) ? a : h,
      port: port,
      user: user,
      identityFile: identityFile,
    ));
  }

  void reset() {
    hostName = null;
    port = 22;
    user = null;
    identityFile = null;
  }

  for (final rawLine in content.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) continue;

    // Pisahkan "key value" atau "key=value" (key berhenti di spasi atau '=').
    final match = RegExp(r'^([^\s=]+)\s*=?\s*(.*)$').firstMatch(line);
    if (match == null) continue;
    final key = match.group(1)!.toLowerCase();
    final value = match.group(2)!.trim();
    if (value.isEmpty && key != 'host') continue;

    switch (key) {
      case 'host':
        flush(); // selesaikan blok sebelumnya
        reset();
        alias = value.split(RegExp(r'\s+')).first;
        break;
      case 'hostname':
        hostName = value;
        break;
      case 'port':
        port = int.tryParse(value) ?? 22;
        break;
      case 'user':
        user = value;
        break;
      case 'identityfile':
        identityFile = value;
        break;
    }
  }
  flush(); // blok terakhir

  return entries;
}
