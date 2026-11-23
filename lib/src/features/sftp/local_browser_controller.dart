import 'dart:io';
import 'dart:typed_data';

import 'file_browser.dart';

/// Backend [FileBrowser] untuk filesystem LOKAL (mesin pengguna) — dipakai
/// sebagai panel kanan agar bisa transfer berkas antara "Mac ini" dan server.
class LocalBrowserController extends FileBrowser {
  @override
  String get rootLabel => 'Mac ini';

  @override
  bool get isLocal => true;

  @override
  Future<String> openConnection() async {
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty && Directory(home).existsSync()) {
      return home;
    }
    return '/';
  }

  @override
  Future<List<FileEntry>> listAt(String absPath) async {
    final dir = Directory(absPath);
    final out = <FileEntry>[];
    await for (final ent in dir.list(followLinks: false)) {
      final p = ent.path;
      final name = p.substring(p.lastIndexOf('/') + 1);
      final FileKind kind = ent is Directory
          ? FileKind.directory
          : ent is Link
              ? FileKind.link
              : FileKind.file;
      int? size;
      int? epoch;
      int? mode;
      try {
        final st = await ent.stat();
        size = kind == FileKind.file ? st.size : null;
        epoch = st.modified.millisecondsSinceEpoch ~/ 1000;
        mode = st.mode & 0x1FF;
      } catch (_) {
        // tautan rusak / izin ditolak → biarkan atribut kosong.
      }
      out.add(FileEntry(
          name: name, kind: kind, size: size, modifyEpoch: epoch, mode: mode));
    }
    return out;
  }

  @override
  Future<Uint8List> readFileAt(String absPath) => File(absPath).readAsBytes();

  @override
  Future<void> writeFileAt(String absPath, Uint8List data) async {
    await File(absPath).writeAsBytes(data);
  }

  @override
  Future<void> mkdirAt(String absPath) async {
    await Directory(absPath).create();
  }

  @override
  Future<void> removeAt(String absPath, FileKind kind) async {
    if (kind == FileKind.directory) {
      await Directory(absPath).delete(recursive: true);
    } else {
      await File(absPath).delete();
    }
  }

  @override
  Future<void> renameAt(String srcAbs, String dstAbs) async {
    if (Directory(srcAbs).existsSync()) {
      await Directory(srcAbs).rename(dstAbs);
    } else {
      await File(srcAbs).rename(dstAbs);
    }
  }

  @override
  Future<void> chmodAt(String absPath, int octal) async {
    final result = await Process.run('chmod', [octal.toRadixString(8), absPath]);
    if (result.exitCode != 0) {
      throw Exception('chmod gagal: ${result.stderr}');
    }
  }
}
