import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_term/src/ssh/ssh_keys.dart';
import 'package:pinenacl/ed25519.dart' as nacl;

void main() {
  group('generateEd25519Key', () {
    test('menghasilkan PEM OpenSSH yang bisa dibaca ulang', () {
      final k = generateEd25519Key(comment: 'hegiketok@web-01');
      expect(k.privatePem, startsWith('-----BEGIN OPENSSH PRIVATE KEY-----'));
      expect(k.privatePem.trim(), endsWith('-----END OPENSSH PRIVATE KEY-----'));
      expect(SSHKeyPair.isEncryptedPem(k.privatePem), isFalse);

      final pairs = SSHKeyPair.fromPem(k.privatePem);
      expect(pairs, hasLength(1));
      expect(pairs.single, isA<OpenSSHEd25519KeyPair>());
    });

    test('public key cocok dengan private key-nya', () {
      final k = generateEd25519Key(comment: 'a@b');
      expect(k.public.type, 'ssh-ed25519');
      expect(k.public.line, startsWith('ssh-ed25519 AAAAC3NzaC1lZDI1NTE5'));
      expect(k.public.line, endsWith(' a@b'));

      final again = describePrivateKey(k.privatePem, comment: 'a@b');
      expect(again.line, k.public.line);
      expect(again.fingerprint, k.public.fingerprint);
    });

    test('tanda tangan dari key baru lolos verifikasi public key-nya', () {
      final k = generateEd25519Key();
      final pair =
          SSHKeyPair.fromPem(k.privatePem).single as OpenSSHEd25519KeyPair;
      final data = Uint8List.fromList(utf8.encode('pesan uji'));
      // Bentuk kawat: string tipe + string tanda tangan (64 byte terakhir).
      final wire = pair.sign(data).encode();
      final raw = Uint8List.fromList(wire.sublist(wire.length - 64));
      final verifier = nacl.VerifyKey(pair.publicKey);
      expect(
        verifier.verify(signature: nacl.Signature(raw), message: data),
        isTrue,
      );
      // Pesan yang diubah harus gagal diverifikasi.
      expect(
        () => verifier.verify(
            signature: nacl.Signature(raw),
            message: Uint8List.fromList(utf8.encode('pesan lain'))),
        throwsA(anything),
      );
    });

    test('tiap panggilan menghasilkan key berbeda', () {
      final a = generateEd25519Key();
      final b = generateEd25519Key();
      expect(a.public.line, isNot(b.public.line));
      expect(a.privatePem, isNot(b.privatePem));
    });

    test('sidik jari berformat SHA256:<43 karakter base64>', () {
      final fp = generateEd25519Key().public.fingerprint;
      expect(fp, matches(RegExp(r'^SHA256:[A-Za-z0-9+/]{43}$')));
    });

    test('komentar kosong → baris tanpa komentar', () {
      final k = generateEd25519Key();
      expect(k.public.line.split(' '), hasLength(2));
    });
  });

  group('describePrivateKey', () {
    test('key kosong / sampah → SshKeyException', () {
      expect(() => describePrivateKey(''), throwsA(isA<SshKeyException>()));
      expect(() => describePrivateKey('bukan key'),
          throwsA(isA<SshKeyException>()));
    });

    test('key ber-passphrase: tanpa/salah passphrase ditolak, benar diterima',
        () {
      final plain = generateEd25519Key();
      final pair =
          SSHKeyPair.fromPem(plain.privatePem).single as OpenSSHEd25519KeyPair;
      // rounds kecil agar tes cepat.
      final encrypted = pair.toPem(passphrase: 'rahasia', rounds: 4);
      expect(SSHKeyPair.isEncryptedPem(encrypted), isTrue);

      expect(
        () => describePrivateKey(encrypted),
        throwsA(isA<SshKeyException>()
            .having((e) => e.message, 'message', contains('passphrase'))),
      );
      expect(() => describePrivateKey(encrypted, passphrase: 'salah'),
          throwsA(isA<SshKeyException>()));
      expect(describePrivateKey(encrypted, passphrase: 'rahasia').fingerprint,
          plain.public.fingerprint);
    });
  });

  group('sanitizeKeyComment', () {
    test('karakter berbahaya diganti, panjang dibatasi', () {
      expect(sanitizeKeyComment('  Server Produksi #1  '), 'Server-Produksi-1');
      expect(sanitizeKeyComment("a'; rm -rf ~; '"), 'a-rm-rf');
      expect(sanitizeKeyComment('x\ny'), 'x-y');
      expect(sanitizeKeyComment('user@host.example_1-a'),
          'user@host.example_1-a');
      expect(sanitizeKeyComment('---'), '');
      expect(sanitizeKeyComment('a' * 200), hasLength(64));
    });
  });

  group('normalizePublicKeyLine', () {
    final good = generateEd25519Key(comment: 'c').public.line;
    final b64 = good.split(' ')[1];

    test('baris sah diterima; spasi berlebih dirapikan', () {
      expect(normalizePublicKeyLine(good), good);
      expect(normalizePublicKeyLine('  ssh-ed25519   $b64   c  '), good);
      expect(normalizePublicKeyLine('ssh-ed25519 $b64'), 'ssh-ed25519 $b64');
    });

    test('komentar berbahaya dinetralkan', () {
      expect(normalizePublicKeyLine("ssh-ed25519 $b64 x'; reboot #"),
          'ssh-ed25519 $b64 x-reboot');
    });

    test('ditolak: baris baru, opsi, tipe asing, base64 cacat', () {
      expect(normalizePublicKeyLine('$good\nssh-rsa AAAA'), isNull);
      expect(normalizePublicKeyLine('command="evil" $good'), isNull);
      expect(normalizePublicKeyLine('ssh-evil $b64'), isNull);
      expect(normalizePublicKeyLine("ssh-ed25519 AAAA'\$(reboot)"), isNull);
      expect(normalizePublicKeyLine('ssh-ed25519'), isNull);
      expect(normalizePublicKeyLine(''), isNull);
    });

    test('ditolak bila tipe di depan ≠ tipe di dalam blob', () {
      expect(normalizePublicKeyLine('ssh-rsa $b64'), isNull);
    });
  });

  group('parseInstallOutput', () {
    test('penanda dikenali', () {
      expect(parseInstallOutput('$kKeyAddedMarker\n'), KeyInstallOutcome.added);
      expect(parseInstallOutput('motd…\n$kKeyExistsMarker\n'),
          KeyInstallOutcome.alreadyPresent);
    });

    test('tanpa penanda → KeyInstallException berisi pesan server', () {
      expect(
        () => parseInstallOutput('sh: touch: Permission denied'),
        throwsA(isA<KeyInstallException>()
            .having((e) => e.message, 'message', contains('Permission'))),
      );
      expect(() => parseInstallOutput(''),
          throwsA(isA<KeyInstallException>()));
    });
  });

  group('buildInstallKeyCommand', () {
    test('menolak masukan yang bukan public key', () {
      expect(() => buildInstallKeyCommand("x'; rm -rf ~ #"),
          throwsArgumentError);
    });
  });

  // Skrip pemasangan dijalankan SUNGGUHAN dengan /bin/sh terhadap HOME
  // sementara — memverifikasi perilaku di server tanpa butuh server.
  group('skrip pemasangan (dijalankan dengan sh lokal)', () {
    late Directory home;
    final key = generateEd25519Key(comment: 'hegiketok@uji').public.line;

    Future<String> run(String line) async {
      final r = await Process.run('sh', ['-c', buildInstallKeyCommand(line)],
          environment: {'HOME': home.path}, includeParentEnvironment: false);
      return '${r.stdout}${r.stderr}';
    }

    File authFile() => File('${home.path}/.ssh/authorized_keys');
    String mode(String path) =>
        (Process.runSync('stat', ['-f', '%Lp', path]).stdout as String).trim();

    setUp(() async {
      home = await Directory.systemTemp.createTemp('hegi_keyinstall_');
    });
    tearDown(() async {
      if (await home.exists()) await home.delete(recursive: true);
    });

    test('HOME kosong → membuat ~/.ssh (700) dan authorized_keys (600)',
        () async {
      final out = await run(key);
      expect(parseInstallOutput(out), KeyInstallOutcome.added);
      expect(authFile().readAsStringSync(), '$key\n');
      expect(mode('${home.path}/.ssh'), '700');
      expect(mode(authFile().path), '600');
    }, skip: !Platform.isMacOS ? 'memakai stat -f (BSD)' : null);

    test('idempoten: pemasangan kedua tidak menggandakan', () async {
      await run(key);
      final out = await run(key);
      expect(parseInstallOutput(out), KeyInstallOutcome.alreadyPresent);
      expect(authFile().readAsLinesSync(), [key]);
    });

    test('key sama dengan komentar berbeda dianggap sudah ada', () async {
      await run(key);
      final renamed = '${key.split(' ').take(2).join(' ')} nama-lain';
      expect(parseInstallOutput(await run(renamed)),
          KeyInstallOutcome.alreadyPresent);
      expect(authFile().readAsLinesSync(), hasLength(1));
    });

    test('key lain yang sudah ada dipertahankan', () async {
      final other = generateEd25519Key(comment: 'lama').public.line;
      Directory('${home.path}/.ssh').createSync();
      authFile().writeAsStringSync('$other\n');
      expect(parseInstallOutput(await run(key)), KeyInstallOutcome.added);
      expect(authFile().readAsLinesSync(), [other, key]);
    });

    test('berkas tanpa baris baru di akhir tidak membuat key menempel',
        () async {
      final other = generateEd25519Key(comment: 'lama').public.line;
      Directory('${home.path}/.ssh').createSync();
      authFile().writeAsStringSync(other); // tanpa \n
      await run(key);
      expect(authFile().readAsLinesSync(), [other, key]);
    });

    test('izin ~/.ssh yang salah diperbaiki lalu key terpasang', () async {
      final ssh = Directory('${home.path}/.ssh')..createSync();
      Process.runSync('chmod', ['500', ssh.path]);
      addTearDown(() => Process.runSync('chmod', ['700', ssh.path]));
      expect(parseInstallOutput(await run(key)), KeyInstallOutcome.added);
      expect(authFile().readAsLinesSync(), [key]);
    });

    test('~/.ssh terhalang berkas biasa → gagal jelas, bukan sukses palsu',
        () async {
      final blocker = File('${home.path}/.ssh')..writeAsStringSync('x');
      final out = await run(key);
      expect(() => parseInstallOutput(out),
          throwsA(isA<KeyInstallException>()));
      expect(blocker.readAsStringSync(), 'x', reason: 'tidak boleh ditimpa');
    });
  });
}
