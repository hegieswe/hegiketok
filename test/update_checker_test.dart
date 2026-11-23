import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_term/src/features/updates/update_checker.dart';
import 'package:nexus_term/src/features/updates/update_ui.dart'
    show shouldAutoCheck;
import 'package:pointycastle/digests/sha256.dart';

String _sha256(List<int> bytes) {
  final d = SHA256Digest();
  final out = d.process(Uint8List.fromList(bytes));
  return out.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

Map<String, dynamic> _release({
  String tag = 'v1.2.0',
  List<Map<String, dynamic>> assets = const [],
  String? body = 'Catatan rilis',
}) =>
    {
      'tag_name': tag,
      'html_url': 'https://github.com/o/r/releases/tag/$tag',
      'body': body,
      'assets': assets,
    };

Map<String, dynamic> _asset(String name, {int size = 10, String? digest}) => {
      'name': name,
      'size': size,
      'browser_download_url': 'https://github.com/o/r/releases/download/v/$name',
      'digest': ?digest,
    };

void main() {
  test('kAppVersion selaras dengan version: di pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final m = RegExp(r'^version:\s*([^\s+]+)', multiLine: true)
        .firstMatch(pubspec);
    expect(m, isNotNull, reason: 'pubspec.yaml harus punya baris version:');
    expect(kAppVersion, m!.group(1));
  });

  group('isNewerVersion', () {
    test('membandingkan mayor/minor/patch secara numerik', () {
      expect(isNewerVersion('1.0.1', '1.0.0'), isTrue);
      expect(isNewerVersion('1.10.0', '1.9.9'), isTrue);
      expect(isNewerVersion('2.0.0', '1.99.99'), isTrue);
      expect(isNewerVersion('1.0.0', '1.0.0'), isFalse);
      expect(isNewerVersion('0.9.9', '1.0.0'), isFalse);
    });

    test('mengabaikan build metadata & melengkapi bagian yang hilang', () {
      expect(isNewerVersion('1.0.0+5', '1.0.0+1'), isFalse);
      expect(isNewerVersion('1.1', '1.0.9'), isTrue);
      expect(isNewerVersion('2', '1.9.9'), isTrue);
    });
  });

  group('parseLatestRelease', () {
    test('versi lebih baru → UpdateAvailable lengkap', () {
      final r = parseLatestRelease(
        _release(assets: [_asset('HegiKetok-macos.zip', size: 4096)]),
        current: '1.0.0',
      );
      expect(r, isA<UpdateAvailable>());
      final info = (r as UpdateAvailable).info;
      expect(info.version, '1.2.0');
      expect(info.url, 'https://github.com/o/r/releases/tag/v1.2.0');
      expect(info.notes, 'Catatan rilis');
      expect(info.asset!.name, 'HegiKetok-macos.zip');
      expect(info.asset!.size, 4096);
    });

    test('versi sama / lebih lama → UpdateUpToDate', () {
      expect(parseLatestRelease(_release(tag: 'v1.0.0'), current: '1.0.0'),
          isA<UpdateUpToDate>());
      expect(parseLatestRelease(_release(tag: '0.9.0'), current: '1.0.0'),
          isA<UpdateUpToDate>());
    });

    test('tag tanpa awalan v tetap dikenali', () {
      final r = parseLatestRelease(_release(tag: '1.5.0'), current: '1.0.0');
      expect((r as UpdateAvailable).info.version, '1.5.0');
    });

    test('tag kosong / bukan versi → UpdateFailed', () {
      expect(parseLatestRelease(_release(tag: ''), current: '1.0.0'),
          isA<UpdateFailed>());
      expect(parseLatestRelease(_release(tag: 'nightly'), current: '1.0.0'),
          isA<UpdateFailed>());
      expect(parseLatestRelease(<String, dynamic>{}, current: '1.0.0'),
          isA<UpdateFailed>());
    });

    test('catatan kosong → null; html_url asing dibuang', () {
      final json = _release(body: '   ')
        ..['html_url'] = 'https://evil.example/phish';
      final info =
          (parseLatestRelease(json, current: '1.0.0') as UpdateAvailable).info;
      expect(info.notes, isNull);
      expect(info.url, isEmpty);
    });
  });

  group('pickMacAsset', () {
    test('.dmg diutamakan di atas .zip', () {
      final a = pickMacAsset([
        _asset('HegiKetok-macos.zip'),
        _asset('HegiKetok-1.2.0.dmg'),
      ]);
      expect(a!.name, 'HegiKetok-1.2.0.dmg');
    });

    test('paket platform lain diabaikan', () {
      expect(
        pickMacAsset([
          _asset('HegiKetok-linux-x64.tar.gz'),
          _asset('HegiKetok-windows-x64.zip'),
        ]),
        isNull,
      );
    });

    test('zip macOS dikenali dari namanya', () {
      expect(pickMacAsset([_asset('app-darwin-universal.zip')])!.name,
          'app-darwin-universal.zip');
    });

    test('digest sha256 valid dibaca; yang cacat diabaikan', () {
      final hex = 'a' * 64;
      expect(pickMacAsset([_asset('x.dmg', digest: 'sha256:$hex')])!.sha256,
          hex);
      expect(pickMacAsset([_asset('x.dmg', digest: 'sha256:xyz')])!.sha256,
          isNull);
      expect(pickMacAsset([_asset('x.dmg', digest: 'md5:$hex')])!.sha256,
          isNull);
    });

    test('URL unduhan di luar github.com ditolak', () {
      final bad = _asset('x.dmg')
        ..['browser_download_url'] = 'https://evil.example/x.dmg';
      final http = _asset('y.dmg')
        ..['browser_download_url'] = 'http://github.com/o/r/y.dmg';
      expect(pickMacAsset([bad, http]), isNull);
    });

    test('masukan aneh tidak melempar', () {
      expect(pickMacAsset(null), isNull);
      expect(pickMacAsset('bukan list'), isNull);
      expect(pickMacAsset([1, 'a', null, <String, dynamic>{}]), isNull);
    });
  });

  group('safeAssetFileName', () {
    test('membuang komponen path & awalan titik', () {
      expect(safeAssetFileName('../../etc/passwd'), 'passwd');
      expect(safeAssetFileName(r'..\..\evil.dmg'), 'evil.dmg');
      expect(safeAssetFileName('.hidden.dmg'), 'hidden.dmg');
      expect(safeAssetFileName('HegiKetok-1.2.0.dmg'), 'HegiKetok-1.2.0.dmg');
    });

    test('nama kosong → nama bawaan', () {
      expect(safeAssetFileName(''), 'HegiKetok-update');
      expect(safeAssetFileName('../'), 'HegiKetok-update');
    });
  });

  group('shouldAutoCheck', () {
    final now = DateTime(2026, 11, 22, 12);

    test('dimatikan → tidak pernah', () {
      expect(shouldAutoCheck(enabled: false, lastCheck: null, now: now),
          isFalse);
    });

    test('belum pernah → ya', () {
      expect(
          shouldAutoCheck(enabled: true, lastCheck: null, now: now), isTrue);
    });

    test('baru saja → tidak; lewat 24 jam → ya', () {
      expect(
        shouldAutoCheck(
            enabled: true,
            lastCheck: now.subtract(const Duration(hours: 3)),
            now: now),
        isFalse,
      );
      expect(
        shouldAutoCheck(
            enabled: true,
            lastCheck: now.subtract(const Duration(hours: 24)),
            now: now),
        isTrue,
      );
    });

    test('jam sistem mundur tidak mengunci pemeriksaan', () {
      expect(
        shouldAutoCheck(
            enabled: true,
            lastCheck: now.add(const Duration(days: 30)),
            now: now),
        isTrue,
      );
    });
  });

  group('downloadReleaseAsset', () {
    late HttpServer server;
    late Directory tmp;
    late List<int> payload;
    // Mode respons server untuk tiap tes.
    var mode = 'ok';

    setUp(() async {
      mode = 'ok';
      payload = List<int>.generate(200000, (i) => (i * 31 + 7) % 256);
      tmp = await Directory.systemTemp.createTemp('hegi_update_test_');
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        final res = req.response;
        switch (mode) {
          case '404':
            res.statusCode = 404;
            await res.close();
          case 'truncated':
            // Kirim separuh tanpa Content-Length → klien melihat stream usai.
            res.add(payload.sublist(0, payload.length ~/ 2));
            await res.close();
          default:
            res.contentLength = payload.length;
            // Kirim bertahap agar ada beberapa laporan kemajuan.
            for (var i = 0; i < payload.length; i += 20000) {
              res.add(payload.sublist(
                  i, (i + 20000).clamp(0, payload.length)));
              await res.flush();
            }
            await res.close();
        }
      });
    });

    tearDown(() async {
      await server.close(force: true);
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    ReleaseAsset asset({String name = 'HegiKetok-macos.zip', String? sha}) =>
        ReleaseAsset(
          name: name,
          url: 'http://127.0.0.1:${server.port}/$name',
          size: payload.length,
          sha256: sha,
        );

    test('unduh utuh + checksum cocok → berkas final, tanpa .part', () async {
      final fractions = <double?>[];
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final f = await downloadReleaseAsset(
        asset(sha: _sha256(payload)),
        directory: tmp,
        onProgress: fractions.add,
        httpClient: client,
      );
      expect(f.path, '${tmp.path}/HegiKetok-macos.zip');
      expect(await f.readAsBytes(), payload);
      expect(File('${f.path}.part').existsSync(), isFalse);
      expect(fractions.first, 0);
      expect(fractions.last, 1.0);
      expect(fractions.length, greaterThanOrEqualTo(2));
    });

    test('checksum tidak cocok → ditolak dan tidak meninggalkan berkas',
        () async {
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      await expectLater(
        downloadReleaseAsset(asset(sha: 'b' * 64),
            directory: tmp, httpClient: client),
        throwsA(isA<UpdateDownloadException>().having(
            (e) => e.message, 'message', contains('Checksum'))),
      );
      expect(tmp.listSync(), isEmpty);
    });

    test('unduhan terpotong → ditolak dan dibersihkan', () async {
      mode = 'truncated';
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      await expectLater(
        downloadReleaseAsset(asset(), directory: tmp, httpClient: client),
        throwsA(isA<UpdateDownloadException>().having(
            (e) => e.message, 'message', contains('tidak lengkap'))),
      );
      expect(tmp.listSync(), isEmpty);
    });

    test('HTTP 404 → galat yang jelas', () async {
      mode = '404';
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      await expectLater(
        downloadReleaseAsset(asset(), directory: tmp, httpClient: client),
        throwsA(isA<UpdateDownloadException>()
            .having((e) => e.message, 'message', contains('404'))),
      );
      expect(tmp.listSync(), isEmpty);
    });

    test('dibatalkan → UpdateDownloadCancelled dan .part dihapus', () async {
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      await expectLater(
        downloadReleaseAsset(
          asset(),
          directory: tmp,
          httpClient: client,
          isCancelled: () => true,
        ),
        throwsA(isA<UpdateDownloadCancelled>()),
      );
      expect(tmp.listSync(), isEmpty);
    });

    test('berkas lama dengan nama sama ditimpa', () async {
      File('${tmp.path}/HegiKetok-macos.zip').writeAsStringSync('lama');
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final f = await downloadReleaseAsset(asset(),
          directory: tmp, httpClient: client);
      expect(await f.length(), payload.length);
    });

    test('nama aset berbahaya tidak keluar dari folder tujuan', () async {
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final f = await downloadReleaseAsset(
        ReleaseAsset(
          name: '../../kabur.zip',
          url: 'http://127.0.0.1:${server.port}/x',
          size: payload.length,
        ),
        directory: tmp,
        httpClient: client,
      );
      expect(f.parent.path, tmp.path);
      expect(f.path, endsWith('/kabur.zip'));
    });

    test('URL non-https ditolak bila tanpa klien uji', () async {
      await expectLater(
        downloadReleaseAsset(asset(), directory: tmp),
        throwsA(isA<UpdateDownloadException>()),
      );
    });
  });

  test('contoh JSON GitHub nyata terurai (bentuk respons API)', () {
    const raw = '''
{"tag_name":"v1.3.0","html_url":"https://github.com/o/r/releases/tag/v1.3.0",
 "body":"- Perbaikan\\n- Fitur baru",
 "assets":[
  {"name":"HegiKetok-linux-x64.tar.gz","size":1,"browser_download_url":"https://github.com/o/r/releases/download/v1.3.0/HegiKetok-linux-x64.tar.gz"},
  {"name":"HegiKetok-1.3.0-macos.dmg","size":52428800,"digest":"sha256:${'0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'}","browser_download_url":"https://github.com/o/r/releases/download/v1.3.0/HegiKetok-1.3.0-macos.dmg"}
 ]}''';
    final r = parseLatestRelease(jsonDecode(raw) as Map<String, dynamic>,
        current: '1.0.0') as UpdateAvailable;
    expect(r.info.asset!.name, 'HegiKetok-1.3.0-macos.dmg');
    expect(r.info.asset!.size, 52428800);
    expect(r.info.asset!.sha256, hasLength(64));
    expect(r.info.notes, contains('Fitur baru'));
  });
}
