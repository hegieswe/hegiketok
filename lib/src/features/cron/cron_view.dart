import 'package:material_ui/material_ui.dart';

import '../../ssh/handshake_stepper.dart';
import '../../theme/app_theme.dart';
import '../../theme/ui.dart';
import 'cron_controller.dart';
import 'cron_models.dart';
import 'cron_service.dart';

/// Panel penjadwal cron: daftar job crontab + tambah/edit/hapus/aktif-nonaktif.
class CronView extends StatelessWidget {
  const CronView({super.key, required this.controller});

  final CronController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        if (c.loading && c.snapshot == null && !c.progress.finished) {
          return HandshakeLoading(
            progress: c.progress,
            title: 'Menyambungkan ke ${c.credentials.label}…',
          );
        }
        if (c.connectError != null && c.snapshot == null) {
          return PanelMessage(
            icon: Icons.error_outline,
            iconColor: AppTheme.warning,
            title: 'Gagal terhubung',
            message: c.connectError!,
            onAction: c.connect,
          );
        }
        if (c.loading && c.snapshot == null) {
          return Container(
            color: AppTheme.bg,
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppTheme.accent),
              ),
            ),
          );
        }
        final snap = c.snapshot!;
        if (snap.error != null) {
          return PanelMessage(
            icon: Icons.schedule,
            iconColor: AppTheme.warning,
            message: snap.error!,
            onAction: c.refresh,
          );
        }
        return Container(
          color: AppTheme.bg,
          child: Column(
            children: [
              _header(context, c),
              Expanded(child: _list(context, c)),
            ],
          ),
        );
      },
    );
  }

  Widget _header(BuildContext context, CronController c) {
    final active = c.jobs.where((j) => j.enabled).length;
    return PanelHeader(
      icon: Icons.schedule,
      title: 'Cron',
      meta: '${c.jobs.length} job · $active aktif',
      actions: [
        GhostIconButton(
          icon: Icons.refresh_rounded,
          tooltip: 'Perbarui',
          busy: c.refreshing,
          onTap: c.refresh,
        ),
        const SizedBox(width: 6),
        _AddButton(onTap: () => _showEditor(context, c)),
      ],
    );
  }

  Widget _list(BuildContext context, CronController c) {
    if (c.jobs.isEmpty) {
      return PanelMessage(
        icon: Icons.schedule_outlined,
        message: 'Belum ada cron job.',
        actionLabel: 'Tambah Job',
        onAction: () => _showEditor(context, c),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: c.jobs.length,
      itemBuilder: (_, i) => _JobCard(controller: c, job: c.jobs[i]),
    );
  }

  void _showEditor(BuildContext context, CronController c, {CronJob? job}) {
    showDialog(
      context: context,
      builder: (_) => _CronEditor(controller: c, existing: job),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.rSm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: AppTheme.accent,
          borderRadius: BorderRadius.circular(AppTheme.rSm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 15, color: AppTheme.onAccent),
            const SizedBox(width: 5),
            Text('Tambah',
                style: TextStyle(
                    color: AppTheme.onAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _JobCard extends StatelessWidget {
  const _JobCard({required this.controller, required this.job});

  final CronController controller;
  final CronJob job;

  Future<void> _act(BuildContext context, Future<String?> future, String ok) async {
    final err = await future;
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: err == null ? AppTheme.success : AppTheme.danger,
      duration: const Duration(seconds: 2),
      content: Text(err ?? ok, style: const TextStyle(color: Colors.white)),
    ));
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text('Hapus cron job?',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
        content: Text(job.command,
            style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Batal',
                style: TextStyle(color: AppTheme.textMuted)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await _act(context, controller.deleteJob(job), 'Job dihapus');
    }
  }

  @override
  Widget build(BuildContext context) {
    final on = job.enabled;
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Tag(job.schedule, mono: true),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(describeCron(job.schedule),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: AppTheme.textMuted, fontSize: 11)),
                    ),
                    if (!on) ...[
                      const SizedBox(width: 8),
                      Pill('nonaktif', color: AppTheme.textMuted),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                SelectableText(
                  job.command,
                  style: TextStyle(
                    color: on ? AppTheme.textPrimary : AppTheme.textMuted,
                    fontSize: 12.5,
                    fontFamily: 'Menlo',
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    ToolButton(
                      icon: on ? Icons.toggle_on : Icons.toggle_off,
                      label: on ? 'Nonaktifkan' : 'Aktifkan',
                      color: on ? AppTheme.success : AppTheme.textMuted,
                      onTap: () => _act(context, controller.toggleJob(job),
                          on ? 'Job dinonaktifkan' : 'Job diaktifkan'),
                    ),
                    ToolButton(
                      icon: Icons.edit_outlined,
                      label: 'Edit',
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (_) =>
                              _CronEditor(controller: controller, existing: job),
                        );
                      },
                    ),
                    const Spacer(),
                    ToolButton(
                      icon: Icons.delete_outline_rounded,
                      label: 'Hapus',
                      color: AppTheme.danger,
                      onTap: () => _confirmDelete(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Dialog tambah/edit cron job.
class _CronEditor extends StatefulWidget {
  const _CronEditor({required this.controller, this.existing});
  final CronController controller;
  final CronJob? existing;

  @override
  State<_CronEditor> createState() => _CronEditorState();
}

class _CronEditorState extends State<_CronEditor> {
  late final TextEditingController _schedule;
  late final TextEditingController _command;
  String? _error;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  static const _presets = {
    'Tiap menit': '* * * * *',
    'Tiap 5 menit': '*/5 * * * *',
    'Tiap jam': '0 * * * *',
    'Tiap hari 00:00': '0 0 * * *',
    'Saat boot': '@reboot',
  };

  @override
  void initState() {
    super.initState();
    _schedule = TextEditingController(text: widget.existing?.schedule ?? '');
    _command = TextEditingController(text: widget.existing?.command ?? '');
  }

  @override
  void dispose() {
    _schedule.dispose();
    _command.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final sched = _schedule.text.trim();
    final cmd = _command.text.trim();
    if (cmd.isEmpty) {
      setState(() => _error = 'Perintah wajib diisi.');
      return;
    }
    if (splitCronLine('$sched $cmd') == null) {
      setState(() => _error =
          'Jadwal tidak valid. Gunakan 5 kolom (mis. "*/5 * * * *") atau @reboot.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final err = _isEdit
        ? await widget.controller.updateJob(widget.existing!, sched, cmd)
        : await widget.controller.addJob(sched, cmd);
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _saving = false;
        _error = err;
      });
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.schedule, size: 20, color: AppTheme.accent),
                  const SizedBox(width: 8),
                  Text(_isEdit ? 'Edit Cron Job' : 'Cron Job Baru',
                      style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 18),
              const SectionLabel('Jadwal'),
              const SizedBox(height: 6),
              _field(_schedule, 'mis. */5 * * * *  atau  @reboot',
                  mono: true),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _presets.entries
                    .map((e) => InkWell(
                          onTap: () => _schedule.text = e.value,
                          borderRadius: BorderRadius.circular(AppTheme.rSm),
                          child: Tag(e.key),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 14),
              const SectionLabel('Perintah'),
              const SizedBox(height: 6),
              _field(_command, 'mis. /usr/bin/backup.sh', mono: true),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.danger.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppTheme.rSm),
                    border:
                        Border.all(color: AppTheme.danger.withValues(alpha: 0.4)),
                  ),
                  child: Text(_error!,
                      style: TextStyle(color: AppTheme.danger, fontSize: 12)),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(),
                    child: Text('Batal',
                        style: TextStyle(color: AppTheme.textMuted)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    style:
                        FilledButton.styleFrom(backgroundColor: AppTheme.accent),
                    child: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : Text(_isEdit ? 'Simpan' : 'Tambah'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String hint, {bool mono = false}) {
    return TextField(
      controller: ctrl,
      style: TextStyle(
        color: AppTheme.textPrimary,
        fontSize: 14,
        fontFamily: mono ? 'Menlo' : null,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: AppTheme.textMuted, fontSize: 13),
        isDense: true,
        filled: true,
        fillColor: AppTheme.surfaceInput,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.rSm),
          borderSide: BorderSide(color: AppTheme.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.rSm),
          borderSide: BorderSide(color: AppTheme.accent),
        ),
      ),
    );
  }
}
