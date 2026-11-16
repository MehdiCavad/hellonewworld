import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../theme/theme.dart';
import '../widgets/common.dart';

/// Hosts the three tabs under a floating glass navigation bar.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  static const _tabs = [
    (icon: Icons.bolt_rounded, label: 'Play'),
    (icon: Icons.public_rounded, label: 'Community'),
    (icon: Icons.history_rounded, label: 'History'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      extendBody: true,
      body: shell,
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 0, 20, 14),
        child: Glass(
          radius: 28,
          padding: const EdgeInsets.all(6),
          child: Row(children: [
            for (final (i, tab) in _tabs.indexed)
              Expanded(
                child: Pressable(
                  semanticLabel: tab.label,
                  onTap: () => shell.goBranch(i, initialLocation: i == shell.currentIndex),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: i == shell.currentIndex ? RankdColors.brandGradient : null,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(tab.icon, size: 21, color: i == shell.currentIndex ? Colors.white : c.muted),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic,
                        child: i == shell.currentIndex
                            ? Padding(
                                padding: const EdgeInsets.only(left: 7),
                                child: Text(tab.label,
                                    style: const TextStyle(fontFamily: body, fontWeight: FontWeight.w700, fontSize: 14, color: Colors.white)),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
