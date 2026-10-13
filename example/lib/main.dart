import 'package:flutter/material.dart';
import 'package:morph_logo/morph_logo.dart';

const _logo = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 120">
  <rect x="4" y="4" width="112" height="112" rx="28" fill="#1C1C1E"/>
  <path d="M68 18L32 66h24l-6 36 38-50H64z" fill="#FFB020"/>
</svg>
''';

void main() => runApp(const SplashDemoApp());

class SplashDemoApp extends StatelessWidget {
  const SplashDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'morph_logo',
      theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      home: const SplashDemoPage(),
    );
  }
}

class SplashDemoPage extends StatefulWidget {
  const SplashDemoPage({super.key});

  @override
  State<SplashDemoPage> createState() => _SplashDemoPageState();
}

class _SplashDemoPageState extends State<SplashDemoPage> {
  final SvgLogo _mark = SvgLogo.parse(_logo);
  int _run = 0;
  bool _done = false;
  bool _throughOrb = false;

  List<MorphLogoStep> get _steps => _throughOrb
      ? const [
          MorphLogoStep(MorphLogoStage.orb, hold: Duration(milliseconds: 600)),
          MorphLogoStep(MorphLogoStage.outline),
          MorphLogoStep(MorphLogoStage.fill),
          MorphLogoStep(MorphLogoStage.solid),
        ]
      : MorphLogoStep.splash;

  void _replay() => setState(() {
    _run++;
    _done = false;
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('morph_logo')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MorphLogo.sequence(
              key: ValueKey(_run),
              logo: _mark,
              size: 180,
              steps: _steps,
              startDelay: const Duration(milliseconds: 200),
              onCompleted: () => setState(() => _done = true),
            ),
            const SizedBox(height: 24),
            Text(_done ? 'onCompleted fired' : 'playing…'),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Start from an orb'),
              value: _throughOrb,
              onChanged: (v) {
                _throughOrb = v;
                _replay();
              },
            ),
            FilledButton.tonal(onPressed: _replay, child: const Text('Replay')),
          ],
        ),
      ),
    );
  }
}
