import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/saved_session.dart';
import '../../engine/ranking_engine.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../widgets/common.dart';

/// The finished ranking: a podium for the top three, then everything else
/// with a strength bar, and a way to sharpen it with ten more duels.
class ResultsScreen extends ConsumerWidget {
  const ResultsScreen({super.key, required this.sessionId});
  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final session = ref.watch(sessionsProvider).where((s) => s.id == sessionId).firstOrNull;
    if (session == null) {
      return Scaffold(body: Center(child: Text('This ranking is no longer on this device.', style: context.t.bodyLarge)));
    }
    final standings = session.engine.standings();
    final accent = session.topic.accent;
    final top = standings.first.item.rating;
    final bottom = standings.last.item.rating;
    final span = (top - bottom).abs() < 1 ? 1.0 : top - bottom;

    void refine() {
      ref.read(sessionsProvider.notifier).mutate(session.id, (e) => e.extend(10));
      context.pushReplacement('/play/${session.id}');
    }

    return Scaffold(
      body: Aurora(
        accent: accent,
        child: CustomScrollView(slivers: [
          SliverSafeArea(
            bottom: false,
            sliver: SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 12, 0),
                child: Row(children: [
                  IconButton(
                    tooltip: 'Home',
                    onPressed: () => context.go('/'),
                    icon: Icon(Icons.close_rounded, color: c.text2),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Copy ranking',
                    onPressed: () => _share(context, session),
                    icon: Icon(Icons.ios_share_rounded, color: c.text2),
                  ),
                ]),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Column(children: [
                Pill(label: '${session.topic.emoji}  ${session.topic.name}', color: accent),
                const SizedBox(height: 12),
                Text('Your ranking', style: context.t.displayMedium, textAlign: TextAlign.center),
                const SizedBox(height: 6),
                Text(
                  '${session.engine.history.length} answers · ${session.level.name} · '
                  '${session.engine.mode == PairingMode.gauntlet ? 'King of the hill' : 'Smart duels'}',
                  style: context.t.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ]),
            ),
          ),
          SliverToBoxAdapter(child: _Podium(session: session, standings: standings.take(3).toList())),
          if (standings.length > 3)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              sliver: SliverList.separated(
                itemCount: standings.length - 3,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final s = standings[i + 3];
                  return _Row(
                    session: session,
                    standing: s,
                    strength: ((s.item.rating - bottom) / span).clamp(.04, 1.0),
                  );
                },
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 24, 20, 24 + MediaQuery.paddingOf(context).bottom),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                GradientButton(
                  label: 'Refine with 10 more',
                  icon: Icons.tune_rounded,
                  gradient: topicGradient(accent),
                  onTap: refine,
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: _Ghost(
                      icon: Icons.public_rounded,
                      label: 'Community',
                      onTap: () => context.go('/community?topic=${session.topic.slug}'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: _Ghost(icon: Icons.home_rounded, label: 'Done', onTap: () => context.go('/'))),
                ]),
                const SizedBox(height: 14),
                Text(
                  'A dim position means it has only been compared a couple of times. Refining asks about those first.',
                  style: context.t.bodySmall?.copyWith(color: c.muted),
                  textAlign: TextAlign.center,
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  static Future<void> _share(BuildContext context, SavedSession session) async {
    final lines = [
      '${session.topic.emoji} My ${session.topic.name} ranking on Rankd',
      for (final s in session.engine.standings().take(10)) '${s.rank}. ${s.item.name}',
    ];
    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Top 10 copied to the clipboard')));
    }
  }
}

class _Podium extends StatelessWidget {
  const _Podium({required this.session, required this.standings});
  final SavedSession session;
  final List<Standing> standings;

  @override
  Widget build(BuildContext context) {
    // Visual order: 2nd, 1st, 3rd.
    const slots = [1, 0, 2];
    const heights = [118.0, 150.0, 96.0];
    const medals = [RankdColors.gold, RankdColors.silver, RankdColors.bronze];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (final slot in slots)
          if (slot < standings.length)
            Expanded(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: Duration(milliseconds: 600 + (2 - slot) * 140),
                curve: Curves.easeOutBack,
                builder: (_, v, child) => Transform.translate(offset: Offset(0, 40 * (1 - v)), child: Opacity(opacity: v.clamp(0, 1), child: child)),
                child: _Step(
                  session: session,
                  standing: standings[slot],
                  medal: medals[slot],
                  height: heights[slot],
                  big: slot == 0,
                ),
              ),
            )
          else
            const Expanded(child: SizedBox()),
      ]),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.session, required this.standing, required this.medal, required this.height, required this.big});
  final SavedSession session;
  final Standing standing;
  final Color medal;
  final double height;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final meta = session.itemMeta[standing.item.id];
    final size = big ? 92.0 : 72.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: Column(children: [
        if (big) const Text('👑', style: TextStyle(fontSize: 26)),
        Stack(clipBehavior: Clip.none, alignment: Alignment.bottomCenter, children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: medal, width: 3),
              boxShadow: [BoxShadow(color: medal.withValues(alpha: .45), blurRadius: 24, offset: const Offset(0, 8))],
            ),
            child: ClipOval(
              child: ItemArt(name: standing.item.name, imageUrl: meta?.image?.url, accent: session.topic.accent, radius: 0, monogramSize: big ? 30 : 24),
            ),
          ),
          Positioned(
            bottom: -10,
            child: Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: medal, shape: BoxShape.circle, border: Border.all(color: c.bg, width: 2)),
              child: Text('${standing.rank}',
                  style: const TextStyle(fontFamily: display, fontWeight: FontWeight.w800, fontSize: 13, color: Color(0xFF1A1325))),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        Text(standing.item.name,
            maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: big ? context.t.titleMedium : context.t.titleSmall),
        const SizedBox(height: 10),
        Container(
          height: height,
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [medal.withValues(alpha: .55), medal.withValues(alpha: .06)],
            ),
          ),
          alignment: Alignment.topCenter,
          padding: const EdgeInsets.only(top: 10),
          child: Text('${(standing.winRate * 100).round()}%',
              style: TextStyle(fontFamily: display, fontWeight: FontWeight.w800, fontSize: 18, color: c.text)),
        ),
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.session, required this.standing, required this.strength});
  final SavedSession session;
  final Standing standing;
  final double strength;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final meta = session.itemMeta[standing.item.id];
    final lowData = standing.confidence < .5;
    return Opacity(
      opacity: lowData ? .62 : 1,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 14, 10),
        decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: c.border)),
        child: Row(children: [
          SizedBox(
            width: 30,
            child: Text('${standing.rank}', textAlign: TextAlign.center, style: context.t.titleMedium?.copyWith(color: c.muted)),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 44,
            height: 44,
            child: ItemArt(name: standing.item.name, imageUrl: meta?.image?.url, accent: session.topic.accent, radius: 12, monogramSize: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(standing.item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.t.titleSmall)),
                if (lowData) ...[
                  const SizedBox(width: 6),
                  Tooltip(message: 'Only a few comparisons so far', child: Icon(Icons.help_outline_rounded, size: 15, color: c.muted)),
                ],
              ]),
              const SizedBox(height: 7),
              GradientProgress(value: strength, height: 5, gradient: topicGradient(session.topic.accent)),
            ]),
          ),
          const SizedBox(width: 12),
          Text('${standing.item.wins}–${standing.item.losses}', style: context.t.bodySmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
      ),
    );
  }
}

class _Ghost extends StatelessWidget {
  const _Ghost({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onTap: onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: c.border)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 19, color: c.text2),
          const SizedBox(width: 8),
          Text(label, style: context.t.titleSmall),
        ]),
      ),
    );
  }
}
