# morph_logo

[![pub package](https://img.shields.io/pub/v/morph_logo.svg)](https://pub.dev/packages/morph_logo)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Animate any SVG logo out of dots. A swirling cloud appears, dots fly in and
draw every contour, the rest of the cloud pours into each shape in its own
colour, and the dots dissolve into the real logo. Made for splash screens.

| | |
| :---: | :---: |
| ![Join Tour logo assembling from dots](https://raw.githubusercontent.com/Vaache/morph_logo/main/doc/media/tour.gif) | ![Varordakan Tester logo assembling from dots](https://raw.githubusercontent.com/Vaache/morph_logo/main/doc/media/varordakan.gif) |
| Logo: [Join Tour](https://jointour.am/login) | Logo: [Varordakan Tester](https://varordakan.am) |

```dart
MorphLogo.sequence(
  logo: await SvgLogo.load('assets/logo.svg'),
  size: 180,
  onCompleted: () => router.replace(const HomeRoute()),
)
```

Pure `Canvas` circles on the [morph_orbs](https://pub.dev/packages/morph_orbs)
dot engine. No shaders, no `flutter_svg`, no other dependencies.

## Installation

```yaml
dependencies:
  morph_logo: ^0.1.1
```

```dart
import 'package:morph_logo/morph_logo.dart';
```

## Splash screen

```dart
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  late final Future<SvgLogo> _logo = SvgLogo.load('assets/logo.svg');

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFF6F4F0),
      child: Center(
        child: FutureBuilder(
          future: _logo,
          builder: (context, snapshot) => snapshot.hasData
              ? MorphLogo.sequence(
                  logo: snapshot.data!,
                  size: 180,
                  color: const Color(0xFF222223),
                  onCompleted: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const HomePage()),
                  ),
                )
              : const SizedBox.square(dimension: 180),
        ),
      ),
    );
  }
}
```

The OS splash runs before Flutter starts and can only show a static image.
Give it the same background colour and let `MorphLogo.sequence` take over on
your first Flutter screen.

## Stages

| Stage     | Shows                                                                 |
| --------- | --------------------------------------------------------------------- |
| `hidden`  | Nothing; the next stage bursts out of the centre                      |
| `dust`    | A slowly swirling, twinkling cloud of every dot the logo will use     |
| `orb`     | Any [morph_orbs](https://pub.dev/packages/morph_orbs) `MorphOrbVariant` |
| `outline` | Dots fly out of the cloud and draw each contour like a pen stroke     |
| `fill`    | The rest of the cloud pours into every filled shape, edge to core, each dot in its shape's colour |
| `solid`   | The dots dissolve into the real logo                                  |

The default `MorphLogoStep.splash` is `dust → outline → fill → solid`, about
3.5 s. Each step waits for its stage to finish, then for its `hold`. Write
your own:

```dart
MorphLogo.sequence(
  logo: logo,
  steps: const [
    MorphLogoStep(MorphLogoStage.orb, hold: Duration(milliseconds: 600)),
    MorphLogoStep(MorphLogoStage.outline, hold: Duration(milliseconds: 300)),
    MorphLogoStep(MorphLogoStage.fill),
    MorphLogoStep(MorphLogoStage.solid),
  ],
  speed: 1.3,
)
```

Or drive it yourself. `MorphLogo(logo: logo, stage: stage)` morphs from
wherever the dots are whenever `stage` changes, for example as loading
progresses.

## Customization

| Parameter                 | Effect                                                         |
| ------------------------- | -------------------------------------------------------------- |
| `color`                   | Ink for the cloud, the outline and `currentColor`; defaults to the ambient text colour |
| `useSvgColors`            | `false` draws fill dots and the final logo in `color`          |
| `speed`                   | Multiplier on every stage's tempo                              |
| `intensity`               | Multiplier on the swirl and the landing pop                    |
| `style.density`           | Multiplier on the number of dots                               |
| `style.dotScale`          | Multiplier on dot size                                         |
| `style.transitionDuration`, `style.transitionCurve` | The morph between stages             |
| `orbVariant`              | The orb drawn in the `orb` stage                               |
| `startDelay`              | Wait before the first step of a sequence                       |

Under reduced motion (`MediaQuery.disableAnimations`) a sequence jumps
straight to its last step.

## SVG support

`path` (every command, arcs included), `rect`, `circle`, `ellipse`, `line`,
`polyline`, `polygon`, nested groups with `transform`, inherited presentation
attributes, `style` attributes, simple `<style>` class rules, `currentColor`
and opacity.

Gradients fall back to the average of their stops for the dots and the final
logo. Clip paths, masks, filters, `text`, `use` and images are ignored:
convert text to outlines before exporting. Figma, Illustrator and most icon
sets export cleanly.

## Performance

One `Ticker` per logo, no widget rebuilds per frame, reused buffers. A
filled logo at 180–240 px is roughly 800–2000 dots while it animates; the
ticker stops once the real logo is on screen. Lower `style.density` for
low-end devices.

## Preview your logo

```bash
tool/render_logo.sh path/to/logo.svg my_logo FFF6F4F0 FF222223
```

Renders the default splash to `doc/media/my_logo.gif` (needs `ffmpeg`).

## License

MIT
