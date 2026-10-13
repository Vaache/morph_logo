import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'svg_logo.dart';
import 'svg_path_data.dart';

final RegExp _numberPattern = RegExp(
  r'[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?',
);
final RegExp _tagPattern = RegExp(
  r'''<(/?)([A-Za-z][\w:.-]*)((?:[^>"']|"[^"]*"|'[^']*')*?)(/?)>''',
);
final RegExp _attrPattern = RegExp(
  r'''([A-Za-z_][\w:.-]*)\s*=\s*(?:"([^"]*)"|'([^']*)')''',
);
final RegExp _stylePattern = RegExp(r'<style[^>]*>([\s\S]*?)</style>');
final RegExp _cssRulePattern = RegExp(r'([^{}]+)\{([^}]*)\}');
final RegExp _transformPattern = RegExp(
  r'(matrix|translate|scale|rotate|skewX|skewY)\s*\(([^)]*)\)',
);

const Set<String> _skipped = {
  'defs',
  'clipPath',
  'mask',
  'symbol',
  'pattern',
  'marker',
  'filter',
  'text',
  'title',
  'desc',
  'metadata',
  'style',
  'linearGradient',
  'radialGradient',
  'foreignObject',
  'image',
  'use',
  'script',
};

const Map<String, int> _namedColors = {
  'black': 0xFF000000,
  'white': 0xFFFFFFFF,
  'red': 0xFFFF0000,
  'green': 0xFF008000,
  'lime': 0xFF00FF00,
  'blue': 0xFF0000FF,
  'yellow': 0xFFFFFF00,
  'cyan': 0xFF00FFFF,
  'aqua': 0xFF00FFFF,
  'magenta': 0xFFFF00FF,
  'fuchsia': 0xFFFF00FF,
  'gray': 0xFF808080,
  'grey': 0xFF808080,
  'silver': 0xFFC0C0C0,
  'maroon': 0xFF800000,
  'olive': 0xFF808000,
  'navy': 0xFF000080,
  'purple': 0xFF800080,
  'teal': 0xFF008080,
  'orange': 0xFFFFA500,
  'pink': 0xFFFFC0CB,
  'transparent': 0x00000000,
};

class _Affine {
  const _Affine(this.a, this.b, this.c, this.d, this.e, this.f);

  static const identity = _Affine(1, 0, 0, 1, 0, 0);

  final double a;
  final double b;
  final double c;
  final double d;
  final double e;
  final double f;

  bool get isIdentity =>
      a == 1 && b == 0 && c == 0 && d == 1 && e == 0 && f == 0;

  _Affine operator *(_Affine o) => _Affine(
    a * o.a + c * o.b,
    b * o.a + d * o.b,
    a * o.c + c * o.d,
    b * o.c + d * o.d,
    a * o.e + c * o.f + e,
    b * o.e + d * o.f + f,
  );

  double get scale => math.sqrt((a * d - b * c).abs());

  Float64List toMatrix4() =>
      Float64List.fromList([a, b, 0, 0, c, d, 0, 0, 0, 0, 1, 0, e, f, 0, 1]);
}

class _Style {
  const _Style({
    this.fill = const SvgInk.color(Color(0xFF000000)),
    this.stroke,
    this.strokeWidth = 1,
    this.fillOpacity = 1,
    this.strokeOpacity = 1,
    this.opacity = 1,
    this.evenOdd = false,
    this.cap = StrokeCap.butt,
    this.join = StrokeJoin.miter,
    this.transform = _Affine.identity,
    this.hidden = false,
  });

  final SvgInk? fill;
  final SvgInk? stroke;
  final double strokeWidth;
  final double fillOpacity;
  final double strokeOpacity;
  final double opacity;
  final bool evenOdd;
  final StrokeCap cap;
  final StrokeJoin join;
  final _Affine transform;
  final bool hidden;
}

class _Tag {
  const _Tag(
    this.name,
    this.attrs, {
    required this.closing,
    required this.selfClosing,
  });

