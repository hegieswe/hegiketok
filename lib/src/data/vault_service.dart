import 'dart:convert';

import '../models/snippet.dart';
import '../models/ssh_host.dart';
import '../ssh/known_hosts.dart';
import 'host_repository.dart';
import 'snippet_repository.dart';

/// Ringkasan hasil restore.
class VaultSummary {
  const VaultSummary(this.hosts, this.snippets, this.knownHosts);
  final int hosts;
  final int snippets;
  final int knownHosts;
}

/// Kumpulkan seluruh data (host + rahasia Keychain, snippet, known-hosts) jadi
/// JSON. Dipanggil sebelum dienkripsi untuk backup.
Future<String> buildVaultJson({
  required HostRepository hosts,
  required SnippetRepository snippets,
  required KnownHostsStore knownHosts,
}) async {
  final hostList = await hosts.loadHosts();
  final hostEntries = <Map<String, dynamic>>[];
  for (final h in hostList) {
    final s = await hosts.loadSecret(h.id);
    hostEntries.add({
      ...h.toJson(),
      'secret': {
        'password': s.password,
        'privateKey': s.privateKey,
        'passphrase': s.passphrase,
      },
    });
  }
  final snips = await snippets.load();
  final kh = await knownHosts.all();
  return jsonEncode({
    'app': 'HegiKetok',
    'version': 1,
    'exportedAt': DateTime.now().toIso8601String(),
    'hosts': hostEntries,
    'snippets': snips.map((e) => e.toJson()).toList(),
    'knownHosts': kh.map((e) => e.toJson()).toList(),
  });
}

/// Pulihkan data dari JSON (hasil dekripsi). Bersifat aditif: menimpa entri
/// dengan id sama. Mengembalikan jumlah tiap jenis yang dipulihkan.
Future<VaultSummary> restoreVaultJson(
  String json, {
  required HostRepository hosts,
  required SnippetRepository snippets,
  required KnownHostsStore knownHosts,
}) async {
  final map = jsonDecode(json) as Map<String, dynamic>;
  var hc = 0, sc = 0, kc = 0;

  for (final e in (map['hosts'] as List<dynamic>? ?? const [])) {
    final m = e as Map<String, dynamic>;
    final secret = m['secret'] as Map<String, dynamic>?;
    final host = SshHost.fromJson(m);
    await hosts.saveHost(
      host,
      password: secret?['password'] as String?,
      privateKey: secret?['privateKey'] as String?,
      passphrase: secret?['passphrase'] as String?,
    );
    hc++;
  }
  for (final e in (map['snippets'] as List<dynamic>? ?? const [])) {
    await snippets.save(Snippet.fromJson(e as Map<String, dynamic>));
    sc++;
  }
  for (final e in (map['knownHosts'] as List<dynamic>? ?? const [])) {
    await knownHosts.trust(KnownHost.fromJson(e as Map<String, dynamic>));
    kc++;
  }
  return VaultSummary(hc, sc, kc);
}
