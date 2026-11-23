import 'package:material_ui/material_ui.dart';

import '../../ssh/known_hosts.dart';
import '../../theme/app_theme.dart';
import '../../theme/ui.dart';

/// Tampilkan daftar host key tepercaya (TOFU) dengan opsi cabut kepercayaan.
Future<void> showKnownHostsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _KnownHostsDialog(),
  );
}

class _KnownHostsDialog extends StatefulWidget {
  const _KnownHostsDialog();

  @override
  State<_KnownHostsDialog> createState() => _KnownHostsDialogState();
}

class _KnownHostsDialogState extends State<_KnownHostsDialog> {
  List<KnownHost>? _items;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final all = await defaultKnownHosts.all();
    if (mounted) setState(() => _items = all);
  }

  Future<void> _forget(KnownHost h) async {
    await defaultKnownHosts.forget(h.hostPort);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.verified_user_rounded,
                      size: 20, color: AppTheme.accent),
                  const SizedBox(width: 8),
                  Text('Known Hosts',
                      style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Sidik jari host key yang kamu percayai. Cabut bila server '
                'dibangun ulang atau kamu ingin verifikasi ulang saat konek '
                'berikutnya.',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 14),
              Flexible(
                child: items == null
                    ? const SizedBox(
                        height: 80,
                        child: Center(child: CircularProgressIndicator()))
                    : items.isEmpty
                        ? _empty()
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: items.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 6),
                            itemBuilder: (_, i) =>
                                _row(items[i]),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _empty() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          Icon(Icons.shield_outlined, size: 34, color: AppTheme.textFaint),
          const SizedBox(height: 10),
          Text('Belum ada host key tersimpan.',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
          const SizedBox(height: 2),
          Text('Akan terisi otomatis saat kamu menyetujui host baru.',
              style: TextStyle(color: AppTheme.textFaint, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _row(KnownHost h) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceInput,
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(h.hostPort,
                        style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    if (h.type.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.bg,
                          borderRadius: BorderRadius.circular(AppTheme.rSm),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Text(h.type,
                            style: TextStyle(
                                color: AppTheme.textMuted,
                                fontSize: 10.5,
                                fontFamily: 'monospace')),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(h.fingerprint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 11,
                        fontFamily: 'monospace')),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GhostIconButton(
            icon: Icons.delete_outline,
            tooltip: 'Cabut kepercayaan',
            size: 16,
            color: AppTheme.danger,
            onTap: () => _forget(h),
          ),
        ],
      ),
    );
  }
}