  final String name;
  final Map<String, String> attrs;
  final bool closing;
  final bool selfClosing;
}

class _Parser {
  _Parser(String source) {
    final clean = source
        .replaceAll(RegExp(r'<!--[\s\S]*?-->'), '')
        .replaceAll(RegExp(r'<\?[\s\S]*?\?>'), '')
        .replaceAll(RegExp(r'<!DOCTYPE[^>]*>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<!\[CDATA\[|\]\]>'), '');
    for (final style in _stylePattern.allMatches(clean)) {
      _readCss(style.group(1)!);
    }
    for (final m in _tagPattern.allMatches(clean)) {
      final attrs = <String, String>{};
      for (final a in _attrPattern.allMatches(m.group(3)!)) {
        attrs[a.group(1)!] = (a.group(2) ?? a.group(3) ?? '').trim();
      }
      _tags.add(
        _Tag(
          _localName(m.group(2)!),
          attrs,
          closing: m.group(1)!.isNotEmpty,
          selfClosing: m.group(4)!.isNotEmpty,
        ),
      );
    }
  }

  final List<_Tag> _tags = [];
  final Map<String, Map<String, String>> _css = {};
  final Map<String, List<Color>> _gradientStops = {};
  final Map<String, String> _gradientLinks = {};
  final List<SvgShape> _shapes = [];
  Rect? _viewBox;

  static String _localName(String name) {
    final colon = name.indexOf(':');
    return colon < 0 ? name : name.substring(colon + 1);
  }

  void _readCss(String css) {
    for (final rule in _cssRulePattern.allMatches(css)) {
      final decls = _declarations(rule.group(2)!);
      for (final raw in rule.group(1)!.split(',')) {
        final selector = raw.trim();
        if (selector.isEmpty) {
          continue;
        }
        (_css[selector] ??= {}).addAll(decls);
      }
    }
  }

  static Map<String, String> _declarations(String text) {
    final out = <String, String>{};
    for (final decl in text.split(';')) {
      final colon = decl.indexOf(':');
      if (colon <= 0) {
        continue;
      }
      out[decl.substring(0, colon).trim()] = decl.substring(colon + 1).trim();
    }
    return out;
  }

  Map<String, String> _properties(_Tag tag) {
    final props = Map<String, String>.of(tag.attrs);
    final byTag = _css[tag.name];
    if (byTag != null) {
      props.addAll(byTag);
    }
    final classes = tag.attrs['class'];
    if (classes != null) {
      for (final name in classes.split(RegExp(r'\s+'))) {
        final rule = _css['.$name'];
        if (rule != null) {
          props.addAll(rule);
        }
      }
    }
    final id = tag.attrs['id'];
    if (id != null) {
      final rule = _css['#$id'];
      if (rule != null) {
        props.addAll(rule);
      }
    }
    final inline = tag.attrs['style'];
    if (inline != null) {
      props.addAll(_declarations(inline));
    }
    return props;
  }

  (Rect, List<SvgShape>) parse() {
    _collectGradients();
    _collectShapes();
    if (_shapes.isEmpty) {
      throw const FormatException('SVG contains no drawable shapes');
    }
    var box = _viewBox;
    if (box == null || box.isEmpty) {
      box = _shapes
          .map((s) => s.path.getBounds().inflate(s.strokeWidth / 2))
          .reduce((a, b) => a.expandToInclude(b));
    }
    return (box, _shapes);
  }

  void _collectGradients() {
    String? current;
    for (final tag in _tags) {
      if (tag.name == 'linearGradient' || tag.name == 'radialGradient') {
        if (tag.closing) {
          current = null;
          continue;
        }
        final id = tag.attrs['id'];
        final link = tag.attrs['href'] ?? tag.attrs['xlink:href'];
        if (id != null) {
          _gradientStops[id] = [];
          if (link != null && link.startsWith('#')) {
            _gradientLinks[id] = link.substring(1);
          }
        }
        current = tag.selfClosing ? null : id;
      } else if (tag.name == 'stop' && current != null && !tag.closing) {
        final props = _properties(tag);
        final color = _parseColor(props['stop-color'] ?? 'black');
        if (color != null) {
          final alpha = _parseOpacity(props['stop-opacity']);
          _gradientStops[current]!.add(
            color.withValues(alpha: color.a * alpha),
          );
        }
      }
    }
  }

