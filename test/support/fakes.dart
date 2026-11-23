// Tiruan bersama untuk pengujian: Keychain di memori dan repository host di
// memori (tanpa I/O berkas, sehingga aman dipakai di dalam testWidgets).
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:nexus_term/src/data/host_repository.dart';
import 'package:nexus_term/src/models/ssh_host.dart';

/// Galat yang sama dengan yang dilempar Keychain macOS saat menolak akses.
PlatformException keychainAuthFailed() => PlatformException(
      code: 'Unexpected security result code',
      message: 'Code: -25293, Message: The user name or passphrase you '
          'entered is not correct.',
      details: -25293,
    );

/// Keychain tiruan: menyimpan di memori, dan bisa disuruh gagal.
class FakeKeychain implements FlutterSecureStorage {
  final Map<String, String> data = {};

  /// Kunci yang penulisannya harus gagal (null = semua berhasil).
  bool Function(String key)? failWrite;

  @override
  dynamic noSuchMethod(Invocation i) {
    final key = i.namedArguments[#key] as String?;
    switch (i.memberName) {
      case #write:
        if (failWrite?.call(key!) ?? false) {
          return Future<void>.error(keychainAuthFailed());
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

/// Repository host di memori dengan semantik yang sama dengan aslinya
/// (rahasia null tidak diubah; kegagalan tidak meninggalkan host yatim).
class FakeHostRepository extends HostRepository {
  FakeHostRepository({List<SshHost>? hosts, Map<String, HostSecret>? secrets})
      : hosts = [...?hosts],
        secrets = {...?secrets};

  final List<SshHost> hosts;
  final Map<String, HostSecret> secrets;

  /// Bila true, penyimpanan gagal seperti Keychain yang menolak akses.
  bool failSaves = false;
  int saveAttempts = 0;

  List<HostBackup> backups = [];
  HostBackup? restored;

  @override
  Future<List<SshHost>> loadHosts() async => List.of(hosts);

  @override
  Future<HostSecret> loadSecret(String id) async =>
      secrets[id] ?? const HostSecret();

  @override
  Future<void> saveHost(
    SshHost host, {
    String? password,
    String? privateKey,
    String? passphrase,
  }) async {
    saveAttempts++;
    if (failSaves) throw keychainAuthFailed();
    final old = secrets[host.id] ?? const HostSecret();
    secrets[host.id] = HostSecret(
      password: password ?? old.password,
      privateKey: privateKey ?? old.privateKey,
      passphrase: passphrase ?? old.passphrase,
    );
    final i = hosts.indexWhere((h) => h.id == host.id);
    if (i >= 0) {
      hosts[i] = host;
    } else {
      hosts.add(host);
    }
  }

  @override
  Future<void> deleteHost(String id) async {
    hosts.removeWhere((h) => h.id == id);
    secrets.remove(id);
  }

  @override
  Future<List<HostBackup>> listBackups() async => List.of(backups);

  @override
  Future<int> restoreBackup(HostBackup backup) async {
    restored = backup;
    hosts
      ..clear()
      ..addAll(backup.hosts);
    return backup.hosts.length;
  }
}

/// Cadangan tiruan (berkasnya tidak pernah dibuka oleh [FakeHostRepository]).
HostBackup fakeBackup(DateTime time, List<SshHost> hosts) => HostBackup(
    file: File('/dev/null/hosts-${time.millisecondsSinceEpoch}.json'),
    time: time,
    hosts: hosts);
