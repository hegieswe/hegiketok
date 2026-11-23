import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';

import '../models/ssh_credentials.dart';
import 'connection_progress.dart';
import 'known_hosts.dart';

/// Hasil koneksi SSH: klien yang terautentikasi ke host target plus seluruh
/// rantai jump-host (bastion) di belakangnya agar bisa dibersihkan bersama.
class SshConnection {
  SshConnection(this.client, this._chain);

  /// Klien ke host target (hop terakhir).
  final SSHClient client;

  /// Semua klien pada rantai, dari bastion terluar sampai target.
  final List<SSHClient> _chain;

  /// Tutup target lebih dulu, lalu bastion dari dalam ke luar.
  void close() {
    for (final c in _chain.reversed) {
      c.close();
    }
  }
}

/// Buka koneksi SSH ke [credentials]. Bila [SshCredentials.jumpHosts] berisi
/// satu atau lebih bastion, koneksi di-tunnel berurutan:
///
///   lokal → jumpHosts[0] → jumpHosts[1] → … → target
///
/// Setiap tahap (TCP/tunnel + autentikasi tiap hop) dilaporkan ke [progress]
/// sehingga UI bisa menampilkan "handshake stepper".
Future<SshConnection> connectSsh(
  SshCredentials credentials, {
  ConnectionProgress? progress,
  KnownHostsStore? knownHosts,
  HostKeyVerifier? verifyHostKey,
}) async {
  final store = knownHosts ?? defaultKnownHosts;
  final verifier = verifyHostKey ?? globalHostKeyVerifier;
  final chain = <SSHClient>[];
  try {
    final hops = <SshCredentials>[...credentials.jumpHosts, credentials];

    SSHClient? previous;
    for (var i = 0; i < hops.length; i++) {
      final hop = hops[i];
      final isTarget = i == hops.length - 1;
      final target = '${hop.host}:${hop.port}';

      // 1) Transport: TCP langsung untuk hop pertama, atau tunnel lewat hop
      //    sebelumnya (channel direct-tcpip) untuk hop berikutnya.
      final transport = progress?.begin(
        previous == null
            ? 'Menghubungkan ke $target'
            : (isTarget
                ? 'Tunnel bastion → target $target'
                : 'Tunnel bastion → $target'),
      );
      final SSHSocket socket;
      try {
        if (previous == null) {
          socket = await SSHSocket.connect(
            hop.host,
            hop.port,
            timeout: const Duration(seconds: 10),
          );
        } else {
          socket = await previous.forwardLocal(hop.host, hop.port);
        }
      } catch (e) {
        if (transport != null) progress!.fail(transport, _short(e));
        rethrow;
      }
      if (transport != null) progress!.complete(transport);

      // 2) Autentikasi hop ini.
      final auth = progress?.begin('Autentikasi ${hop.username}@${hop.host}');
      try {
        final identities = hop.usesKey
            ? SSHKeyPair.fromPem(
                hop.privateKey!,
                // Passphrase kosong = tanpa passphrase.
                (hop.passphrase?.isEmpty ?? true) ? null : hop.passphrase,
              )
            : null;
        final hostPort = '${hop.host}:${hop.port}';
        final client = SSHClient(
          socket,
          username: hop.username,
          identities: identities,
          // Agent forwarding hanya ke host tujuan akhir, dan hanya bila
          // diminta: agen menjawab dengan key yang sama dengan yang dipakai
          // login (private key tidak pernah meninggalkan perangkat ini).
          agentHandler: (isTarget && hop.forwardAgent && identities != null)
              ? SSHKeyPairAgent(identities)
              : null,
          onPasswordRequest: hop.usesKey ? null : () => hop.password,
          // Verifikasi host key (Trust On First Use). Kunci yang sudah cocok
          // lolos diam-diam; host baru atau kunci yang berubah harus disetujui
          // pengguna lewat [verifier]. Tanpa verifier (headless/test) →
          // fail-closed: tolak demi keamanan.
          onVerifyHostKey: (type, fingerprintBytes) async {
            final fingerprint = utf8.decode(fingerprintBytes);
            final known = await store.lookup(hostPort);
            final status = classifyHostKey(known, fingerprint);
            if (status == HostKeyStatus.match) return true;
            if (verifier == null) return false;
            final accepted = await verifier(HostKeyPrompt(
              host: hop.host,
              port: hop.port,
              type: type,
              fingerprint: fingerprint,
              status: status,
              previousFingerprint: known?.fingerprint,
            ));
            if (accepted) {
              await store.trust(KnownHost(
                hostPort: hostPort,
                type: type,
                fingerprint: fingerprint,
                firstSeen: known?.firstSeen ?? DateTime.now(),
              ));
            }
            return accepted;
          },
        );
        await client.authenticated;
        chain.add(client);
        previous = client;
      } catch (e) {
        if (auth != null) progress!.fail(auth, _friendly(e));
        rethrow;
      }
      if (auth != null) {
        progress!.complete(auth, detail: isTarget ? 'terhubung ✓' : 'bastion ✓');
      }
    }

    progress?.finish();
    return SshConnection(chain.last, chain);
  } catch (e) {
    for (final c in chain.reversed) {
      c.close();
    }
    rethrow;
  }
}

String _short(Object e) {
  final t = e.toString();
  return t.length > 80 ? '${t.substring(0, 80)}…' : t;
}

/// Pesan error yang ramah pengguna. Kegagalan verifikasi host key (termasuk
/// penolakan pengguna) diterjemahkan agar tak muncul sebagai string mentah.
String _friendly(Object e) {
  final t = e.toString();
  if (t.contains('Hostkey verification failed') ||
      t.contains('SSHHostkeyError')) {
    return 'Verifikasi host key dibatalkan';
  }
  return _short(e);
}
