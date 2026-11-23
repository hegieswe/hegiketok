import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xterm/xterm.dart';

import '../../theme/app_theme.dart';
import '../settings/settings_providers.dart';
import '../settings/terminal_themes.dart';

/// Satu kecocokan hasil pencarian di buffer terminal.
class _Match {
  const _Match(this.y, this.start, this.length);
  final int y; // indeks baris absolut di buffer
  final int start; // kolom awal
  final int length;
}

/// Menampilkan satu [Terminal] dengan tema & ukuran font dari pengaturan, plus
/// pencarian dalam buffer (⌘F) ala editor: sorot kecocokan + navigasi naik/turun.
///
/// Dipakai ulang oleh sesi lokal maupun SSH; berubah langsung saat tema diganti.
class SessionView extends ConsumerStatefulWidget {
  const SessionView(this.terminal, {super.key});

  final Terminal terminal;

  @override
  ConsumerState<SessionView> createState() => _SessionViewState();
}

class _SessionViewState extends ConsumerState<SessionView> {
  final _termController = TerminalController();
  final _scrollController = ScrollController();
  final _searchFocus = FocusNode();
  final _searchField = TextEditingController();

  bool _searchOpen = false;
  List<_Match> _matches = const [];
  int _current = -1;
  TerminalHighlight? _highlight;
  final List<CellAnchor> _anchors = [];

  @override
  void dispose() {
    _clearHighlight();
    _termController.dispose();
    _scrollController.dispose();
    _searchFocus.dispose();
    _searchField.dispose();
    super.dispose();
  }

  void _clearHighlight() {
    _highlight?.dispose();
    _highlight = null;
    for (final a in _anchors) {
      a.dispose();
    }
    _anchors.clear();
  }

  void _openSearch() {
    setState(() => _searchOpen = true);
    _searchFocus.requestFocus();
    _searchField.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _searchField.text.length,
    );
    if (_searchField.text.isNotEmpty) _runSearch(_searchField.text);
  }

  void _closeSearch() {
    _clearHighlight();
    setState(() {
      _searchOpen = false;
      _matches = const [];
      _current = -1;
    });
  }

  void _runSearch(String raw) {
    final query = raw.toLowerCase();
    if (query.isEmpty) {
      _clearHighlight();
      setState(() {
        _matches = const [];
        _current = -1;
      });
      return;
    }
    final buffer = widget.terminal.buffer;
    final found = <_Match>[];
    final lineCount = buffer.lines.length;
    for (var y = 0; y < lineCount; y++) {
      final text = buffer.lines[y].getText().toLowerCase();
      if (text.isEmpty) continue;
      var from = 0;
      while (true) {
        final idx = text.indexOf(query, from);
        if (idx < 0) break;
        found.add(_Match(y, idx, query.length));
        from = idx + query.length;
      }
    }
    setState(() {
      _matches = found;
      // Pilih kecocokan pertama dari bawah (paling baru) agar relevan.
      _current = found.isEmpty ? -1 : found.length - 1;
    });
    if (_current >= 0) _goTo(_current);
  }

  void _step(int delta) {
    if (_matches.isEmpty) return;
    final next = (_current + delta) % _matches.length;
    setState(() => _current = next < 0 ? next + _matches.length : next);
    _goTo(_current);
  }

  void _goTo(int index) {
    final m = _matches[index];
    _clearHighlight();
    final buffer = widget.terminal.buffer;
    if (m.y >= buffer.lines.length) return;
    final p1 = buffer.createAnchor(m.start, m.y);
    final p2 = buffer.createAnchor(m.start + m.length, m.y);
    _anchors
      ..add(p1)
      ..add(p2);
    _highlight = _termController.highlight(
      p1: p1,
      p2: p2,
      color: AppTheme.accent.withValues(alpha: 0.45),
    );
    _scrollToLine(m.y);
  }

  /// Gulir agar baris [y] (indeks absolut) terlihat di tengah viewport.
  void _scrollToLine(int y) {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final total = widget.terminal.buffer.lines.length;
    final viewHeight = widget.terminal.viewHeight;
    final scrollableLines = total - viewHeight;
    if (scrollableLines <= 0 || pos.maxScrollExtent <= 0) return;
    // lineHeight presisi diturunkan dari extent scroll runtime.
    final lineHeight = pos.maxScrollExtent / scrollableLines;
    final target = ((y - viewHeight / 2) * lineHeight)
        .clamp(0.0, pos.maxScrollExtent);
    _scrollController.jumpTo(target);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final isFind = event.logicalKey == LogicalKeyboardKey.keyF &&
        HardwareKeyboard.instance.isMetaPressed;
    if (isFind) {
      _openSearch();
      return KeyEventResult.handled;
    }
    if (_searchOpen && event.logicalKey == LogicalKeyboardKey.escape) {
      _closeSearch();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final preset = themeByName(settings.themeName);

    return Focus(
      onKeyEvent: _onKey,
      child: Stack(
        children: [
          Container(
            color: preset.background,
            padding: const EdgeInsets.all(8),
            child: TerminalView(
              widget.terminal,
              controller: _termController,
              scrollController: _scrollController,
              autofocus: true,
              padding: const EdgeInsets.all(8),
              theme: preset.theme,
              textStyle: TerminalStyle(
                fontSize: settings.fontSize,
                fontFamily: 'Menlo',
              ),
            ),
          ),
          if (_searchOpen)
            Positioned(
              top: 10,
              right: 14,
              child: _SearchBar(
                controller: _searchField,
                focusNode: _searchFocus,
                count: _matches.length,
                current: _current,
                onChanged: _runSearch,
                onNext: () => _step(1),
                onPrev: () => _step(-1),
                onClose: _closeSearch,
              ),
            ),
        ],
      ),
    );
  }
}

