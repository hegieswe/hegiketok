import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_term/src/data/host_repository.dart';
import 'package:nexus_term/src/features/hosts/host_editor.dart'
    show describeSaveError;
import 'package:nexus_term/src/models/ssh_host.dart';

import 'support/fakes.dart';

SshHost _host(String id, {String label = 'srv'}) =>
    SshHost(id: id, label: label, host: '10.0.0.1', username: 'u');

void main() {
  late Directory dir;
  late FakeKeychain keychain;
  late HostRepository repo;

  File hostsFile() => File('${dir.path}/hosts.json');
  List<dynamic> onDisk() =>
      jsonDecode(hostsFile().readAsStringSync()) as List<dynamic>;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('hegi_repo_test_');
    keychain = FakeKeychain();
    repo = HostRepository(secureStorage: keychain, directory: dir);
  });
  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('simpan berhasil: host di daftar + rahasia di Keychain', () async {
    await repo.saveHost(_host('a'), password: 'pw');
    expect((await repo.loadHosts()).single.id, 'a');
    expect((await repo.loadSecret('a')).password, 'pw');
  });

  test('Keychain gagal → host baru TIDAK masuk daftar (tak ada host yatim)',
      () async {
    keychain.failWrite = (_) => true;
    await expectLater(repo.saveHost(_host('a'), password: 'pw'),
        throwsA(isA<PlatformException>()));
    expect(await repo.loadHosts(), isEmpty);
    expect(onDisk(), isEmpty);
    expect(keychain.data, isEmpty);
  });

  test('gagal berulang lalu berhasil → tetap satu host (regresi 5 duplikat)',
      () async {
    keychain.failWrite = (_) => true;
    for (var i = 0; i < 5; i++) {
      await expectLater(repo.saveHost(_host('a'), password: 'pw'),
          throwsA(anything));
    }
    keychain.failWrite = null;
    await repo.saveHost(_host('a'), password: 'pw');
    expect(await repo.loadHosts(), hasLength(1));
  });

  test('gagal di rahasia kedua → rahasia pertama host baru dibersihkan',
      () async {
    keychain.failWrite = (k) => k.endsWith('_passphrase');
    await expectLater(
        repo.saveHost(_host('a'), privateKey: 'KEY', passphrase: 'pp'),
        throwsA(anything));
    expect(keychain.data, isEmpty, reason: 'private key tak boleh tertinggal');
    expect(await repo.loadHosts(), isEmpty);
  });

  test('edit yang gagal tidak merusak host & rahasia yang sudah ada', () async {
    await repo.saveHost(_host('a', label: 'lama'), password: 'pw-lama');
    keychain.failWrite = (_) => true;
    await expectLater(
        repo.saveHost(_host('a', label: 'baru'), password: 'pw-baru'),
        throwsA(anything));
    expect((await repo.loadHosts()).single.label, 'lama');
    expect((await repo.loadSecret('a')).password, 'pw-lama');
  });

  test('rahasia null tidak mengubah yang tersimpan', () async {
    await repo.saveHost(_host('a'), password: 'pw');
    await repo.saveHost(_host('a', label: 'ganti-nama'));
    expect((await repo.loadSecret('a')).password, 'pw');
    expect((await repo.loadHosts()).single.label, 'ganti-nama');
  });

  test('hosts.json rusak → simpan/hapus menolak, berkas TIDAK ditimpa',
      () async {
    await repo.saveHost(_host('a'), password: 'pw');
    const rusak = '[{"id": "a", "label": ';
    hostsFile().writeAsStringSync(rusak);
    await expectLater(
        repo.saveHost(_host('b'), password: 'x'), throwsA(isA<FormatException>()));
    await expectLater(repo.deleteHost('a'), throwsA(isA<FormatException>()));
    expect(hostsFile().readAsStringSync(), rusak);
    expect(keychain.data.keys.where((k) => k.contains('host_b_')), isEmpty);
  });

  test('hapus host membuang rahasianya', () async {
    await repo.saveHost(_host('a'), password: 'pw', privateKey: 'K');
    await repo.deleteHost('a');
    expect(await repo.loadHosts(), isEmpty);
    expect(keychain.data, isEmpty);
  });

  group('cadangan otomatis', () {
    late DateTime now;
    setUp(() {
      now = DateTime.utc(2026, 11, 23, 6, 0, 0);
      // Jam maju 1 menit tiap dibaca → nama cadangan unik & terurut.
      repo = HostRepository(
        secureStorage: keychain,
        directory: dir,
        clock: () => now = now.add(const Duration(minutes: 1)),
      );
    });

    Directory backupDir() => Directory('${dir.path}/backups');

    test('host pertama: belum ada yang perlu dicadangkan', () async {
      await repo.saveHost(_host('a'), password: 'pw');
      expect(await repo.listBackups(), isEmpty);
    });

    test('tiap perubahan menyimpan versi SEBELUMNYA', () async {
      await repo.saveHost(_host('a', label: 'satu'), password: 'pw');
      await repo.saveHost(_host('b', label: 'dua'), password: 'pw');
      await repo.deleteHost('a');

      final backups = await repo.listBackups();
      expect(backups, hasLength(2));
      // Terbaru dulu: sebelum penghapusan ada dua host.
      expect(backups[0].hosts.map((h) => h.label), ['satu', 'dua']);
      expect(backups[1].hosts.map((h) => h.label), ['satu']);
      expect(backups[0].time.isAfter(backups[1].time), isTrue);
    });

    test('menyimpan tanpa perubahan tidak menambah cadangan', () async {
      await repo.saveHost(_host('a'), password: 'pw');
      await repo.saveHost(_host('b'), password: 'pw');
      final before = (await repo.listBackups()).length;
      await repo.saveHost(_host('b'), password: 'pw-baru'); // metadata sama
      expect((await repo.listBackups()).length, before);
    });

    test('daftar yang dikosongkan bisa dipulihkan penuh', () async {
      for (final id in ['a', 'b', 'c']) {
        await repo.saveHost(_host(id, label: 'srv-$id'), password: 'pw-$id');
      }
      // Rahasia dihapus bersama host; ketiganya hilang dari daftar.
      for (final id in ['a', 'b', 'c']) {
        await repo.deleteHost(id);
      }
      expect(await repo.loadHosts(), isEmpty);

      final full = (await repo.listBackups())
          .firstWhere((b) => b.hosts.length == 3);
      expect(await repo.restoreBackup(full), 3);
      expect((await repo.loadHosts()).map((h) => h.label),
          ['srv-a', 'srv-b', 'srv-c']);
    });

    test('pemulihan mencadangkan daftar yang digantikan (bisa dibatalkan)',
        () async {
      await repo.saveHost(_host('a', label: 'lama'), password: 'pw');
      await repo.saveHost(_host('a', label: 'baru'), password: 'pw');
      final old = (await repo.listBackups()).single;
      await repo.restoreBackup(old);
      expect((await repo.loadHosts()).single.label, 'lama');
      // Versi "baru" kini ada di riwayat.
      expect(
        (await repo.listBackups()).any((b) => b.hosts.single.label == 'baru'),
        isTrue,
      );
    });

    test('rahasia di Keychain bertahan melewati pemulihan metadata', () async {
      await repo.saveHost(_host('a', label: 'v1'), password: 'pw');
      await repo.saveHost(_host('a', label: 'v2'));
      await repo.restoreBackup((await repo.listBackups()).single);
      expect((await repo.loadSecret('a')).password, 'pw');
    });

    test('hanya ${HostRepository.maxBackups} cadangan terbaru yang disimpan',
        () async {
      for (var i = 0; i < HostRepository.maxBackups + 6; i++) {
        await repo.saveHost(_host('a', label: 'v$i'), password: 'pw');
      }
      final backups = await repo.listBackups();
      expect(backups, hasLength(HostRepository.maxBackups));
      // Yang paling baru = versi sebelum simpan terakhir.
      expect(backups.first.hosts.single.label,
          'v${HostRepository.maxBackups + 4}');
    });

    test('cadangan rusak dilewati, tidak membuat daftar gagal dimuat',
        () async {
      await repo.saveHost(_host('a', label: 'v1'), password: 'pw');
      await repo.saveHost(_host('a', label: 'v2'), password: 'pw');
      File('${backupDir().path}/hosts-20990101-000000-000.json')
          .writeAsStringSync('{ rusak');
      File('${backupDir().path}/catatan.txt').writeAsStringSync('bukan cadangan');
      final backups = await repo.listBackups();
      expect(backups, hasLength(1));
      expect(backups.single.hosts.single.label, 'v1');
    });

    test('folder cadangan tak bisa dibuat → penyimpanan tetap berhasil',
        () async {
      await repo.saveHost(_host('a', label: 'v1'), password: 'pw');
      // Halangi folder backups dengan berkas biasa.
      File('${dir.path}/backups').writeAsStringSync('penghalang');
      await repo.saveHost(_host('a', label: 'v2'), password: 'pw');
      expect((await repo.loadHosts()).single.label, 'v2');
    });

    test('penulisan atomik: tidak ada berkas .tmp tertinggal', () async {
      await repo.saveHost(_host('a'), password: 'pw');
      await repo.saveHost(_host('b'), password: 'pw');
      expect(File('${dir.path}/hosts.json.tmp').existsSync(), isFalse);
      expect(onDisk(), hasLength(2));
    });
  });

  group('describeSaveError', () {
    test('-25293 → penjelasan + langkah perbaikan, tanpa teks teknis mentah',
        () {
      final msg = describeSaveError(keychainAuthFailed());
      expect(msg, contains('Keychain'));
      expect(msg, contains('buka lagi'));
      expect(msg, contains('belum disimpan'));
      expect(msg, isNot(contains('PlatformException')));
    });

    test('hosts.json rusak dijelaskan', () {
      expect(describeSaveError(const FormatException('x')),
          contains('hosts.json'));
    });

    test('galat lain tetap ditampilkan', () {
      expect(describeSaveError(StateError('aneh')), contains('aneh'));
    });
  });
}
