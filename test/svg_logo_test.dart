import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:morph_logo/morph_logo.dart';

const _appIcon = '''
<?xml version="1.0" encoding="UTF-8"?>
<!-- exported -->
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#6D5DFC"/>
      <stop offset="1" stop-color="#3B82F6"/>
    </linearGradient>
    <clipPath id="c"><rect width="10" height="10"/></clipPath>
  </defs>
  <rect width="1024" height="1024" rx="230" fill="url(#bg)"/>
  <g transform="translate(512 512)" fill="#fff">
    <path d="M-60-260L-200 40h150l-40 220L200-60H50l40-200z"/>
  </g>
</svg>
''';

const _strokeIcon = '''
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"
  fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <circle cx="12" cy="12" r="10"/>
  <polyline points="12 6 12 12 16 14"/>
</svg>
''';

void main() {
  group('SvgLogo.parse', () {
    test('reads viewBox, shapes, gradients and transforms', () {
      final icon = SvgLogo.parse(_appIcon);
      expect(icon.viewBox, const Rect.fromLTWH(0, 0, 1024, 1024));
      expect(icon.shapes, hasLength(2));
      final bg = icon.shapes.first;
      expect(bg.fill?.color, isNotNull);
      expect(bg.fill!.color!.b, greaterThan(bg.fill!.color!.g));
      final bolt = icon.shapes.last;
      expect(bolt.fill?.color, const Color(0xFFFFFFFF));
      final bounds = bolt.path.getBounds();
      expect(bounds.left, closeTo(312, 0.01));
      expect(bounds.top, closeTo(252, 0.01));
      expect(bounds.right, closeTo(712, 0.01));
    });

    test('inherits stroke paint and resolves currentColor', () {
      final icon = SvgLogo.parse(_strokeIcon);
      expect(icon.shapes, hasLength(2));
      for (final shape in icon.shapes) {
        expect(shape.fill, isNull);
        expect(shape.stroke?.isCurrentColor, isTrue);
        expect(shape.strokeWidth, 2);
        expect(shape.strokeCap, StrokeCap.round);
      }
    });

    test('applies css classes and inline styles', () {
      final icon = SvgLogo.parse('''
<svg viewBox="0 0 10 10"><style>.a{fill:#ff0000}.b{fill:none;stroke:#00f}</style>
<rect class="a" width="4" height="4"/>
<rect class="b" x="5" width="4" height="4" style="stroke-width:3"/>
<rect width="4" height="4" style="display:none"/>
</svg>''');
      expect(icon.shapes, hasLength(2));
      expect(icon.shapes[0].fill?.color, const Color(0xFFFF0000));
      expect(icon.shapes[1].fill, isNull);
      expect(icon.shapes[1].stroke?.color, const Color(0xFF0000FF));
      expect(icon.shapes[1].strokeWidth, 3);
    });

    test('parses compact path data with arcs and smooth curves', () {
      final icon = SvgLogo.pathData(
        'M2 12a10 10 0 1020 0A10 10 0 002 12zm5-1c1-2 3-2 4 0s3 2 4 0q1-2 2 0t2 0',
        viewBox: const Rect.fromLTWH(0, 0, 24, 24),
      );
      final bounds = icon.shapes.single.path.getBounds();
      expect(bounds.left, closeTo(2, 0.01));
      expect(bounds.right, closeTo(22, 0.01));
      expect(bounds.top, closeTo(2, 0.01));
      expect(bounds.bottom, closeTo(22, 0.01));
    });

    test('rejects documents without shapes', () {
      expect(
        () => SvgLogo.parse('<svg viewBox="0 0 1 1"><g/></svg>'),
        throwsFormatException,
      );
    });
  });

  group('outlinePoints', () {
    test('lays dots inside the unit square and caches by count', () {
      final icon = SvgLogo.parse(_appIcon);
      final points = icon.outlinePoints(200);
      expect(points, hasLength(400));
      for (final v in points) {
        expect(v, inInclusiveRange(-0.5, 0.5));
      }
      expect(identical(icon.outlinePoints(200), points), isTrue);
      expect(icon.outlineLength, greaterThan(3));
    });

    test('centres a non-square viewBox', () {
      final icon = SvgLogo.pathData(
        'M0 0H20V10H0Z',
        viewBox: const Rect.fromLTWH(0, 0, 20, 10),
      );
      final points = icon.outlinePoints(60);
      var minY = 1.0;
      var maxY = -1.0;
      for (var i = 1; i < points.length; i += 2) {
        minY = points[i] < minY ? points[i] : minY;
        maxY = points[i] > maxY ? points[i] : maxY;
      }
      expect(minY, closeTo(-0.25, 0.02));
      expect(maxY, closeTo(0.25, 0.02));
    });
  });

  group('dotLayout', () {
    test('adds coloured interior dots after the outline', () {
      final icon = SvgLogo.parse(_appIcon);
      final layout = icon.dotLayout(outlineCount: 300, spacing: 0.03);
      expect(layout.outlineCount, 300);
      expect(layout.interiorCount, greaterThan(300));
      for (var k = 0; k < layout.count; k++) {
        expect(layout.order[k], inInclusiveRange(0, 1));
        expect(layout.positions[k * 2], inInclusiveRange(-0.5, 0.5));
      }
      final last = layout.count - 1;
      expect(layout.tinted[last], 1);
      expect(
        identical(icon.dotLayout(outlineCount: 300, spacing: 0.03), layout),
        isTrue,
      );
    });

    test('stroke-only icons have no interior and no tint for currentColor', () {
      final icon = SvgLogo.parse(_strokeIcon);
      final layout = icon.dotLayout(outlineCount: 80, spacing: 0.03);
      expect(layout.interiorCount, 0);
      expect(layout.tinted.every((t) => t == 0), isTrue);
    });

    test('ignores svg colours on request', () {
      final icon = SvgLogo.parse(_appIcon);
      final layout = icon.dotLayout(
        outlineCount: 100,
        spacing: 0.05,
        useSvgColors: false,
      );
      expect(layout.tinted.every((t) => t == 0), isTrue);
    });
  });
}