  Color? _gradientColor(String id, [int depth = 0]) {
    final stops = _gradientStops[id];
    if (stops != null && stops.isNotEmpty) {
      var r = 0.0;
      var g = 0.0;
      var b = 0.0;
      var a = 0.0;
      for (final c in stops) {
        r += c.r;
        g += c.g;
        b += c.b;
        a += c.a;
      }
      final n = stops.length;
      return Color.from(alpha: a / n, red: r / n, green: g / n, blue: b / n);
    }
    final link = _gradientLinks[id];
    if (link != null && depth < 4) {
      return _gradientColor(link, depth + 1);
    }
    return null;
  }

  void _collectShapes() {
    final stack = <_Style>[const _Style()];
    var skipDepth = 0;
    for (final tag in _tags) {
      if (skipDepth > 0) {
        if (tag.closing) {
          skipDepth--;
        } else if (!tag.selfClosing) {
          skipDepth++;
        }
        continue;
      }
      if (tag.closing) {
        if (stack.length > 1) {
          stack.removeLast();
        }
        continue;
      }
      if (_skipped.contains(tag.name)) {
        if (!tag.selfClosing) {
          skipDepth = 1;
        }
        continue;
      }
      final props = _properties(tag);
      if (tag.name == 'svg' && _viewBox == null) {
        _viewBox = _readViewBox(props);
      }
      final style = _inherit(stack.last, props, root: tag.name == 'svg');
      if (!style.hidden) {
        final path = _shapePath(tag.name, props);
        if (path != null) {
          _addShape(path, style);
        }
      }
      if (!tag.selfClosing) {
        stack.add(style);
      }
    }
  }

  Rect? _readViewBox(Map<String, String> props) {
    final raw = props['viewBox'];
    if (raw != null) {
      final v = _numbers(raw);
      if (v.length == 4 && v[2] > 0 && v[3] > 0) {
        return Rect.fromLTWH(v[0], v[1], v[2], v[3]);
      }
    }
    final w = _length(props['width']);
    final h = _length(props['height']);
    if (w != null && h != null && w > 0 && h > 0) {
      return Rect.fromLTWH(0, 0, w, h);
    }
    return null;
  }

  _Style _inherit(_Style parent, Map<String, String> p, {bool root = false}) {
    var transform = parent.transform;
    final t = p['transform'];
    if (t != null && !root) {
      transform = transform * _parseTransform(t);
    }
    final display = p['display'];
    final visibility = p['visibility'];
    return _Style(
      fill: p.containsKey('fill')
          ? _parsePaint(p['fill']!, parent.fill)
          : parent.fill,
      stroke: p.containsKey('stroke')
          ? _parsePaint(p['stroke']!, parent.stroke)
          : parent.stroke,
      strokeWidth: _length(p['stroke-width']) ?? parent.strokeWidth,
      fillOpacity: p.containsKey('fill-opacity')
          ? _parseOpacity(p['fill-opacity'])
          : parent.fillOpacity,
      strokeOpacity: p.containsKey('stroke-opacity')
          ? _parseOpacity(p['stroke-opacity'])
          : parent.strokeOpacity,
      opacity: parent.opacity * _parseOpacity(p['opacity']),
      evenOdd: switch (p['fill-rule']) {
        'evenodd' => true,
        'nonzero' => false,
        _ => parent.evenOdd,
      },
      cap: switch (p['stroke-linecap']) {
        'round' => StrokeCap.round,
        'square' => StrokeCap.square,
        'butt' => StrokeCap.butt,
        _ => parent.cap,
      },
      join: switch (p['stroke-linejoin']) {
        'round' => StrokeJoin.round,
        'bevel' => StrokeJoin.bevel,
        'miter' || 'miter-clip' || 'arcs' => StrokeJoin.miter,
        _ => parent.join,
      },
      transform: transform,
      hidden: parent.hidden || display == 'none' || visibility == 'hidden',
    );
  }

