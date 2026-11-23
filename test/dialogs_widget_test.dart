// Tes TAMPILAN: banner kegagalan koneksi, riwayat daftar host, dan dialog
// pembaruan.
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexus_term/src/data/host_providers.dart';
import 'package:nexus_term/src/features/settings/host_backups_dialog.dart';
import 'package:nexus_term/src/features/ssh/ssh_session_view.dart';
import 'package:nexus_term/src/features/updates/update_checker.dart';
import 'package:nexus_term/src/features/updates/update_ui.dart';
import 'package:nexus_term/src/models/ssh_credentials.dart';
import 'package:nexus_term/src/models/ssh_host.dart';
import 'package:nexus_term/src/ssh/ssh_errors.dart';

import 'support/fakes.dart';

Future<void> _pump(WidgetTester tester, Widget child,
    {FakeHostRepository? repo}) async {
  tester.view.physicalSize = const ui.Size(1200, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      if (repo != null) hostRepositoryProvider.overrideWithValue(repo),
    ],
    child: MaterialApp(home: Scaffold(body: child)),
  ));
}

Widget _opener(Future<void> Function(BuildContext) open) => Builder(
      builder: (context) => ElevatedButton(
          onPressed: () => open(context), child: const Text('open')),
    );

SshHost _h(String id, String label) =>
    SshHost(id: id, label: label, host: '10.0.0.1', username: 'u');

void main() {
  group('ConnectionFailureBanner', () {
    final auth = describeSshError(Exception('SSHAuthFailError'),
        credentials: const SshCredentials(
            host: 'h', username: 'deploy!x', password: 'p'));

    testWidgets('login ditolak: pesan, saran, dan kedua tombol bekerja',
        (tester) async {
      var retried = 0, edited = 0;
      await _pump(
        tester,
        ConnectionFailureBanner(
          failure: auth,
          onRetry: () => retried++,
          onEditHost: () => edited++,
        ),
      );
      expect(find.text('Login ditolak untuk user "deploy!x".'), findsOneWidget);
      expect(find.text('Periksa username dan password.'), findsOneWidget);

      await tester.tap(find.text('Edit host'));
      await tester.tap(find.text('Coba lagi'));
      expect((edited, retried), (1, 1));
    });

    testWidgets('sesi tanpa host tersimpan → tanpa tombol Edit host',
        (tester) async {
      await _pump(tester,
          ConnectionFailureBanner(failure: auth, onRetry: () {}));
      expect(find.text('Edit host'), findsNothing);
      expect(find.text('Coba lagi'), findsOneWidget);
    });

    testWidgets('timeout → Edit host tidak ditawarkan (bukan soal data host)',
        (tester) async {
      await _pump(
        tester,
        ConnectionFailureBanner(
          failure: describeSshError(Exception('Connection timed out')),
          onRetry: () {},
          onEditHost: () {},
        ),
      );
      expect(find.text('Edit host'), findsNothing);
      expect(find.textContaining('timeout'), findsOneWidget);
    });
  });

  group('riwayat daftar host', () {
    test('format waktu & ringkasan', () {
      expect(formatBackupTime(DateTime(2026, 11, 23, 9, 5)),
          '23 Nov 2026, 09.05');
      expect(summarizeBackupHosts([]), 'kosong');
      expect(summarizeBackupHosts(['a', 'b']), 'a, b');
      expect(summarizeBackupHosts(['a', 'b', 'c', 'd', 'e']),
          'a, b, c, +2 lainnya');
    });

    testWidgets('belum ada cadangan → penjelasan, bukan daftar kosong',
        (tester) async {
      await _pump(tester, _opener(showHostBackupsDialog),
          repo: FakeHostRepository());
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Belum ada cadangan'), findsOneWidget);
    });

    testWidgets('pulihkan butuh konfirmasi; Batal tidak mengubah apa pun',
        (tester) async {
      final repo = FakeHostRepository(hosts: [_h('x', 'sekarang')])
        ..backups = [
          fakeBackup(DateTime(2026, 11, 23, 13, 52),
              [_h('a', 'web-01'), _h('b', 'db-01')]),
        ];
      await _pump(tester, _opener(showHostBackupsDialog), repo: repo);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('23 Nov 2026, 13.52  ·  2 host'), findsOneWidget);
      expect(find.text('web-01, db-01'), findsOneWidget);

      await tester.tap(find.text('Pulihkan'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Ganti daftar host sekarang'), findsOneWidget);
      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();
      expect(repo.restored, isNull);
      expect(repo.hosts.single.label, 'sekarang');
    });

    testWidgets('konfirmasi → daftar dipulihkan & diberi tahu', (tester) async {
      final repo = FakeHostRepository(hosts: [_h('x', 'sekarang')])
        ..backups = [
          fakeBackup(DateTime(2026, 11, 23, 13, 52),
              [_h('a', 'web-01'), _h('b', 'db-01')]),
        ];
      await _pump(tester, _opener(showHostBackupsDialog), repo: repo);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pulihkan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ya, pulihkan'));
      await tester.pumpAndSettle();

      expect(repo.restored, isNotNull);
      expect(repo.hosts.map((h) => h.label), ['web-01', 'db-01']);
      expect(find.textContaining('2 host dipulihkan'), findsOneWidget);
    });
  });

  group('dialog pembaruan', () {
    const asset = ReleaseAsset(
      name: 'HegiKetok-1.2.0-macos.dmg',
      url: 'https://github.com/o/r/releases/download/v1.2.0/x.dmg',
      size: 22020096,
      sha256:
          '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
    );

    testWidgets('dengan paket macOS: versi, catatan, ukuran, tombol unduh',
        (tester) async {
      await _pump(
        tester,
        _opener((c) => showUpdateDialog(
            c,
            const UpdateInfo(
                version: '1.2.0',
                url: 'https://github.com/o/r/releases/tag/v1.2.0',
                notes: '- Perbaikan A\n- Fitur B',
                asset: asset))),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Versi 1.2.0 sudah rilis'), findsOneWidget);
      expect(find.textContaining('Fitur B'), findsOneWidget);
      expect(find.text('HegiKetok-1.2.0-macos.dmg · 21.0 MB'), findsOneWidget);
      expect(find.textContaining('SHA-256'), findsOneWidget);
      expect(find.text('Unduh & buka'), findsOneWidget);
      expect(find.text('Halaman rilis'), findsOneWidget);
    });

    testWidgets('tanpa paket macOS: arahkan ke halaman rilis, tanpa unduh',
        (tester) async {
      await _pump(
        tester,
        _opener((c) => showUpdateDialog(
            c,
            const UpdateInfo(
                version: '1.2.0',
                url: 'https://github.com/o/r/releases/tag/v1.2.0'))),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.textContaining('tidak menyertakan paket macOS'),
          findsOneWidget);
      expect(find.text('Unduh & buka'), findsNothing);
      expect(find.text('Halaman rilis'), findsOneWidget);

      await tester.tap(find.text('Tutup'));
      await tester.pumpAndSettle();
      expect(find.text('Pembaruan tersedia'), findsNothing);
    });
  });
}
