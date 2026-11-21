import 'package:dartssh2/dartssh2.dart';
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../ssh/handshake_stepper.dart';
import '../../theme/app_theme.dart';
import '../../theme/ui.dart';
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
        title: Text('Hapus?',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
        content: Text('"${entry.filename}" akan dihapus permanen.',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Batal',
                style: TextStyle(color: AppTheme.textMuted)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
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
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Batal',
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
          if (c.error != null) {
            return PanelMessage(
              icon: Icons.error_outline,
              iconColor: AppTheme.danger,
              message: c.error!,
              onAction: c.connect,
            );
          }
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
              Divider(height: 1, color: AppTheme.border),
              Expanded(child: _body()),
              if (c.transferStatus != null) _transferBar(),
            ],
          ),
        );
      },
    );
  }

  Widget _toolbar() {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          GhostIconButton(
            icon: Icons.arrow_upward,
            tooltip: 'Naik satu level',
            onTap: c.goUp,
          ),
          GhostIconButton(
            icon: Icons.refresh,
            tooltip: 'Muat ulang',
            onTap: c.refresh,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 36,
              child: TextField(
                controller: _pathCtrl,
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: AppTheme.surfaceInput,
                  prefixIcon: Icon(Icons.folder_open_rounded,
                      size: 16, color: AppTheme.textFaint),
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.rSm),
                    borderSide: BorderSide(color: AppTheme.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.rSm),
                    borderSide: BorderSide(color: AppTheme.accent),
                  ),
                ),
                onSubmitted: c.navigateTo,
              ),
            ),
          ),
          const SizedBox(width: 8),
          GhostIconButton(
            icon: Icons.create_new_folder_outlined,
            tooltip: 'Folder baru',
            onTap: _newFolder,
          ),
          const SizedBox(width: 4),
          ToolButton(
            icon: Icons.upload_file,
            label: 'Unggah',
            color: AppTheme.accent,
            onTap: _upload,
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (c.error != null) {
      return PanelMessage(
        icon: Icons.error_outline,
        iconColor: AppTheme.danger,
        message: c.error!,
        actionLabel: 'Coba lagi',
        onAction: c.refresh,
      );
    }
    if (c.loading) {
      return Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: AppTheme.accent),
        ),
      );
    }
    if (c.entries.isEmpty) {
      return const PanelMessage(
        icon: Icons.folder_open_rounded,
        message: 'Folder kosong',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
    final tint = isError
        ? AppTheme.danger
        : isDone
            ? AppTheme.success
            : AppTheme.textMuted;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: (isError || isDone)
            ? tint.withValues(alpha: 0.10)
            : AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          if (!isError && !isDone)
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppTheme.accent),
            )
          else
            Icon(isError ? Icons.error_outline : Icons.check_circle_outline,
                size: 14, color: tint),
          const SizedBox(width: 8),
          Expanded(
            child: Text(msg,
                style: TextStyle(
                  color: (isError || isDone) ? tint : AppTheme.textMuted,
                  fontSize: 12,
                )),
          ),
        ],
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
      child: GestureDetector(
        onTap: widget.onOpen,
        child: AnimatedContainer(
          duration: AppTheme.fast,
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: _hover ? AppTheme.surfaceInput : Colors.transparent,
            borderRadius: BorderRadius.circular(AppTheme.rSm),
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isDir ? AppTheme.accentSoft : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppTheme.rSm),
                ),
                child: Icon(
                  isDir
                      ? Icons.folder_rounded
                      : isLink
                          ? Icons.link_rounded
                          : Icons.insert_drive_file_outlined,
                  size: 16,
                  color: isDir ? AppTheme.accent : AppTheme.textMuted,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  e.filename,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: AppTheme.textPrimary, fontSize: 13),
                ),
              ),
              if (!isDir)
                Text(
                  _formatSize(e.attr.size),
                  style: TextStyle(
                      color: AppTheme.textFaint, fontSize: 11),
                ),
              if (_hover) ...[
                const SizedBox(width: 8),
                if (!isDir)
                  GhostIconButton(
                    icon: Icons.download_outlined,
                    tooltip: 'Unduh',
                    size: 16,
                    onTap: widget.onDownload,
                  ),
                GhostIconButton(
                  icon: Icons.delete_outline,
                  tooltip: 'Hapus',
                  size: 16,
                  color: AppTheme.danger,
                  onTap: widget.onDelete,
                ),
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
