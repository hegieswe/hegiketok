import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../theme/app_theme.dart';
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
                      color: selected ? AppTheme.onAccent : AppTheme.textMuted,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600)),
            ],
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
