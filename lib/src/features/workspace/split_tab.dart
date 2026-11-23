import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../../session/terminal_session.dart';
import '../../session/workspace_tab.dart';
import '../../theme/app_theme.dart';
import '../terminal/terminal_tab.dart';

/// Membungkus DUA [WorkspaceTab] dalam satu tab dengan pembatas yang bisa
/// digeser (split pane ala Termius/iTerm/tmux). Bisa berdampingan ([Axis.
/// horizontal]) atau bertumpuk ([Axis.vertical]). Tiap panel punya tombol tutup
/// kecil untuk kembali ke satu panel. Mendukung synchronized-input (broadcast
/// ketikan ke kedua panel, ala tmux `synchronize-panes`).
class SplitTab implements WorkspaceTab {
  SplitTab(this.left, this.right,
      {this.onUnsplit, this.direction = Axis.horizontal});

  final WorkspaceTab left;
  final WorkspaceTab right;

  /// Arah pembagian: [Axis.horizontal] = dua panel bersebelahan (kiri|kanan),
  /// [Axis.vertical] = bertumpuk (atas/bawah).
  final Axis direction;

  /// Dipanggil saat salah satu panel ditutup: [keep] dipertahankan sebagai
  /// tab tunggal, [drop] dilepas sumber dayanya. Diisi oleh workspace.
  void Function(WorkspaceTab keep, WorkspaceTab drop)? onUnsplit;

  @override
  String get title => '${left.title} | ${right.title}';

  @override
  IconData get icon => direction == Axis.horizontal
      ? Icons.vertical_split_rounded
      : Icons.horizontal_split_rounded;

  @override
  Widget build(BuildContext context) => _SplitView(tab: this);

  /// Online bila salah satu panel tersambung (panel tanpa pelacakan koneksi
  /// dianggap selalu online).
  _MergedConnection? _merged;

  @override
  ValueListenable<bool> get connection =>
      _merged ??= _MergedConnection(left.connection, right.connection);

  /// Lepas penggabung koneksi tanpa menutup panel anak — dipakai saat unsplit,
  /// di mana salah satu panel tetap hidup sebagai tab tunggal.
  void releaseConnection() {
    _merged?.detach();
    _merged = null;
  }

  @override
  void dispose() {
    _merged?.detach();
    left.dispose();
    right.dispose();
  }
}

/// Menggabungkan status koneksi dua panel: true bila salah satu tersambung.
class _MergedConnection extends ValueNotifier<bool> {
  _MergedConnection(this.a, this.b) : super(_eval(a, b)) {
    a?.addListener(_update);
    b?.addListener(_update);
  }

  final ValueListenable<bool>? a;
  final ValueListenable<bool>? b;

  static bool _eval(ValueListenable<bool>? a, ValueListenable<bool>? b) =>
      (a?.value ?? true) || (b?.value ?? true);

  void _update() => value = _eval(a, b);

  void detach() {
    a?.removeListener(_update);
    b?.removeListener(_update);
    dispose();
  }
}

class _SplitView extends StatefulWidget {
  const _SplitView({required this.tab});

  final SplitTab tab;

  @override
  State<_SplitView> createState() => _SplitViewState();
}

class _SplitViewState extends State<_SplitView> {
  double _ratio = 0.5;
  bool _sync = false;
  static const double _dividerWidth = 6;
  static const double _minPaneFraction = 0.2;

  TerminalSession? get _leftSession {
    final t = widget.tab.left;
    return t is TerminalTab ? t.session : null;
  }

  TerminalSession? get _rightSession {
    final t = widget.tab.right;
    return t is TerminalTab ? t.session : null;
  }

  /// Dua panel terminal = syarat synchronized-input.
  bool get _canSync => _leftSession != null && _rightSession != null;

  @override
  void dispose() {
    _wireSync(false); // lepas keran agar tidak menggantung
    super.dispose();
  }

  void _toggleSync() {
    setState(() => _sync = !_sync);
    _wireSync(_sync);
  }

