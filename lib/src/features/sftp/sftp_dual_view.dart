import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/host_providers.dart';
import '../../models/ssh_credentials.dart';
import '../../models/ssh_host.dart';
import '../../ssh/handshake_stepper.dart';
import '../../theme/app_theme.dart';
import '../../theme/ui.dart';
import '../hosts/host_sidebar.dart' show hostOsIcon;
import 'file_browser.dart';
import 'local_browser_controller.dart';
import 'sftp_browser_controller.dart';

/// Browser berkas dua-panel ala Termius: panel kiri = server (SFTP), panel
/// kanan bisa server LAIN atau filesystem lokal ("Mac ini"), dengan transfer
/// berkas/folder antar-panel (multi-pilih didukung).
class SftpDualView extends ConsumerStatefulWidget {
  const SftpDualView({
    super.key,
    required this.left,
    required this.leftLabel,
    required this.resolveCreds,
  });

  final FileBrowser left;
  final String leftLabel;
  final Future<SshCredentials> Function(SshHost host) resolveCreds;

  @override
  ConsumerState<SftpDualView> createState() => _SftpDualViewState();
}

class _SftpDualViewState extends ConsumerState<SftpDualView> {
  FileBrowser? _right;
  String? _rightLabel;

  @override
  void dispose() {
    // Panel kiri dimiliki oleh tab; hanya panel kanan yang kita buat sendiri.
    _right?.dispose();
    super.dispose();
  }

  Future<void> _openRightServer(SshHost host) async {
    final creds = await widget.resolveCreds(host);
    final ctrl = SftpBrowserController(creds, label: host.label);
    setState(() {
      _right = ctrl;
      _rightLabel = host.label;
    });
    ctrl.connect();
  }

  void _openRightLocal() {
    final ctrl = LocalBrowserController();
    setState(() {
      _right = ctrl;
      _rightLabel = 'Mac ini';
    });
    ctrl.connect();
  }

  void _closeRight() {
    final old = _right;
    setState(() {
      _right = null;
      _rightLabel = null;
    });
    old?.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final right = _right;
    return Container(
      color: AppTheme.bg,
      child: Row(
        children: [
          Expanded(
            child: _BrowserPane(
              controller: widget.left,
              label: widget.leftLabel,
              toRight: true,
              onCopyToOther: (right != null && right.connected)
                  ? (items) => right.copyManyFrom(widget.left, items)
                  : null,
            ),
          ),
          Container(width: 1, color: AppTheme.border),
          Expanded(
            child: right == null
                ? _RightPlaceholder(
                    onPickServer: _openRightServer,
                    onPickLocal: _openRightLocal,
                  )
                : _BrowserPane(
                    controller: right,
                    label: _rightLabel ?? right.rootLabel,
                    toRight: false,
                    onClose: _closeRight,
                    onCopyToOther: widget.left.connected
                        ? (items) => widget.left.copyManyFrom(right, items)
                        : null,
                  ),
          ),
        ],
      ),
    );
  }
}

/// Panel kanan sebelum dipilih: tombol "Mac ini (lokal)" + daftar host.
class _RightPlaceholder extends ConsumerWidget {
  const _RightPlaceholder(
      {required this.onPickServer, required this.onPickLocal});

