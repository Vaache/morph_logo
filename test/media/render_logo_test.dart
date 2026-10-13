import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph_logo/morph_logo.dart';

void main() {
  final svgPath = Platform.environment['LOGO_SVG'];
  final outDir = Platform.environment['LOGO_OUT'];
  final background = Color(
    int.parse(Platform.environment['LOGO_BG'] ?? 'FFF6F4F0', radix: 16),
  );
  final ink = Color(
    int.parse(Platform.environment['LOGO_INK'] ?? 'FF222223', radix: 16),
  );
  const fps = 30;
  const frame = Duration(microseconds: 1000000 ~/ fps);
  final key = GlobalKey();

  testWidgets('logo splash preview', (tester) async {
    final logo = SvgLogo.parse(File(svgPath!).readAsStringSync());
    final out = Directory(outDir!)..createSync(recursive: true);
    const side = 320.0;
    tester.view
      ..physicalSize = const Size(side, side)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var done = false;
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: ColoredBox(
          color: background,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: MorphLogo.sequence(
                logo: logo,
                size: 200,
                color: ink,
                startDelay: const Duration(milliseconds: 200),
                onCompleted: () => done = true,
              ),
            ),
          ),
        ),
      ),
    );
    var n = 0;
    var tail = 0;
    while (tail < fps && n < fps * 10) {
      await tester.pump(frame);
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await tester.runAsync(
        () => boundary.toImage(pixelRatio: 2),
      );
      final bytes = await tester.runAsync(
        () => image!.toByteData(format: ui.ImageByteFormat.png),
      );
      File(
        '${out.path}/${n.toString().padLeft(4, '0')}.png',
      ).writeAsBytesSync(bytes!.buffer.asUint8List());
      n++;
      if (done) {
        tail++;
      }
    }
  }, skip: svgPath == null || outDir == null);
}
