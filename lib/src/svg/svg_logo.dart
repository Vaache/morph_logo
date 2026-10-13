import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import 'svg_document.dart';
import 'svg_path_data.dart';

/// A paint value from an SVG: a concrete colour, or `currentColor`.
class SvgInk {
  /// A fixed colour.
  const SvgInk.color(Color this.color);

  /// `currentColor`: resolved to the widget's ink at paint time.
  const SvgInk.current() : color = null;

  final Color? color;

  /// Whether this paint follows the widget's ink.
  bool get isCurrentColor => color == null;
}

/// One drawable element of an [SvgLogo], already transformed into the
/// viewBox's coordinate space.
class SvgShape {
  const SvgShape({
    required this.path,
    this.fill,
    this.stroke,
    this.strokeWidth = 1,
    this.opacity = 1,
    this.fillOpacity = 1,
    this.strokeOpacity = 1,
    this.strokeCap = StrokeCap.butt,
    this.strokeJoin = StrokeJoin.miter,
  });

  /// The outline, with its fill rule applied.
  final Path path;

  /// Fill paint, or null for `fill="none"`.
  final SvgInk? fill;

  /// Stroke paint, or null for no stroke.
  final SvgInk? stroke;

  /// Stroke width in viewBox units.
  final double strokeWidth;

  /// Element opacity, multiplied down from its groups.
  final double opacity;
  final double fillOpacity;
  final double strokeOpacity;
  final StrokeCap strokeCap;
  final StrokeJoin strokeJoin;

  /// Whether the shape paints anything.
  bool get isVisible =>
      opacity > 0 && (fill != null || (stroke != null && strokeWidth > 0));
}

/// A parsed SVG, ready for [MorphLogo] to assemble out of dots.
///
/// Parse it once and keep it: the dot layouts it computes are cached on the
/// instance.
///
/// ```dart
/// final logo = await SvgLogo.load('assets/logo.svg');
/// ```
///
/// Supports `path` (every command, arcs included), `rect`, `circle`,
/// `ellipse`, `line`, `polyline`, `polygon`, nested groups with `transform`,
/// inherited presentation attributes, `style` attributes, simple `<style>`
/// class rules, `currentColor` and opacity. Gradients fall back to the
/// average of their stops; clip paths, masks, filters, text, `use` and
/// images are ignored.
class SvgLogo {
  /// Builds a logo from already parsed [shapes] in [viewBox] space.
  /// Invisible shapes are dropped.
  SvgLogo({required this.viewBox, required List<SvgShape> shapes})
    : assert(
        viewBox.width > 0 && viewBox.height > 0,
        'viewBox must not be empty',
      ),
      shapes = List.unmodifiable(shapes.where((s) => s.isVisible));

  /// Parses SVG markup.
  ///
  /// Throws a [FormatException] when the document has nothing to draw.
  factory SvgLogo.parse(String source) {
    final (viewBox, shapes) = parseSvgDocument(source);
    return SvgLogo(viewBox: viewBox, shapes: shapes);
  }

  /// Builds a single-shape logo from SVG path data (`d`).
  ///
  /// Filled with [color] by default; pass [strokeWidth] to stroke it instead.
  /// Without [viewBox] the path's bounds are used. A null [color] follows the
  /// widget's ink.
  factory SvgLogo.pathData(
    String data, {
    Rect? viewBox,
    Color? color,
    double? strokeWidth,
  }) {
    final path = parseSvgPathData(data);
    final ink = color == null ? const SvgInk.current() : SvgInk.color(color);
    final stroked = strokeWidth != null;
    var box = viewBox ?? path.getBounds();
    if (viewBox == null && stroked) {
      box = box.inflate(strokeWidth / 2);
    }
    return SvgLogo(
      viewBox: box,
      shapes: [
        SvgShape(
          path: path,
          fill: stroked ? null : ink,
          stroke: stroked ? ink : null,
          strokeWidth: strokeWidth ?? 0,
          strokeCap: StrokeCap.round,
          strokeJoin: StrokeJoin.round,
        ),
      ],
    );
  }

  /// Loads and parses an SVG asset.
  static Future<SvgLogo> load(String assetName, {AssetBundle? bundle}) async {
    final source = await (bundle ?? rootBundle).loadString(assetName);
    return SvgLogo.parse(source);
  }

  /// The SVG's viewBox; the logo is fitted into the widget by its longer
  /// side and centred.
  final Rect viewBox;

  /// Visible shapes, in paint order.
  final List<SvgShape> shapes;

  double get _unit => 1 / math.max(viewBox.width, viewBox.height);

