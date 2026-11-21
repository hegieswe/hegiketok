import 'package:material_ui/material_ui.dart';

import '../../ssh/handshake_stepper.dart';
import '../../ssh/port_forward.dart';
import '../../theme/app_theme.dart';
import '../terminal/session_view.dart';
import 'ssh_terminal_session.dart';

const _green = Color(0xFF3FB950);

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
              color: AppTheme.surface,
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
              color: AppTheme.surface,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          const Icon(Icons.bolt, size: 16, color: AppTheme.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Server terdeteksi di port ${suggestion.port} — teruskan ke localhost?',
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          _MiniButton(
            label: 'Forward',
            primary: true,
            onTap: () => _accept(context),
          ),
          const SizedBox(width: 6),
          IconButton(
            icon: const Icon(Icons.close, size: 15, color: AppTheme.textMuted),
            tooltip: 'Abaikan',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            onPressed: () => session.dismissSuggestion(suggestion),
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
        color: _green.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _green.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.swap_horiz, size: 14, color: _green),
          const SizedBox(width: 6),
          Text(
            forward.label,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
          ),
          if (forward.connections > 0) ...[
            const SizedBox(width: 6),
            Text('(${forward.connections})',
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
          ],
          IconButton(
            icon: const Icon(Icons.stop_circle_outlined,
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

class _MiniButton extends StatelessWidget {
  const _MiniButton(
      {required this.label, required this.onTap, this.primary = false});

  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: primary
              ? AppTheme.accent.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: primary ? AppTheme.accent : AppTheme.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: primary ? AppTheme.accent : AppTheme.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// Listenable kosong untuk placeholder saat manajer forward belum siap.
class _NullListenable extends ChangeNotifier {}