  final void Function(SshHost host) onPickServer;
  final VoidCallback onPickLocal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hostsAsync = ref.watch(hostsProvider);
    return Container(
      color: AppTheme.bg,
      child: Column(
        children: [
          Container(
            height: 46,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: AppTheme.border)),
            ),
            child: Text('Pilih sumber untuk panel ini',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: _LocalRow(onTap: onPickLocal),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SectionLabel('SERVER TERSIMPAN'),
            ),
          ),
          Expanded(
            child: hostsAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (e, _) => PanelMessage(
                  icon: Icons.error_outline,
                  iconColor: AppTheme.danger,
                  message: '$e'),
              data: (hosts) => hosts.isEmpty
                  ? const PanelMessage(
                      icon: Icons.dns_outlined,
                      message: 'Belum ada host tersimpan.')
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      itemCount: hosts.length,
                      itemBuilder: (_, i) => _PickRow(
                        host: hosts[i],
                        onTap: () => onPickServer(hosts[i]),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LocalRow extends StatelessWidget {
  const _LocalRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: AppTheme.surfaceInput,
            borderRadius: BorderRadius.circular(AppTheme.rMd),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppTheme.accentSoft,
                  borderRadius: BorderRadius.circular(AppTheme.rSm),
                ),
                child: Icon(Icons.laptop_mac_rounded,
                    size: 16, color: AppTheme.accent),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Mac ini (lokal)',
                        style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                    Text('Jelajah berkas di komputer ini',
                        style: TextStyle(
                            color: AppTheme.textMuted, fontSize: 11)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  size: 18, color: AppTheme.textFaint),
            ],
          ),
        ),
      ),
    );
  }
}

class _PickRow extends StatelessWidget {
  const _PickRow({required this.host, required this.onTap});

  final SshHost host;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppTheme.accentSoft,
                  borderRadius: BorderRadius.circular(AppTheme.rSm),
                ),
                child:
                    Icon(hostOsIcon(host), size: 16, color: AppTheme.accent),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(host.label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                    Text(host.subtitle,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: AppTheme.textMuted, fontSize: 11)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  size: 18, color: AppTheme.textFaint),
            ],
          ),
        ),
      ),
    );
  }
}

/// Muatan drag antar-panel: panel sumber + entri yang diseret.
class _DragPayload {
  const _DragPayload(this.source, this.entries);
  final FileBrowser source;
  final List<FileEntry> entries;
}

class _BrowserPane extends StatefulWidget {
  const _BrowserPane({
    required this.controller,
    required this.label,
    required this.toRight,
    this.onCopyToOther,
    this.onClose,
  });

  final FileBrowser controller;
  final String label;

  /// Arah tombol salin (true = panel kiri, salin ke kanan).
  final bool toRight;
  final void Function(Iterable<FileEntry> entries)? onCopyToOther;
  final VoidCallback? onClose;

  @override
  State<_BrowserPane> createState() => _BrowserPaneState();
}

class _BrowserPaneState extends State<_BrowserPane> {
  final Set<FileEntry> _selection = {};
  FileEntry? _anchor;
  bool _filtering = false;
  String _filter = '';
  List<FileEntry> _list = const [];

  FileBrowser get c => widget.controller;

  List<FileEntry> _computeList() {
    var items = c.visibleEntries;
    final q = _filter.trim().toLowerCase();
    if (q.isNotEmpty) {
      items = items.where((e) => e.name.toLowerCase().contains(q)).toList();
    }
    return items;
  }

  void _clearSelection() {
    _selection.clear();
    _anchor = null;
  }

  void _onRowTap(FileEntry e) {
    final meta = HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    setState(() {
      if (shift && _anchor != null) {
        final a = _list.indexOf(_anchor!);
        final b = _list.indexOf(e);
        if (a >= 0 && b >= 0) {
          final lo = a < b ? a : b;
          final hi = a < b ? b : a;
          _selection
            ..clear()
            ..addAll(_list.sublist(lo, hi + 1));
        } else {
          _selection
            ..clear()
            ..add(e);
          _anchor = e;
        }
      } else if (meta) {
        if (!_selection.add(e)) _selection.remove(e);
        _anchor = e;
      } else {
        _selection
          ..clear()
          ..add(e);
        _anchor = e;
      }
    });
  }

