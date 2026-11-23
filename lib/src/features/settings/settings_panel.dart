import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../theme/app_theme.dart';
import '../ssh/known_hosts_dialog.dart';
import '../updates/update_checker.dart';
import '../updates/update_ui.dart';
import 'backup_actions.dart';
import 'host_backups_dialog.dart';
import 'settings_providers.dart';
import 'terminal_themes.dart';

/// Panel pengaturan tampilan (drawer kanan): mode tema aplikasi, ukuran font,
/// dan pemilih tema terminal dengan pratinjau langsung.
class SettingsPanel extends ConsumerWidget {
  const SettingsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Drawer(
      width: 348,
      backgroundColor: AppTheme.surface,
      shape: Border(left: BorderSide(color: AppTheme.border)),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
              child: Row(
                children: [
                  Text(
                    'Tampilan',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.close_rounded,
                        size: 18, color: AppTheme.textMuted),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: AppTheme.border),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                children: [
                  _sectionLabel('MODE TEMA'),
                  const SizedBox(height: 10),
                  _ModeToggle(
                    mode: settings.themeMode,
                    onChanged: notifier.setThemeMode,
                  ),
                  const SizedBox(height: 24),
                  _sectionLabel('UKURAN FONT'),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.text_fields_rounded,
                          size: 16, color: AppTheme.textMuted),
                      Expanded(
                        child: Slider(
                          value: settings.fontSize,
                          min: 10,
                          max: 22,
                          divisions: 12,
                          label: settings.fontSize.toStringAsFixed(0),
                          onChanged: notifier.setFontSize,
                        ),
                      ),
                      SizedBox(
                        width: 38,
                        child: Text(
                          '${settings.fontSize.toStringAsFixed(0)} pt',
                          style: TextStyle(
                              color: AppTheme.textPrimary, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  _sectionLabel('TEMA TERMINAL'),
                  const SizedBox(height: 10),
                  for (final preset in kTerminalThemes)
                    _ThemeCard(
                      preset: preset,
                      selected: preset.name == settings.themeName,
                      onTap: () => notifier.setTheme(preset.name),
                    ),
                  const SizedBox(height: 22),
                  _sectionLabel('KEAMANAN'),
                  const SizedBox(height: 10),
                  _SettingsTile(
                    icon: Icons.verified_user_outlined,
                    title: 'Known Hosts',
                    subtitle: 'Kelola host key tepercaya (TOFU)',
                    onTap: () => showKnownHostsDialog(context),
                  ),
                  const SizedBox(height: 22),
                  _sectionLabel('DATA'),
                  const SizedBox(height: 10),
                  _SettingsTile(
                    icon: Icons.lock_outline_rounded,
                    title: 'Backup terenkripsi',
                    subtitle: 'Ekspor host, snippet & known-host (AES-256)',
                    onTap: () => exportVault(context, ref),
                  ),
                  const SizedBox(height: 8),
                  _SettingsTile(
                    icon: Icons.restore_rounded,
                    title: 'Restore dari backup',
                    subtitle: 'Impor berkas .hvault',
                    onTap: () => importVault(context, ref),
                  ),
                  const SizedBox(height: 8),
                  _SettingsTile(
                    icon: Icons.history_rounded,
                    title: 'Riwayat daftar host',
                    subtitle: 'Cadangan otomatis — pulihkan versi sebelumnya',
                    onTap: () => showHostBackupsDialog(context),
                  ),
                  const SizedBox(height: 22),
                  _sectionLabel('APLIKASI'),
                  const SizedBox(height: 10),
                  _SettingsTile(
                    icon: Icons.system_update_alt_rounded,
                    title: 'Periksa pembaruan',
                    subtitle: 'HegiKetok v$kAppVersion',
                    onTap: () => checkForUpdateInteractive(context),
                  ),
                  const SizedBox(height: 8),
                  _SwitchTile(
                    icon: Icons.autorenew_rounded,
                    title: 'Periksa otomatis',
                    subtitle: 'Sekali sehari saat app dibuka (GitHub Releases)',
                    value: settings.autoCheckUpdates,
                    onChanged: notifier.setAutoCheckUpdates,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: TextStyle(
          color: AppTheme.textFaint,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.9,
        ),
      );
}

/// Baris pengaturan yang bisa ditekan (membuka dialog/aksi).
/// Baris pengaturan dengan sakelar (hidup/mati).
class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 7, 6, 7),
          decoration: BoxDecoration(
            color: AppTheme.surfaceInput,
            borderRadius: BorderRadius.circular(AppTheme.rMd),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            children: [
              Icon(icon, size: 17, color: AppTheme.textMuted),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 1),
                    Text(subtitle,
                        style: TextStyle(
                            color: AppTheme.textMuted, fontSize: 11.5)),
                  ],
                ),
              ),
              Transform.scale(
                scale: 0.78,
                child: Switch(
                  value: value,
                  onChanged: onChanged,
                  activeThumbColor: AppTheme.onAccent,
                  activeTrackColor: AppTheme.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: AppTheme.surfaceInput,
            borderRadius: BorderRadius.circular(AppTheme.rMd),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            children: [
              Icon(icon, size: 17, color: AppTheme.textMuted),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 1),
                    Text(subtitle,
                        style: TextStyle(
                            color: AppTheme.textMuted, fontSize: 11.5)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  size: 18, color: AppTheme.textFaint),
            ],
          ),
        ),
      ),
    );
  }
}

