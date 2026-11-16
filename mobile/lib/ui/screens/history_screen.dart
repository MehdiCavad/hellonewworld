import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/saved_session.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../widgets/common.dart';

/// Every ranking on this device: resume the open ones, revisit the finished ones.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(sessionsProvider);
    final open = sessions.where((s) => !s.finished).toList();
    final done = sessions.where((s) => s.finished).toList();

    return Aurora(
      child: CustomScrollView(slivers: [
        SliverSafeArea(
          bottom: false,
          sliver: SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('History', style: context.t.displayMedium),
                const SizedBox(height: 6),
                Text('Swipe a ranking away to delete it.', style: context.t.bodyMedium),
              ]),
            ),
          ),
        ),
        if (sessions.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(40, 0, 40, 140),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Text('🗂️', style: TextStyle(fontSize: 52)),
                const SizedBox(height: 14),
                Text('Nothing ranked yet', style: context.t.titleMedium),
                const SizedBox(height: 6),
                Text('Pick a topic on the Play tab and your rankings will collect here.',
                    style: context.t.bodyMedium, textAlign: TextAlign.center),
              ]),
            ),
          ),
        if (open.isNotEmpty) ...[
          const SliverToBoxAdapter(child: SectionTitle('In progress')),
          _List(sessions: open),
        ],
        if (done.isNotEmpty) ...[
          const SliverToBoxAdapter(child: SectionTitle('Finished')),
          _List(sessions: done),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ]),
    );
  }
}

class _List extends ConsumerWidget {
  const _List({required this.sessions});
  final List<SavedSession> sessions;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverList.separated(
          itemCount: sessions.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (_, i) {
            final s = sessions[i];
            return Dismissible(
              key: ValueKey(s.id),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 24),
                decoration: BoxDecoration(color: RankdColors.bad.withValues(alpha: .9), borderRadius: BorderRadius.circular(24)),
                child: const Icon(Icons.delete_rounded, color: Colors.white),
              ),
              onDismissed: (_) => ref.read(sessionsProvider.notifier).remove(s.id),
              child: _Tile(session: s),
            );
          },
        ),
      );
}

class _Tile extends StatelessWidget {
  const _Tile({required this.session});
  final SavedSession session;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = session.topic;
    final p = session.engine.progress();
    final leader = session.engine.standings().firstOrNull;
    return Pressable(
      onTap: () => context.push(session.finished ? '/results/${session.id}' : '/play/${session.id}'),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(24), border: Border.all(color: c.border)),
        child: Row(children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(gradient: topicGradient(t.accent), borderRadius: BorderRadius.circular(18)),
            child: Text(t.emoji, style: const TextStyle(fontSize: 28)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.name, style: context.t.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 3),
              Text(
                session.finished && leader != null
                    ? '👑 ${leader.item.name}'
                    : '${p.rounds} of ${p.target} · ${session.level.name}',
                style: context.t.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (!session.finished) ...[
                const SizedBox(height: 7),
                GradientProgress(value: p.ratio, height: 4, gradient: topicGradient(t.accent)),
              ],
            ]),
          ),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(_when(session.updatedAt), style: context.t.bodySmall?.copyWith(color: c.muted)),
            const SizedBox(height: 6),
            Icon(session.finished ? Icons.leaderboard_rounded : Icons.play_circle_fill_rounded,
                color: session.finished ? c.muted : t.accent, size: 24),
          ]),
        ]),
      ),
    );
  }

  static String _when(DateTime t) {
    final local = t.toLocal();
    final d = DateTime.now().difference(local);
    if (d.inMinutes < 1) return 'now';
    if (d.inHours < 1) return '${d.inMinutes}m';
    if (d.inDays < 1) return '${d.inHours}h';
    if (d.inDays < 7) return '${d.inDays}d';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${local.day} ${months[local.month - 1]}';
  }
}