  SvgInk? _parsePaint(String value, SvgInk? inherited) {
    final v = value.trim();
    if (v == 'none' || v.isEmpty) {
      return null;
    }
    if (v == 'inherit') {
      return inherited;
    }
    if (v == 'currentColor') {
      return const SvgInk.current();
    }
    if (v.startsWith('url(')) {
      final id = RegExp(r'url\(\s*#([^)\s]+)\s*\)').firstMatch(v)?.group(1);
      final color = id == null ? null : _gradientColor(id);
      if (color != null) {
        return SvgInk.color(color);
      }
      final fallback = v.substring(v.indexOf(')') + 1).trim();
      if (fallback.isNotEmpty) {
        return _parsePaint(fallback, inherited);
      }
      return const SvgInk.current();
    }
    final color = _parseColor(v);
    return color == null ? inherited : SvgInk.color(color);
  }

  Path? _shapePath(String name, Map<String, String> p) {
    double n(String key, [double fallback = 0]) => _length(p[key]) ?? fallback;
    switch (name) {
      case 'path':
        final d = p['d'];
        if (d == null || d.isEmpty) {
          return null;
        }
        try {
          return parseSvgPathData(d);
        } on FormatException {
          return null;
        }
      case 'rect':
        final w = n('width');
        final h = n('height');
        if (w <= 0 || h <= 0) {
          return null;
        }
        final rect = Rect.fromLTWH(n('x'), n('y'), w, h);
        var rx = _length(p['rx']);
        var ry = _length(p['ry']);
        rx ??= ry;
        ry ??= rx;
        if (rx == null || ry == null || rx <= 0 || ry <= 0) {
          return Path()..addRect(rect);
        }
        return Path()..addRRect(
          RRect.fromRectXY(rect, math.min(rx, w / 2), math.min(ry, h / 2)),
        );
      case 'circle':
        final r = n('r');
        if (r <= 0) {
          return null;
        }
        return Path()..addOval(
          Rect.fromCircle(center: Offset(n('cx'), n('cy')), radius: r),
        );
      case 'ellipse':
        final rx = n('rx');
        final ry = n('ry');
        if (rx <= 0 || ry <= 0) {
          return null;
        }
        return Path()..addOval(
          Rect.fromCenter(
            center: Offset(n('cx'), n('cy')),
            width: rx * 2,
            height: ry * 2,
          ),
        );
      case 'line':
        return Path()
          ..moveTo(n('x1'), n('y1'))
          ..lineTo(n('x2'), n('y2'));
      case 'polyline' || 'polygon':
        final v = _numbers(p['points'] ?? '');
        if (v.length < 4) {
          return null;
        }
        return Path()..addPolygon([
          for (var i = 0; i + 1 < v.length; i += 2) Offset(v[i], v[i + 1]),
        ], name == 'polygon');
    }
    return null;
  }

  void _addShape(Path raw, _Style style) {
    final path = style.transform.isIdentity
        ? raw
        : raw.transform(style.transform.toMatrix4());
    path.fillType = style.evenOdd ? PathFillType.evenOdd : PathFillType.nonZero;
    _shapes.add(
      SvgShape(
        path: path,
        fill: style.fill,
        stroke: style.stroke,
        strokeWidth: style.strokeWidth * style.transform.scale,
        opacity: style.opacity,
        fillOpacity: style.fillOpacity,
        strokeOpacity: style.strokeOpacity,
        strokeCap: style.cap,
        strokeJoin: style.join,
      ),
    );
  }

