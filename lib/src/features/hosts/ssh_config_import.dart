import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uuid/uuid.dart';

import '../../data/host_providers.dart';
import '../../models/ssh_host.dart';
import '../../theme/app_theme.dart';
import 'ssh_config_parser.dart';

/// Tampilkan dialog import dari `~/.ssh/config`.
Future<void> showSshConfigImport(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _ImportDialog(),
  );
}

class _ImportDialog extends ConsumerStatefulWidget {
  const _ImportDialog();

  @override
  ConsumerState<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends ConsumerState<_ImportDialog> {
  List<SshConfigEntry> _entries = [];
  final Set<int> _selected = {};
  Set<String> _existingKeys = {};
  bool _loading = true;
  bool _importing = false;
  String? _error;
  String? _configPath;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final home = Platform.environment['HOME'] ?? '';
      final path = '$home/.ssh/config';
      _configPath = path;
      final file = File(path);
      if (!await file.exists()) {
        setState(() {
          _loading = false;
          _error = 'File ~/.ssh/config tidak ditemukan.';
        });
        return;
      }
      final content = await file.readAsString();
      final entries = parseSshConfig(content);

      // Tandai host yang sudah tersimpan agar tak dobel.
      final existing = ref.read(hostsProvider).value ?? [];
      _existingKeys =
          existing.map((h) => _key(h.host, h.port, h.username)).toSet();

      setState(() {
        _entries = entries;
        _loading = false;
        // Pilih default semua yang belum ada.
        for (var i = 0; i < entries.length; i++) {
          if (!_isDuplicate(entries[i])) _selected.add(i);
        }
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Gagal membaca config: $e';
      });
    }
  }

  String _key(String host, int port, String user) => '$user@$host:$port';

  bool _isDuplicate(SshConfigEntry e) =>
      _existingKeys.contains(_key(e.hostName, e.port, e.user ?? ''));

  Future<void> _import() async {
    setState(() => _importing = true);
    final notifier = ref.read(hostsProvider.notifier);
    final home = Platform.environment['HOME'] ?? '';

    for (final i in _selected) {
      final e = _entries[i];

      // Coba baca private key bila IdentityFile ditentukan.
      String? privateKey;
      if (e.usesKey) {
        var path = e.identityFile!;
        if (path.startsWith('~/')) path = '$home/${path.substring(2)}';
        try {
          final f = File(path);
          if (await f.exists()) privateKey = await f.readAsString();
        } catch (_) {/* abaikan; user bisa isi key nanti */}
      }

      final host = SshHost(
        id: const Uuid().v4(),
        label: e.alias,
        host: e.hostName,
        port: e.port,
        username: e.user ?? '',
        authMethod: e.usesKey ? SshAuthMethod.key : SshAuthMethod.password,
      );

      await notifier.save(host, privateKey: privateKey);
    }

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppTheme.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.download_outlined,
                      color: AppTheme.accent, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'Import dari ~/.ssh/config',
                    style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Flexible(child: _content()),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _importing
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Tutup',
                        style: TextStyle(color: AppTheme.textMuted)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: (_selected.isEmpty || _importing) ? null : _import,
                    style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.accent),
                    child: _importing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : Text('Import (${_selected.length})'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppTheme.accent),
          ),
        ),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Text(_error!,
            style: const TextStyle(color: Color(0xFFFF7B72), fontSize: 13)),
      );
    }
    if (_entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Text(
          'Tidak ada host konkret di $_configPath.',
          style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Ditemukan ${_entries.length} host:',
          style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
        ),
        const SizedBox(height: 8),
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _entries.length,
            itemBuilder: (_, i) => _entryTile(i),
          ),
        ),
      ],
    );
  }

  Widget _entryTile(int i) {
    final e = _entries[i];
    final dup = _isDuplicate(e);
    final checked = _selected.contains(i);
    return InkWell(
      onTap: () => setState(() {
        if (checked) {
          _selected.remove(i);
        } else {
          _selected.add(i);
        }
      }),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: checked,
                onChanged: (v) => setState(() {
                  if (v == true) {
                    _selected.add(i);
                  } else {
                    _selected.remove(i);
                  }
                }),
                activeColor: AppTheme.accent,
                side: const BorderSide(color: AppTheme.border),
              ),
            ),
            const SizedBox(width: 10),
            Icon(e.usesKey ? Icons.vpn_key_outlined : Icons.dns_outlined,
                size: 15, color: AppTheme.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(e.alias,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w500)),
                      ),
                      if (dup) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppTheme.textMuted.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('sudah ada',
                              style: TextStyle(
                                  color: AppTheme.textMuted, fontSize: 10)),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    '${e.user ?? '—'}@${e.hostName}:${e.port}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppTheme.textMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
