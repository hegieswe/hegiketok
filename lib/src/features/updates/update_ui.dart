import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

import '../../theme/app_theme.dart';
import '../settings/settings_providers.dart';
import 'update_checker.dart';

/// Jeda minimum antar pemeriksaan otomatis.
const Duration kAutoUpdateInterval = Duration(hours: 24);

/// true bila pemeriksaan otomatis sudah waktunya dijalankan.
bool shouldAutoCheck({
  required bool enabled,
  required DateTime? lastCheck,
  required DateTime now,
  Duration interval = kAutoUpdateInterval,
}) {
  if (!enabled) return false;
  if (lastCheck == null) return true;
  // Jam sistem mundur → anggap sudah waktunya (jangan terkunci selamanya).
  if (lastCheck.isAfter(now)) return true;
  return now.difference(lastCheck) >= interval;
}

/// Pemeriksaan senyap saat aplikasi dibuka: paling sering sekali per
/// [kAutoUpdateInterval], hanya bersuara bila memang ada versi baru. Kegagalan
/// (offline, belum ada rilis) diabaikan diam-diam.
Future<void> maybeAutoCheckForUpdate(
    BuildContext context, WidgetRef ref) async {
  final notifier = ref.read(settingsProvider.notifier);
  final now = DateTime.now();
  if (!shouldAutoCheck(
    enabled: ref.read(settingsProvider).autoCheckUpdates,
    lastCheck: notifier.lastUpdateCheck,
    now: now,
  )) {
    return;
  }

  final result = await checkForUpdate();
  // Catat hanya bila GitHub benar-benar menjawab, agar saat offline kita
  // mencoba lagi pada pembukaan berikutnya.
  if (result is! UpdateFailed) notifier.markUpdateChecked(now);
  if (result is! UpdateAvailable || !context.mounted) return;

  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.showSnackBar(SnackBar(
    behavior: SnackBarBehavior.floating,
    duration: const Duration(seconds: 12),
    content: Text('HegiKetok ${result.info.version} tersedia.'),
    action: SnackBarAction(
      label: 'Lihat',
      textColor: AppTheme.accent,
      onPressed: () {
        if (context.mounted) showUpdateDialog(context, result.info);
      },
    ),
  ));
}

/// Jalankan pemeriksaan pembaruan dengan umpan balik visual.
Future<void> checkForUpdateInteractive(BuildContext context) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.showSnackBar(const SnackBar(
    content: Text('Memeriksa pembaruan…'),
    duration: Duration(seconds: 2),
    behavior: SnackBarBehavior.floating,
  ));

  final result = await checkForUpdate();
  if (!context.mounted) return;
  messenger?.hideCurrentSnackBar();

  switch (result) {
    case UpdateUpToDate():
      messenger?.showSnackBar(const SnackBar(
        content: Text('Kamu memakai versi terbaru ($kAppVersion).'),
        behavior: SnackBarBehavior.floating,
      ));
    case UpdateFailed(:final message):
      messenger?.showSnackBar(SnackBar(
        content: Text(message, style: TextStyle(color: AppTheme.onAccent)),
        backgroundColor: AppTheme.danger,
        behavior: SnackBarBehavior.floating,
      ));
    case UpdateAvailable(:final info):
      await showUpdateDialog(context, info);
  }
}

/// Dialog "Pembaruan tersedia" untuk [info].
Future<void> showUpdateDialog(BuildContext context, UpdateInfo info) {
  return showDialog<void>(
    context: context,
    builder: (_) => _UpdateDialog(info: info),
  );
}

void _openExternally(String target) {
  if (target.isEmpty) return;
  if (Platform.isMacOS) {
    Process.run('open', [target]);
  } else if (Platform.isLinux) {
    Process.run('xdg-open', [target]);
  } else if (Platform.isWindows) {
    Process.run('cmd', ['/c', 'start', '', target]);
  }
}

String _formatBytes(int bytes) {
  if (bytes <= 0) return '';
  const mb = 1024 * 1024;
  if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(1)} MB';
  return '${(bytes / 1024).toStringAsFixed(0)} KB';
}

