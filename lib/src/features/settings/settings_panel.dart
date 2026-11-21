import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../theme/app_theme.dart';
import 'settings_providers.dart';
import 'terminal_themes.dart';

/// Panel pengaturan tampilan (muncul sebagai drawer kanan): pemilih tema
/// terminal dengan pratinjau langsung + ukuran font.
class SettingsPanel extends ConsumerWidget {
  const SettingsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Drawer(
      width: 340,
      backgroundColor: AppTheme.surface,
      shape: const Border(left: BorderSide(color: AppTheme.border)),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 10),
              child: Row(
                children: [
                  const Icon(Icons.palette_outlined,
                      size: 18, color: AppTheme.accent),
                  const SizedBox(width: 8),
                  const Text(
                    'Tampilan',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close,
                        size: 18, color: AppTheme.textMuted),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppTheme.border),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
                children: [
                  _sectionLabel('UKURAN FONT'),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.text_fields,
                          size: 16, color: AppTheme.textMuted),
                      Expanded(
                        child: Slider(
                          value: settings.fontSize,
                          min: 10,
                          max: 22,
                          divisions: 12,
                          activeColor: AppTheme.accent,
                          label: settings.fontSize.toStringAsFixed(0),
                          onChanged: notifier.setFontSize,
                        ),
                      ),
                      SizedBox(
                        width: 34,
                        child: Text(
                          '${settings.fontSize.toStringAsFixed(0)} pt',
                          style: const TextStyle(
                              color: AppTheme.textPrimary, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _sectionLabel('TEMA TERMINAL'),
                  const SizedBox(height: 8),
                  for (final preset in kTerminalThemes)
                    _ThemeCard(
                      preset: preset,
                      fontSize: settings.fontSize,
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
        style: const TextStyle(
          color: AppTheme.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.7,
        ),
      );
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.preset,
    required this.selected,
    required this.onTap,
    required this.fontSize,
  });

  final TerminalThemePreset preset;
  final bool selected;
  final VoidCallback onTap;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppTheme.accent : AppTheme.border,
              width: selected ? 2 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Pratinjau: latar tema + baris prompt palsu + swatch warna.
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
              // Baris nama + indikator terpilih.
              Container(
                color: selected
                    ? AppTheme.accent.withValues(alpha: 0.12)
                    : AppTheme.bg,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Text(
                      preset.name,
                      style: TextStyle(
                        color: selected
                            ? AppTheme.accent
                            : AppTheme.textPrimary,
                        fontSize: 13,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    if (selected)
                      const Icon(Icons.check_circle,
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
