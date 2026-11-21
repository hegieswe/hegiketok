import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';
import 'connection_progress.dart';

const _red = Color(0xFFFF7B72);

/// Menampilkan tahapan handshake koneksi SSH (resolusi, TCP/tunnel, autentikasi,
/// buka channel) sebagai daftar berikon. Dipakai pada layar loading SFTP, info
/// server, dan Docker, serta sebagai overlay terminal.
class HandshakeStepper extends StatelessWidget {
  const HandshakeStepper({super.key, required this.progress, this.compact = false});

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
              const SizedBox(height: 4),
              Text(
                progress.error!,
                style: const TextStyle(color: _red, fontSize: 12),
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
          child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accent),
        );
        color = AppTheme.textPrimary;
        break;
      case StepStatus.done:
        leading = Icon(Icons.check_circle, size: 15, color: AppTheme.success);
        break;
      case StepStatus.failed:
        leading = const Icon(Icons.cancel, size: 15, color: _red);
        color = _red;
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
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                ),
            ]),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Pembungkus terpusat: tampilkan stepper di tengah layar loading.
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
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              Text(
                title!,
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 14),
            ],
            HandshakeStepper(progress: progress),
          ],
        ),
      ),
    );
  }
}