enum _Phase { idle, downloading, done, failed }

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.info});
  final UpdateInfo info;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  _Phase _phase = _Phase.idle;
  double? _progress;
  String? _error;
  File? _file;
  bool _cancel = false;

  @override
  void dispose() {
    _cancel = true; // hentikan unduhan bila dialog ditutup
    super.dispose();
  }

  Future<void> _download() async {
    final asset = widget.info.asset;
    if (asset == null) return;
    setState(() {
      _phase = _Phase.downloading;
      _progress = 0;
      _error = null;
      _cancel = false;
    });
    try {
      final dir = await getDownloadsDirectory() ??
          await getApplicationSupportDirectory();
      final file = await downloadReleaseAsset(
        asset,
        directory: dir,
        isCancelled: () => _cancel,
        onProgress: (f) {
          if (mounted) setState(() => _progress = f);
        },
      );
      if (!mounted) return;
      setState(() {
        _phase = _Phase.done;
        _file = file;
      });
      _openExternally(file.path);
    } on UpdateDownloadCancelled {
      if (mounted) setState(() => _phase = _Phase.idle);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.failed;
        _error = e is UpdateDownloadException ? e.message : 'Gagal: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final asset = info.asset;
    final busy = _phase == _Phase.downloading;

    return AlertDialog(
      backgroundColor: AppTheme.surface,
      title: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: AppTheme.accentSoft,
              borderRadius: BorderRadius.circular(AppTheme.rSm),
            ),
            child: Icon(Icons.system_update_alt_rounded,
                size: 16, color: AppTheme.accent),
          ),
          const SizedBox(width: 11),
          Text('Pembaruan tersedia',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Versi ${info.version} sudah rilis — kamu memakai $kAppVersion.',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
            ),
            if (info.notes != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 180),
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceInput,
                  borderRadius: BorderRadius.circular(AppTheme.rSm),
                  border: Border.all(color: AppTheme.border),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    info.notes!,
                    style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 12.5,
                        height: 1.45),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            ..._status(asset),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            if (busy) {
              setState(() => _cancel = true);
            } else {
              Navigator.of(context).pop();
            }
          },
          child: Text(busy ? 'Batalkan' : 'Tutup',
              style: TextStyle(color: AppTheme.textMuted)),
        ),
        if (!busy && info.url.isNotEmpty)
          TextButton(
            onPressed: () => _openExternally(info.url),
            child: Text('Halaman rilis',
                style: TextStyle(color: AppTheme.accent)),
          ),
        if (_phase == _Phase.done && _file != null)
          FilledButton(
            onPressed: () => _openExternally(_file!.path),
            style: FilledButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: AppTheme.onAccent),
            child: const Text('Buka lagi'),
          )
        else if (asset != null && !busy)
          FilledButton(
            onPressed: _download,
            style: FilledButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: AppTheme.onAccent),
            child: Text(
                _phase == _Phase.failed ? 'Coba lagi' : 'Unduh & buka'),
          ),
      ],
    );
  }

  List<Widget> _status(ReleaseAsset? asset) {
    final muted = TextStyle(color: AppTheme.textMuted, fontSize: 12);
    switch (_phase) {
      case _Phase.idle:
        if (asset == null) {
          return [
            Text(
              'Rilis ini tidak menyertakan paket macOS. Buka halaman rilis '
              'untuk mengunduh secara manual.',
              style: muted,
            ),
          ];
        }
        final size = _formatBytes(asset.size);
        return [
          Row(
            children: [
              Icon(Icons.inventory_2_outlined,
                  size: 14, color: AppTheme.textFaint),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  size.isEmpty ? asset.name : '${asset.name} · $size',
                  overflow: TextOverflow.ellipsis,
                  style: muted.copyWith(fontFamily: 'Menlo', fontSize: 11.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            asset.sha256 != null
                ? 'Disimpan ke folder Downloads dan diverifikasi (SHA-256).'
                : 'Disimpan ke folder Downloads.',
            style: muted,
          ),
        ];
      case _Phase.downloading:
        final pct = _progress == null ? '' : ' ${(_progress! * 100).round()}%';
        return [
          Text('Mengunduh…$pct', style: muted),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.rPill),
            child: LinearProgressIndicator(
              value: _progress,
              minHeight: 5,
              color: AppTheme.accent,
              backgroundColor: AppTheme.border,
            ),
          ),
        ];
      case _Phase.done:
        return [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.check_circle_rounded,
                  size: 15, color: AppTheme.success),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Terunduh dan dibuka. Tutup HegiKetok, seret versi baru ke '
                  'folder Applications (timpa yang lama), lalu buka kembali.',
                  style: muted.copyWith(color: AppTheme.textPrimary),
                ),
              ),
            ],
          ),
        ];
      case _Phase.failed:
        return [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline_rounded,
                  size: 15, color: AppTheme.danger),
              const SizedBox(width: 7),
              Expanded(
                child: Text(_error ?? 'Unduhan gagal.',
                    style: muted.copyWith(color: AppTheme.danger)),
              ),
            ],
          ),
        ];
    }
  }
}
