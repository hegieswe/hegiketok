import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uuid/uuid.dart';

import '../../data/snippet_providers.dart';
import '../../models/snippet.dart';
import '../../theme/app_theme.dart';
import '../../theme/ui.dart';

/// Tampilkan pustaka snippet. Jika [onType]/[onRun] diberikan (dari terminal
/// aktif), tiap snippet bisa diketik atau dijalankan ke sesi.
Future<void> showSnippetsDialog(
  BuildContext context, {
  void Function(String command)? onType,
  void Function(String command)? onRun,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _SnippetsDialog(onType: onType, onRun: onRun),
  );
}

class _SnippetsDialog extends ConsumerWidget {
  const _SnippetsDialog({this.onType, this.onRun});

  final void Function(String command)? onType;
  final void Function(String command)? onRun;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(snippetsProvider);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.code_rounded, size: 20, color: AppTheme.accent),
                  const SizedBox(width: 8),
                  Text('Snippets',
                      style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w700)),
                  const Spacer(),
                  ToolButton(
                    icon: Icons.add_rounded,
                    label: 'Baru',
                    color: AppTheme.accent,
                    onTap: () => _edit(context, ref, null),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                onType == null
                    ? 'Kelola perintah tersimpan. Buka dari terminal untuk mengetik/menjalankan.'
                    : 'Ketik ke terminal (tinjau dulu) atau jalankan langsung.',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 14),
              Flexible(
                child: async.when(
                  loading: () => const SizedBox(
                      height: 80,
                      child: Center(child: CircularProgressIndicator())),
                  error: (e, _) => Text('Gagal memuat: $e',
                      style: TextStyle(color: AppTheme.danger)),
                  data: (items) => items.isEmpty
                      ? _empty()
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: items.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 6),
                          itemBuilder: (_, i) => _SnippetRow(
                            snippet: items[i],
                            onType: onType,
                            onRun: onRun,
                            onEdit: () => _edit(context, ref, items[i]),
                            onDelete: () =>
                                ref.read(snippetsProvider.notifier).delete(items[i].id),
                            closeDialog: () => Navigator.of(context).pop(),
                          ),
                        ),
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
          Icon(Icons.code_off_rounded, size: 34, color: AppTheme.textFaint),
          const SizedBox(height: 10),
          Text('Belum ada snippet.',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
          const SizedBox(height: 2),
          Text('Simpan perintah yang sering dipakai lewat tombol "Baru".',
              style: TextStyle(color: AppTheme.textFaint, fontSize: 12)),
        ],
      ),
    );
  }

  Future<void> _edit(
      BuildContext context, WidgetRef ref, Snippet? existing) async {
    final result = await showDialog<Snippet>(
      context: context,
      builder: (_) => _SnippetEditor(existing: existing),
    );
    if (result != null) {
      await ref.read(snippetsProvider.notifier).save(result);
    }
  }
}

class _SnippetRow extends StatelessWidget {
  const _SnippetRow({
    required this.snippet,
    required this.onType,
    required this.onRun,
    required this.onEdit,
    required this.onDelete,
    required this.closeDialog,
  });

  final Snippet snippet;
  final void Function(String command)? onType;
  final void Function(String command)? onRun;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback closeDialog;

  @override
  Widget build(BuildContext context) {
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
                Text(snippet.name,
                    style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(snippet.command,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 11.5,
                        fontFamily: 'monospace')),
              ],
            ),
          ),
          if (onType != null) ...[
            GhostIconButton(
              icon: Icons.keyboard_rounded,
              tooltip: 'Ketik ke terminal',
              size: 16,
              onTap: () {
                onType!(snippet.command);
                closeDialog();
              },
            ),
            GhostIconButton(
              icon: Icons.play_arrow_rounded,
              tooltip: 'Jalankan',
              size: 18,
              color: AppTheme.accent,
              onTap: () {
                onRun?.call(snippet.command);
                closeDialog();
              },
            ),
          ],
          GhostIconButton(
            icon: Icons.edit_outlined,
            tooltip: 'Edit',
            size: 15,
            onTap: onEdit,
          ),
          GhostIconButton(
            icon: Icons.delete_outline,
            tooltip: 'Hapus',
            size: 15,
            color: AppTheme.danger,
            onTap: onDelete,
          ),
        ],
      ),
    );
  }
}

class _SnippetEditor extends StatefulWidget {
  const _SnippetEditor({this.existing});

  final Snippet? existing;

  @override
  State<_SnippetEditor> createState() => _SnippetEditorState();
}

class _SnippetEditorState extends State<_SnippetEditor> {
  late final TextEditingController _name;
  late final TextEditingController _command;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _command = TextEditingController(text: widget.existing?.command ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _command.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    final command = _command.text.trim();
    if (name.isEmpty || command.isEmpty) return;
    final snip = (widget.existing ??
            Snippet(id: const Uuid().v4(), name: '', command: ''))
        .copyWith(name: name, command: command);
    Navigator.of(context).pop(snip);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.existing == null ? 'Snippet baru' : 'Edit snippet',
                  style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              _field('Nama', _name, 'mis. Lihat log nginx'),
              const SizedBox(height: 12),
              _field('Perintah', _command, 'mis. tail -f /var/log/nginx/error.log',
                  mono: true, lines: 3),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('Batal',
                        style: TextStyle(color: AppTheme.textMuted)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _save,
                    style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.accent,
                        foregroundColor: AppTheme.onAccent),
                    child: const Text('Simpan'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl, String hint,
      {bool mono = false, int lines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          maxLines: lines,
          style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 13.5,
              fontFamily: mono ? 'monospace' : null),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: AppTheme.textFaint, fontSize: 13),
            isDense: true,
            filled: true,
            fillColor: AppTheme.surfaceInput,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.rSm),
              borderSide: BorderSide(color: AppTheme.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.rSm),
              borderSide: BorderSide(color: AppTheme.accent),
            ),
          ),
        ),
      ],
    );
  }
}