/// Bar pencarian mengambang ala editor (pojok kanan atas terminal).
class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.focusNode,
    required this.count,
    required this.current,
    required this.onChanged,
    required this.onNext,
    required this.onPrev,
    required this.onClose,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final int count;
  final int current;
  final ValueChanged<String> onChanged;
  final VoidCallback onNext;
  final VoidCallback onPrev;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final label = count == 0
        ? (controller.text.isEmpty ? '' : 'Tidak ada')
        : '${current + 1}/$count';
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.rMd),
          border: Border.all(color: AppTheme.border),
          boxShadow: AppTheme.softShadow(AppTheme.current),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_rounded, size: 15, color: AppTheme.textMuted),
            const SizedBox(width: 7),
            SizedBox(
              width: 180,
              child: Shortcuts(
                shortcuts: const <ShortcutActivator, Intent>{
                  SingleActivator(LogicalKeyboardKey.enter):
                      _NextIntent(),
                  SingleActivator(LogicalKeyboardKey.enter, shift: true):
                      _PrevIntent(),
                },
                child: Actions(
                  actions: <Type, Action<Intent>>{
                    _NextIntent: CallbackAction<_NextIntent>(
                        onInvoke: (_) {
                      onNext();
                      return null;
                    }),
                    _PrevIntent: CallbackAction<_PrevIntent>(
                        onInvoke: (_) {
                      onPrev();
                      return null;
                    }),
                  },
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    autofocus: true,
                    style: TextStyle(
                        color: AppTheme.textPrimary, fontSize: 13),
                    cursorColor: AppTheme.accent,
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      hintText: 'Cari di terminal…',
                      hintStyle: TextStyle(
                          color: AppTheme.textFaint, fontSize: 13),
                    ),
                    onChanged: onChanged,
                  ),
                ),
              ),
            ),
            if (label.isNotEmpty) ...[
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 11.5,
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ],
            const SizedBox(width: 4),
            _MiniBtn(
                icon: Icons.keyboard_arrow_up_rounded,
                tooltip: 'Sebelumnya (⇧⏎)',
                onTap: onPrev),
            _MiniBtn(
                icon: Icons.keyboard_arrow_down_rounded,
                tooltip: 'Berikutnya (⏎)',
                onTap: onNext),
            _MiniBtn(
                icon: Icons.close_rounded,
                tooltip: 'Tutup (Esc)',
                onTap: onClose),
          ],
        ),
      ),
    );
  }
}

class _MiniBtn extends StatelessWidget {
  const _MiniBtn(
      {required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 17, color: AppTheme.textMuted),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      padding: EdgeInsets.zero,
      onPressed: onTap,
    );
  }
}

class _NextIntent extends Intent {
  const _NextIntent();
}

class _PrevIntent extends Intent {
  const _PrevIntent();
}
