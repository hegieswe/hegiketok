import 'package:dartssh2/dartssh2.dart';
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../ssh/handshake_stepper.dart';
import '../../theme/app_theme.dart';
import 'sftp_browser_controller.dart';

/// UI browser file SFTP: navigasi direktori remote + unduh/unggah/hapus.
class SftpBrowserView extends StatefulWidget {
  const SftpBrowserView({super.key, required this.controller});

  final SftpBrowserController controller;

  @override
  State<SftpBrowserView> createState() => _SftpBrowserViewState();
}

class _SftpBrowserViewState extends State<SftpBrowserView> {
  final _pathCtrl = TextEditingController();

  SftpBrowserController get c => widget.controller;

  @override
  void dispose() {
    _pathCtrl.dispose();
    super.dispose();
  }

  Future<void> _upload() async {
    try {
      final file = await FilePicker.pickFile();
      final path = file?.path;
      if (path != null) await c.upload(path);
    } catch (e) {
      c.reportError('Gagal membuka dialog file: $e');
    }
  }

  Future<void> _download(SftpName entry) async {
    try {
      final data = await c.fetchBytes(entry);
      if (data == null) return;
      // saveFile menampilkan dialog "Simpan sebagai…" lalu menulis bytes-nya.
      await FilePicker.saveFile(
        dialogTitle: 'Simpan ${entry.filename}',
        fileName: entry.filename,
        bytes: data,
      );
    } catch (e) {
      c.reportError('Gagal menyimpan file: $e');
    }
  }

  Future<void> _newFolder() async {
    final name = await _promptText('Folder baru', 'Nama folder');
    if (name != null && name.trim().isNotEmpty) await c.makeDir(name.trim());
  }

  Future<void> _confirmDelete(SftpName entry) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Hapus?',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
        content: Text('"${entry.filename}" akan dihapus permanen.',
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal',
                style: TextStyle(color: AppTheme.textMuted)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF7B72)),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (ok == true) await c.deleteEntry(entry);
  }

  Future<String?> _promptText(String title, String hint) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(title,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal',
                style: TextStyle(color: AppTheme.textMuted)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.accent),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        // Sebelum terhubung: tampilkan handshake stepper (atau error + retry).
        if (!c.connected) {
          if (c.error != null) return _connectError();
          return HandshakeLoading(
            progress: c.progress,
            title: 'Menyambungkan SFTP ke ${c.credentials.label}…',
          );
        }
        if (_pathCtrl.text != c.cwd) _pathCtrl.text = c.cwd;
        return Container(
          color: AppTheme.bg,
          child: Column(
            children: [
              _toolbar(),
              const Divider(height: 1, color: AppTheme.border),
              Expanded(child: _body()),
              if (c.transferStatus != null) _transferBar(),
            ],
          ),
        );
      },
    );
  }

  Widget _connectError() {
    return Container(
      color: AppTheme.bg,
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Color(0xFFFF7B72), size: 36),
            const SizedBox(height: 12),
            Text(c.error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFFF7B72), fontSize: 13)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: c.connect,
              icon: const Icon(Icons.refresh, size: 15),
              label: const Text('Coba lagi'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolbar() {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          _toolBtn(Icons.arrow_upward, 'Naik satu level', c.goUp),
          _toolBtn(Icons.refresh, 'Muat ulang', c.refresh),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _pathCtrl,
              style:
                  const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: AppTheme.surface,
                prefixIcon: const Icon(Icons.folder_open,
                    size: 15, color: AppTheme.textMuted),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppTheme.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppTheme.accent),
                ),
              ),
              onSubmitted: c.navigateTo,
            ),
          ),
          const SizedBox(width: 8),
          _toolBtn(Icons.create_new_folder_outlined, 'Folder baru', _newFolder),
          _actionBtn(Icons.upload_file, 'Unggah', _upload),
        ],
      ),
    );
  }

  Widget _body() {
    if (c.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  color: Color(0xFFFF7B72), size: 36),
              const SizedBox(height: 12),
              Text(c.error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Color(0xFFFF7B72), fontSize: 13)),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: c.refresh,
                icon: const Icon(Icons.refresh, size: 15),
                label: const Text('Coba lagi'),
              ),
            ],
          ),
        ),
      );
    }
    if (c.loading) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: AppTheme.accent),
        ),
      );
    }
    if (c.entries.isEmpty) {
      return const Center(
        child: Text('Folder kosong',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
      );
    }
    return ListView.builder(
      itemCount: c.entries.length,
      itemBuilder: (_, i) => _EntryTile(
        entry: c.entries[i],
        onOpen: () {
          final e = c.entries[i];
          if (e.attr.type == SftpFileType.directory) {
            c.openDir(e.filename);
          }
        },
        onDownload: () => _download(c.entries[i]),
        onDelete: () => _confirmDelete(c.entries[i]),
      ),
    );
  }

  Widget _transferBar() {
    final msg = c.transferStatus!;
    final isError = msg.startsWith('✗');
    final isDone = msg.startsWith('✓');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: AppTheme.surface,
      child: Row(
        children: [
          if (!isError && !isDone)
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppTheme.accent),
            )
          else
            Icon(isError ? Icons.error_outline : Icons.check_circle_outline,
                size: 14,
                color: isError ? const Color(0xFFFF7B72) : AppTheme.success),
          const SizedBox(width: 8),
          Expanded(
            child: Text(msg,
                style: TextStyle(
                  color: isError ? const Color(0xFFFF7B72) : AppTheme.textMuted,
                  fontSize: 12,
                )),
          ),
        ],
      ),
    );
  }

  Widget _toolBtn(IconData icon, String tip, VoidCallback onTap) {
    return IconButton(
      icon: Icon(icon, size: 17, color: AppTheme.textMuted),
      tooltip: tip,
      onPressed: onTap,
    );
  }

  Widget _actionBtn(IconData icon, String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: FilledButton.icon(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.accent,
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        icon: Icon(icon, size: 15),
        label: Text(label),
      ),
    );
  }
}

