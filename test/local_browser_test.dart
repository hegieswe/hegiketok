import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_term/src/features/sftp/local_browser_controller.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('hegi_local_test_');
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  Future<LocalBrowserController> openAt(String path) async {
    final c = LocalBrowserController();
    await c.connect();
    await c.navigateTo(path);
    return c;
  }

  test('list menampilkan file & folder, folder didahulukan', () async {
    await File('${tmp.path}/b.txt').writeAsString('hi');
    await Directory('${tmp.path}/adir').create();
    final c = await openAt(tmp.path);
    expect(c.connected, isTrue);
    final names = c.visibleEntries.map((e) => e.name).toList();
    expect(names, ['adir', 'b.txt']);
    expect(c.visibleEntries.first.isDir, isTrue);
    c.dispose();
  });

  test('file tersembunyi hanya tampil saat showHidden', () async {
    await File('${tmp.path}/.secret').writeAsString('x');
    await File('${tmp.path}/open.txt').writeAsString('y');
    final c = await openAt(tmp.path);
    expect(c.visibleEntries.map((e) => e.name), ['open.txt']);
    c.toggleHidden();
    expect(c.visibleEntries.map((e) => e.name).toSet(),
        {'.secret', 'open.txt'});
    c.dispose();
  });

  test('makeDir, rename, dan deleteEntries', () async {
    final c = await openAt(tmp.path);
    await c.makeDir('foo');
    expect(Directory('${tmp.path}/foo').existsSync(), isTrue);

    final foo = c.visibleEntries.firstWhere((e) => e.name == 'foo');
    await c.rename(foo, 'bar');
    expect(Directory('${tmp.path}/bar').existsSync(), isTrue);
    expect(Directory('${tmp.path}/foo').existsSync(), isFalse);

    final bar = c.visibleEntries.firstWhere((e) => e.name == 'bar');
    await c.deleteEntries([bar]);
    expect(Directory('${tmp.path}/bar').existsSync(), isFalse);
    c.dispose();
  });

  test('copyManyFrom menyalin file & folder rekursif antar panel', () async {
    // Sumber: satu file + satu folder berisi file.
    final srcDir = Directory('${tmp.path}/src')..createSync();
    final dstDir = Directory('${tmp.path}/dst')..createSync();
    await File('${srcDir.path}/a.txt').writeAsString('alpha');
    await Directory('${srcDir.path}/sub').create();
    await File('${srcDir.path}/sub/b.txt').writeAsString('beta');

    final src = await openAt(srcDir.path);
    final dst = await openAt(dstDir.path);

    await dst.copyManyFrom(src, src.visibleEntries);

    expect(await File('${dstDir.path}/a.txt').readAsString(), 'alpha');
    expect(await File('${dstDir.path}/sub/b.txt').readAsString(), 'beta');
    src.dispose();
    dst.dispose();
  });

  test('downloadManyInto menyalin ke folder tujuan', () async {
    await File('${tmp.path}/doc.txt').writeAsString('data');
    final out = Directory('${tmp.path}/out')..createSync();
    final c = await openAt(tmp.path);
    final doc = c.visibleEntries.firstWhere((e) => e.name == 'doc.txt');
    await c.downloadManyInto([doc], out.path);
    expect(await File('${out.path}/doc.txt').readAsString(), 'data');
    c.dispose();
  });

  test('writeFileAt + readFileAt round-trip', () async {
    final c = await openAt(tmp.path);
    final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
    await c.writeFileAt('${tmp.path}/raw.bin', bytes);
    final back = await c.readFileAt('${tmp.path}/raw.bin');
    expect(back, bytes);
    c.dispose();
  });
}