  late final List<(PathMetric, int)> _shapeMetrics = [
    for (var i = 0; i < shapes.length; i++)
      for (final metric in shapes[i].path.computeMetrics()) (metric, i),
  ];

  late final List<PathMetric> _metrics = [
    for (final (metric, _) in _shapeMetrics) metric,
  ];

  late final double _totalLength = _metrics.fold(
    0.0,
    (sum, m) => sum + m.length,
  );

  /// Total length of every contour, with the viewBox's longer side as 1.
  double get outlineLength => _totalLength * _unit;

  final Map<int, Float64List> _pointCache = {};

  /// [count] points spread evenly along every contour, as x, y pairs in a
  /// unit square centred on 0 (−0.5..0.5). Cached per count.
  Float64List outlinePoints(int count) {
    final cached = _pointCache[count];
    if (cached != null) {
      return cached;
    }
    final out = Float64List(count * 2);
    final unit = _unit;
    final center = viewBox.center;
    if (_metrics.isEmpty || _totalLength == 0) {
      return _pointCache[count] = out;
    }
    var metric = 0;
    var acc = 0.0;
    for (var k = 0; k < count; k++) {
      final target = (k + 0.5) / count * _totalLength;
      while (metric < _metrics.length - 1 &&
          acc + _metrics[metric].length < target) {
        acc += _metrics[metric].length;
        metric++;
      }
      final m = _metrics[metric];
      final position = m
          .getTangentForOffset((target - acc).clamp(0.0, m.length))
          ?.position;
      if (position != null) {
        out[k * 2] = (position.dx - center.dx) * unit;
        out[k * 2 + 1] = (position.dy - center.dy) * unit;
      }
    }
    if (_pointCache.length > 8) {
      _pointCache.remove(_pointCache.keys.first);
    }
    return _pointCache[count] = out;
  }

  final Map<(int, int), LogoDotLayout> _layoutCache = {};

  /// Where every dot of the animation lands: [outlineCount] dots along the
  /// contours, then a hex grid [spacing] apart (in unit space) inside each
  /// filled shape. Cached per arguments.
  LogoDotLayout dotLayout({
    required int outlineCount,
    required double spacing,
    bool useSvgColors = true,
  }) {
    final key = (
      outlineCount,
      (spacing * 1e5).round() * (useSvgColors ? 1 : -1),
    );
    final cached = _layoutCache[key];
    if (cached != null) {
      return cached;
    }
    final layout = _buildLayout(outlineCount, spacing, useSvgColors);
    if (_layoutCache.length > 4) {
      _layoutCache.remove(_layoutCache.keys.first);
    }
    return _layoutCache[key] = layout;
  }

  LogoDotLayout _buildLayout(int outlineCount, double spacing, bool own) {
    final unit = _unit;
    final center = viewBox.center;
    final xs = <double>[];
    final ys = <double>[];
    final orders = <double>[];
    final colors = <Color?>[];

    Color? colorOf(SvgInk? ink) => own ? ink?.color : null;

    if (_totalLength > 0) {
      var index = 0;
      var acc = 0.0;
      for (var k = 0; k < outlineCount; k++) {
        final target = (k + 0.5) / outlineCount * _totalLength;
        while (index < _shapeMetrics.length - 1 &&
            acc + _shapeMetrics[index].$1.length < target) {
          acc += _shapeMetrics[index].$1.length;
          index++;
        }
        final (metric, shapeIndex) = _shapeMetrics[index];
        final offset = (target - acc).clamp(0.0, metric.length);
        final position = metric.getTangentForOffset(offset)?.position;
        if (position == null) {
          continue;
        }
        final shape = shapes[shapeIndex];
        final stroked = shape.stroke != null && shape.strokeWidth > 0;
        xs.add((position.dx - center.dx) * unit);
        ys.add((position.dy - center.dy) * unit);
        orders.add(metric.length == 0 ? 0 : offset / metric.length);
        colors.add(colorOf(stroked ? shape.stroke : shape.fill));
      }
    }
    final outline = xs.length;

    final halfW = viewBox.width * unit / 2;
    final halfH = viewBox.height * unit / 2;
    final rowStep = spacing * math.sqrt(3) / 2;
    final minGap = spacing * 0.6;
    final interiorShape = <int>[];
    final interiorDistance = <double>[];
    var row = 0;
    for (var y = -halfH + rowStep / 2; y < halfH; y += rowStep, row++) {
      final shift = row.isOdd ? spacing / 2 : 0.0;
      for (var x = -halfW + spacing / 2 + shift; x < halfW; x += spacing) {
        final point = Offset(x / unit + center.dx, y / unit + center.dy);
        var owner = -1;
        for (var i = shapes.length - 1; i >= 0; i--) {
          if (shapes[i].fill != null && shapes[i].path.contains(point)) {
            owner = i;
            break;
          }
        }
        if (owner < 0) {
          continue;
        }
        var nearest = double.infinity;
        for (var k = 0; k < outline; k++) {
          final dx = xs[k] - x;
          final dy = ys[k] - y;
          final d = dx * dx + dy * dy;
          if (d < nearest) {
            nearest = d;
          }
        }
        nearest = math.sqrt(nearest);
        if (nearest < minGap) {
          continue;
        }
        xs.add(x);
        ys.add(y);
        colors.add(colorOf(shapes[owner].fill));
        interiorShape.add(owner);
        interiorDistance.add(nearest);
      }
    }
    final deepest = <int, double>{};
    for (var i = 0; i < interiorShape.length; i++) {
      final owner = interiorShape[i];
      deepest[owner] = math.max(deepest[owner] ?? 0, interiorDistance[i]);
    }
    for (var i = 0; i < interiorShape.length; i++) {
      final max = deepest[interiorShape[i]]!;
      orders.add(max <= 0 ? 0 : interiorDistance[i] / max);
    }

    final count = xs.length;
    final positions = Float64List(count * 2);
    final order = Float64List(count);
    final rgb = Float64List(count * 3);
    final tinted = Uint8List(count);
    for (var k = 0; k < count; k++) {
      positions[k * 2] = xs[k];
      positions[k * 2 + 1] = ys[k];
      order[k] = orders[k];
      final color = colors[k];
      if (color != null) {
        rgb[k * 3] = color.r;
        rgb[k * 3 + 1] = color.g;
        rgb[k * 3 + 2] = color.b;
        tinted[k] = 1;
      }
    }
    return LogoDotLayout._(
      outlineCount: outline,
      positions: positions,
      order: order,
      rgb: rgb,
      tinted: tinted,
    );
  }