class _EntryTile extends StatefulWidget {
  const _EntryTile({
    required this.entry,
    required this.onOpen,
    required this.onDownload,
    required this.onDelete,
  });

  final SftpName entry;
  final VoidCallback onOpen;
  final VoidCallback onDownload;
  final VoidCallback onDelete;

  @override
  State<_EntryTile> createState() => _EntryTileState();
}

class _EntryTileState extends State<_EntryTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final isDir = e.attr.type == SftpFileType.directory;
    final isLink = e.attr.type == SftpFileType.symbolicLink;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: InkWell(
        onTap: widget.onOpen,
        child: Container(
          color: _hover ? AppTheme.surface : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Row(
            children: [
              Icon(
                isDir
                    ? Icons.folder
                    : isLink
                        ? Icons.link
                        : Icons.insert_drive_file_outlined,
                size: 17,
                color: isDir ? AppTheme.accent : AppTheme.textMuted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  e.filename,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppTheme.textPrimary, fontSize: 13),
                ),
              ),
              if (!isDir)
                Text(
                  _formatSize(e.attr.size),
                  style: const TextStyle(
                      color: AppTheme.textMuted, fontSize: 11),
                ),
              if (_hover) ...[
                const SizedBox(width: 8),
                if (!isDir)
                  _IconBtn(
                      icon: Icons.download_outlined,
                      tip: 'Unduh',
                      onTap: widget.onDownload),
                _IconBtn(
                    icon: Icons.delete_outline,
                    tip: 'Hapus',
                    onTap: widget.onDelete),
              ] else
                const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }

  String _formatSize(int? bytes) {
    if (bytes == null) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, required this.onTap, this.tip});

  final IconData icon;
  final VoidCallback onTap;
  final String? tip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 16, color: AppTheme.textMuted),
      tooltip: tip,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
      onPressed: onTap,
    );
  }
}