  /// Pasang/lepas broadcast ketikan antar kedua sesi. Tulisan ke sesi lain
  /// lewat [TerminalSession.writeInput] (tidak memicu keran-nya → tanpa loop).
  void _wireSync(bool on) {
    final l = _leftSession;
    final r = _rightSession;
    if (l == null || r == null) return;
    if (on) {
      l.onUserInput = (d) => r.writeInput(d);
      r.onUserInput = (d) => l.writeInput(d);
    } else {
      l.onUserInput = null;
      r.onUserInput = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final horizontal = widget.tab.direction == Axis.horizontal;
    return Stack(
      children: [
        Positioned.fill(child: _panes(horizontal)),
        if (_canSync)
          Positioned(
            top: 6,
            left: 0,
            right: 0,
            child: Center(child: _syncToggle()),
          ),
      ],
    );
  }

  Widget _panes(bool horizontal) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final total =
            horizontal ? constraints.maxWidth : constraints.maxHeight;
        final avail = total - _dividerWidth;
        final firstExtent = (avail * _ratio).clamp(
          avail * _minPaneFraction,
          avail * (1 - _minPaneFraction),
        );
        final first = SizedBox(
          width: horizontal ? firstExtent : null,
          height: horizontal ? null : firstExtent,
          child: _Pane(
            child: widget.tab.left.build(context),
            onClose: () =>
                widget.tab.onUnsplit?.call(widget.tab.right, widget.tab.left),
          ),
        );
        final divider = _Divider(
          horizontal: horizontal,
          onDrag: (delta) {
            setState(() {
              _ratio = ((firstExtent + delta) / avail).clamp(
                _minPaneFraction,
                1 - _minPaneFraction,
              );
            });
          },
        );
        final second = Expanded(
          child: _Pane(
            child: widget.tab.right.build(context),
            onClose: () =>
                widget.tab.onUnsplit?.call(widget.tab.left, widget.tab.right),
          ),
        );
        final children = [first, divider, second];
        return horizontal
            ? Row(children: children)
            : Column(children: children);
      },
    );
  }

  Widget _syncToggle() {
    final on = _sync;
    return Material(
      color: on
          ? AppTheme.accent.withValues(alpha: 0.92)
          : AppTheme.surface.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(AppTheme.rPill),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.rPill),
        onTap: _toggleSync,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.sync_alt_rounded,
                  size: 14,
                  color: on ? AppTheme.onAccent : AppTheme.textMuted),
              const SizedBox(width: 6),
              Text(
                on ? 'Ketik ke semua: AKTIF' : 'Ketik ke semua',
                style: TextStyle(
                  color: on ? AppTheme.onAccent : AppTheme.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Satu panel split dengan tombol tutup kecil mengambang di pojok kanan atas.
class _Pane extends StatelessWidget {
  const _Pane({required this.child, required this.onClose});

  final Widget child;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: child),
        Positioned(
          top: 6,
          right: 6,
          child: Material(
            color: AppTheme.surface.withValues(alpha: 0.85),
            shape: const CircleBorder(),
            child: IconButton(
              icon: Icon(Icons.close_rounded, size: 15, color: AppTheme.textMuted),
              tooltip: 'Tutup panel ini',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
              padding: EdgeInsets.zero,
              onPressed: onClose,
            ),
          ),
        ),
      ],
    );
  }
}

class _Divider extends StatefulWidget {
  const _Divider({required this.onDrag, required this.horizontal});

  final ValueChanged<double> onDrag;
  final bool horizontal;

  @override
  State<_Divider> createState() => _DividerState();
}

class _DividerState extends State<_Divider> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final h = widget.horizontal;
    final bar = Container(
      width: h ? _SplitViewState._dividerWidth : double.infinity,
      height: h ? double.infinity : _SplitViewState._dividerWidth,
      color: _hover ? AppTheme.accent.withValues(alpha: 0.5) : AppTheme.border,
    );
    return MouseRegion(
      cursor: h
          ? SystemMouseCursors.resizeLeftRight
          : SystemMouseCursors.resizeUpDown,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate:
            h ? (d) => widget.onDrag(d.delta.dx) : null,
        onVerticalDragUpdate:
            h ? null : (d) => widget.onDrag(d.delta.dy),
        child: bar,
      ),
    );
  }
}
