import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../stages/logo_stages.dart';
import '../models/morph_logo_stage.dart';
import '../svg/svg_logo.dart';
import 'package:morph_orbs/engine.dart';
import 'package:morph_orbs/morph_orbs.dart';

class _ResolvedStage {
  const _ResolvedStage(this.stage, {this.orb, this.dots});

  final MorphLogoStage stage;
  final ResolvedOrbState? orb;
  final LogoStageGeometry? dots;
}

/// Drives one [MorphLogo]: a single ticker, the current stage and the morph
/// from the previous one. Listeners (the painter) are notified per frame;
/// nothing in the widget tree rebuilds. The ticker stops once a stage has
/// settled and nothing moves.
class MorphLogoController extends ChangeNotifier {
  MorphLogoController({
    required TickerProvider vsync,
    required SvgLogo logo,
    MorphLogoStage stage = MorphLogoStage.solid,
    MorphOrbVariant orbVariant = MorphOrbVariant.globe,
    double size = 120,
    MorphOrbStyle style = const MorphOrbStyle(),
    Color fallbackColor = const Color(0xFFFFFFFF),
    double speed = 1,
    double intensity = 1,
    bool useSvgColors = true,
    bool reducedMotion = false,
  }) : _logo = logo,
       _stage = stage,
       _variant = orbVariant,
       _size = size,
       _style = style,
       _fallbackColor = fallbackColor,
       _speed = speed,
       _intensity = intensity,
       _useSvgColors = useSvgColors,
       _reducedMotion = reducedMotion {
    _ticker = vsync.createTicker(_onTick);
    _current = _resolve(stage, orbVariant);
    _ensureTicking();
  }

  late final Ticker _ticker;

  SvgLogo _logo;
  MorphLogoStage _stage;
  MorphOrbVariant _variant;
  MorphLogoStage? _previousStage;
  MorphOrbVariant? _previousVariant;
  late _ResolvedStage _current;
  _ResolvedStage? _previous;

  double _size;
  MorphOrbStyle _style;
  Color _fallbackColor;
  double _speed;
  double _intensity;
  bool _useSvgColors;
  bool _reducedMotion;
  LogoDotLayout? _layout;

  double _clock = 0;
  double _clockAtStart = 0;
  double _stageEnteredAt = 0;
  double _previousEnteredAt = 0;
  double _transitionStartedAt = 0;
  bool _fromSnapshot = false;
  bool _disposed = false;
  double _solid = 0;
  double _snapshotSolid = 0;
  final List<Completer<void>> _settleWaiters = [];

  final OrbFrame _fromFrame = OrbFrame();
  final OrbFrame _toFrame = OrbFrame();
  final OrbFrame _outFrame = OrbFrame();
  final OrbFrame _snapshot = OrbFrame();

  /// The logo being assembled.
  SvgLogo get logo => _logo;

  /// The stage being shown or morphed into.
  MorphLogoStage get stage => _stage;

  /// The orb drawn in [MorphLogoStage.orb].
  MorphOrbVariant get orbVariant => _variant;
  double get size => _size;
  MorphOrbStyle get style => _style;
  bool get useSvgColors => _useSvgColors;
  bool get reducedMotion => _reducedMotion;

  /// Whether the ticker is running.
  bool get isTicking => _ticker.isActive;

  /// Whether a morph between two stages is in progress.
  bool get isTransitioning => _previous != null;

  /// How far the real logo has faded in, 0..1, as of the last [render].
  double get solidOpacity => _solid;

  /// Eased 0..1 progress of the current morph; 1 when none runs.
  double get transitionProgress {
    if (_previous == null) {
      return 1;
    }
    final seconds = _transitionSeconds;
    if (seconds <= 0) {
      return 1;
    }
    return _style.transitionCurve.transform(
      clamp01((_clock - _transitionStartedAt) / seconds),
    );
  }

  /// How long the current stage takes to finish animating: at least the
  /// transition, longer when the stage's own animation outlasts it.
  Duration get stageDuration {
    if (_reducedMotion) {
      return Duration.zero;
    }
    final settle = (_current.dots?.settleTime(_dotLayout) ?? 0) / _speed;
    final seconds = math.max(_transitionSeconds, settle);
    return Duration(microseconds: (seconds * 1e6).round());
  }

  /// Whether the morph is over and the current stage has finished its own
  /// animation. Looping stages count as settled once the morph is over.
  bool get isSettled {
    if (_previous != null) {
      return false;
    }
    if (_reducedMotion) {
      return true;
    }
    final geometry = _current.dots;
    if (geometry == null) {
      return true;
    }
    return _localTime * _speed >= geometry.settleTime(_dotLayout);
  }

