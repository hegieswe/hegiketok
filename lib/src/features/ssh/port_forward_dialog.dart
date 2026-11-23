import 'package:material_ui/material_ui.dart';

import '../../ssh/port_forward.dart';
import '../../theme/app_theme.dart';

/// Dialog kelola port-forward lokal (setara `ssh -L`): lihat forward aktif,
/// tambah baru (local → remoteHost:remotePort), dan hentikan.
Future<void> showPortForwardDialog(
    BuildContext context, PortForwardManager? manager) {
  return showDialog<void>(
    context: context,
    builder: (_) => _PortForwardDialog(manager: manager),
  );
}

class _PortForwardDialog extends StatefulWidget {
  const _PortForwardDialog({required this.manager});

  final PortForwardManager? manager;

  @override
  State<_PortForwardDialog> createState() => _PortForwardDialogState();
}

class _PortForwardDialogState extends State<_PortForwardDialog> {
  final _localPort = TextEditingController();
  final _remoteHost = TextEditingController(text: 'localhost');
  final _remotePort = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _localPort.dispose();
    _remoteHost.dispose();
    _remotePort.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final mgr = widget.manager;
    if (mgr == null) return;
    final rp = int.tryParse(_remotePort.text.trim());
    if (rp == null || rp < 1 || rp > 65535) {
      setState(() => _error = 'Port remote tidak valid (1–65535).');
      return;
    }
    final lpText = _localPort.text.trim();
    final lp = lpText.isEmpty ? 0 : int.tryParse(lpText);
    if (lp == null || lp < 0 || lp > 65535) {
      setState(() => _error = 'Port lokal tidak valid.');
      return;
    }
    final host = _remoteHost.text.trim().isEmpty
        ? 'localhost'
        : _remoteHost.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await mgr.start(rp, remoteHost: host, localPort: lp);
      _remotePort.clear();
      _localPort.clear();
    } catch (e) {
      setState(() => _error = 'Gagal membuka forward: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mgr = widget.manager;
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
                  Icon(Icons.swap_horiz_rounded,
                      size: 20, color: AppTheme.accent),
                  const SizedBox(width: 8),
                  Text('Port Forwarding',
                      style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w700)),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.close_rounded,
                        size: 18, color: AppTheme.textMuted),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Teruskan port lokal ke server (seperti ssh -L). Berguna untuk '
                'DB, dashboard, atau dev-server di balik SSH.',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 16),
              if (mgr == null)
                _InfoBox(
                  icon: Icons.link_off_rounded,
                  text: 'Belum tersambung. Sambungkan sesi SSH dulu.',
                )
              else ...[
                ListenableBuilder(
                  listenable: mgr,
                  builder: (context, _) {
                    final list = mgr.forwards;
                    if (list.isEmpty) {
                      return _InfoBox(
                        icon: Icons.inbox_outlined,
                        text: 'Belum ada forward aktif.',
                      );
                    }
                    return Column(
                      children: [
                        for (final f in list)
                          _ForwardTile(
                            forward: f,
                            onStop: () => mgr.stop(f),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                Divider(height: 1, color: AppTheme.border),
                const SizedBox(height: 16),
                Text('Tambah forward',
                    style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: _MiniField(
                        label: 'Port lokal',
                        controller: _localPort,
                        hint: 'auto',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: _MiniField(
                        label: 'Remote host',
                        controller: _remoteHost,
                        hint: 'localhost',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MiniField(
                        label: 'Port remote',
                        controller: _remotePort,
                        hint: '5432',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 1),
                      child: FilledButton(
                        onPressed: _busy ? null : _add,
                        style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.accent,
                            foregroundColor: AppTheme.onAccent),
                        child: _busy
                            ? SizedBox(
                                width: 15,
                                height: 15,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppTheme.onAccent))
                            : const Text('Forward'),
                      ),
                    ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!,
                      style: TextStyle(color: AppTheme.danger, fontSize: 12)),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ForwardTile extends StatelessWidget {
  const _ForwardTile({required this.forward, required this.onStop});

  final ActiveForward forward;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      decoration: BoxDecoration(
        color: AppTheme.success.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTheme.rSm),
        border: Border.all(color: AppTheme.success.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.swap_horiz_rounded, size: 15, color: AppTheme.success),
          const SizedBox(width: 8),
          Expanded(
            child: Text(forward.label,
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 12.5)),
          ),
          if (forward.connections > 0)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text('${forward.connections} konek',
                  style:
                      TextStyle(color: AppTheme.textMuted, fontSize: 11)),
            ),
          IconButton(
            icon: Icon(Icons.stop_circle_outlined,
                size: 17, color: AppTheme.textMuted),
            tooltip: 'Hentikan',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            padding: EdgeInsets.zero,
            onPressed: onStop,
          ),
        ],
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  const _InfoBox({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceInput,
        borderRadius: BorderRadius.circular(AppTheme.rSm),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.textFaint),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(color: AppTheme.textMuted, fontSize: 12.5)),
          ),
        ],
      ),
    );
  }
}

class _MiniField extends StatelessWidget {
  const _MiniField(
      {required this.label, required this.controller, this.hint});

  final String label;
  final TextEditingController controller;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
        const SizedBox(height: 5),
        TextField(
          controller: controller,
          style: TextStyle(color: AppTheme.textPrimary, fontSize: 13),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: AppTheme.surfaceInput,
            hintText: hint,
            hintStyle: TextStyle(color: AppTheme.textFaint, fontSize: 12.5),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
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
