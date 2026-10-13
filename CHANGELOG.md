## 0.1.0

Initial release.

- `MorphLogo` assembles any SVG logo out of dots: a swirling cloud draws
  every contour, pours into each shape in its own colour and dissolves into
  the real logo.
- Stages `hidden`, `dust`, `orb`, `outline`, `fill` and `solid`; any two morph
  dot-for-dot, interruptible mid-way.
- `MorphLogo.sequence` plays configurable `MorphLogoStep`s, waits for each
  stage to finish and reports `onCompleted`, for splash screens.
- `SvgLogo` parses SVG markup, path data or assets with no extra
  dependencies.
- Reduced-motion support, one ticker per logo, no per-frame widget rebuilds.
