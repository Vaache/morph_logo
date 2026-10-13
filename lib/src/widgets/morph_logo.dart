import 'dart:async';

import 'package:flutter/widgets.dart';

import '../controllers/morph_logo_controller.dart';
import '../models/morph_logo_stage.dart';
import '../painters/morph_logo_painter.dart';
import '../svg/svg_logo.dart';
import 'package:morph_orbs/morph_orbs.dart';

/// An SVG logo built out of dots.
///
/// Use [MorphLogo.sequence] for a splash screen: it plays every step and
/// calls [onCompleted] once the real logo is on screen.
///
/// ```dart
/// MorphLogo.sequence(
///   logo: logo,
///   size: 180,
///   onCompleted: () => router.replace(const HomeRoute()),
/// )
/// ```
///
/// Or drive the stage yourself with [MorphLogo.new]: changing [stage] morphs
/// from wherever the dots are.
class MorphLogo extends StatefulWidget {
  /// Shows [stage], morphing whenever it changes.
  const MorphLogo({
    super.key,
    required this.logo,
    this.stage = MorphLogoStage.solid,
    this.orbVariant = MorphOrbVariant.globe,
    this.size = 120,
    this.color,
    this.style = const MorphOrbStyle(),
    this.speed = 1,
    this.intensity = 1,
    this.useSvgColors = true,
    this.semanticsLabel,
    this.excludeFromSemantics = false,
  }) : steps = null,
       onCompleted = null,
       startDelay = Duration.zero,
       overlap = 0,
       assert(size > 0, 'size must be positive'),
       assert(speed > 0, 'speed must be positive'),
       assert(intensity >= 0, 'intensity must not be negative');

  /// Plays [steps] from [stage] (hidden by default) after [startDelay], then
  /// calls [onCompleted]. Each step waits for its stage to finish animating,
  /// then for its hold. Under reduced motion it jumps to the last step.
  const MorphLogo.sequence({
    super.key,
    required this.logo,
    List<MorphLogoStep> this.steps = MorphLogoStep.splash,
    this.onCompleted,
    this.startDelay = Duration.zero,
    this.stage = MorphLogoStage.hidden,
    this.orbVariant = MorphOrbVariant.globe,
    this.size = 120,
    this.color,
    this.style = const MorphOrbStyle(),
    this.speed = 1,
    this.intensity = 1,
    this.useSvgColors = true,
    this.semanticsLabel,
    this.excludeFromSemantics = false,
    this.overlap = 0,
  }) : assert(size > 0, 'size must be positive'),
       assert(speed > 0, 'speed must be positive'),
       assert(intensity >= 0, 'intensity must not be negative'),
       assert(overlap >= 0 && overlap < 1, 'overlap must be in [0, 1)');

  /// The logo to assemble.
  final SvgLogo logo;

  /// The stage to show; the starting stage for [MorphLogo.sequence].
  final MorphLogoStage stage;

  /// The orb drawn in [MorphLogoStage.orb].
  final MorphOrbVariant orbVariant;

  /// The steps [MorphLogo.sequence] plays; null for a manually driven logo.
  final List<MorphLogoStep>? steps;

  /// Called once, after the last step has settled and held.
  final VoidCallback? onCompleted;

  /// Wait before the first step, for example while the first frame settles.
  final Duration startDelay;

  /// Side of the square the logo is drawn in, in logical pixels.
  final double size;

  /// Ink for the cloud and the outline, and for `currentColor`. Defaults to
  /// the ambient text colour.
  final Color? color;

  /// Transition duration and curve, dot density and dot scale.
  final MorphOrbStyle style;

  /// Multiplier on every stage's tempo.
  final double speed;

  /// Multiplier on the swirl, the landing pop and orb deformation.
  final double intensity;

  /// Whether fill dots and the final logo use the SVG's own colours; when
  /// false everything is drawn in [color].
  final bool useSvgColors;

  /// Read by screen readers, for example the app's name.
  final String? semanticsLabel;

  /// Hides the logo from screen readers.
  final bool excludeFromSemantics;

  /// How much of each step's stage the next step cuts into, from 0 (each
  /// stage settles before the next starts) to just under 1. The dots morph
  /// on from wherever they are, so steps blend instead of pausing.
  final double overlap;

  @override
  State<MorphLogo> createState() => _MorphLogoState();
}

class _MorphLogoState extends State<MorphLogo>
    with SingleTickerProviderStateMixin {
  late final MorphLogoController _controller;
  Timer? _timer;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = MorphLogoController(
      vsync: this,
      logo: widget.logo,
      stage: widget.stage,
      orbVariant: widget.orbVariant,
      size: widget.size,
      style: _effectiveStyle,
      speed: widget.speed,
      intensity: widget.intensity,
      useSvgColors: widget.useSvgColors,
    );
  }

  MorphOrbStyle get _effectiveStyle => widget.color == null
      ? widget.style
      : widget.style.copyWith(color: widget.color);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.update(
      fallbackColor: _ambientColor(context),
      reducedMotion: MediaQuery.maybeDisableAnimationsOf(context) ?? false,
    );
    if (!_started && widget.steps != null) {
      _started = true;
      _timer = Timer(widget.startDelay, _start);
    }
  }

  @override
  void didUpdateWidget(MorphLogo oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.update(
      logo: widget.logo,
      size: widget.size,
      style: _effectiveStyle,
      speed: widget.speed,
      intensity: widget.intensity,
      useSvgColors: widget.useSvgColors,
    );
    if (widget.steps == null &&
        (widget.stage != oldWidget.stage ||
            widget.orbVariant != oldWidget.orbVariant)) {
      _timer?.cancel();
      _controller.setStage(widget.stage, variant: widget.orbVariant);
    }
  }

  void _start() {
    final steps = widget.steps;
    if (!mounted || steps == null || steps.isEmpty) {
      _complete();
      return;
    }
    if (_controller.reducedMotion) {
      final last = steps.last;
      _controller.setStage(last.stage, variant: last.variant);
      _timer = Timer(last.hold, _complete);
      return;
    }
    _runStep(steps, 0);
  }

  void _runStep(List<MorphLogoStep> steps, int index) {
    if (!mounted) {
      return;
    }
    final step = steps[index];
    _controller.setStage(step.stage, variant: step.variant);
    final isLast = index + 1 == steps.length;
    final share = isLast ? 1.0 : 1 - widget.overlap;
    final wait = _controller.stageDuration * share + step.hold;
    _timer = Timer(wait, () {
      if (index + 1 < steps.length) {
        _runStep(steps, index + 1);
      } else {
        _controller.whenSettled().then((_) => _complete());
      }
    });
  }

  void _complete() {
    if (mounted) {
      widget.onCompleted?.call();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logo = RepaintBoundary(
      child: CustomPaint(
        size: Size.square(widget.size),
        isComplex: true,
        painter: MorphLogoPainter(
          controller: _controller,
          useSvgColors: widget.useSvgColors,
        ),
      ),
    );
    if (widget.excludeFromSemantics) {
      return ExcludeSemantics(child: logo);
    }
    return Semantics(label: widget.semanticsLabel, image: true, child: logo);
  }

  static Color _ambientColor(BuildContext context) {
    final text = DefaultTextStyle.of(context).style.color;
    if (text != null) {
      return text;
    }
    final icon = IconTheme.of(context).color;
    if (icon != null) {
      return icon;
    }
    final dark =
        MediaQuery.maybePlatformBrightnessOf(context) == Brightness.dark;
    return dark ? const Color(0xFFFFFFFF) : const Color(0xFF171717);
  }
}
