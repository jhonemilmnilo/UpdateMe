import 'package:flutter/material.dart';

/// Provides custom organic, fluid Bézier blob clipping paths
/// inspired by Instagram Story cutout stickers and fluid photo overlays.
class OrganicBlobClipper extends CustomClipper<Path> {
  final int variant;

  const OrganicBlobClipper({this.variant = 0});

  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path();

    switch (variant % 4) {
      case 0:
        // Variant 0: Asymmetric organic pebble / rounded fluid quad (matching user's reference)
        path.moveTo(w * 0.18, h * 0.04);
        // Top edge with gentle curve
        path.cubicTo(w * 0.45, -h * 0.02, w * 0.72, h * 0.02, w * 0.88, h * 0.12);
        // Right top bulge
        path.cubicTo(w * 1.02, h * 0.22, w * 1.01, h * 0.52, w * 0.94, h * 0.76);
        // Bottom right rounded curve
        path.cubicTo(w * 0.88, h * 0.95, w * 0.65, h * 1.02, w * 0.42, h * 0.98);
        // Bottom left pinched sweep
        path.cubicTo(w * 0.18, h * 0.94, w * 0.02, h * 0.82, w * 0.03, h * 0.58);
        // Left side organic bulge closing
        path.cubicTo(w * 0.04, h * 0.32, w * 0.06, h * 0.12, w * 0.18, h * 0.04);
        path.close();
        break;

      case 1:
        // Variant 1: Soft fluid egg / arch blob with organic indentations
        path.moveTo(w * 0.28, h * 0.03);
        // Smooth arched crest
        path.cubicTo(w * 0.55, -h * 0.01, w * 0.75, h * 0.04, w * 0.92, h * 0.20);
        // Right waist
        path.cubicTo(w * 1.00, h * 0.35, w * 0.96, h * 0.68, w * 0.90, h * 0.84);
        // Bottom wide base
        path.cubicTo(w * 0.82, h * 0.99, w * 0.48, h * 1.01, w * 0.26, h * 0.95);
        // Left sweep
        path.cubicTo(w * 0.06, h * 0.89, w * 0.02, h * 0.60, w * 0.05, h * 0.38);
        path.cubicTo(w * 0.08, h * 0.16, w * 0.15, h * 0.06, w * 0.28, h * 0.03);
        path.close();
        break;

      case 2:
        // Variant 2: Slanted organic teardrop / pebble blob
        path.moveTo(w * 0.12, h * 0.15);
        // Top right diagonal rise
        path.cubicTo(w * 0.25, h * 0.02, w * 0.68, h * 0.00, w * 0.86, h * 0.08);
        // Right flank curve
        path.cubicTo(w * 1.02, h * 0.18, w * 0.98, h * 0.48, w * 0.95, h * 0.72);
        // Lower right corner round
        path.cubicTo(w * 0.92, h * 0.92, w * 0.70, h * 0.99, w * 0.48, h * 0.97);
        // Left lower bulb
        path.cubicTo(w * 0.22, h * 0.95, w * 0.01, h * 0.80, w * 0.02, h * 0.52);
        path.cubicTo(w * 0.03, h * 0.28, w * 0.05, h * 0.22, w * 0.12, h * 0.15);
        path.close();
        break;

      case 3:
      default:
        // Variant 3: Deep fluid squircle with wavy organic borders
        path.moveTo(w * 0.22, h * 0.02);
        path.cubicTo(w * 0.50, h * 0.04, w * 0.78, -h * 0.01, w * 0.94, h * 0.14);
        path.cubicTo(w * 1.03, h * 0.32, w * 0.97, h * 0.65, w * 0.92, h * 0.88);
        path.cubicTo(w * 0.84, h * 1.02, w * 0.52, h * 0.97, w * 0.28, h * 0.98);
        path.cubicTo(w * 0.08, h * 0.99, w * 0.01, h * 0.75, w * 0.03, h * 0.45);
        path.cubicTo(w * 0.05, h * 0.18, w * 0.08, h * 0.01, w * 0.22, h * 0.02);
        path.close();
        break;
    }

    return path;
  }

  @override
  bool shouldReclip(covariant OrganicBlobClipper oldClipper) {
    return oldClipper.variant != variant;
  }
}
