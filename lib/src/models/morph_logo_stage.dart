import 'package:flutter/foundation.dart';
import 'package:morph_orbs/morph_orbs.dart';

/// What a [MorphLogo] shows. Moving between any two stages is a dot-for-dot
/// morph.
enum MorphLogoStage {
  /// Nothing; the next stage bursts out of the centre.
  hidden,

  /// A slowly swirling, twinkling cloud of every dot the logo will use.
  dust,

  /// A `morph_orbs` orb in the chosen [MorphOrbVariant].
  orb,

  /// Dots fly out of the cloud and draw every contour like pen strokes;
  /// the rest of the cloud keeps swirling.
  outline,

  /// The rest of the cloud pours into each filled shape, edge to core, every
  /// dot taking its shape's colour.
  fill,

  /// The dots dissolve into the real logo.
  solid;

  /// Whether the dots already sit on the logo.
  bool get isLogoShaped => this == outline || this == fill || this == solid;
}

@immutable
/// One step of [MorphLogo.sequence]: a stage, and how long to hold it once
/// its animation has finished.
class MorphLogoStep {
  const MorphLogoStep(this.stage, {this.hold = Duration.zero, this.variant});

  /// The stage to move to.
  final MorphLogoStage stage;

  /// Extra time to stay after the stage has finished animating.
  final Duration hold;

  /// The orb to show in [MorphLogoStage.orb]; ignored by other stages.
  final MorphOrbVariant? variant;

  /// dust → outline → fill → solid, about 3.5 s: the default splash.
  static const List<MorphLogoStep> splash = [
    MorphLogoStep(MorphLogoStage.dust, hold: Duration(milliseconds: 150)),
    MorphLogoStep(MorphLogoStage.outline, hold: Duration(milliseconds: 100)),
    MorphLogoStep(MorphLogoStage.fill, hold: Duration(milliseconds: 100)),
    MorphLogoStep(MorphLogoStage.solid),
  ];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MorphLogoStep &&
          other.stage == stage &&
          other.hold == hold &&
          other.variant == variant;

  @override
  int get hashCode => Object.hash(stage, hold, variant);
}
