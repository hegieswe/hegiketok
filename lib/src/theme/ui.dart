import 'package:material_ui/material_ui.dart';

import 'app_theme.dart';

/// ── Kit UI bersama ──────────────────────────────────────────────────────
/// Komponen reusable yang mengemas bahasa desain (Linear/Raycast, indigo).
/// Panel cukup menyusun komponen ini agar tampilan seragam di seluruh app
/// dan otomatis benar di mode gelap & terang.

/// Kartu permukaan standar: sudut membulat, border halus, bayangan lembut.
class AppCard extends StatefulWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.onTap,
    this.danger = false,
    this.margin = const EdgeInsets.only(bottom: 10),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final bool danger;
  final EdgeInsetsGeometry margin;

  @override
  State<AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<AppCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.current;
    final card = AnimatedContainer(
      duration: AppTheme.fast,
      margin: widget.margin,
      padding: widget.padding,
      decoration: BoxDecoration(
        color: _hover && widget.onTap != null
            ? AppTheme.surfaceInput
            : AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.rLg),
        border: Border.all(
          color: widget.danger
              ? AppTheme.danger.withValues(alpha: 0.5)
              : AppTheme.border,
        ),
        boxShadow: p.isDark ? null : AppTheme.softShadow(p),
      ),
      child: widget.child,
    );
    if (widget.onTap == null) return card;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(onTap: widget.onTap, child: card),
    );
  }
}

/// Header panel: chip ikon aksen + judul + meta + aksi di kanan.
class PanelHeader extends StatelessWidget {
  const PanelHeader({
    super.key,
    required this.icon,
    required this.title,
    this.meta,
    this.actions = const [],
  });

  final IconData icon;
  final String title;
  final String? meta;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppTheme.accentSoft,
              borderRadius: BorderRadius.circular(AppTheme.rSm),
            ),
            child: Icon(icon, size: 17, color: AppTheme.accent),
          ),
          const SizedBox(width: 12),
          Text(title,
              style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700)),
          if (meta != null) ...[
            const SizedBox(width: 10),
            Flexible(
              child: Text(meta!,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
            ),
          ],
          const Spacer(),
          ...actions,
        ],
      ),
    );
  }
}

/// Label seksi kecil huruf kapital redup.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: TextStyle(
          color: AppTheme.textFaint,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.9,
        ),
      );
}

/// Titik status berwarna.
class StatusDot extends StatelessWidget {
  const StatusDot(this.color, {super.key, this.size = 9});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 5),
          ],
        ),
      );
}

/// Chip kecil berlatar tint warna (status/label).
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, required this.color, this.icon});
  final String text;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(icon == null ? 8 : 6, 3, 8, 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppTheme.rPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 4),
          ],
          Text(text,
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Chip netral berbingkai (mis. stat kecil).
class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.icon, this.mono = false});
  final String text;
  final IconData? icon;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surfaceInput,
        borderRadius: BorderRadius.circular(AppTheme.rSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: AppTheme.textFaint),
            const SizedBox(width: 5),
          ],
          Text(text,
              style: TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 11,
                  fontFamily: mono ? 'Menlo' : null)),
        ],
      ),
    );
  }
}

/// Tombol aksi kecil berbingkai dengan hover (dipakai di kartu).
class ToolButton extends StatefulWidget {
  const ToolButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  State<ToolButton> createState() => _ToolButtonState();
}

class _ToolButtonState extends State<ToolButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? AppTheme.textMuted;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: AppTheme.fast,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _hover ? color.withValues(alpha: 0.12) : Colors.transparent,
              borderRadius: BorderRadius.circular(AppTheme.rSm),
              border: Border.all(
                  color: _hover ? color.withValues(alpha: 0.5) : AppTheme.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, size: 14, color: color),
                const SizedBox(width: 5),
                Text(widget.label,
                    style: TextStyle(color: color, fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tombol ikon polos.
class GhostIconButton extends StatelessWidget {
  const GhostIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.color,
    this.size = 18,
    this.busy = false,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final Color? color;
  final double size;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      onPressed: busy ? null : onTap,
      icon: busy
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppTheme.accent))
          : Icon(icon, size: size, color: color ?? AppTheme.textMuted),
    );
  }
}

