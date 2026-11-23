import 'dart:io';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../../ssh/connection_progress.dart';

/// Jenis entri berkas, netral terhadap backend (SFTP remote atau lokal).
enum FileKind { directory, file, link }

/// Satu entri berkas/folder — abstraksi tunggal yang dipakai panel browser,
/// baik isinya berasal dari server (SFTP) maupun filesystem lokal (Mac ini).
class FileEntry {
  const FileEntry({
    required this.name,
    required this.kind,
    this.size,
    this.modifyEpoch,
    this.mode,
  });

  final String name;
  final FileKind kind;
  final int? size;
  final int? modifyEpoch; // epoch detik
  final int? mode; // 9 bit izin (rwxrwxrwx), null bila tak diketahui

  bool get isDir => kind == FileKind.directory;
  bool get isLink => kind == FileKind.link;
}

/// Kontrak umum untuk sebuah panel browser berkas. Menyimpan state navigasi &
/// transfer sekali di sini; backend konkret ([SftpBrowserController],
/// [LocalBrowserController]) cukup menyediakan primitif IO (list/baca/tulis/…).
///
/// Transfer antar-panel ([copyManyFrom]) bekerja lintas backend lewat primitif
/// itu — jadi SFTP↔SFTP, lokal↔SFTP, dan lokal↔lokal semuanya didukung.
abstract class FileBrowser extends ChangeNotifier {
  final ConnectionProgress progress = ConnectionProgress();

  String cwd = '/';
  List<FileEntry> entries = [];
  bool loading = true;
  bool connected = false;
  bool showHidden = false;
  String? error;
  String? transferStatus;

  /// Label backend untuk header (mis. nama host, atau "Mac ini").
  String get rootLabel;

  /// true bila filesystem lokal (memengaruhi ikon & label aksi).
  bool get isLocal;

  List<FileEntry> get visibleEntries => showHidden
      ? entries
      : entries.where((e) => !e.name.startsWith('.')).toList();

  // ---- primitif yang disediakan backend ----------------------------------

  /// Buka koneksi/sesi dan kembalikan direktori awal (absolut).
  Future<String> openConnection();

  Future<List<FileEntry>> listAt(String absPath);
  Future<Uint8List> readFileAt(String absPath);
  Future<void> writeFileAt(String absPath, Uint8List data);
  Future<void> mkdirAt(String absPath);
  Future<void> removeAt(String absPath, FileKind kind);
  Future<void> renameAt(String srcAbs, String dstAbs);
  Future<void> chmodAt(String absPath, int octal);

  String join(String base, String name) =>
      base.endsWith('/') ? '$base$name' : '$base/$name';

  String parentOf(String path) {
    if (path == '/' || path.isEmpty) return '/';
    final trimmed =
        path.endsWith('/') ? path.substring(0, path.length - 1) : path;
    final idx = trimmed.lastIndexOf('/');
    return idx <= 0 ? '/' : trimmed.substring(0, idx);
  }

  // ---- state & navigasi ---------------------------------------------------

  void toggleHidden() {
    showHidden = !showHidden;
    notifyListeners();
  }

  Future<void> connect() async {
    error = null;
    loading = true;
    notifyListeners();
    try {
      cwd = await openConnection();
      connected = true;
      await _load();
    } catch (e) {
      error = friendly(e);
      loading = false;
      notifyListeners();
    }
  }

