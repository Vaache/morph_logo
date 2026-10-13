/// Animate any SVG logo out of dots: a swirling cloud draws the outline,
/// pours into each shape in its own colour and dissolves into the real
/// logo. Made for splash screens.
///
/// ```dart
/// MorphLogo.sequence(
///   logo: await SvgLogo.load('assets/logo.svg'),
///   onCompleted: () => Navigator.of(context).pushReplacement(...),
/// )
/// ```
library;

export 'package:morph_orbs/morph_orbs.dart' show MorphOrbStyle, MorphOrbVariant;

export 'src/controllers/morph_logo_controller.dart';
export 'src/models/morph_logo_stage.dart';
export 'src/svg/svg_logo.dart' show SvgLogo, SvgShape, SvgInk, LogoDotLayout;
export 'src/widgets/morph_logo.dart';
