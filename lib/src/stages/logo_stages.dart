import 'dart:math' as math;

import '../svg/svg_logo.dart';
import 'package:morph_orbs/engine.dart';

class LogoStageContext {
  const LogoStageContext({
    required this.size,
    required this.layout,
    required this.dotRadius,
    required this.fillRadius,
    required this.intensity,
  });

  final double size;
  final LogoDotLayout layout;
  final double dotRadius;
  final double fillRadius;
  final double intensity;
}

abstract class LogoStageGeometry {
  const LogoStageGeometry();

  void build(OrbFrame out, LogoStageContext c, double clock, double local);

  double settleTime(LogoDotLayout layout) => 0;

  bool isAnimatingAt(double local, LogoDotLayout layout) =>
      local < settleTime(layout);

  double solidAt(double local) => 0;
}

double _easeOut(double x) {
  final c = 1 - clamp01(x);
  return 1 - c * c * c;
}

double _sx = 0;
double _sy = 0;

void _scatter(LogoDotLayout layout, int k, double clock, double intensity) {
  final id = k.toDouble();
  final tx = layout.positions[k * 2];
  final ty = layout.positions[k * 2 + 1];
  final base = tx * tx + ty * ty < 1e-6
      ? hashD(id, 1.7) * kTau
      : math.atan2(ty, tx);
  final angle =
      base +
      (hashD(id, 2.9) - 0.5) * 1.4 +
      clock * (0.22 + 0.3 * hashD(id, 3.3));
  final radius =
      0.1 +
      0.34 * math.sqrt(hashD(id, 4.1)) +
      0.02 * intensity * math.sin(clock * 1.7 + hashD(id, 5.3) * kTau);
  _sx = math.cos(angle) * radius;
  _sy = math.sin(angle) * radius;
}

double _cloudInk(int k, double clock) {
  final id = k.toDouble();
  final twinkle =
      0.5 +
      0.5 * math.sin(clock * (1.4 + hashD(id, 2.2)) + hashD(id, 5.5) * kTau);
  return 0.2 + 0.45 * (1 - twinkle);
}

double _cloudScale(int k) => 0.6 + 0.45 * hashD(k.toDouble(), 6.6);

void _addDot(
  OrbFrame out,
  LogoStageContext c,
  int k,
  double x,
  double y,
  double z,
  double radius,
  double ink,
  double tint,
) {
  final layout = c.layout;
  final half = c.size / 2;
  if (tint > 0 && layout.tinted[k] == 1) {
    out.addTinted(
      half + x * c.size,
      half + y * c.size,
      z,
      radius,
      ink,
      1,
      layout.rgb[k * 3],
      layout.rgb[k * 3 + 1],
      layout.rgb[k * 3 + 2],
      tint,
    );
  } else {
    out.add(half + x * c.size, half + y * c.size, z, radius, ink);
  }
}

void _addCloudDot(OrbFrame out, LogoStageContext c, int k, double clock) {
  _scatter(c.layout, k, clock, c.intensity);
  _addDot(
    out,
    c,
    k,
    _sx,
    _sy,
    hashD(k.toDouble(), 8.8) - 1,
    c.dotRadius * _cloudScale(k),
    _cloudInk(k, clock),
    0,
  );
}

void _addFlyingDot(
  OrbFrame out,
  LogoStageContext c,
  int k,
  double clock,
  double progress,
  double radius,
  double tint,
) {
  _scatter(c.layout, k, clock, c.intensity);
  final tx = c.layout.positions[k * 2];
  final ty = c.layout.positions[k * 2 + 1];
  final pop = 1 + 0.6 * c.intensity * math.sin(math.pi * progress);
  _addDot(
    out,
    c,
    k,
    lerp(_sx, tx, progress),
    lerp(_sy, ty, progress),
    progress,
    lerp(c.dotRadius * _cloudScale(k), radius, progress) * pop,
    lerp(_cloudInk(k, clock), 0, progress),
    tint,
  );
}

class LogoHiddenStage extends LogoStageGeometry {
  const LogoHiddenStage();

  @override
  void build(OrbFrame out, LogoStageContext c, double clock, double local) {
    out
      ..clear()
      ..add(c.size / 2, c.size / 2, 0, 0, 0);
  }
}

class LogoDustStage extends LogoStageGeometry {
  const LogoDustStage();

  @override
  bool isAnimatingAt(double local, LogoDotLayout layout) => true;

  @override
  void build(OrbFrame out, LogoStageContext c, double clock, double local) {
    out.clear();
    for (var k = 0; k < c.layout.count; k++) {
      _addCloudDot(out, c, k, clock);
    }
  }
}

class LogoOutlineStage extends LogoStageGeometry {
  const LogoOutlineStage({this.drawSpan = 0.55, this.flight = 0.45});

  final double drawSpan;
  final double flight;

  @override
  double settleTime(LogoDotLayout layout) => drawSpan + flight;

  @override
  bool isAnimatingAt(double local, LogoDotLayout layout) =>
      layout.interiorCount > 0 || local < settleTime(layout);

  @override
  void build(OrbFrame out, LogoStageContext c, double clock, double local) {
    out.clear();
    final layout = c.layout;
    for (var k = 0; k < layout.count; k++) {
      if (k >= layout.outlineCount) {
        _addCloudDot(out, c, k, clock);
        continue;
      }
      final progress = _easeOut((local - layout.order[k] * drawSpan) / flight);
      _addFlyingDot(out, c, k, clock, progress, c.dotRadius, 0);
    }
  }
}

class LogoFillStage extends LogoStageGeometry {
  const LogoFillStage({
    this.fillSpan = 0.6,
    this.flight = 0.45,
    this.tintIn = 0.35,
  });

  final double fillSpan;
  final double flight;
  final double tintIn;

  static const double _jitter = 0.08;

  @override
  double settleTime(LogoDotLayout layout) =>
      layout.interiorCount > 0 ? fillSpan + _jitter + flight : tintIn;

  @override
  void build(OrbFrame out, LogoStageContext c, double clock, double local) {
    out.clear();
    final layout = c.layout;
    final outlineTint = smoothStep(local / tintIn);
    for (var k = 0; k < layout.count; k++) {
      if (k < layout.outlineCount) {
        _addDot(
          out,
          c,
          k,
          layout.positions[k * 2],
          layout.positions[k * 2 + 1],
          1,
          c.dotRadius,
          0,
          outlineTint,
        );
        continue;
      }
      final delay =
          layout.order[k] * fillSpan + hashD(k.toDouble(), 9.1) * _jitter;
      final progress = _easeOut((local - delay) / flight);
      _addFlyingDot(out, c, k, clock, progress, c.fillRadius, progress);
    }
  }
}

class LogoSolidStage extends LogoStageGeometry {
  const LogoSolidStage({this.delay = 0.12, this.fadeDuration = 0.45});

  final double delay;
  final double fadeDuration;

  @override
  double solidAt(double local) => smoothStep((local - delay) / fadeDuration);

  @override
  double settleTime(LogoDotLayout layout) => delay + fadeDuration;

  @override
  void build(OrbFrame out, LogoStageContext c, double clock, double local) {
    out.clear();
    final layout = c.layout;
    final shrink = 1 - solidAt(local);
    for (var k = 0; k < layout.count; k++) {
      final interior = k >= layout.outlineCount;
      _addDot(
        out,
        c,
        k,
        layout.positions[k * 2],
        layout.positions[k * 2 + 1],
        1,
        (interior ? c.fillRadius : c.dotRadius) * shrink,
        0,
        1,
      );
    }
  }
}
