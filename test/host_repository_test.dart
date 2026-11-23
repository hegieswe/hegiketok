import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_term/src/data/host_repository.dart';
import 'package:nexus_term/src/features/hosts/host_editor.dart'
    show describeSaveError;
import 'package:nexus_term/src/models/ssh_host.dart';

/// Keychain tiruan: menyimpan di memori, dan bisa disuruh gagal seperti
/// Keychain macOS sungguhan (PlatformException -25293).
class _FakeKeychain implements FlutterSecureStorage {
  final Map<String, String> data = {};

  /// Kunci yang penulisannya harus gagal (null = semua berhasil).
  bool Function(String key)? failWrite;

  static PlatformException authFailed() => PlatformException(
        code: 'Unexpected security result code',
        message: 'Code: -25293, Message: The user name or passphrase you '
            'entered is not correct.',
        details: -25293,
      );

  @override
  dynamic noSuchMethod(Invocation i) {
    final key = i.namedArguments[#key] as String?;
    switch (i.memberName) {
      case #write:
        if (failWrite?.call(key!) ?? false) {
          return Future<void>.error(authFailed());
        }
        final value = i.namedArguments[#value] as String?;
        if (value == null) {
          data.remove(key);
        } else {
          data[key!] = value;
        }
        return Future<void>.value();
      case #read:
        return Future<String?>.value(data[key]);
      case #delete:
        data.remove(key);
        return Future<void>.value();
    }
    return super.noSuchMethod(i);
  }
}

SshHost _host(String id, {String label = 'srv'}) =>
    SshHost(id: id, label: label, host: '10.0.0.1', username: 'u');

void main() {
  late Directory dir;
  late _FakeKeychain keychain;
  late HostRepository repo;

  File hostsFile() => File('${dir.path}/hosts.json');
  List<dynamic> onDisk() =>
      jsonDecode(hostsFile().readAsStringSync()) as List<dynamic>;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('hegi_repo_test_');
    keychain = _FakeKeychain();
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

  group('describeSaveError', () {
    test('-25293 → penjelasan + langkah perbaikan, tanpa teks teknis mentah',
        () {
      final msg = describeSaveError(_FakeKeychain.authFailed());
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
