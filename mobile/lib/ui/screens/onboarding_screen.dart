import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../widgets/common.dart';

/// Three swipeable pages: the idea, how it works, and what happens to answers.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pages = PageController();
  int _page = 0;

  static const _content = [
    (
      title: 'Rank anything,\ntwo at a time.',
      body: 'Films, footballers, food, songs. Answer one question over and over: this one, or that one?',
      a: ('🎬', Color(0xFFFF5D5D)),
      b: ('🍜', Color(0xFFFF8A3D)),
    ),
    (
      title: 'A few dozen taps.\nA ranking you trust.',
      body: 'A proper statistical model fits every answer together, and always asks the question it is least sure about.',
      a: ('⚽', Color(0xFF22C55E)),
      b: ('🎸', Color(0xFFF59E0B)),
    ),
    (
      title: 'No sign-up.\nJust play.',
      body: 'Your answers stay anonymous and also count towards a community ranking for every topic.',
      a: ('🌍', Color(0xFF14B8A6)),
      b: ('📺', Color(0xFF7C5CFF)),
    ),
  ];

  void _finish() {
    ref.read(onboardedProvider.notifier).done();
    context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      body: Aurora(
        child: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
              child: Row(children: [
                const RankdMark(size: 32),
                const SizedBox(width: 10),
                Text('Rankd', style: context.t.titleLarge),
                const Spacer(),
                TextButton(onPressed: _finish, child: Text('Skip', style: TextStyle(color: c.muted, fontWeight: FontWeight.w600))),
              ]),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pages,
                itemCount: _content.length,
                onPageChanged: (p) => setState(() => _page = p),
                itemBuilder: (_, i) {
                  final p = _content[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(children: [
                      const Spacer(),
                      SizedBox(height: 300, child: _Duel(a: p.a, b: p.b)),
                      const Spacer(),
                      Text(p.title, style: context.t.displayMedium, textAlign: TextAlign.center),
                      const SizedBox(height: 14),
                      Text(p.body, style: context.t.bodyLarge?.copyWith(color: c.text2), textAlign: TextAlign.center),
                      const SizedBox(height: 28),
                    ]),
                  );
                },
              ),
            ),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 0; i < _content.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 240),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: i == _page ? 26 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    gradient: i == _page ? RankdColors.brandGradient : null,
                    color: i == _page ? null : c.border,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
            ]),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
              child: GradientButton(
                label: _page == _content.length - 1 ? 'Start ranking' : 'Next',
                icon: _page == _content.length - 1 ? Icons.bolt_rounded : null,
                onTap: () => _page == _content.length - 1
                    ? _finish()
                    : _pages.nextPage(duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Two tilted cards facing off, with a VS badge between them.
class _Duel extends StatelessWidget {
  const _Duel({required this.a, required this.b});

  final (String, Color) a;
  final (String, Color) b;

  @override
  Widget build(BuildContext context) {
    Widget card((String, Color) x, double angle, Offset offset) => Transform.translate(
          offset: offset,
          child: Transform.rotate(
            angle: angle,
            child: Container(
              width: 150,
              height: 206,
              decoration: BoxDecoration(
                gradient: topicGradient(x.$2),
                borderRadius: BorderRadius.circular(28),
                boxShadow: [BoxShadow(color: x.$2.withValues(alpha: .45), blurRadius: 40, offset: const Offset(0, 18))],
              ),
              alignment: Alignment.center,
              child: Text(x.$1, style: const TextStyle(fontSize: 72)),
            ),
          ),
        );
    return Stack(alignment: Alignment.center, children: [
      card(a, -.14, const Offset(-70, 0)),
      card(b, .12, const Offset(70, 14)),
      Container(
        width: 62,
        height: 62,
        decoration: BoxDecoration(
          color: context.c.surface,
          shape: BoxShape.circle,
          border: Border.all(color: context.c.border, width: 1.5),
          boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 24, offset: Offset(0, 10))],
        ),
        alignment: Alignment.center,
        child: ShaderMask(
          shaderCallback: (r) => RankdColors.brandGradient.createShader(r),
          child: const Text('VS', style: TextStyle(fontFamily: display, fontWeight: FontWeight.w800, fontSize: 22, color: Colors.white)),
        ),
      ),
    ]);
  }
}
