import 'package:material_ui/material_ui.dart';

import '../../ssh/handshake_stepper.dart';
import '../../ssh/port_forward.dart';
import '../../theme/app_theme.dart';
import '../../theme/ui.dart';
import '../terminal/session_view.dart';
import 'ssh_terminal_session.dart';

/// Tampilan sesi SSH: terminal + banner handshake (sebelum terhubung) + bar
/// port-forward (saran dari output & daftar forward aktif).
class SshSessionView extends StatelessWidget {
  const SshSessionView({super.key, required this.session});

  final SshTerminalSession session;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Banner handshake: tampil sampai koneksi selesai.
        ListenableBuilder(
          listenable: session.progress,
          builder: (context, _) {
            if (session.progress.finished) return const SizedBox.shrink();
            return Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppTheme.surface,
                border: Border(bottom: BorderSide(color: AppTheme.border)),
              ),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: HandshakeStepper(progress: session.progress),
            );
          },
        ),
        _ForwardBar(session: session),
        Expanded(child: SessionView(session.terminal)),
      ],
    );
  }
}

class _ForwardBar extends StatelessWidget {
  const _ForwardBar({required this.session});

  final SshTerminalSession session;

  @override
  Widget build(BuildContext context) {
    final mgr = session.forwards;
    return ValueListenableBuilder<List<PortSuggestion>>(
      valueListenable: session.suggestions,
      builder: (context, suggestions, _) {
        return ListenableBuilder(
          listenable: mgr ?? _NullListenable(),
          builder: (context, child) {
            final actives = mgr?.forwards ?? const <ActiveForward>[];
            if (suggestions.isEmpty && actives.isEmpty) {
              return const SizedBox.shrink();
            }
            return Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppTheme.surface,
                border: Border(bottom: BorderSide(color: AppTheme.border)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final s in suggestions)
                    _SuggestionRow(session: session, suggestion: s),
                  if (actives.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        for (final f in actives)
                          _ActiveChip(session: session, forward: f),
                      ],
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({required this.session, required this.suggestion});

  final SshTerminalSession session;
  final PortSuggestion suggestion;

  Future<void> _accept(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final err = await session.acceptSuggestion(suggestion);
    if (err != null) {
      messenger?.showSnackBar(SnackBar(content: Text(err)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(Icons.bolt_rounded, size: 16, color: AppTheme.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Server terdeteksi di port ${suggestion.port} — teruskan ke localhost?',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 12.5),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          ToolButton(
            icon: Icons.swap_horiz_rounded,
            label: 'Forward',
            color: AppTheme.accent,
            onTap: () => _accept(context),
          ),
          GhostIconButton(
            icon: Icons.close_rounded,
            size: 15,
            tooltip: 'Abaikan',
            onTap: () => session.dismissSuggestion(suggestion),
          ),
        ],
      ),
    );
  }
}

class _ActiveChip extends StatelessWidget {
  const _ActiveChip({required this.session, required this.forward});

  final SshTerminalSession session;
  final ActiveForward forward;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 5, 4, 5),
      decoration: BoxDecoration(
        color: AppTheme.success.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppTheme.rPill),
        border: Border.all(color: AppTheme.success.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.swap_horiz_rounded, size: 14, color: AppTheme.success),
          const SizedBox(width: 6),
          Text(
            forward.label,
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 12),
          ),
          if (forward.connections > 0) ...[
            const SizedBox(width: 6),
            Text('(${forward.connections})',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
          ],
          IconButton(
            icon: Icon(Icons.stop_circle_outlined,
                size: 15, color: AppTheme.textMuted),
            tooltip: 'Hentikan forward',
            padding: const EdgeInsets.only(left: 4),
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            onPressed: () => session.forwards?.stop(forward),
          ),
        ],
      ),
    );
  }
}

/// Listenable kosong untuk placeholder saat manajer forward belum siap.
class _NullListenable extends ChangeNotifier {}