/// Segmented control untuk memilih mode tema aplikasi.
class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.mode, required this.onChanged});

  final ThemeMode mode;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppTheme.surfaceInput,
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          _seg(ThemeMode.system, Icons.brightness_auto_outlined, 'Sistem'),
          _seg(ThemeMode.light, Icons.light_mode_outlined, 'Terang'),
          _seg(ThemeMode.dark, Icons.dark_mode_outlined, 'Gelap'),
        ],
      ),
    );
  }

  Widget _seg(ThemeMode m, IconData icon, String label) {
    final selected = mode == m;
    return Expanded(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => onChanged(m),
          child: AnimatedContainer(
            duration: AppTheme.fast,
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: selected ? AppTheme.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(AppTheme.rSm),
            ),
            child: Column(
              children: [
                Icon(icon,
                    size: 16,
                    color: selected ? AppTheme.onAccent : AppTheme.textMuted),
                const SizedBox(height: 4),
                Text(label,
                    style: TextStyle(
                        color:
                            selected ? AppTheme.onAccent : AppTheme.textMuted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final TerminalThemePreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.rMd),
            border: Border.all(
              color: selected ? AppTheme.accent : AppTheme.border,
              width: selected ? 2 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 58,
                color: preset.background,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    RichText(
                      text: TextSpan(
                        style: const TextStyle(
                            fontFamily: 'Menlo', fontSize: 11.5),
                        children: [
                          TextSpan(
                              text: 'hegi',
                              style: TextStyle(color: preset.theme.green)),
                          TextSpan(
                              text: '@ketok ',
                              style: TextStyle(color: preset.foreground)),
                          TextSpan(
                              text: '~ ',
                              style: TextStyle(color: preset.theme.blue)),
                          TextSpan(
                              text: r'$ ls',
                              style: TextStyle(color: preset.foreground)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        for (final c in preset.swatches)
                          Container(
                            width: 16,
                            height: 7,
                            margin: const EdgeInsets.only(right: 4),
                            decoration: BoxDecoration(
                              color: c,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                color: selected ? AppTheme.accentSoft : AppTheme.bg,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Text(
                      preset.name,
                      style: TextStyle(
                        color:
                            selected ? AppTheme.accent : AppTheme.textPrimary,
                        fontSize: 13,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    if (selected)
                      Icon(Icons.check_circle,
                          size: 16, color: AppTheme.accent),
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