  double get _transitionSeconds =>
      _style.transitionDuration.inMicroseconds / 1e6;

  double get _localTime => _clock - _stageEnteredAt;

  double get _dotRadius =>
      math.max(0.55, _size * 0.0085) * math.max(0.1, _style.dotScale);

  LogoDotLayout get _dotLayout {
    final cached = _layout;
    if (cached != null) {
      return cached;
    }
    final density = math.max(0.1, _style.density);
    final outline = (_logo.outlineLength * _size / (_dotRadius * 2.8) * density)
        .round()
        .clamp(24, 2000);
    final spacing = _dotRadius * 2.5 / _size / math.sqrt(density);
    return _layout = _logo.dotLayout(
      outlineCount: outline,
      spacing: spacing,
      useSvgColors: _useSvgColors,
    );
  }

  /// Moves to [next], morphing from wherever the dots are now.
  void setStage(MorphLogoStage next, {MorphOrbVariant? variant}) {
    final nextVariant = variant ?? _variant;
    if (next == _stage &&
        (next != MorphLogoStage.orb || nextVariant == _variant)) {
      _variant = nextVariant;
      return;
    }
    _retarget(next, nextVariant);
  }

  /// Completes once [isSettled] is true, or when the controller is disposed.
  Future<void> whenSettled() {
    if (isSettled || _disposed) {
      return Future.value();
    }
    final waiter = Completer<void>();
    _settleWaiters.add(waiter);
    _ensureTicking();
    return waiter.future;
  }

  void _retarget(MorphLogoStage stage, MorphOrbVariant variant) {
    if (_previous != null) {
      _snapshot.copyFrom(_outFrame);
      _snapshotSolid = _solid;
      _fromSnapshot = true;
    } else {
      _fromSnapshot = false;
    }
    _previous = _current;
    _previousStage = _stage;
    _previousVariant = _variant;
    _previousEnteredAt = _stageEnteredAt;
    _stage = stage;
    _variant = variant;
    _current = _resolve(stage, variant, from: _previousStage);
    _stageEnteredAt = _clock;
    _transitionStartedAt = _clock;
    if (_reducedMotion) {
      _finishTransition();
    }
    _ensureTicking();
    notifyListeners();
  }

  /// Applies new settings; dot layouts are rebuilt only when the logo, size,
  /// colours, density, dot scale or transition change.
  void update({
    SvgLogo? logo,
    double? size,
    MorphOrbStyle? style,
    Color? fallbackColor,
    double? speed,
    double? intensity,
    bool? useSvgColors,
    bool? reducedMotion,
  }) {
    var changed = false;
    if (fallbackColor != null && fallbackColor != _fallbackColor) {
      _fallbackColor = fallbackColor;
      changed = true;
    }
    if (speed != null && speed != _speed) {
      _speed = speed;
      changed = true;
    }
    if (intensity != null && intensity != _intensity) {
      _intensity = intensity;
      changed = true;
    }
    final resolveAgain =
        (logo != null && !identical(logo, _logo)) ||
        (size != null && size != _size) ||
        (useSvgColors != null && useSvgColors != _useSvgColors) ||
        (style != null &&
            (style.density != _style.density ||
                style.dotScale != _style.dotScale ||
                style.transitionDuration != _style.transitionDuration));
    if (logo != null) {
      _logo = logo;
    }
    if (size != null) {
      _size = size;
    }
    if (useSvgColors != null) {
      _useSvgColors = useSvgColors;
    }
    if (style != null && style != _style) {
      _style = style;
      changed = true;
    }
    if (resolveAgain) {
      _resolveAll();
      changed = true;
    }
    if (reducedMotion != null && reducedMotion != _reducedMotion) {
      _reducedMotion = reducedMotion;
      if (reducedMotion) {
        _finishTransition();
      }
      changed = true;
    }
    if (changed) {
      _ensureTicking();
      notifyListeners();
    }
  }

  /// The ink for this frame.
  Color inkColor() => _style.color ?? _fallbackColor;

  /// Builds the dots to draw now for a logo of [size]. The frame is a reused
  /// buffer, valid until the next call.
  OrbFrame render(double size) {
    if (size != _size) {
      _size = size;
      _resolveAll();
    }
    _buildFrame(_current, _stageEnteredAt, _toFrame);
    final toSolid = _solidOf(_current, _stageEnteredAt);
    final previous = _previous;
    if (previous == null) {
      _outFrame.copyFrom(_toFrame);
      _solid = toSolid;
    } else {
      final progress = transitionProgress;
      if (progress >= 1) {
        _finishTransition();
        _outFrame.copyFrom(_toFrame);
        _solid = toSolid;
      } else {
        final double fromSolid;
        if (_fromSnapshot) {
          _fromFrame.copyFrom(_snapshot);
          fromSolid = _snapshotSolid;
        } else {
          _buildFrame(previous, _previousEnteredAt, _fromFrame);
          fromSolid = _solidOf(previous, _previousEnteredAt);
        }
        OrbFrame.blend(_fromFrame, _toFrame, progress, _outFrame);
        _solid = lerp(fromSolid, toSolid, progress);
      }
    }
    _outFrame.sortByDepth();
    return _outFrame;
  }

