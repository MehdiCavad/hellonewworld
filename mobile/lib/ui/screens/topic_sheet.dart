import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/models.dart';
import '../../engine/ranking_engine.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../widgets/common.dart';

Future<void> showTopicSheet(BuildContext context, Topic topic) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true, // above the floating tab bar
      builder: (_) => TopicSheet(topic: topic),
    );

/// Choose a level and a style, then start.
class TopicSheet extends ConsumerStatefulWidget {
  const TopicSheet({super.key, required this.topic});
  final Topic topic;

  @override
  ConsumerState<TopicSheet> createState() => _TopicSheetState();
}

class _TopicSheetState extends ConsumerState<TopicSheet> {
  String _level = 'standard';
  PairingMode _mode = PairingMode.smart;
  bool _starting = false;

  Future<void> _start(Level level) async {
    setState(() => _starting = true);
    try {
      final session = await ref.read(sessionsProvider.notifier).start(widget.topic, level, _mode);
      if (!mounted) return;
      final router = GoRouter.of(context);
      Navigator.of(context).pop();
      router.push('/play/${session.id}');
    } catch (e) {
      if (mounted) {
        setState(() => _starting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not start: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = widget.topic;
    final levels = ref.watch(levelsProvider).value ?? const <Level>[];
    final selected = levels.where((l) => l.id == _level).firstOrNull ?? levels.firstOrNull;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.paddingOf(context).bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(gradient: topicGradient(t.accent), borderRadius: BorderRadius.circular(20)),
            alignment: Alignment.center,
            child: Text(t.emoji, style: const TextStyle(fontSize: 34)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.name, style: context.t.displaySmall),
              const SizedBox(height: 2),
              Text(t.description, style: context.t.bodyMedium),
            ]),
          ),
        ]),
        const SizedBox(height: 26),
        Text('How deep?', style: context.t.titleMedium),
        const SizedBox(height: 12),
        if (levels.isEmpty)
          const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
        else
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.55,
            children: [
              for (final l in levels)
                _Choice(
                  selected: l.id == selected?.id,
                  accent: t.accent,
                  onTap: () => setState(() => _level = l.id),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text(l.emoji, style: const TextStyle(fontSize: 22)),
                      const Spacer(),
                      if (l.id == selected?.id) Icon(Icons.check_circle_rounded, color: t.accent, size: 20),
                    ]),
                    const Spacer(),
                    Text(l.name, style: context.t.titleMedium),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text('${t.countFor(l)} options · ~${roundsFor(l.roundBudget, t.countFor(l))} taps', style: context.t.bodySmall),
                    ),
                  ]),
                ),
            ],
          ),
        if (selected != null) ...[
          const SizedBox(height: 10),
          Text(selected.description, style: context.t.bodySmall, textAlign: TextAlign.center),
        ],
        const SizedBox(height: 24),
        Text('Style', style: context.t.titleMedium),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: _ModeCard(
              selected: _mode == PairingMode.smart,
              accent: t.accent,
              icon: Icons.auto_awesome_rounded,
              title: 'Smart duels',
              body: 'Asks the pair it is least sure about. Sharpest ranking.',
              onTap: () => setState(() => _mode = PairingMode.smart),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ModeCard(
              selected: _mode == PairingMode.gauntlet,
              accent: t.accent,
              icon: Icons.emoji_events_rounded,
              title: 'King of the hill',
              body: 'Your pick stays on and defends against challengers.',
              onTap: () => setState(() => _mode = PairingMode.gauntlet),
            ),
          ),
        ]),
        const SizedBox(height: 26),
        GradientButton(
          label: 'Start ranking',
          icon: Icons.bolt_rounded,
          gradient: topicGradient(t.accent),
          busy: _starting,
          onTap: selected == null ? null : () => _start(selected),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text('Answers are anonymous.', style: context.t.bodySmall?.copyWith(color: c.muted)),
        ),
      ]),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({required this.selected, required this.accent, required this.onTap, required this.child});

  final bool selected;
  final Color accent;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: context.isDark ? .16 : .1) : c.surface2,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? accent : Colors.transparent, width: 1.6),
        ),
        child: child,
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.selected,
    required this.accent,
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
  });

  final bool selected;
  final Color accent;
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _Choice(
        selected: selected,
        accent: accent,
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: selected ? topicGradient(accent) : null,
              color: selected ? null : context.c.border,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: selected ? Colors.white : context.c.text2),
          ),
          const SizedBox(height: 12),
          Text(title, style: context.t.titleSmall),
          const SizedBox(height: 4),
          Text(body, style: context.t.bodySmall?.copyWith(height: 1.35)),
        ]),
      );
}
