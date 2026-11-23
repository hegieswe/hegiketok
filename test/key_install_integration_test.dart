// Tes integrasi NYATA manajemen SSH key terhadap container uji
// `nexus-ssh-test` (127.0.0.1:2222, user nexus / nexus123) — server yang sama
// dengan sftp_integration_test.dart. Bila server tidak berjalan, tiap tes
// dilaporkan runner sebagai dilewati (bukan lolos).
//
// Alur yang diuji persis seperti di app: buat key → pasang lewat login
// password → login memakai key → agent forwarding. Key uji dihapus lagi dari
// authorized_keys di akhir.
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_term/src/ssh/ssh_keys.dart';

const _host = '127.0.0.1';
const _port = 2222;
const _user = 'nexus';
const _pass = 'nexus123';
const _skipReason =
    'Server uji (container nexus-ssh-test di 127.0.0.1:2222) tidak berjalan.';

Future<SSHClient> _passwordClient() async {
  final socket = await SSHSocket.connect(_host, _port)
      .timeout(const Duration(seconds: 4));
  final client =
      SSHClient(socket, username: _user, onPasswordRequest: () => _pass);
  await client.authenticated;
  return client;
}

Future<void> main() async {
  // Keterjangkauan dicek SEBELUM tes didaftarkan supaya tes yang tak bisa
  // jalan dilaporkan sebagai "skipped" oleh runner, bukan "passed".
  bool serverUp;
  try {
    (await _passwordClient()).close();
    serverUp = true;
  } catch (_) {
    serverUp = false;
  }
  final skip = serverUp ? null : _skipReason;
  final key = generateEd25519Key(comment: 'hegiketok@uji-integrasi');

  tearDownAll(() async {
    if (!serverUp) return;
    // Bersihkan: buang key uji dari authorized_keys.
    final client = await _passwordClient();
    final blob = key.public.line.split(' ')[1];
    await client.run(
        'f="\$HOME/.ssh/authorized_keys"; [ -f "\$f" ] && '
        'grep -vF -- \'$blob\' "\$f" > "\$f.tmp"; '
        '[ -f "\$f.tmp" ] && cat "\$f.tmp" > "\$f" && rm -f "\$f.tmp"');
    client.close();
  });

  test('pasang key lewat password, lalu pemasangan ulang idempoten', () async {
    final client = await _passwordClient();
    addTearDown(client.close);
    expect(await installPublicKey(client, key.public.line),
        KeyInstallOutcome.added);
    expect(await installPublicKey(client, key.public.line),
        KeyInstallOutcome.alreadyPresent);
  }, skip: skip);

  test('login memakai key yang baru dipasang (tanpa password)', () async {
    final socket = await SSHSocket.connect(_host, _port);
    final client = SSHClient(socket,
        username: _user, identities: SSHKeyPair.fromPem(key.privatePem));
    addTearDown(client.close);
    await client.authenticated;
    expect(utf8.decode(await client.run('whoami')).trim(), _user);
  }, skip: skip);

  test('agent forwarding: server melihat key lewat agen', () async {
    final identities = SSHKeyPair.fromPem(key.privatePem);
    final socket = await SSHSocket.connect(_host, _port);
    final client = SSHClient(socket,
        username: _user,
        identities: identities,
        agentHandler: SSHKeyPairAgent(identities));
    addTearDown(client.close);
    await client.authenticated;
    final out = utf8.decode(await client.run(
        'command -v ssh-add >/dev/null 2>&1 || { echo NO_SSH_ADD; exit 0; }; '
        'echo SOCK=\${SSH_AUTH_SOCK:-none}; ssh-add -L 2>&1'));
    if (out.contains('NO_SSH_ADD')) {
      markTestSkipped('ssh-add tidak tersedia di container uji.');
      return;
    }
    expect(out, isNot(contains('SOCK=none')),
        reason: 'server tidak menyiapkan SSH_AUTH_SOCK: $out');
    expect(out, contains(key.public.line.split(' ')[1]));
  }, skip: skip);
}
