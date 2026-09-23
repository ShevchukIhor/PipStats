import 'package:flutter/material.dart';

import 'package:pipstats/theme.dart';

/// CRT treatment drawn over the app: scanlines and an edge vignette.
///
/// The overlay is purely decorative and must never intercept input, so it
/// sits in an [IgnorePointer]. It is also fully static — the painter reports
/// `shouldRepaint => false` and lives behind a [RepaintBoundary], so it is
/// rasterised once instead of on every frame.
///
/// Rendered only for palettes with [DeviceStatsColors.crt] set; the
/// high-contrast and light palettes stay clean.
class CrtOverlay extends StatelessWidget {
  final Widget child;

  const CrtOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    if (!ds.crt) return child;

    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _CrtPainter(
                  scanline: ds.scanline,
                  vignette: ds.bg,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CrtPainter extends CustomPainter {
  final Color scanline;
  final Color vignette;

  const _CrtPainter({required this.scanline, required this.vignette});

  /// Distance between scanlines in logical pixels. Tighter than ~3 and the
  /// lines alias into a flat grey wash on a high-density panel.
  static const double _spacing = 3;

  @override
  void paint(Canvas canvas, Size size) {
    // Scanlines: a dark 1px rule every _spacing px.
    final linePaint = Paint()
      ..color = scanline
      ..strokeWidth = 1;
    for (var y = 0.0; y < size.height; y += _spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }

    // Vignette: the phosphor falls off toward the tube edges.
    final rect = Offset.zero & size;
    final vignettePaint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 1.15,
        // Deliberately weak. At 0.75 alpha the edges swallowed the app bar
        // and the last visible row — undoing the legibility this pass is for.
        colors: [
          vignette.withValues(alpha: 0),
          vignette.withValues(alpha: 0.10),
          vignette.withValues(alpha: 0.28),
        ],
        stops: const [0.70, 0.92, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, vignettePaint);
  }

  @override
  bool shouldRepaint(covariant _CrtPainter old) =>
      old.scanline != scanline || old.vignette != vignette;
}

/// Phosphor glow for text that should look emissive.
///
/// Applied to headings and values only. Putting a blur behind dense table
/// body text smears it, which would work against the readability this pass
/// is meant to improve.
List<Shadow> pipGlow(Color color, {double blur = 8}) => [
  Shadow(color: color.withValues(alpha: 0.75), blurRadius: blur),
];
