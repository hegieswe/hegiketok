import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../../models/ssh_credentials.dart';
import '../../ssh/ssh_connector.dart';
import 'file_browser.dart';

/// Backend [FileBrowser] untuk SFTP remote: membuka koneksi SSH dengan
/// [dartssh2] lalu menyediakan primitif IO di atas [SftpClient].
class SftpBrowserController extends FileBrowser {
  SftpBrowserController(this.credentials, {this.label});

  final SshCredentials credentials;
  final String? label;

  SshConnection? _conn;
  SftpClient? _sftp;

  @override
  String get rootLabel => label ?? '${credentials.username}@${credentials.host}';

  @override
  bool get isLocal => false;

  @override
  Future<String> openConnection() async {
    progress.reset();
    final conn = await connectSsh(credentials, progress: progress);
    _conn = conn;
    final step = progress.begin('Membuka channel SFTP');
    final sftp = await conn.client.sftp();
    progress.complete(step);
    _sftp = sftp;
    return await sftp.absolute('.');
  }

  @override
  Future<List<FileEntry>> listAt(String absPath) async {
    final list = await _sftp!.listdir(absPath);
    return list.map(_toEntry).toList();
  }

  FileEntry _toEntry(SftpName n) {
    final t = n.attr.type;
    final kind = t == SftpFileType.directory
        ? FileKind.directory
        : t == SftpFileType.symbolicLink
            ? FileKind.link
            : FileKind.file;
    return FileEntry(
      name: n.filename,
      kind: kind,
      size: n.attr.size,
      modifyEpoch: n.attr.modifyTime,
      mode: _modeBits(n.attr.mode),
    );
  }

  int? _modeBits(SftpFileMode? m) {
    if (m == null) return null;
    int bit(bool b, int v) => b ? v : 0;
    return bit(m.userRead, 256) +
        bit(m.userWrite, 128) +
        bit(m.userExecute, 64) +
        bit(m.groupRead, 32) +
        bit(m.groupWrite, 16) +
        bit(m.groupExecute, 8) +
        bit(m.otherRead, 4) +
        bit(m.otherWrite, 2) +
        bit(m.otherExecute, 1);
  }

  @override
  Future<Uint8List> readFileAt(String absPath) async {
    final f = await _sftp!.open(absPath, mode: SftpFileOpenMode.read);
    try {
      return await f.readBytes();
    } finally {
      await f.close();
    }
  }

  @override
  Future<void> writeFileAt(String absPath, Uint8List data) async {
    final f = await _sftp!.open(
      absPath,
      mode: SftpFileOpenMode.create |
          SftpFileOpenMode.write |
          SftpFileOpenMode.truncate,
    );
    try {
      await f.writeBytes(data);
    } finally {
      await f.close();
    }
  }

  @override
  Future<void> mkdirAt(String absPath) => _sftp!.mkdir(absPath);

  @override
  Future<void> removeAt(String absPath, FileKind kind) async {
    if (kind == FileKind.directory) {
      await _sftp!.rmdir(absPath);
    } else {
      await _sftp!.remove(absPath);
    }
  }

  @override
  Future<void> renameAt(String srcAbs, String dstAbs) =>
      _sftp!.rename(srcAbs, dstAbs);

  @override
  Future<void> chmodAt(String absPath, int octal) => _sftp!.setStat(
        absPath,
        SftpFileAttrs(mode: SftpFileMode.value(octal)),
      );

  @override
  void dispose() {
    _sftp?.close();
    _conn?.close();
    super.dispose();
  }
}
