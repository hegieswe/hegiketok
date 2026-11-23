import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';
import 'known_hosts.dart';

/// Kunci navigator global → memungkinkan dialog verifikasi host key muncul dari
/// dalam alur koneksi (yang berjalan di controller, bukan widget).
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// [HostKeyVerifier] berbasis dialog. Dipasang ke [globalHostKeyVerifier] saat
/// startup. Mengembalikan `false` bila konteks navigator belum siap (fail-safe:
/// koneksi dibatalkan, tidak pernah menerima kunci diam-diam).
Future<bool> hostKeyDialogVerifier(HostKeyPrompt prompt) async {
  final context = navigatorKey.currentContext;
  if (context == null) return false;
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false, // tap di luar = batal (aman), bukan terima
    builder: (_) => _HostKeyDialog(prompt: prompt),
  );
  return result ?? false;
}

class _HostKeyDialog extends StatelessWidget {
  const _HostKeyDialog({required this.prompt});

  final HostKeyPrompt prompt;

  bool get _changed => prompt.status == HostKeyStatus.changed;

  @override
  Widget build(BuildContext context) {
    final accent = _changed ? AppTheme.danger : AppTheme.accent;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(22),
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
                      color: accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(AppTheme.rMd),
                    ),
                    child: Icon(
                      _changed
                          ? Icons.gpp_maybe_rounded
                          : Icons.verified_user_rounded,
                      size: 19,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _changed
                          ? 'Host key BERUBAH'
                          : 'Host baru — verifikasi sidik jari',
                      style: TextStyle(
                        color: _changed ? AppTheme.danger : AppTheme.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _changed
                    ? 'Sidik jari kunci untuk ${prompt.hostPort} berbeda dari yang '
                        'tersimpan. Ini BISA berarti serangan man-in-the-middle '
                        '— atau server memang dibangun ulang. Jangan lanjutkan '
                        'kecuali kamu yakin penyebabnya.'
                    : 'Kamu pertama kali terhubung ke ${prompt.hostPort}. '
                        'Cocokkan sidik jari di bawah dengan yang ada di server '
                        '(mis. `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub`) '
                        'sebelum mempercayainya.',
                style: TextStyle(
                    color: AppTheme.textMuted, fontSize: 12.5, height: 1.45),
              ),
              const SizedBox(height: 16),
              _TypeBadge(type: prompt.type),
              const SizedBox(height: 10),
              if (_changed) ...[
                _FingerprintBox(
                  label: 'Tersimpan (lama)',
                  value: prompt.previousFingerprint ?? '—',
                  tone: AppTheme.textMuted,
                  strike: true,
                ),
                const SizedBox(height: 8),
                _FingerprintBox(
                  label: 'Ditawarkan sekarang (baru)',
                  value: prompt.fingerprint,
                  tone: AppTheme.danger,
                ),
              ] else
                _FingerprintBox(
                  label: 'Sidik jari SHA256',
                  value: prompt.fingerprint,
                  tone: AppTheme.textPrimary,
                ),
              const SizedBox(height: 20),
              _buttons(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buttons(BuildContext context) {
    // Host baru: aksi "percayai" ditonjolkan (alur lancar, nyaman).
    // Host berubah: aksi AMAN ("batal") yang ditonjolkan; "percayai kunci baru"
    // sengaja di-de-emphasize sebagai tombol berisiko.
    final cancel = TextButton(
      onPressed: () => Navigator.of(context).pop(false),
      style: TextButton.styleFrom(foregroundColor: AppTheme.textMuted),
      child: const Text('Batal'),
    );
    final trust = FilledButton.icon(
      onPressed: () => Navigator.of(context).pop(true),
      icon: Icon(
        _changed ? Icons.warning_amber_rounded : Icons.check_rounded,
        size: 17,
      ),
      label: Text(_changed ? 'Percayai kunci baru' : 'Percayai & Lanjut'),
      style: FilledButton.styleFrom(
        backgroundColor: _changed ? AppTheme.danger : AppTheme.accent,
        foregroundColor: AppTheme.onAccent,
      ),
    );

    if (_changed) {
      // Tombol aman (Batal) dibuat solid & dominan di kanan; aksi berisiko
      // diletakkan di kiri dengan gaya rendah.
      final risky = TextButton.icon(
        onPressed: () => Navigator.of(context).pop(true),
        icon: const Icon(Icons.warning_amber_rounded, size: 16),
        label: const Text('Percayai kunci baru'),
        style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
      );
      final safe = FilledButton(
        onPressed: () => Navigator.of(context).pop(false),
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.accent,
          foregroundColor: AppTheme.onAccent,
        ),
        child: const Text('Batalkan (disarankan)'),
      );
      return Row(
        children: [
          risky,
          const Spacer(),
          safe,
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        cancel,
        const SizedBox(width: 8),
        trust,
      ],
    );
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.type});
  final String type;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surfaceInput,
        borderRadius: BorderRadius.circular(AppTheme.rSm),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.vpn_key_rounded, size: 13, color: AppTheme.textMuted),
          const SizedBox(width: 6),
          Text(
            type.isEmpty ? 'host key' : type,
            style: TextStyle(
              color: AppTheme.textMuted,
              fontSize: 11.5,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _FingerprintBox extends StatelessWidget {
  const _FingerprintBox({
    required this.label,
    required this.value,
    required this.tone,
    this.strike = false,
  });

  final String label;
  final String value;
  final Color tone;
  final bool strike;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: AppTheme.textFaint,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.surfaceInput,
            borderRadius: BorderRadius.circular(AppTheme.rSm),
            border: Border.all(
              color: strike ? AppTheme.border : tone.withValues(alpha: 0.35),
            ),
          ),
          child: SelectableText(
            value,
            style: TextStyle(
              color: tone,
              fontSize: 12.5,
              fontFamily: 'monospace',
              height: 1.35,
              decoration:
                  strike ? TextDecoration.lineThrough : TextDecoration.none,
            ),
          ),
        ),
      ],
    );
  }
}