  /// Paints the logo itself into [rect] at [opacity]. `currentColor`, and
  /// every colour when [useSvgColors] is false, use [ink].
  void paint(
    Canvas canvas,
    Rect rect, {
    required Color ink,
    double opacity = 1,
    bool useSvgColors = true,
  }) {
    if (opacity <= 0) {
      return;
    }
    final scale = math.min(rect.width, rect.height) * _unit;
    canvas
      ..save()
      ..translate(rect.center.dx, rect.center.dy)
      ..scale(scale)
      ..translate(-viewBox.center.dx, -viewBox.center.dy);
    final layered = opacity < 1;
    if (layered) {
      canvas.saveLayer(
        viewBox.inflate(viewBox.longestSide),
        Paint()..color = Color.fromRGBO(0, 0, 0, opacity),
      );
    }
    final paint = Paint()..isAntiAlias = true;
    for (final shape in shapes) {
      final fill = shape.fill;
      if (fill != null) {
        paint
          ..style = PaintingStyle.fill
          ..color = _resolve(
            fill,
            ink,
            useSvgColors,
            shape.opacity * shape.fillOpacity,
          );
        canvas.drawPath(shape.path, paint);
      }
      final stroke = shape.stroke;
      if (stroke != null && shape.strokeWidth > 0) {
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = shape.strokeWidth
          ..strokeCap = shape.strokeCap
          ..strokeJoin = shape.strokeJoin
          ..color = _resolve(
            stroke,
            ink,
            useSvgColors,
            shape.opacity * shape.strokeOpacity,
          );
        canvas.drawPath(shape.path, paint);
      }
    }
    if (layered) {
      canvas.restore();
    }
    canvas.restore();
  }

  static Color _resolve(SvgInk ink, Color fallback, bool own, double alpha) {
    final base = own && ink.color != null ? ink.color! : fallback;
    return base.withValues(alpha: base.a * alpha.clamp(0.0, 1.0));
  }
}

/// The dots of one logo at one density: outline dots first, interior dots
/// after them.
class LogoDotLayout {
  const LogoDotLayout._({
    required this.outlineCount,
    required this.positions,
    required this.order,
    required this.rgb,
    required this.tinted,
  });

  /// How many leading dots sit on the contours.
  final int outlineCount;

  /// Unit-space x, y pairs, −0.5..0.5.
  final Float64List positions;

  /// When each dot arrives, 0..1: the position along its contour for
  /// outline dots, the depth from the shape's edge for interior dots.
  final Float64List order;

  /// The colour each dot takes, as red, green, blue triples in 0..1.
  final Float64List rgb;

  /// 1 where the dot has a colour of its own, 0 where it uses the ink.
  final Uint8List tinted;

  /// Every dot.
  int get count => order.length;

  /// Dots inside filled shapes.
  int get interiorCount => count - outlineCount;
}
