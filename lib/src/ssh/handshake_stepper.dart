import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';
import 'connection_progress.dart';

/// Menampilkan tahapan handshake koneksi SSH (resolusi, TCP/tunnel, autentikasi,
/// buka channel) sebagai daftar berikon. Dipakai pada layar loading SFTP, info
/// server, dan Docker, serta sebagai overlay terminal.
class HandshakeStepper extends StatelessWidget {
  const HandshakeStepper(
      {super.key, required this.progress, this.compact = false});

  final ConnectionProgress progress;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: progress,
      builder: (context, _) {
        final steps = progress.steps;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final s in steps)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: _StepRow(step: s),
              ),
            if (progress.error != null) ...[
              const SizedBox(height: 6),
              Text(
                progress.error!,
                style: TextStyle(color: AppTheme.danger, fontSize: 12),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step});

  final HandshakeStep step;

  @override
  Widget build(BuildContext context) {
    final Widget leading;
    Color color = AppTheme.textMuted;
    switch (step.status) {
      case StepStatus.active:
        leading = SizedBox(
          width: 15,
          height: 15,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: AppTheme.accent),
        );
        color = AppTheme.textPrimary;
        break;
      case StepStatus.done:
        leading =
            Icon(Icons.check_circle_rounded, size: 16, color: AppTheme.success);
        break;
      case StepStatus.failed:
        leading = Icon(Icons.cancel_rounded, size: 16, color: AppTheme.danger);
        color = AppTheme.danger;
        break;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(width: 18, child: Center(child: leading)),
        const SizedBox(width: 10),
        Flexible(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(
                text: step.label,
                style: TextStyle(color: color, fontSize: 13),
              ),
              if (step.detail != null)
                TextSpan(
                  text: '  ·  ${step.detail}',
                  style: TextStyle(color: AppTheme.textFaint, fontSize: 12),
                ),
            ]),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Pembungkus terpusat: layar "menyambungkan…" berbranding + stepper.
class HandshakeLoading extends StatelessWidget {
  const HandshakeLoading({super.key, required this.progress, this.title});

  final ConnectionProgress progress;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.bg,
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppTheme.accent, AppTheme.violet],
                    ),
                    borderRadius: BorderRadius.circular(AppTheme.rMd),
                  ),
                  child: const Icon(Icons.lan_rounded,
                      size: 18, color: Colors.white),
                ),
                const SizedBox(width: 12),
                if (title != null)
                  Flexible(
                    child: Text(
                      title!,
                      style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            HandshakeStepper(progress: progress),
          ],
        ),
      ),
    );
  }
}
