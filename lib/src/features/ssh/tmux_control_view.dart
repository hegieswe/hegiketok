import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xterm/xterm.dart';

import '../../ssh/handshake_stepper.dart';
import '../../ssh/tmux_control.dart';
import '../../ssh/tmux_control_client.dart';
import '../../theme/app_theme.dart';
import '../../theme/ui.dart';
import '../settings/settings_providers.dart';
import '../settings/terminal_themes.dart';

/// Tampilan **tmux control mode**: jendela tmux remote sebagai tab, panel
/// sebagai split native — digerakkan oleh [TmuxControlClient]. Eksperimental.
class TmuxControlView extends ConsumerWidget {
  const TmuxControlView({super.key, required this.client});

  final TmuxControlClient client;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final preset = themeByName(settings.themeName);

    return ListenableBuilder(
      listenable: client,
      builder: (context, _) {
        if (client.error != null && client.windows.isEmpty) {
          return PanelMessage(
            icon: Icons.error_outline_rounded,
            iconColor: AppTheme.danger,
            title: 'tmux control mode gagal',
            message: client.error!,
          );
        }
        if (!client.connected && client.windows.isEmpty) {
          return HandshakeLoading(
            progress: client.progress,
            title: 'Menyiapkan tmux…',
          );
        }
        if (client.windows.isEmpty) {
          return PanelMessage(
            icon: Icons.grid_view_rounded,
            iconColor: AppTheme.accent,
            title: 'Menunggu jendela tmux',
            message: client.hint ??
                'Terhubung ke control mode. Membaca jendela tmux…',
          );
        }

        final activeId = client.activeWindow;
        final active =
            activeId == null ? null : client.windows[activeId];

        return Column(
          children: [
            _WindowBar(client: client),
            if (client.error != null)
              Container(
                width: double.infinity,
                color: AppTheme.danger.withValues(alpha: 0.14),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Text(client.error!,
                    style: TextStyle(color: AppTheme.danger, fontSize: 12)),
              ),
            Expanded(
              child: ColoredBox(
                color: preset.background,
                child: active?.tree == null
                    ? PanelMessage(
                        icon: Icons.view_quilt_outlined,
                        iconColor: AppTheme.textFaint,
                        message: 'Jendela ini belum punya layout.',
                      )
                    : LayoutBuilder(
                        builder: (context, box) {
                          // Laporkan ukuran area (dalam sel) ke tmux supaya
                          // layout panel di server mengikuti jendela ini.
                          final cell = _cellSize(settings.fontSize);
                          final grid = computeTmuxGrid(
                            width: box.maxWidth - _panePadding * 2,
                            height: box.maxHeight - _panePadding * 2,
                            cellWidth: cell.width,
                            cellHeight: cell.height,
                          );
                          if (grid != null) client.setClientSize(grid);
                          return _LayoutNodeView(
                            node: active!.tree!,
                            client: client,
                            preset: preset,
                            fontSize: settings.fontSize,
                          );
                        },
                      ),
              ),
            ),
          ],
        );
      },
    );
  }
}

const double _panePadding = 4;

TerminalStyle _termStyle(double fontSize) =>
    TerminalStyle(fontSize: fontSize, fontFamily: 'Menlo');

/// Ukuran satu sel karakter untuk gaya terminal pada [fontSize] — diukur
/// dengan gaya teks yang sama persis dengan yang dipakai [TerminalView].
Size _cellSize(double fontSize) {
  const sample = 'mmmmmmmmmm';
  final tp = TextPainter(
    text: TextSpan(text: sample, style: _termStyle(fontSize).toTextStyle()),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  final size = Size(tp.width / sample.length, tp.height);
  tp.dispose();
  return size;
}

/// Baris tab jendela tmux + tombol jendela baru.
class _WindowBar extends StatelessWidget {
  const _WindowBar({required this.client});

  final TmuxControlClient client;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Icon(Icons.dashboard_customize_outlined,
              size: 15, color: AppTheme.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final id in client.windowOrder)
                  _WindowChip(
                    label: client.windows[id]?.name ?? 'win$id',
                    active: client.activeWindow == id,
                    onTap: () => client.setActiveWindow(id),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Tooltip(
            message: 'Jendela tmux baru',
            child: InkWell(
              borderRadius: BorderRadius.circular(AppTheme.rSm),
              onTap: client.newWindow,
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: Icon(Icons.add_rounded,
                    size: 18, color: AppTheme.textMuted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WindowChip extends StatelessWidget {
  const _WindowChip(
      {required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 3),
      child: Material(
        color: active ? AppTheme.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(AppTheme.rSm),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.rSm),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Text(
              label,
              style: TextStyle(
                color: active ? AppTheme.accent : AppTheme.textMuted,
                fontSize: 12.5,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Render satu node pohon layout tmux secara rekursif menjadi Row/Column.
class _LayoutNodeView extends StatelessWidget {
  const _LayoutNodeView({
    required this.node,
    required this.client,
    required this.preset,
    required this.fontSize,
  });

  final TmuxLayoutNode node;
  final TmuxControlClient client;
  final TerminalThemePreset preset;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    if (node.isLeaf) {
      final pane = client.panes[node.paneId];
      if (pane == null) return ColoredBox(color: preset.background);
      return _PaneView(terminal: pane.terminal, preset: preset, fontSize: fontSize);
    }

    final horizontal = node.dir == TmuxSplitDir.leftRight;
    final children = <Widget>[];
    for (var i = 0; i < node.children.length; i++) {
      final c = node.children[i];
      final weight = (horizontal ? c.width : c.height).clamp(1, 1 << 20);
      children.add(Expanded(
        flex: weight,
        child: _LayoutNodeView(
          node: c,
          client: client,
          preset: preset,
          fontSize: fontSize,
        ),
      ));
      if (i < node.children.length - 1) {
        children.add(Container(
          width: horizontal ? 1 : null,
          height: horizontal ? null : 1,
          color: AppTheme.border,
        ));
      }
    }
    return horizontal
        ? Row(children: children)
        : Column(children: children);
  }
}

class _PaneView extends StatelessWidget {
  const _PaneView(
      {required this.terminal, required this.preset, required this.fontSize});

  final Terminal terminal;
  final TerminalThemePreset preset;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return TerminalView(
      terminal,
      // Ukuran grid ditentukan tmux (lihat TmuxControlClient._syncPanes),
      // bukan oleh widget — agar pembungkusan baris sama dengan di server.
      autoResize: false,
      padding: const EdgeInsets.all(_panePadding),
      theme: preset.theme,
      textStyle: _termStyle(fontSize),
    );
  }
}
