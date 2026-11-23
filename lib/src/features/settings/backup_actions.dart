import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/host_providers.dart';
import '../../data/snippet_providers.dart';
import '../../data/vault_crypto.dart';
import '../../data/vault_service.dart';
import '../../ssh/known_hosts.dart';
import '../../theme/app_theme.dart';

/// Backup: kumpulkan data → enkripsi dengan password → simpan ke berkas.
Future<void> exportVault(BuildContext context, WidgetRef ref) async {
  final password = await _promptPassword(context,
      title: 'Password backup',
      hint: 'Minimal 6 karakter',
      confirm: true);
  if (password == null) return;

  try {
    final json = await buildVaultJson(
      hosts: ref.read(hostRepositoryProvider),
      snippets: ref.read(snippetRepositoryProvider),
      knownHosts: defaultKnownHosts,
    );
    final encrypted = encryptVault(json, password);
    final path = await FilePicker.saveFile(
      dialogTitle: 'Simpan backup terenkripsi',
      fileName: 'hegiketok-backup.hvault',
      bytes: Uint8List.fromList(utf8.encode(encrypted)),
    );
    if (!context.mounted) return;
    _toast(context, path == null ? 'Backup dibatalkan.' : '✓ Backup tersimpan.');
  } catch (e) {
    if (context.mounted) _toast(context, '✗ Gagal backup: $e', error: true);
  }
}

/// Restore: pilih berkas → minta password → dekripsi → pulihkan data.
Future<void> importVault(BuildContext context, WidgetRef ref) async {
  String fileText;
  try {
    final file = await FilePicker.pickFile();
    final path = file?.path;
    if (path == null) return;
    fileText = await File(path).readAsString();
  } catch (e) {
    if (context.mounted) _toast(context, '✗ Gagal buka berkas: $e', error: true);
    return;
  }

  if (!context.mounted) return;
  final password = await _promptPassword(context,
      title: 'Password backup', hint: 'Masukkan password backup');
  if (password == null) return;

  try {
    final json = decryptVault(fileText, password);
    final summary = await restoreVaultJson(
      json,
      hosts: ref.read(hostRepositoryProvider),
      snippets: ref.read(snippetRepositoryProvider),
      knownHosts: defaultKnownHosts,
    );
    ref.invalidate(hostsProvider);
    ref.invalidate(snippetsProvider);
    if (!context.mounted) return;
    _toast(context,
        '✓ Pulih: ${summary.hosts} host, ${summary.snippets} snippet, ${summary.knownHosts} known-host.');
  } on FormatException catch (e) {
    if (context.mounted) _toast(context, '✗ ${e.message}', error: true);
  } catch (_) {
    if (context.mounted) {
      _toast(context, '✗ Password salah atau berkas rusak.', error: true);
    }
  }
}

void _toast(BuildContext context, String msg, {bool error = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.showSnackBar(SnackBar(
    content: Text(msg),
    backgroundColor: error ? AppTheme.danger : AppTheme.surfaceHigh,
    behavior: SnackBarBehavior.floating,
  ));
}

Future<String?> _promptPassword(
  BuildContext context, {
  required String title,
  required String hint,
  bool confirm = false,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _PasswordDialog(title: title, hint: hint, confirm: confirm),
  );
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog(
      {required this.title, required this.hint, required this.confirm});

  final String title;
  final String hint;
  final bool confirm;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  String? _err;

  @override
  void dispose() {
    _pw.dispose();
    _pw2.dispose();
    super.dispose();
  }

  void _submit() {
    final p = _pw.text;
    if (p.length < 6) {
      setState(() => _err = 'Minimal 6 karakter.');
      return;
    }
    if (widget.confirm && p != _pw2.text) {
      setState(() => _err = 'Konfirmasi password tidak cocok.');
      return;
    }
    Navigator.of(context).pop(p);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surface,
      title: Text(widget.title,
          style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _pw,
            autofocus: true,
            obscureText: true,
            style: TextStyle(color: AppTheme.textPrimary),
            decoration: InputDecoration(hintText: widget.hint),
            onSubmitted: (_) => widget.confirm ? null : _submit(),
          ),
          if (widget.confirm) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _pw2,
              obscureText: true,
              style: TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(hintText: 'Ulangi password'),
              onSubmitted: (_) => _submit(),
            ),
          ],
          if (_err != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(_err!,
                  style: TextStyle(color: AppTheme.danger, fontSize: 12)),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Batal', style: TextStyle(color: AppTheme.textMuted)),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(backgroundColor: AppTheme.accent),
          child: const Text('OK'),
        ),
      ],
    );
  }
}
