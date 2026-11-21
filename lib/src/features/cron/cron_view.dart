import 'package:material_ui/material_ui.dart';

import '../../ssh/handshake_stepper.dart';
import '../../theme/app_theme.dart';
import 'cron_controller.dart';
import 'cron_models.dart';
import 'cron_service.dart';

const _red = Color(0xFFFF7B72);
const _green = Color(0xFF3FB950);
const _amber = Color(0xFFD29922);

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
          return _errorState(c.connectError!, c.connect);
        }
        if (c.loading && c.snapshot == null) {
          return const _Centered(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppTheme.accent),
            ),
          );
        }
        final snap = c.snapshot!;
        if (snap.error != null) {
          return _errorState(snap.error!, c.refresh, icon: Icons.schedule);
        }
        return Container(
          color: AppTheme.bg,
          child: Column(
            children: [
              _header(context, c),
              const Divider(height: 1, color: AppTheme.border),
              Expanded(child: _list(context, c)),
            ],
          ),
        );
      },
    );
  }

  Widget _header(BuildContext context, CronController c) {
    final active = c.jobs.where((j) => j.enabled).length;
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: AppTheme.surface,
      child: Row(
        children: [
          const Icon(Icons.schedule, size: 20, color: AppTheme.accent),
          const SizedBox(width: 10),
          const Text('Cron',
              style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          const SizedBox(width: 10),
          Text('${c.jobs.length} job · $active aktif',
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
          const Spacer(),
          IconButton(
            onPressed: c.refreshing ? null : c.refresh,
            tooltip: 'Perbarui',
            icon: c.refreshing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppTheme.accent))
                : const Icon(Icons.refresh, size: 18, color: AppTheme.textMuted),
          ),
          const SizedBox(width: 6),
          _AddButton(onTap: () => _showEditor(context, c)),
        ],
      ),
    );
  }

  Widget _list(BuildContext context, CronController c) {
    if (c.jobs.isEmpty) {
      return _Centered(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.schedule_outlined, size: 34, color: AppTheme.border),
            const SizedBox(height: 10),
            const Text('Belum ada cron job.',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () => _showEditor(context, c),
              icon: const Icon(Icons.add, size: 15),
              label: const Text('Tambah Job'),
            ),
          ],
        ),
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

  Widget _errorState(String msg, VoidCallback onRetry,
      {IconData icon = Icons.error_outline}) {
    return _Centered(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: _amber, size: 38),
          const SizedBox(height: 12),
          SizedBox(
            width: 360,
            child: Text(msg,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 15),
            label: const Text('Coba lagi'),
          ),
        ],
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      Container(color: AppTheme.bg, child: Center(child: child));
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: AppTheme.accent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.accent),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 15, color: AppTheme.accent),
            SizedBox(width: 5),
            Text('Tambah',
                style: TextStyle(
                    color: AppTheme.accent,
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
      backgroundColor: err == null ? _green : _red,
      duration: const Duration(seconds: 2),
      content: Text(err ?? ok, style: const TextStyle(color: Colors.white)),
    ));
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Hapus cron job?',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
        content: Text(job.command,
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal',
                style: TextStyle(color: AppTheme.textMuted)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: _red),
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
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.bg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(job.schedule,
                          style: TextStyle(
                              color: on ? AppTheme.accent : AppTheme.textMuted,
                              fontSize: 12,
                              fontFamily: 'Menlo',
                              fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(describeCron(job.schedule),
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: AppTheme.textMuted, fontSize: 11)),
                    ),
                    if (!on) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.textMuted.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('nonaktif',
                            style: TextStyle(
                                color: AppTheme.textMuted, fontSize: 10)),
                      ),
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
              ],
            ),
          ),
          const SizedBox(width: 8),
          _iconBtn(
            on ? Icons.toggle_on : Icons.toggle_off,
            on ? 'Nonaktifkan' : 'Aktifkan',
            on ? _green : AppTheme.textMuted,
            () => _act(context, controller.toggleJob(job),
                on ? 'Job dinonaktifkan' : 'Job diaktifkan'),
          ),
          _iconBtn(Icons.edit_outlined, 'Edit', AppTheme.textMuted, () {
            showDialog(
              context: context,
              builder: (_) => _CronEditor(controller: controller, existing: job),
            );
          }),
          _iconBtn(Icons.delete_outline, 'Hapus', _red,
              () => _confirmDelete(context)),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon, String tip, Color color, VoidCallback onTap) {
    return IconButton(
      icon: Icon(icon, size: 18, color: color),
      tooltip: tip,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      padding: EdgeInsets.zero,
      onPressed: onTap,
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
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppTheme.border),
      ),
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
                  const Icon(Icons.schedule, size: 20, color: AppTheme.accent),
                  const SizedBox(width: 8),
                  Text(_isEdit ? 'Edit Cron Job' : 'Cron Job Baru',
                      style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 18),
              _label('Jadwal'),
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
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.bg,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppTheme.border),
                            ),
                            child: Text(e.key,
                                style: const TextStyle(
                                    color: AppTheme.textMuted, fontSize: 11)),
                          ),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 14),
              _label('Perintah'),
              const SizedBox(height: 6),
              _field(_command, 'mis. /usr/bin/backup.sh', mono: true),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _red.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _red.withValues(alpha: 0.4)),
                  ),
                  child: Text(_error!,
                      style: const TextStyle(color: _red, fontSize: 12)),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(),
                    child: const Text('Batal',
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

  Widget _label(String t) =>
      Text(t, style: const TextStyle(color: AppTheme.textMuted, fontSize: 12));

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
        hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
        isDense: true,
        filled: true,
        fillColor: AppTheme.bg,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppTheme.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppTheme.accent),
        ),
      ),
    );
  }
}