  static List<double> _numbers(String text) => [
    for (final m in _numberPattern.allMatches(text)) double.parse(m.group(0)!),
  ];

  static double? _length(String? raw) {
    if (raw == null) {
      return null;
    }
    final v = raw.trim();
    if (v.endsWith('%')) {
      return null;
    }
    final m = _numberPattern.matchAsPrefix(v);
    return m == null ? null : double.parse(m.group(0)!);
  }

  static double _parseOpacity(String? raw) {
    if (raw == null) {
      return 1;
    }
    final v = raw.trim();
    final m = _numberPattern.matchAsPrefix(v);
    if (m == null) {
      return 1;
    }
    final n = double.parse(m.group(0)!);
    return (v.endsWith('%') ? n / 100 : n).clamp(0.0, 1.0);
  }

  static _Affine _parseTransform(String text) {
    var result = _Affine.identity;
    for (final m in _transformPattern.allMatches(text)) {
      final v = _numbers(m.group(2)!);
      double at(int i, [double fallback = 0]) => i < v.length ? v[i] : fallback;
      final next = switch (m.group(1)) {
        'matrix' when v.length >= 6 => _Affine(
          v[0],
          v[1],
          v[2],
          v[3],
          v[4],
          v[5],
        ),
        'translate' => _Affine(1, 0, 0, 1, at(0), at(1)),
        'scale' => _Affine(at(0, 1), 0, 0, at(1, at(0, 1)), 0, 0),
        'rotate' => _rotate(at(0), at(1), at(2)),
        'skewX' => _Affine(1, 0, math.tan(at(0) * math.pi / 180), 1, 0, 0),
        'skewY' => _Affine(1, math.tan(at(0) * math.pi / 180), 0, 1, 0, 0),
        _ => _Affine.identity,
      };
      result = result * next;
    }
    return result;
  }

  static _Affine _rotate(double degrees, double cx, double cy) {
    final r = degrees * math.pi / 180;
    final cos = math.cos(r);
    final sin = math.sin(r);
    final rotation = _Affine(cos, sin, -sin, cos, 0, 0);
    if (cx == 0 && cy == 0) {
      return rotation;
    }
    return _Affine(1, 0, 0, 1, cx, cy) *
        rotation *
        _Affine(1, 0, 0, 1, -cx, -cy);
  }

  static Color? _parseColor(String raw) {
    final v = raw.trim().toLowerCase();
    if (v.startsWith('#')) {
      var hex = v.substring(1);
      if (hex.length == 3 || hex.length == 4) {
        hex = hex.split('').map((c) => '$c$c').join();
      }
      final value = int.tryParse(hex, radix: 16);
      if (value == null) {
        return null;
      }
      if (hex.length == 6) {
        return Color(0xFF000000 | value);
      }
      if (hex.length == 8) {
        return Color(((value & 0xFF) << 24) | (value >> 8));
      }
      return null;
    }
    if (v.startsWith('rgb')) {
      final open = v.indexOf('(');
      final close = v.lastIndexOf(')');
      if (open < 0 || close <= open) {
        return null;
      }
      final parts = v
          .substring(open + 1, close)
          .split(RegExp(r'[\s,/]+'))
          .where((s) => s.isNotEmpty)
          .toList();
      if (parts.length < 3) {
        return null;
      }
      double channel(String s) {
        final n = double.tryParse(s.replaceAll('%', '')) ?? 0;
        return (s.endsWith('%') ? n / 100 : n / 255).clamp(0.0, 1.0);
      }

      final alpha = parts.length > 3 ? _parseOpacity(parts[3]) : 1.0;
      return Color.from(
        alpha: alpha,
        red: channel(parts[0]),
        green: channel(parts[1]),
        blue: channel(parts[2]),
      );
    }
    final named = _namedColors[v];
    return named == null ? null : Color(named);
  }
}

(Rect, List<SvgShape>) parseSvgDocument(String source) =>
    _Parser(source).parse();