  double _localFor(double enteredAt) =>
      _reducedMotion ? 1e3 : (_clock - enteredAt) * _speed;

  double get _sharedClock =>
      _reducedMotion ? kReducedMotionInstant : _clock * _speed;

  double _solidOf(_ResolvedStage resolved, double enteredAt) =>
      resolved.dots?.solidAt(_localFor(enteredAt)) ?? 0;

  void _buildFrame(_ResolvedStage resolved, double enteredAt, OrbFrame out) {
    final dots = resolved.dots;
    if (dots != null) {
      dots.build(
        out,
        LogoStageContext(
          size: _size,
          layout: _dotLayout,
          dotRadius: _dotRadius,
          fillRadius:
              _dotRadius *
              2.5 *
              0.47 /
              math.sqrt(math.max(0.1, _style.density)),
          intensity: _intensity,
        ),
        _sharedClock,
        _localFor(enteredAt),
      );
      return;
    }
    final orb = resolved.orb!;
    final t = _reducedMotion
        ? kReducedMotionInstant
        : _clock * orb.profile.speed * _speed;
    orb.geometry.build(out, _size, t, orb.profile, _intensity);
  }

  void _resolveAll() {
    _layout = null;
    _current = _resolve(_stage, _variant, from: _previousStage);
    final previousStage = _previousStage;
    if (previousStage != null && !_fromSnapshot) {
      _previous = _resolve(previousStage, _previousVariant ?? _variant);
    }
  }

  _ResolvedStage _resolve(
    MorphLogoStage stage,
    MorphOrbVariant variant, {
    MorphLogoStage? from,
  }) => switch (stage) {
    MorphLogoStage.hidden => const _ResolvedStage(
      MorphLogoStage.hidden,
      dots: LogoHiddenStage(),
    ),
    MorphLogoStage.dust => const _ResolvedStage(
      MorphLogoStage.dust,
      dots: LogoDustStage(),
    ),
    MorphLogoStage.orb => _ResolvedStage(
      stage,
      orb: resolveOrbState(
        MorphOrbState.thinking,
        _size,
        variant: variant,
        density: _style.density,
        dotScale: _style.dotScale,
      ),
    ),
    MorphLogoStage.outline => const _ResolvedStage(
      MorphLogoStage.outline,
      dots: LogoOutlineStage(),
    ),
    MorphLogoStage.fill => const _ResolvedStage(
      MorphLogoStage.fill,
      dots: LogoFillStage(),
    ),
    MorphLogoStage.solid => _ResolvedStage(
      stage,
      dots: LogoSolidStage(
        delay: from != null && from.isLogoShaped
            ? 0.12
            : _transitionSeconds * 0.8,
      ),
    ),
  };

  void _finishTransition() {
    _previous = null;
    _previousStage = null;
    _previousVariant = null;
    _fromSnapshot = false;
  }

  bool get _needsTicking {
    if (_reducedMotion) {
      return false;
    }
    if (_previous != null) {
      return true;
    }
    final dots = _current.dots;
    if (dots == null) {
      return true;
    }
    return dots.isAnimatingAt(_localTime * _speed, _dotLayout);
  }

  void _ensureTicking() {
    if (_disposed) {
      return;
    }
    final needs = _needsTicking;
    if (needs && !_ticker.isActive) {
      _clockAtStart = _clock;
      _ticker.start();
    } else if (!needs && _ticker.isActive) {
      _ticker.stop();
    }
    _releaseSettled();
  }

  void _releaseSettled() {
    if (_settleWaiters.isEmpty || !(isSettled || _disposed)) {
      return;
    }
    final waiters = List.of(_settleWaiters);
    _settleWaiters.clear();
    for (final waiter in waiters) {
      waiter.complete();
    }
  }

  void _onTick(Duration sinceStart) {
    _clock = _clockAtStart + sinceStart.inMicroseconds / 1e6;
    if (_previous != null && transitionProgress >= 1) {
      _finishTransition();
    }
    notifyListeners();
    if (!_needsTicking) {
      _ticker.stop();
    }
    _releaseSettled();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker.dispose();
    _releaseSettled();
    super.dispose();
  }
}
