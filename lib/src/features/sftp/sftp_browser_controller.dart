import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/ssh_credentials.dart';

/// Mengelola satu koneksi SFTP: navigasi direktori remote serta transfer file
/// (unduh/unggah). Memakai [ChangeNotifier] agar UI bisa rebuild saat state
/// berubah.
class SftpBrowserController extends ChangeNotifier {
  SftpBrowserController(this.credentials);

  final SshCredentials credentials;

  SSHClient? _client;
  SftpClient? _sftp;

  String cwd = '/';
  List<SftpName> entries = [];
  bool loading = true;
  bool connected = false;
  String? error;
  String? transferStatus;

  Future<void> connect() async {
    try {
      final socket = await SSHSocket.connect(
        credentials.host,
        credentials.port,
        timeout: const Duration(seconds: 10),
      );
      final identities = credentials.usesKey
          ? SSHKeyPair.fromPem(credentials.privateKey!, credentials.passphrase)
          : null;
      final client = SSHClient(
        socket,
        username: credentials.username,
        identities: identities,
        onPasswordRequest:
            credentials.usesKey ? null : () => credentials.password,
      );
      _client = client;
      final sftp = await client.sftp();
      _sftp = sftp;
      cwd = await sftp.absolute('.');
      connected = true;
      await _load();
    } catch (e) {
      error = _friendly(e);
      loading = false;
      notifyListeners();
    }
  }

  Future<void> _load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final list = await _sftp!.listdir(cwd);
      list.removeWhere((e) => e.filename == '.' || e.filename == '..');
      list.sort((a, b) {
        final ad = a.attr.type == SftpFileType.directory;
        final bd = b.attr.type == SftpFileType.directory;
        if (ad != bd) return ad ? -1 : 1; // folder dulu
        return a.filename.toLowerCase().compareTo(b.filename.toLowerCase());
      });
      entries = list;
    } catch (e) {
      error = _friendly(e);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() => _load();

  Future<void> openDir(String name) async {
    cwd = _join(cwd, name);
    await _load();
  }

  Future<void> goUp() async {
    cwd = _parent(cwd);
    await _load();
  }

  Future<void> navigateTo(String path) async {
    cwd = path.isEmpty ? '/' : path;
    await _load();
  }

  /// Ambil isi sebuah file remote sebagai bytes (untuk disimpan lokal oleh UI).
  /// Mengembalikan null bila gagal.
  Future<Uint8List?> fetchBytes(SftpName entry) async {
    _setTransfer('Mengunduh ${entry.filename}…');
    try {
      final file = await _sftp!
          .open(_join(cwd, entry.filename), mode: SftpFileOpenMode.read);
      final data = await file.readBytes();
      await file.close();
      _setTransfer('✓ Terunduh: ${entry.filename}');
      return data;
    } catch (e) {
      _setTransfer('✗ Gagal unduh: ${_friendly(e)}');
      return null;
    }
  }

  /// Unggah file lokal [localPath] ke direktori aktif remote.
  Future<void> upload(String localPath) async {
    final name = localPath.split(Platform.pathSeparator).last;
    _setTransfer('Mengunggah $name…');
    try {
      final data = await File(localPath).readAsBytes();
      final file = await _sftp!.open(
        _join(cwd, name),
        mode: SftpFileOpenMode.create |
            SftpFileOpenMode.write |
            SftpFileOpenMode.truncate,
      );
      await file.writeBytes(data);
      await file.close();
      _setTransfer('✓ Terunggah: $name');
      await _load();
    } catch (e) {
      _setTransfer('✗ Gagal unggah: ${_friendly(e)}');
    }
  }

  Future<void> deleteEntry(SftpName entry) async {
    try {
      final path = _join(cwd, entry.filename);
      if (entry.attr.type == SftpFileType.directory) {
        await _sftp!.rmdir(path);
      } else {
        await _sftp!.remove(path);
      }
      await _load();
    } catch (e) {
      _setTransfer('✗ Gagal hapus: ${_friendly(e)}');
    }
  }

  Future<void> makeDir(String name) async {
    try {
      await _sftp!.mkdir(_join(cwd, name));
      await _load();
    } catch (e) {
      _setTransfer('✗ Gagal buat folder: ${_friendly(e)}');
    }
  }

  void _setTransfer(String msg) {
    transferStatus = msg;
    notifyListeners();
  }

  /// Laporkan error dari lapisan UI (mis. dialog file gagal dibuka).
  void reportError(String msg) => _setTransfer('✗ $msg');

  String _join(String base, String name) =>
      base.endsWith('/') ? '$base$name' : '$base/$name';

  String _parent(String path) {
    if (path == '/' || path.isEmpty) return '/';
    final trimmed =
        path.endsWith('/') ? path.substring(0, path.length - 1) : path;
    final idx = trimmed.lastIndexOf('/');
    return idx <= 0 ? '/' : trimmed.substring(0, idx);
  }

  String _friendly(Object e) {
    final text = e.toString().toLowerCase();
    if (text.contains('auth')) return 'Autentikasi gagal.';
    if (text.contains('permission')) return 'Akses ditolak (permission).';
    if (text.contains('no such')) return 'Berkas/direktori tidak ditemukan.';
    if (text.contains('refused')) return 'Koneksi ditolak.';
    return e.toString();
  }

  @override
  void dispose() {
    _sftp?.close();
    _client?.close();
    super.dispose();
  }
}
