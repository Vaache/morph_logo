import 'dart:math' as math;

import 'package:flutter/rendering.dart';

import '../controllers/morph_logo_controller.dart';
import 'package:morph_orbs/engine.dart';

class MorphLogoPainter extends CustomPainter {
  MorphLogoPainter({required this.controller, this.useSvgColors = true})
    : super(repaint: controller);

  final MorphLogoController controller;
  final bool useSvgColors;

  final Paint _dotPaint = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.fill;
  final Paint _linePaint = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    final offset = Offset((size.width - side) / 2, (size.height - side) / 2);
    final frame = controller.render(side);
    final ink = controller.inkColor();
    paintOrbFrame(
      canvas,
      frame,
      ink: ink,
      background: controller.style.backgroundColor,
      offset: offset,
      dotPaint: _dotPaint,
      linePaint: _linePaint,
    );
    final solid = controller.solidOpacity;
    if (solid > 0.002) {
      controller.logo.paint(
        canvas,
        offset & Size.square(side),
        ink: ink,
        opacity: solid,
        useSvgColors: useSvgColors,
      );
    }
  }

  @override
  bool shouldRepaint(MorphLogoPainter oldDelegate) =>
      oldDelegate.controller != controller ||
      oldDelegate.useSvgColors != useSvgColors;
}
