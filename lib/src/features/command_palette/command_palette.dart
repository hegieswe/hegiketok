import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/host_providers.dart';
import '../../models/ssh_host.dart';
import '../../theme/app_theme.dart';
import '../hosts/host_sidebar.dart' show hostOsIcon;

/// Satu aksi statis di command palette (mis. "Terminal Lokal").
class PaletteCommand {
  const PaletteCommand(
      {required this.icon, required this.label, required this.run});
  final IconData icon;
  final String label;
  final VoidCallback run;
}

/// Tampilkan command palette (⌘K): cari host untuk connect + aksi cepat.
Future<void> showCommandPalette(
  BuildContext context, {
  required void Function(SshHost host) onConnectHost,
  required List<PaletteCommand> commands,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (_) =>
        _CommandPalette(onConnectHost: onConnectHost, commands: commands),
  );
}

class _CommandPalette extends ConsumerStatefulWidget {
  const _CommandPalette({required this.onConnectHost, required this.commands});

  final void Function(SshHost host) onConnectHost;
  final List<PaletteCommand> commands;

  @override
  ConsumerState<_CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends ConsumerState<_CommandPalette> {
  final _ctrl = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hosts = ref.watch(hostsProvider).asData?.value ?? const <SshHost>[];
    final q = _q.trim().toLowerCase();

    final hostMatches = hosts.where((h) {
      if (q.isEmpty) return true;
      return '${h.label} ${h.host} ${h.username} ${h.tags.join(' ')}'
          .toLowerCase()
          .contains(q);
    }).toList();
    final cmdMatches = widget.commands
        .where((c) => q.isEmpty || c.label.toLowerCase().contains(q))
        .toList();

    void runFirst() {
      if (hostMatches.isNotEmpty) {
        Navigator.of(context).pop();
        widget.onConnectHost(hostMatches.first);
      } else if (cmdMatches.isNotEmpty) {
        Navigator.of(context).pop();
        cmdMatches.first.run();
      }
    }

    return Align(
      alignment: const Alignment(0, -0.45),
      child: Material(
        color: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 460),
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.surfaceHigh,
              borderRadius: BorderRadius.circular(AppTheme.rLg),
              border: Border.all(color: AppTheme.border),
              boxShadow: AppTheme.softShadow(AppTheme.current),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                  child: Row(
                    children: [
                      Icon(Icons.search_rounded,
                          size: 18, color: AppTheme.textMuted),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _ctrl,
                          autofocus: true,
                          style: TextStyle(
                              color: AppTheme.textPrimary, fontSize: 15),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            hintText: 'Cari host atau perintah…',
                            hintStyle: TextStyle(
                                color: AppTheme.textFaint, fontSize: 15),
                          ),
                          onChanged: (v) => setState(() => _q = v),
                          onSubmitted: (_) => runFirst(),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceInput,
                          borderRadius: BorderRadius.circular(AppTheme.rSm),
                        ),
                        child: Text('⌘K',
                            style: TextStyle(
                                color: AppTheme.textFaint, fontSize: 11)),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: AppTheme.border),
                Flexible(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    shrinkWrap: true,
                    children: [
                      if (hostMatches.isNotEmpty)
                        _sectionLabel('HOSTS'),
                      for (final h in hostMatches)
                        _row(
                          icon: hostOsIcon(h),
                          title: h.label,
                          subtitle: h.subtitle,
                          onTap: () {
                            Navigator.of(context).pop();
                            widget.onConnectHost(h);
                          },
                        ),
                      if (cmdMatches.isNotEmpty) _sectionLabel('AKSI'),
                      for (final c in cmdMatches)
                        _row(
                          icon: c.icon,
                          title: c.label,
                          onTap: () {
                            Navigator.of(context).pop();
                            c.run();
                          },
                        ),
                      if (hostMatches.isEmpty && cmdMatches.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Center(
                            child: Text('Tak ada hasil.',
                                style: TextStyle(
                                    color: AppTheme.textMuted, fontSize: 13)),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Text(t,
            style: TextStyle(
                color: AppTheme.textFaint,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6)),
      );

  Widget _row({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            children: [
              Icon(icon, size: 17, color: AppTheme.textMuted),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: AppTheme.textPrimary, fontSize: 13.5)),
                    if (subtitle != null)
                      Text(subtitle,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: AppTheme.textMuted, fontSize: 11.5)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
