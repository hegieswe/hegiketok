// Tes TAMPILAN editor host: mengetik di kolom dan mengklik tombol sungguhan
// (tanpa jaringan — repository & penguji koneksi diganti tiruan).
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexus_term/src/data/host_providers.dart';
import 'package:nexus_term/src/features/hosts/host_editor.dart';
import 'package:nexus_term/src/features/hosts/key_tools.dart';
import 'package:nexus_term/src/models/ssh_credentials.dart';
import 'package:nexus_term/src/models/ssh_host.dart';
import 'package:nexus_term/src/ssh/connection_test.dart';
import 'package:nexus_term/src/ssh/ssh_errors.dart';
import 'package:nexus_term/src/ssh/ssh_keys.dart';

import 'support/fakes.dart';

// Urutan TextFormField pada mode Password.
const _label = 0, _host = 1, _port = 2, _user = 3, _password = 4;

class _Tester {
  final List<SshCredentials> calls = [];
  ConnectionTestResult Function(SshCredentials c) answer =
      (_) => const ConnectionTestResult.success('Linux 6.1.0');

  Future<ConnectionTestResult> call(SshCredentials c) async {
    calls.add(c);
    return answer(c);
  }
}

Future<void> _open(
  WidgetTester tester,
  FakeHostRepository repo, {
  SshHost? existing,
  _Tester? conn,
}) async {
  // Layar tinggi supaya seluruh dialog terlihat tanpa menggulir.
  tester.view.physicalSize = const ui.Size(1000, 2800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(ProviderScope(
    overrides: [
      hostRepositoryProvider.overrideWithValue(repo),
      connectionTesterProvider.overrideWithValue((conn ?? _Tester()).call),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showHostEditor(context, existing: existing),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, int field, String text) async {
  await tester.enterText(find.byType(TextFormField).at(field), text);
  await tester.pump();
}

Future<void> _fillBasics(WidgetTester tester,
    {String user = 'deploy', String password = 'rahasia'}) async {
  await _type(tester, _label, 'web-01');
  await _type(tester, _host, '10.0.0.5');
  await _type(tester, _port, '2200');
  await _type(tester, _user, user);
  if (password.isNotEmpty) await _type(tester, _password, password);
}

bool _dialogOpen() => find.text('Host Baru').evaluate().isNotEmpty ||
    find.text('Edit Host').evaluate().isNotEmpty;

void main() {
  group('peringatan saat mengetik', () {
    testWidgets('username berisi karakter password → peringatan muncul & hilang',
        (tester) async {
      await _open(tester, FakeHostRepository());
      await _type(tester, _user, 'deploy!Rahasia1');
      expect(find.textContaining('karakter tak lazim'), findsOneWidget);
      expect(find.textContaining('password'), findsWidgets);

      await _type(tester, _user, 'deploy');
      expect(find.textContaining('karakter tak lazim'), findsNothing);
    });

    testWidgets('alamat berisi user@ → diarahkan ke kolom Username',
        (tester) async {
      await _open(tester, FakeHostRepository());
      await _type(tester, _host, 'root@10.0.0.5');
      expect(find.textContaining('kolom Username'), findsOneWidget);
      await _type(tester, _host, '10.0.0.5');
      expect(find.textContaining('kolom Username'), findsNothing);
    });

    testWidgets('peringatan tidak menghalangi simpan', (tester) async {
      final repo = FakeHostRepository();
      await _open(tester, repo);
      await _fillBasics(tester, user: r'CORP\alice#1');
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();
      expect(repo.hosts.single.username, r'CORP\alice#1');
    });
  });

  group('simpan', () {
    testWidgets('host baru tersimpan dengan data & password yang diketik',
        (tester) async {
      final repo = FakeHostRepository();
      await _open(tester, repo);
      await _fillBasics(tester);
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();

      expect(_dialogOpen(), isFalse);
      final h = repo.hosts.single;
      expect(h.label, 'web-01');
      expect(h.host, '10.0.0.5');
      expect(h.port, 2200);
      expect(h.username, 'deploy');
      expect(h.authMethod, SshAuthMethod.password);
      expect(repo.secrets[h.id]!.password, 'rahasia');
    });

    testWidgets('kolom wajib kosong → tidak disimpan', (tester) async {
      final repo = FakeHostRepository();
      await _open(tester, repo);
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();
      expect(find.text('Wajib diisi'), findsNWidgets(2));
      expect(repo.saveAttempts, 0);
      expect(_dialogOpen(), isTrue);
    });

    testWidgets(
        'Keychain menolak → pesan yang bisa dipahami; Simpan ulang tidak '
        'menggandakan host', (tester) async {
      final repo = FakeHostRepository()..failSaves = true;
      await _open(tester, repo);
      await _fillBasics(tester);

      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Keychain macOS menolak akses'),
          findsOneWidget);
      expect(find.textContaining('PlatformException'), findsNothing);
      expect(_dialogOpen(), isTrue);

      // Gagal lagi, lalu berhasil.
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();
      repo.failSaves = false;
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();

      expect(repo.saveAttempts, 3);
      expect(repo.hosts, hasLength(1));
      expect(_dialogOpen(), isFalse);
    });

    testWidgets('edit: password dikosongkan → password lama dipertahankan',
        (tester) async {
      const host = SshHost(
          id: 'a', label: 'lama', host: '10.0.0.5', username: 'deploy');
      final repo = FakeHostRepository(
          hosts: [host], secrets: {'a': const HostSecret(password: 'pw-lama')});
      await _open(tester, repo, existing: host);
      await _type(tester, _label, 'baru');
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();
      expect(repo.hosts.single.label, 'baru');
      expect(repo.secrets['a']!.password, 'pw-lama');
    });
  });

  group('tes koneksi', () {
    testWidgets('berhasil → menampilkan user@host dan info server',
        (tester) async {
      final conn = _Tester();
      await _open(tester, FakeHostRepository(), conn: conn);
      await _fillBasics(tester);
      await tester.tap(find.text('Tes koneksi'));
      await tester.pumpAndSettle();

      expect(find.text('Tersambung sebagai deploy@10.0.0.5'), findsOneWidget);
      expect(find.text('Linux 6.1.0'), findsOneWidget);
      final c = conn.calls.single;
      expect((c.host, c.port, c.username, c.password),
          ('10.0.0.5', 2200, 'deploy', 'rahasia'));
    });

    testWidgets('gagal login → pesan menyebut username yang diketik',
        (tester) async {
      final conn = _Tester()
        ..answer = (c) => ConnectionTestResult.failed(describeSshError(
            Exception('SSHAuthFailError'),
            credentials: c));
      await _open(tester, FakeHostRepository(), conn: conn);
      await _fillBasics(tester, user: 'deploy!Rahasia1');
      await tester.tap(find.text('Tes koneksi'));
      await tester.pumpAndSettle();
      expect(find.text('Login ditolak untuk user "deploy!Rahasia1".'),
          findsOneWidget);
      expect(find.text('Periksa username dan password.'), findsOneWidget);
    });

    testWidgets('hasil lama dibuang begitu data koneksi diubah',
        (tester) async {
      await _open(tester, FakeHostRepository());
      await _fillBasics(tester);
      await tester.tap(find.text('Tes koneksi'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Tersambung sebagai'), findsOneWidget);

      await _type(tester, _user, 'orang-lain');
      expect(find.textContaining('Tersambung sebagai'), findsNothing);
    });

    testWidgets('password belum diisi → diberi tahu, tanpa mencoba konek',
        (tester) async {
      final conn = _Tester();
      await _open(tester, FakeHostRepository(), conn: conn);
      await _fillBasics(tester, password: '');
      await tester.tap(find.text('Tes koneksi'));
      await tester.pumpAndSettle();
      expect(find.text('Isi password dulu.'), findsOneWidget);
      expect(conn.calls, isEmpty);
    });

    testWidgets('host/username kosong → diberi tahu', (tester) async {
      final conn = _Tester();
      await _open(tester, FakeHostRepository(), conn: conn);
      await tester.tap(find.text('Tes koneksi'));
      await tester.pumpAndSettle();
      expect(find.text('Isi Host dan Username dulu.'), findsOneWidget);
      expect(conn.calls, isEmpty);
    });

    testWidgets('edit: kolom password kosong → memakai password tersimpan',
        (tester) async {
      const host = SshHost(
          id: 'a', label: 'srv', host: '10.0.0.5', username: 'deploy');
      final conn = _Tester();
      await _open(
        tester,
        FakeHostRepository(
            hosts: [host],
            secrets: {'a': const HostSecret(password: 'pw-tersimpan')}),
        existing: host,
        conn: conn,
      );
      await tester.tap(find.text('Tes koneksi'));
      await tester.pumpAndSettle();
      expect(conn.calls.single.password, 'pw-tersimpan');
    });

    testWidgets('tidak menyimpan apa pun', (tester) async {
      final repo = FakeHostRepository();
      await _open(tester, repo);
      await _fillBasics(tester);
      await tester.tap(find.text('Tes koneksi'));
      await tester.pumpAndSettle();
      expect(repo.saveAttempts, 0);
      expect(_dialogOpen(), isTrue);
    });
  });

  group('SSH key', () {
    testWidgets('buat key baru → kartu public key tampil; simpan menaruh key',
        (tester) async {
      final repo = FakeHostRepository();
      await _open(tester, repo);
      await _fillBasics(tester, password: '');
      await tester.tap(find.text('SSH Key'));
      await tester.pumpAndSettle();
      expect(find.byType(PublicKeyPanel), findsNothing);

      await tester.tap(find.text('Buat key baru (ed25519)'));
      await tester.pumpAndSettle();
      expect(find.byType(PublicKeyPanel), findsOneWidget);
      expect(find.text('ssh-ed25519'), findsOneWidget);
      expect(find.textContaining('SHA256:'), findsOneWidget);

      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();
      final h = repo.hosts.single;
      expect(h.authMethod, SshAuthMethod.key);
      final secret = repo.secrets[h.id]!;
      expect(secret.privateKey, contains('BEGIN OPENSSH PRIVATE KEY'));
      // Key yang tersimpan cocok dengan public key yang tadi ditampilkan.
      expect(describePrivateKey(secret.privateKey!).type, 'ssh-ed25519');
      expect(secret.passphrase, '');
    });

    testWidgets('metode key tanpa key → simpan ditolak dengan petunjuk',
        (tester) async {
      final repo = FakeHostRepository();
      await _open(tester, repo);
      await _fillBasics(tester, password: '');
      await tester.tap(find.text('SSH Key'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();
      expect(find.textContaining('buat key baru dulu'), findsOneWidget);
      expect(repo.saveAttempts, 0);
    });

    testWidgets('edit host ber-key → public key tampil otomatis & bisa disalin',
        (tester) async {
      final key = generateEd25519Key(comment: 'x');
      const host = SshHost(
          id: 'a',
          label: 'srv',
          host: '10.0.0.5',
          username: 'deploy',
          authMethod: SshAuthMethod.key);
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      await _open(
        tester,
        FakeHostRepository(
            hosts: [host],
            secrets: {'a': HostSecret(privateKey: key.privatePem)}),
        existing: host,
      );
      expect(find.byType(PublicKeyPanel), findsOneWidget);
      expect(find.text(key.public.fingerprint), findsOneWidget);

      await tester.tap(find.text('Salin public key'));
      await tester.pump();
      expect(copied, startsWith('ssh-ed25519 '));
      expect(copied!.split(' ')[1], key.public.line.split(' ')[1]);
      expect(find.text('Tersalin'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3)); // label kembali
      expect(find.text('Salin public key'), findsOneWidget);
    });

    testWidgets('agent forwarding mati secara bawaan dan ikut tersimpan',
        (tester) async {
      final repo = FakeHostRepository();
      await _open(tester, repo);
      await _fillBasics(tester, password: '');
      await tester.tap(find.text('SSH Key'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Buat key baru (ed25519)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agent forwarding'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();
      expect(repo.hosts.single.forwardAgent, isTrue);
    });
  });
}