/// Satu segmen filter (mis. Semua / Berjalan / Gagal).
class FilterTab extends StatelessWidget {
  const FilterTab({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
    this.color,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.accent;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppTheme.fast,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? c.withValues(alpha: 0.14) : Colors.transparent,
          borderRadius: BorderRadius.circular(AppTheme.rSm),
          border: Border.all(color: active ? c : AppTheme.border),
        ),
        child: Text(label,
            style: TextStyle(
                color: active ? c : AppTheme.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      ),
    );
  }
}

/// Kolom pencarian seragam.
class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    required this.hint,
    required this.onChanged,
    this.controller,
  });

  final String hint;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: TextStyle(color: AppTheme.textPrimary, fontSize: 13),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: AppTheme.surfaceInput,
          hintText: hint,
          hintStyle: TextStyle(color: AppTheme.textFaint, fontSize: 13),
          prefixIcon: Icon(Icons.search_rounded, size: 17, color: AppTheme.textFaint),
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
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
    );
  }
}

/// State tengah layar: loading ringan / error / kosong + tombol aksi opsional.
class PanelMessage extends StatelessWidget {
  const PanelMessage({
    super.key,
    required this.icon,
    required this.message,
    this.iconColor,
    this.actionLabel,
    this.onAction,
    this.title,
  });

  final IconData icon;
  final String message;
  final Color? iconColor;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.bg,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: (iconColor ?? AppTheme.textFaint).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppTheme.rLg),
            ),
            child: Icon(icon, size: 26, color: iconColor ?? AppTheme.textFaint),
          ),
          const SizedBox(height: 14),
          if (title != null) ...[
            Text(title!,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
          ],
          SizedBox(
            width: 360,
            child: Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
          ),
          if (onAction != null) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onAction,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.textPrimary,
                side: BorderSide(color: AppTheme.border),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 15),
              label: Text(actionLabel ?? 'Coba lagi'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Kontrol auto-refresh + pemilih interval (dipakai Docker/Services/Info).
class RefreshControls extends StatelessWidget {
  const RefreshControls({
    super.key,
    required this.auto,
    required this.interval,
    required this.onToggleAuto,
    required this.onInterval,
    required this.onRefresh,
    required this.busy,
    this.options = const [2, 5, 10, 30, 60],
  });

  final bool auto;
  final int interval;
  final VoidCallback onToggleAuto;
  final ValueChanged<int> onInterval;
  final VoidCallback onRefresh;
  final bool busy;
  final List<int> options;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (auto)
          PopupMenuButton<int>(
            initialValue: interval,
            tooltip: 'Interval refresh',
            onSelected: onInterval,
            position: PopupMenuPosition.under,
            itemBuilder: (_) => options
                .map((s) => PopupMenuItem(
                      value: s,
                      height: 38,
                      child: Text('$s detik',
                          style: TextStyle(
                              color: AppTheme.textPrimary, fontSize: 13)),
                    ))
                .toList(),
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppTheme.rSm),
                border: Border.all(color: AppTheme.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.timer_outlined, size: 13, color: AppTheme.textMuted),
                  const SizedBox(width: 5),
                  Text('${interval}s',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                  Icon(Icons.arrow_drop_down, size: 16, color: AppTheme.textMuted),
                ],
              ),
            ),
          ),
        _AutoChip(active: auto, onTap: onToggleAuto),
        const SizedBox(width: 8),
        GhostIconButton(
          icon: Icons.refresh_rounded,
          tooltip: 'Perbarui',
          busy: busy,
          onTap: onRefresh,
        ),
      ],
    );
  }
}

class _AutoChip extends StatelessWidget {
  const _AutoChip({required this.active, required this.onTap});
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.success;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? c.withValues(alpha: 0.14) : Colors.transparent,
          borderRadius: BorderRadius.circular(AppTheme.rSm),
          border: Border.all(color: active ? c : AppTheme.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(active ? Icons.sync_rounded : Icons.sync_disabled_rounded,
                size: 13, color: active ? c : AppTheme.textMuted),
            const SizedBox(width: 5),
            Text('Auto',
                style: TextStyle(
                    color: active ? c : AppTheme.textMuted, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