  void _selectAll() {
    setState(() {
      _selection
        ..clear()
        ..addAll(_list);
      _anchor = _list.isEmpty ? null : _list.last;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        if (!c.connected) {
          if (c.error != null) {
            return PanelMessage(
              icon: Icons.error_outline,
              iconColor: AppTheme.danger,
              message: c.error!,
              actionLabel: 'Coba lagi',
              onAction: c.connect,
            );
          }
          return HandshakeLoading(
            progress: c.progress,
            title: 'Menyambungkan ke ${widget.label}…',
          );
        }
        _list = _computeList();
        // Buang item terpilih yang tak lagi ada (mis. setelah navigasi/refresh).
        _selection.removeWhere((e) => !_list.contains(e));
        return Column(
          children: [
            _header(),
            if (_filtering) _filterRow(),
            _breadcrumb(),
            Divider(height: 1, color: AppTheme.border),
            _columnHeader(),
            Divider(height: 1, color: AppTheme.border),
            Expanded(child: _dropTarget(_body())),
            if (c.transferStatus != null) _transferBar(),
          ],
        );
      },
    );
  }

  // ---- header -------------------------------------------------------------

  Widget _header() {
    final selCount = _selection.length;
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(c.isLocal ? Icons.laptop_mac_rounded : Icons.dns_rounded,
              size: 16, color: AppTheme.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
                selCount > 1 ? '$selCount dipilih' : widget.label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600)),
          ),
          if (widget.onCopyToOther != null)
            _CopyButton(
              toRight: widget.toRight,
              enabled: selCount > 0,
              onTap: () {
                if (_selection.isNotEmpty) {
                  widget.onCopyToOther!(_selection.toList());
                }
              },
            ),
          GhostIconButton(
            icon: Icons.search_rounded,
            tooltip: 'Filter',
            size: 17,
            onTap: () => setState(() {
              _filtering = !_filtering;
              if (!_filtering) _filter = '';
            }),
          ),
          _actionsMenu(),
          if (widget.onClose != null)
            GhostIconButton(
              icon: Icons.close_rounded,
              tooltip: 'Tutup panel',
              size: 17,
              onTap: widget.onClose!,
            ),
        ],
      ),
    );
  }

  Widget _actionsMenu() {
    final sel = _selection.length;
    final hasSel = sel > 0;
    final one = sel == 1;
    return PopupMenuButton<String>(
      tooltip: 'Actions',
      position: PopupMenuPosition.under,
      constraints: const BoxConstraints(minWidth: 200),
      icon: Icon(Icons.more_horiz_rounded, size: 18, color: AppTheme.textMuted),
      onSelected: (v) async {
        switch (v) {
          case 'upload':
            await _upload();
          case 'newfolder':
            await _newFolder();
          case 'download':
            if (hasSel) await _downloadSelection();
          case 'rename':
            if (one) await _rename(_selection.first);
          case 'chmod':
            if (one) await _editPermissions(_selection.first);
          case 'delete':
            if (hasSel) await _confirmDelete();
          case 'selectall':
            _selectAll();
          case 'clear':
            setState(_clearSelection);
          case 'refresh':
            setState(_clearSelection);
            await c.refresh();
          case 'hidden':
            c.toggleHidden();
        }
      },
      itemBuilder: (_) => [
        _mi('upload', Icons.upload_file,
            c.isLocal ? 'Salin berkas ke sini…' : 'Unggah dari lokal…'),
        _mi('newfolder', Icons.create_new_folder_outlined, 'Folder baru'),
        const PopupMenuDivider(),
        _mi('download', Icons.download_outlined,
            sel > 1 ? 'Unduh $sel item' : 'Unduh', enabled: hasSel),
        _mi('rename', Icons.edit_outlined, 'Ganti nama', enabled: one),
        _mi('chmod', Icons.lock_outline_rounded, 'Izin (chmod)…', enabled: one),
        _mi('delete', Icons.delete_outline,
            sel > 1 ? 'Hapus $sel item' : 'Hapus',
            enabled: hasSel, danger: true),
        const PopupMenuDivider(),
        _mi('selectall', Icons.select_all_rounded, 'Pilih semua'),
        _mi('clear', Icons.deselect_rounded, 'Kosongkan pilihan',
            enabled: hasSel),
        const PopupMenuDivider(),
        _mi('refresh', Icons.refresh, 'Muat ulang'),
        _mi('hidden', c.showHidden ? Icons.visibility_off : Icons.visibility,
            c.showHidden
                ? 'Sembunyikan file tersembunyi'
                : 'Tampilkan file tersembunyi'),
      ],
    );
  }

  PopupMenuItem<String> _mi(String v, IconData icon, String label,
      {bool enabled = true, bool danger = false}) {
    final color = !enabled
        ? AppTheme.textFaint
        : (danger ? AppTheme.danger : AppTheme.textMuted);
    return PopupMenuItem<String>(
      value: v,
      enabled: enabled,
      height: 38,
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Text(label,
              style: TextStyle(
                  color: !enabled
                      ? AppTheme.textFaint
                      : (danger ? AppTheme.danger : AppTheme.textPrimary),
                  fontSize: 13)),
        ],
      ),
    );
  }

  Widget _filterRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: SearchField(
        hint: 'Filter nama…',
        onChanged: (v) => setState(() => _filter = v),
      ),
    );
  }

  // ---- breadcrumb ---------------------------------------------------------

  Widget _breadcrumb() {
    final parts = c.cwd.split('/').where((p) => p.isNotEmpty).toList();
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          GhostIconButton(
            icon: Icons.arrow_upward_rounded,
            tooltip: 'Naik',
            size: 16,
            onTap: () {
              setState(_clearSelection);
              c.goUp();
            },
          ),
          const SizedBox(width: 4),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(
                children: [
                  _crumb(Icons.home_rounded, '', '/'),
                  for (var i = 0; i < parts.length; i++) ...[
                    Icon(Icons.chevron_right_rounded,
                        size: 15, color: AppTheme.textFaint),
                    _crumb(null, parts[i],
                        '/${parts.sublist(0, i + 1).join('/')}'),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _crumb(IconData? icon, String label, String path) {
    return InkWell(
      onTap: () {
        setState(_clearSelection);
        c.navigateTo(path);
      },
      borderRadius: BorderRadius.circular(AppTheme.rSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: icon != null
            ? Icon(icon, size: 15, color: AppTheme.textMuted)
            : Text(label,
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 12.5)),
      ),
    );
  }

  // ---- table --------------------------------------------------------------

  static const double _dateW = 150;
  static const double _sizeW = 84;
  static const double _kindW = 68;

  Widget _columnHeader() {
    return LayoutBuilder(builder: (context, c2) {
      final wide = c2.maxWidth > 520;
      TextStyle st = TextStyle(
          color: AppTheme.textFaint,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3);
      return Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            const SizedBox(width: 28),
            Expanded(child: Text('NAME', style: st)),
            if (wide)
              SizedBox(
                  width: _dateW, child: Text('DATE MODIFIED', style: st)),
            SizedBox(
                width: _sizeW,
                child: Text('SIZE', style: st, textAlign: TextAlign.right)),
            if (wide)
              SizedBox(
                  width: _kindW,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Text('KIND', style: st),
                  )),
          ],
        ),
      );
    });
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
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: AppTheme.accent),
        ),
      );
    }
    final items = _list;
    if (items.isEmpty) {
      return const PanelMessage(
          icon: Icons.folder_open_rounded, message: 'Folder kosong');
    }
    return LayoutBuilder(builder: (context, c2) {
      final wide = c2.maxWidth > 520;
      return ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: items.length,
        itemBuilder: (_, i) {
          final e = items[i];
          final row = _FileRow(
            entry: e,
            wide: wide,
            selected: _selection.contains(e),
            onSelect: () => _onRowTap(e),
            onOpen: () {
              if (e.isDir) {
                setState(_clearSelection);
                c.openDir(e.name);
              } else {
                _downloadOne(e);
              }
            },
          );
          // Seret seluruh pilihan bila baris ini bagian dari pilihan majemuk.
          final dragEntries = (_selection.contains(e) && _selection.length > 1)
              ? _selection.toList()
              : <FileEntry>[e];
          return Draggable<_DragPayload>(
            data: _DragPayload(c, dragEntries),
            dragAnchorStrategy: pointerDragAnchorStrategy,
            feedback: _dragFeedback(dragEntries.length),
            childWhenDragging: Opacity(opacity: 0.4, child: row),
            child: row,
          );
        },
      );
    });
  }

  /// Area terima drop dari panel seberang → salin ke cwd panel ini.
  Widget _dropTarget(Widget child) {
    return DragTarget<_DragPayload>(
      onWillAcceptWithDetails: (d) => d.data.source != c && c.connected,
      onAcceptWithDetails: (d) => c.copyManyFrom(d.data.source, d.data.entries),
      builder: (context, candidate, rejected) {
        final active = candidate.isNotEmpty;
        return Container(
          decoration: BoxDecoration(
            color: active ? AppTheme.accent.withValues(alpha: 0.06) : null,
            border: Border.all(
              color: active ? AppTheme.accent : Colors.transparent,
              width: 2,
            ),
          ),
          child: child,
        );
      },
    );
  }

  Widget _dragFeedback(int count) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.accent,
          borderRadius: BorderRadius.circular(AppTheme.rPill),
          boxShadow: AppTheme.softShadow(AppTheme.current),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.drag_indicator_rounded,
                size: 15, color: AppTheme.onAccent),
            const SizedBox(width: 6),
            Text(count == 1 ? '1 item' : '$count item',
                style: TextStyle(
                    color: AppTheme.onAccent,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600)),
          ],
        ),
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
                    strokeWidth: 2, color: AppTheme.accent))
          else
            Icon(isError ? Icons.error_outline : Icons.check_circle_outline,
                size: 14, color: tint),
          const SizedBox(width: 8),
          Expanded(
            child: Text(msg,
                style: TextStyle(
                    color: (isError || isDone) ? tint : AppTheme.textMuted,
                    fontSize: 12)),
          ),
        ],
      ),
    );
  }

  // ---- actions ------------------------------------------------------------

  Future<void> _upload() async {
    try {
      final file = await FilePicker.pickFile();
      final path = file?.path;
      if (path != null) await c.uploadLocalPath(path);
    } catch (e) {
      c.reportError('Gagal membuka dialog file: $e');
    }
  }

  Future<void> _downloadOne(FileEntry entry) async {
    try {
      if (entry.isDir) {
        final uri = await FilePicker.pickDirectory(
            dialogTitle: 'Pilih folder tujuan unduhan');
        if (uri == null) return;
        await c.downloadManyInto([entry], uri.toFilePath());
        return;
      }
      final data = await c.fetchBytes(entry);
      if (data == null) return;
      await FilePicker.saveFile(
        dialogTitle: 'Simpan ${entry.name}',
        fileName: entry.name,
        bytes: data,
      );
    } catch (e) {
      c.reportError('Gagal menyimpan: $e');
    }
  }

  Future<void> _downloadSelection() async {
    final items = _selection.toList();
    // Satu file → dialog "simpan sebagai"; selain itu → pilih folder tujuan.
    if (items.length == 1 && !items.first.isDir) {
      await _downloadOne(items.first);
      return;
    }
    try {
      final uri = await FilePicker.pickDirectory(
          dialogTitle: 'Pilih folder tujuan unduhan');
      if (uri == null) return;
      await c.downloadManyInto(items, uri.toFilePath());
    } catch (e) {
      c.reportError('Gagal mengunduh: $e');
    }
  }

  Future<void> _editPermissions(FileEntry entry) async {
    final octal = await showDialog<int>(
      context: context,
      builder: (_) => _ChmodDialog(
        name: entry.name,
        initial: entry.mode ?? 0x1A4, // 0o644
      ),
    );
    if (octal != null) await c.chmod(entry, octal);
  }

  Future<void> _newFolder() async {
    final name = await _promptText('Folder baru', 'Nama folder');
    if (name != null && name.trim().isNotEmpty) await c.makeDir(name.trim());
  }

  Future<void> _rename(FileEntry entry) async {
    final name =
        await _promptText('Ganti nama', 'Nama baru', initial: entry.name);
    if (name != null && name.trim().isNotEmpty) {
      await c.rename(entry, name.trim());
      setState(_clearSelection);
    }
  }

  Future<void> _confirmDelete() async {
    final items = _selection.toList();
    final label = items.length == 1
        ? '"${items.first.name}"'
        : '${items.length} item';
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text('Hapus?',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
        content: Text('$label akan dihapus permanen.',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Batal', style: TextStyle(color: AppTheme.textMuted)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await c.deleteEntries(items);
      setState(_clearSelection);
    }
  }

  Future<String?> _promptText(String title, String hint, {String? initial}) {
    final ctrl = TextEditingController(text: initial ?? '');
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
            child: Text('Batal', style: TextStyle(color: AppTheme.textMuted)),
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
}

class _CopyButton extends StatelessWidget {
  const _CopyButton(
      {required this.toRight, required this.enabled, required this.onTap});

  final bool toRight;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = enabled ? AppTheme.accent : AppTheme.textFaint;
    return Tooltip(
      message:
          enabled ? 'Salin ke panel seberang' : 'Pilih file/folder dulu',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(AppTheme.rSm),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!toRight)
                  Icon(Icons.arrow_back_rounded, size: 15, color: color),
                Icon(Icons.copy_rounded, size: 14, color: color),
                if (toRight)
                  Icon(Icons.arrow_forward_rounded, size: 15, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FileRow extends StatefulWidget {
  const _FileRow({
    required this.entry,
    required this.wide,
    required this.selected,
    required this.onSelect,
    required this.onOpen,
  });

  final FileEntry entry;
  final bool wide;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onOpen;

  @override
  State<_FileRow> createState() => _FileRowState();
}

class _FileRowState extends State<_FileRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final isDir = e.isDir;
    final isLink = e.isLink;
    final selected = widget.selected;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onSelect,
        onDoubleTap: widget.onOpen,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.accent.withValues(alpha: 0.16)
                : (_hover ? AppTheme.surfaceInput : Colors.transparent),
            borderRadius: BorderRadius.circular(AppTheme.rSm),
            border: Border.all(
              color: selected
                  ? AppTheme.accent.withValues(alpha: 0.5)
                  : Colors.transparent,
            ),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: AppTheme.textPrimary, fontSize: 13)),
                    Text(_permString(e),
                        style: TextStyle(
                            color: AppTheme.textFaint,
                            fontSize: 10.5,
                            fontFamily: 'monospace')),
                  ],
                ),
              ),
              if (widget.wide)
                SizedBox(
                  width: _BrowserPaneState._dateW,
                  child: Text(_formatDate(e.modifyEpoch),
                      style: TextStyle(
                          color: AppTheme.textMuted, fontSize: 11.5)),
                ),
              SizedBox(
                width: _BrowserPaneState._sizeW,
                child: Text(isDir ? '— —' : _formatSize(e.size),
                    textAlign: TextAlign.right,
                    style:
                        TextStyle(color: AppTheme.textMuted, fontSize: 11.5)),
              ),
              if (widget.wide)
                SizedBox(
                  width: _BrowserPaneState._kindW,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Text(_kind(e),
                        overflow: TextOverflow.ellipsis,
                        style:
                            TextStyle(color: AppTheme.textFaint, fontSize: 11)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dialog ubah izin (chmod): grid rwx untuk user/group/other + readout octal.
class _ChmodDialog extends StatefulWidget {
  const _ChmodDialog({required this.name, required this.initial});

  final String name;
  final int initial;

  @override
  State<_ChmodDialog> createState() => _ChmodDialogState();
}

class _ChmodDialogState extends State<_ChmodDialog> {
  late List<bool> _bits; // urutan: u r,w,x ; g r,w,x ; o r,w,x

  @override
  void initState() {
    super.initState();
    final v = widget.initial;
    _bits = [
      v & 256 != 0, v & 128 != 0, v & 64 != 0, //
      v & 32 != 0, v & 16 != 0, v & 8 != 0, //
      v & 4 != 0, v & 2 != 0, v & 1 != 0, //
    ];
  }

  int get _octal {
    const weights = [256, 128, 64, 32, 16, 8, 4, 2, 1];
    var v = 0;
    for (var i = 0; i < 9; i++) {
      if (_bits[i]) v += weights[i];
    }
    return v;
  }

  String get _octalStr {
    final u = (_octal >> 6) & 7;
    final g = (_octal >> 3) & 7;
    final o = _octal & 7;
    return '$u$g$o';
  }

  @override
  Widget build(BuildContext context) {
    Widget rowFor(String label, int base) {
      return Row(
        children: [
          SizedBox(
              width: 64,
              child: Text(label,
                  style:
                      TextStyle(color: AppTheme.textMuted, fontSize: 12.5))),
          for (var j = 0; j < 3; j++)
            Expanded(
              child: CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _bits[base + j],
                onChanged: (v) =>
                    setState(() => _bits[base + j] = v ?? false),
                title: Text(const ['r', 'w', 'x'][j],
                    style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 12,
                        fontFamily: 'monospace')),
              ),
            ),
        ],
      );
    }

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.lock_outline_rounded,
                      size: 18, color: AppTheme.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Izin — ${widget.name}',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceInput,
                      borderRadius: BorderRadius.circular(AppTheme.rSm),
                    ),
                    child: Text(_octalStr,
                        style: TextStyle(
                            color: AppTheme.accent,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'monospace')),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              rowFor('Owner', 0),
              rowFor('Group', 3),
              rowFor('Other', 6),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('Batal',
                        style: TextStyle(color: AppTheme.textMuted)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(_octal),
                    style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.accent,
                        foregroundColor: AppTheme.onAccent),
                    child: const Text('Terapkan'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- formatters -----------------------------------------------------------

String _kind(FileEntry e) {
  switch (e.kind) {
    case FileKind.directory:
      return 'folder';
    case FileKind.link:
      return 'link';
    case FileKind.file:
      final dot = e.name.lastIndexOf('.');
      if (dot > 0 && dot < e.name.length - 1) {
        return e.name.substring(dot + 1).toLowerCase();
      }
      return 'file';
  }
}

String _permString(FileEntry e) {
  final m = e.mode;
  if (m == null) return '';
  String tri(int shift) {
    final bits = (m >> shift) & 7;
    return '${bits & 4 != 0 ? 'r' : '-'}'
        '${bits & 2 != 0 ? 'w' : '-'}'
        '${bits & 1 != 0 ? 'x' : '-'}';
  }

  final typeChar = switch (e.kind) {
    FileKind.directory => 'd',
    FileKind.link => 'l',
    FileKind.file => '-',
  };
  return '$typeChar${tri(6)}${tri(3)}${tri(0)}';
}

String _formatSize(int? bytes) {
  if (bytes == null) return '';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} kB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

String _formatDate(int? epochSeconds) {
  if (epochSeconds == null || epochSeconds == 0) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(epochSeconds * 1000);
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final ampm = d.hour < 12 ? 'AM' : 'PM';
  final min = d.minute.toString().padLeft(2, '0');
  return '${d.day}/${d.month}/${d.year}, $h:$min $ampm';
}
