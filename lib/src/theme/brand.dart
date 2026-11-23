import 'package:material_ui/material_ui.dart';

import 'app_theme.dart';

/// Identitas HegiKetok — tema "baja & bara" (steel & ember): besi tempa yang
/// dipanaskan. Maknanya pas: *ketok* = menempa logam panas di landasan.

/// Gradien baja gunmetal untuk badge (terang di kiri-atas → nyaris hitam).
const List<Color> kSteelGradient = [
  Color(0xFF3B434D),
  Color(0xFF212730),
  Color(0xFF0C0F14),
];

/// Gradien bara api (molten): emas → jingga → merah. Untuk glyph & "KETOK".
const List<Color> kEmberGradient = [
  Color(0xFFFFC24B),
  Color(0xFFFF6A2C),
  Color(0xFFE11D2A),
];

Color get _emberCore => const Color(0xFFFF7A1F);

/// Logo lengkap: badge + wordmark + (opsional) pill "local-first".
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.markSize = 30, this.showTag = true});

  final double markSize;
  final bool showTag;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BrandMark(size: markSize),
        const SizedBox(width: 11),
        const BrandWordmark(),
        if (showTag) ...[
          const SizedBox(width: 11),
          const _TagPill(),
        ],
      ],
    );
  }
}

/// Badge ikon: pelat baja tempa gelap dengan glyph prompt `>_` yang membara.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 30});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.26),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: kSteelGradient,
        ),
        border: Border.all(
          color: const Color(0xFF4C545F).withValues(alpha: 0.7),
          width: 1,
        ),
        boxShadow: [
          // Bayangan berat (logam padat).
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: size * 0.42,
            offset: Offset(0, size * 0.18),
          ),
          // Sedikit pendar bara.
          BoxShadow(
            color: _emberCore.withValues(alpha: 0.28),
            blurRadius: size * 0.5,
            offset: Offset(0, size * 0.1),
          ),
        ],
      ),
      child: CustomPaint(painter: _MarkPainter()),
    );
  }
}

class _MarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;

    // Kilau baja (brushed metal) tipis di atas.
    final sheen = Paint()
      ..color = Colors.white.withValues(alpha: 0.10)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.12);
    canvas.drawOval(
      Rect.fromLTWH(-s * 0.2, -s * 0.5, s * 1.0, s * 0.85),
      sheen,
    );

    // Bentuk glyph `>_`.
    final chevron = Path()
      ..moveTo(s * 0.30, s * 0.27)
      ..lineTo(s * 0.47, s * 0.50)
      ..lineTo(s * 0.30, s * 0.73);
    final cursor = RRect.fromRectAndRadius(
      Rect.fromLTWH(s * 0.53, s * 0.615, s * 0.19, s * 0.085),
      Radius.circular(s * 0.045),
    );

    final glyphRect = Rect.fromLTWH(s * 0.28, s * 0.25, s * 0.47, s * 0.50);
    final ember = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: kEmberGradient,
    ).createShader(glyphRect);

    // Pendar panas (glow) di belakang glyph.
    final glow = Paint()
      ..shader = ember
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.105
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.07);
    canvas.drawPath(chevron, glow);
    canvas.drawRRect(cursor, Paint()
      ..shader = ember
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.07));

    // Glyph tajam (logam pijar).
    final solid = Paint()
      ..shader = ember
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.095
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(chevron, solid);
    canvas.drawRRect(cursor, Paint()..shader = ember);

    // Percik bara.
    final spark = Paint()..color = const Color(0xFFFFD27A);
    canvas.drawCircle(Offset(s * 0.78, s * 0.30), s * 0.022, spark);
    canvas.drawCircle(Offset(s * 0.73, s * 0.21),
        s * 0.015, spark..color = const Color(0xFFFFB24B));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Wordmark "HEGIKETOK": "HEGI" baja, "KETOK" membara — huruf besar, kokoh.
class BrandWordmark extends StatelessWidget {
  const BrandWordmark({super.key});

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w900,
      letterSpacing: 0.8,
      height: 1.0,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('HEGI', style: base.copyWith(color: AppTheme.textPrimary)),
        ShaderMask(
          shaderCallback: (rect) => const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: kEmberGradient,
          ).createShader(rect),
          blendMode: BlendMode.srcIn,
          child: Text('KETOK', style: base.copyWith(color: Colors.white)),
        ),
        const SizedBox(width: 4),
        Transform.translate(
          offset: const Offset(0, -1),
          child: Icon(Icons.local_fire_department_rounded,
              size: 13, color: _emberCore),
        ),
      ],
    );
  }
}

class _TagPill extends StatelessWidget {
  const _TagPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.surfaceInput,
        borderRadius: BorderRadius.circular(AppTheme.rSm),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bolt_rounded, size: 11, color: _emberCore),
          const SizedBox(width: 4),
          Text('LOCAL-FIRST',
              style: TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6)),
        ],
      ),
    );
  }
}