  Future<void> _load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final list = await listAt(cwd);
      list.removeWhere((e) => e.name == '.' || e.name == '..');
      list.sort((a, b) {
        if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      entries = list;
    } catch (e) {
      error = friendly(e);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() => _load();

  Future<void> openDir(String name) async {
    cwd = join(cwd, name);
    await _load();
  }

  Future<void> goUp() async {
    cwd = parentOf(cwd);
    await _load();
  }

  Future<void> navigateTo(String path) async {
    cwd = path.isEmpty ? '/' : path;
    await _load();
  }

  Future<void> makeDir(String name) async {
    try {
      await mkdirAt(join(cwd, name));
      await _load();
    } catch (e) {
      _setStatus('✗ Gagal buat folder: ${friendly(e)}');
    }
  }

  Future<void> rename(FileEntry e, String newName) async {
    final target = newName.trim();
    if (target.isEmpty || target == e.name) return;
    try {
      await renameAt(join(cwd, e.name), join(cwd, target));
      await _load();
    } catch (err) {
      _setStatus('✗ Gagal ganti nama: ${friendly(err)}');
    }
  }

  Future<void> chmod(FileEntry e, int octal) async {
    try {
      await chmodAt(join(cwd, e.name), octal);
      await _load();
    } catch (err) {
      _setStatus('✗ Gagal ubah izin: ${friendly(err)}');
    }
  }

  // ---- operasi banyak-entri ----------------------------------------------

  Future<void> deleteEntries(Iterable<FileEntry> items) async {
    final list = items.toList();
    if (list.isEmpty) return;
    try {
      for (var i = 0; i < list.length; i++) {
        final e = list[i];
        _setStatus('Menghapus ${e.name} (${i + 1}/${list.length})…');
        await removeAt(join(cwd, e.name), e.kind);
      }
      _setStatus('✓ Terhapus ${list.length} item');
      await _load();
    } catch (e) {
      _setStatus('✗ Gagal hapus: ${friendly(e)}');
      await _load();
    }
  }

  /// Ambil isi satu file (dari cwd) sebagai bytes untuk disimpan UI.
  Future<Uint8List?> fetchBytes(FileEntry e) async {
    _setStatus('Mengunduh ${e.name}…');
    try {
      final d = await readFileAt(join(cwd, e.name));
      _setStatus('✓ Terunduh: ${e.name}');
      return d;
    } catch (err) {
      _setStatus('✗ Gagal unduh: ${friendly(err)}');
      return null;
    }
  }

  /// Unggah file lokal [localPath] ke cwd panel ini.
  Future<void> uploadLocalPath(String localPath) async {
    final name = localPath.split(Platform.pathSeparator).last;
    _setStatus('Mengunggah $name…');
    try {
      final data = await File(localPath).readAsBytes();
      await writeFileAt(join(cwd, name), data);
      _setStatus('✓ Terunggah: $name');
      await _load();
    } catch (e) {
      _setStatus('✗ Gagal unggah: ${friendly(e)}');
    }
  }

  /// Unduh banyak entri (file/folder rekursif) ke direktori lokal [localDir].
  Future<void> downloadManyInto(
      Iterable<FileEntry> items, String localDir) async {
    final list = items.toList();
    if (list.isEmpty) return;
    try {
      for (var i = 0; i < list.length; i++) {
        final e = list[i];
        _setStatus('Mengunduh ${e.name} (${i + 1}/${list.length})…');
        await _downloadEntry(
            join(cwd, e.name), '$localDir/${e.name}', e.kind);
      }
      _setStatus('✓ Terunduh ${list.length} item');
    } catch (e) {
      _setStatus('✗ Gagal unduh: ${friendly(e)}');
    }
  }

  Future<void> _downloadEntry(
      String srcPath, String localPath, FileKind kind) async {
    if (kind == FileKind.directory) {
      await Directory(localPath).create(recursive: true);
      final kids = await listAt(srcPath);
      for (final k in kids) {
        if (k.name == '.' || k.name == '..') continue;
        await _downloadEntry(
            join(srcPath, k.name), '$localPath/${k.name}', k.kind);
      }
    } else {
      final data = await readFileAt(srcPath);
      await File(localPath).writeAsBytes(data);
    }
  }

  /// Salin banyak entri dari panel [src] ke cwd panel ini (lintas backend).
  Future<void> copyManyFrom(FileBrowser src, Iterable<FileEntry> items) async {
    final list =
        items.where((e) => e.name != '.' && e.name != '..').toList();
    if (list.isEmpty) return;
    try {
      for (var i = 0; i < list.length; i++) {
        final e = list[i];
        _setStatus('Menyalin ${e.name} (${i + 1}/${list.length})…');
        await _copyEntry(src, src.join(src.cwd, e.name),
            join(cwd, e.name), e.kind);
      }
      _setStatus('✓ Tersalin ${list.length} item');
      await _load();
    } catch (e) {
      _setStatus('✗ Gagal salin: ${friendly(e)}');
    }
  }

  Future<void> _copyEntry(
      FileBrowser src, String srcPath, String dstPath, FileKind kind) async {
    if (kind == FileKind.directory) {
      try {
        await mkdirAt(dstPath);
      } catch (_) {
        // folder mungkin sudah ada → lanjutkan isinya.
      }
      final kids = await src.listAt(srcPath);
      for (final k in kids) {
        if (k.name == '.' || k.name == '..') continue;
        await _copyEntry(src, src.join(srcPath, k.name),
            join(dstPath, k.name), k.kind);
      }
    } else {
      final data = await src.readFileAt(srcPath);
      await writeFileAt(dstPath, data);
    }
  }

  // ---- util ---------------------------------------------------------------

  void _setStatus(String msg) {
    transferStatus = msg;
    notifyListeners();
  }

  void reportError(String msg) => _setStatus('✗ $msg');

  String friendly(Object e) {
    final text = e.toString().toLowerCase();
    if (text.contains('auth')) return 'Autentikasi gagal.';
    if (text.contains('permission') || text.contains('denied')) {
      return 'Akses ditolak (permission).';
    }
    if (text.contains('no such') || text.contains('not found')) {
      return 'Berkas/direktori tidak ditemukan.';
    }
    if (text.contains('refused')) return 'Koneksi ditolak.';
    return e.toString();
  }
}
