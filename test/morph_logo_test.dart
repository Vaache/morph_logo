import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph_logo/morph_logo.dart';
import 'package:morph_logo/src/painters/morph_logo_painter.dart';

final _icon = SvgLogo.pathData(
  'M4 4h16v16H4zM8 12l3 3 5-6',
  viewBox: const Rect.fromLTWH(0, 0, 24, 24),
  strokeWidth: 2,
);

final _filled = SvgLogo.parse('''
<svg viewBox="0 0 24 24">
  <rect width="24" height="24" rx="6" fill="#1C1C1E"/>
  <circle cx="12" cy="12" r="6" fill="#FFA41A"/>
</svg>''');

Widget _host(Widget child, {bool reduced = false}) => Directionality(
  textDirection: TextDirection.ltr,
  child: MediaQuery(
    data: MediaQueryData(disableAnimations: reduced),
    child: DefaultTextStyle(
      style: const TextStyle(color: Color(0xFF123456)),
      child: Center(child: child),
    ),
  ),
);

MorphLogoController _controllerOf(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(
    find.descendant(
      of: find.byType(MorphLogo),
      matching: find.byType(CustomPaint),
    ),
  );
  return (paint.painter! as MorphLogoPainter).controller;
}

void main() {
  group('MorphLogo', () {
    testWidgets('renders at the given size', (tester) async {
      await tester.pumpWidget(_host(MorphLogo(logo: _icon, size: 96)));
      expect(tester.getSize(find.byType(MorphLogo)), const Size.square(96));
      await tester.pumpAndSettle();
    });

    testWidgets('solid stage fades the icon in and stops ticking', (
      tester,
    ) async {
      await tester.pumpWidget(_host(MorphLogo(logo: _icon)));
      final controller = _controllerOf(tester);
      expect(controller.isTicking, isTrue);
      await tester.pumpAndSettle();
      expect(controller.isTicking, isFalse);
      expect(controller.solidOpacity, 1);
    });

    testWidgets('orb stage loops until moved to the icon', (tester) async {
      await tester.pumpWidget(
        _host(MorphLogo(logo: _icon, stage: MorphLogoStage.orb)),
      );
      final controller = _controllerOf(tester);
      await tester.pump(const Duration(seconds: 2));
      expect(controller.isTicking, isTrue);
      expect(controller.solidOpacity, 0);

      await tester.pumpWidget(
        _host(MorphLogo(logo: _icon, stage: MorphLogoStage.outline)),
      );
      expect(controller.isTransitioning, isTrue);
      await tester.pumpAndSettle();
      expect(controller.stage, MorphLogoStage.outline);
      expect(controller.isSettled, isTrue);
    });

    testWidgets('sequence walks every step and reports completion', (
      tester,
    ) async {
      var completed = 0;
      final seen = <MorphLogoStage>{};
      await tester.pumpWidget(
        _host(
          MorphLogo.sequence(
            logo: _icon,
            steps: const [
              MorphLogoStep(
                MorphLogoStage.dust,
                hold: Duration(milliseconds: 100),
              ),
              MorphLogoStep(
                MorphLogoStage.orb,
                variant: MorphOrbVariant.swarm,
                hold: Duration(milliseconds: 300),
              ),
              MorphLogoStep(MorphLogoStage.outline),
              MorphLogoStep(MorphLogoStage.fill),
              MorphLogoStep(MorphLogoStage.solid),
            ],
            onCompleted: () => completed++,
          ),
        ),
      );
      final controller = _controllerOf(tester);
      expect(controller.stage, MorphLogoStage.hidden);
      for (var i = 0; i < 160 && completed == 0; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        seen.add(controller.stage);
      }
      expect(seen, containsAll(MorphLogoStage.values.skip(1)));
      expect(completed, 1);
      expect(controller.solidOpacity, 1);
      await tester.pumpAndSettle();
      expect(completed, 1);
    });

    testWidgets('default splash goes dust → outline → fill → solid', (
      tester,
    ) async {
      var completed = false;
      final seen = <MorphLogoStage>[];
      await tester.pumpWidget(
        _host(
          MorphLogo.sequence(
            logo: _filled,
            onCompleted: () => completed = true,
          ),
        ),
      );
      final controller = _controllerOf(tester);
      for (var i = 0; i < 200 && !completed; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (seen.isEmpty || seen.last != controller.stage) {
          seen.add(controller.stage);
        }
      }
      expect(seen, [
        MorphLogoStage.dust,
        MorphLogoStage.outline,
        MorphLogoStage.fill,
        MorphLogoStage.solid,
      ]);
      expect(completed, isTrue);
      await tester.pumpAndSettle();
      expect(controller.isTicking, isFalse);
    });

    testWidgets('reduced motion jumps to the last step', (tester) async {
      var completed = false;
      await tester.pumpWidget(
        _host(
          MorphLogo.sequence(logo: _icon, onCompleted: () => completed = true),
          reduced: true,
        ),
      );
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 1));
      final controller = _controllerOf(tester);
      expect(controller.stage, MorphLogoStage.solid);
      expect(controller.isTicking, isFalse);
      expect(completed, isTrue);
    });

    testWidgets('disposing mid-sequence cancels the callback', (tester) async {
      var completed = false;
      await tester.pumpWidget(
        _host(
          MorphLogo.sequence(logo: _icon, onCompleted: () => completed = true),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpWidget(_host(const SizedBox()));
      await tester.pump(const Duration(seconds: 5));
      expect(completed, isFalse);
    });
  });
}
