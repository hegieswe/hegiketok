import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/host_providers.dart';
import '../../data/host_repository.dart';
import '../../theme/app_theme.dart';

/// Dialog "Riwayat daftar host": cadangan otomatis yang dibuat tiap kali
/// daftar host berubah, dengan tombol pulihkan.
Future<void> showHostBackupsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _HostBackupsDialog(),
  );
}

/// Format waktu singkat tanpa dependensi lokal: `23 Nov 2026, 13.52`.
String formatBackupTime(DateTime t) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
    'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
  ];
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.day} ${months[t.month - 1]} ${t.year}, '
      '${two(t.hour)}.${two(t.minute)}';
}

/// Ringkasan isi cadangan: beberapa label pertama + sisa.
String summarizeBackupHosts(List<String> labels, {int show = 3}) {
  if (labels.isEmpty) return 'kosong';
  final head = labels.take(show).join(', ');
  final rest = labels.length - show;
  return rest > 0 ? '$head, +$rest lainnya' : head;
}

class _HostBackupsDialog extends ConsumerStatefulWidget {
  const _HostBackupsDialog();

  @override
  ConsumerState<_HostBackupsDialog> createState() => _HostBackupsDialogState();
}

class _HostBackupsDialogState extends ConsumerState<_HostBackupsDialog> {
  late Future<List<HostBackup>> _backups;
  HostBackup? _confirming;
  bool _busy = false;
  String? _message;
  bool _messageIsError = false;

  @override
  void initState() {
    super.initState();
    _backups = ref.read(hostRepositoryProvider).listBackups();
  }

  Future<void> _restore(HostBackup b) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final n = await ref.read(hostsProvider.notifier).restoreBackup(b);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _confirming = null;
        _messageIsError = false;
        _message = '$n host dipulihkan. Daftar sebelumnya ikut dicadangkan.';
        _backups = ref.read(hostRepositoryProvider).listBackups();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _confirming = null;
        _messageIsError = true;
        _message = 'Gagal memulihkan: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surface,
      title: Row(
        children: [
          Icon(Icons.history_rounded, size: 18, color: AppTheme.accent),
          const SizedBox(width: 9),
          Text('Riwayat daftar host',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Setiap kali daftar host berubah, versi sebelumnya disimpan di '
              'sini (maks. ${HostRepository.maxBackups}). Password dan key '
              'tetap di Keychain dan tidak ikut berubah.',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12.5),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: FutureBuilder<List<HostBackup>>(
                future: _backups,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return Padding(
                      padding: const EdgeInsets.all(20),
                      child: Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppTheme.accent),
                        ),
                      ),
                    );
                  }
                  final items = snap.data ?? const <HostBackup>[];
                  if (items.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      child: Text(
                        'Belum ada cadangan. Cadangan pertama dibuat saat kamu '
                        'mengubah daftar host berikutnya.',
                        style:
                            TextStyle(color: AppTheme.textFaint, fontSize: 12.5),
                      ),
                    );
                  }
                  return ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (_, i) => _row(items[i]),
                    ),
                  );
                },
              ),
            ),
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(_message!,
                  style: TextStyle(
                      color:
                          _messageIsError ? AppTheme.danger : AppTheme.success,
                      fontSize: 12.5)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text('Tutup', style: TextStyle(color: AppTheme.textMuted)),
        ),
      ],
    );
  }

  Widget _row(HostBackup b) {
    final confirming = identical(_confirming, b);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
      decoration: BoxDecoration(
        color: AppTheme.surfaceInput,
        borderRadius: BorderRadius.circular(AppTheme.rSm),
        border: Border.all(
            color: confirming ? AppTheme.warning : AppTheme.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${formatBackupTime(b.time)}  ·  ${b.hosts.length} host',
                  style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  confirming
                      ? 'Ganti daftar host sekarang dengan versi ini?'
                      : summarizeBackupHosts(
                          b.hosts.map((h) => h.label).toList()),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color:
                          confirming ? AppTheme.warning : AppTheme.textMuted,
                      fontSize: 11.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (confirming) ...[
            TextButton(
              onPressed: _busy ? null : () => setState(() => _confirming = null),
              child:
                  Text('Batal', style: TextStyle(color: AppTheme.textMuted)),
            ),
            FilledButton(
              onPressed: _busy ? null : () => _restore(b),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: AppTheme.onAccent,
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('Ya, pulihkan'),
            ),
          ] else
            OutlinedButton(
              onPressed: _busy ? null : () => setState(() => _confirming = b),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.textPrimary,
                side: BorderSide(color: AppTheme.borderStrong),
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('Pulihkan'),
            ),
        ],
      ),
    );
  }
}
