import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/models.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../widgets/common.dart';

/// Everyone's answers, fitted together per topic, with movement since the last run.
class CommunityScreen extends ConsumerStatefulWidget {
  const CommunityScreen({super.key, this.initialSlug});
  final String? initialSlug;

  @override
  ConsumerState<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends ConsumerState<CommunityScreen> {
  String? _slug;

  @override
  void initState() {
    super.initState();
    _slug = widget.initialSlug;
  }

  @override
  void didUpdateWidget(CommunityScreen old) {
    super.didUpdateWidget(old);
    if (widget.initialSlug != null && widget.initialSlug != old.initialSlug) _slug = widget.initialSlug;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final topics = ref.watch(topicsProvider).value?.value ?? const <Topic>[];
    final topic = topics.where((t) => t.slug == _slug).firstOrNull ?? topics.firstOrNull;

    return Aurora(
      accent: topic?.accent,
      child: CustomScrollView(slivers: [
        SliverSafeArea(
          bottom: false,
          sliver: SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Community', style: context.t.displayMedium),
                const SizedBox(height: 6),
                Text('Every anonymous answer, fitted into one ranking per topic.', style: context.t.bodyMedium),
              ]),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 64,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              itemCount: topics.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final t = topics[i];
                final on = t.slug == topic?.slug;
                return Pressable(
                  onTap: () => setState(() => _slug = t.slug),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: on ? topicGradient(t.accent) : null,
                      color: on ? null : c.surface,
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: on ? Colors.transparent : c.border),
                    ),
                    child: Text('${t.emoji}  ${t.name}',
                        style: TextStyle(fontFamily: body, fontWeight: FontWeight.w700, fontSize: 13.5, color: on ? Colors.white : c.text2)),
                  ),
                );
              },
            ),
          ),
        ),
        if (topic == null)
          const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))
        else
          _Board(topic: topic),
      ]),
    );
  }
}

class _Board extends ConsumerWidget {
  const _Board({required this.topic});
  final Topic topic;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    return ref.watch(globalRankingProvider(topic.slug)).when(
          loading: () => const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator())),
          error: (_, _) => SliverFillRemaining(
            hasScrollBody: false,
            child: _Empty(
              icon: Icons.cloud_off_rounded,
              title: 'Community rankings need a connection',
              body: 'Your own rankings keep working offline and upload when you are back.',
              action: TextButton(onPressed: () => ref.invalidate(globalRankingProvider(topic.slug)), child: const Text('Try again')),
            ),
          ),
          data: (g) {
            if (g.rows.isEmpty) {
              return SliverFillRemaining(
                hasScrollBody: false,
                child: _Empty(
                  icon: Icons.hourglass_top_rounded,
                  title: 'Not enough answers yet',
                  body: 'Be one of the first to rank ${topic.name}.',
                ),
              );
            }
            final top = g.rows.first.rating, bottom = g.rows.last.rating;
            final span = (top - bottom).abs() < 1 ? 1.0 : top - bottom;
            return SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
              sliver: SliverList.list(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                  child: Row(children: [
                    Icon(Icons.groups_rounded, size: 17, color: c.muted),
                    const SizedBox(width: 6),
                    Text('${g.devices} people', style: context.t.bodySmall),
                    const Spacer(),
                    if (g.computedAt != null) Text('Updated ${_ago(g.computedAt!)}', style: context.t.bodySmall),
                  ]),
                ),
                for (final r in g.rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _GlobalRowTile(row: r, topic: topic, strength: ((r.rating - bottom) / span).clamp(.04, 1.0)),
                  ),
              ]),
            );
          },
        );
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t.toLocal());
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }
}

class _GlobalRowTile extends StatelessWidget {
  const _GlobalRowTile({required this.row, required this.topic, required this.strength});
  final GlobalRow row;
  final Topic topic;
  final double strength;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final medal = switch (row.rank) { 1 => RankdColors.gold, 2 => RankdColors.silver, 3 => RankdColors.bronze, _ => null };
    final move = row.previousRank == null ? null : row.previousRank! - row.rank;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 14, 10),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: medal?.withValues(alpha: .55) ?? c.border),
      ),
      child: Row(children: [
        SizedBox(
          width: 30,
          child: Text('${row.rank}', textAlign: TextAlign.center, style: context.t.titleMedium?.copyWith(color: medal ?? c.muted)),
        ),
        const SizedBox(width: 6),
        SizedBox(width: 44, height: 44, child: ItemArt(name: row.name, imageUrl: row.image?.url, accent: topic.accent, radius: 12, monogramSize: 16)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(row.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.t.titleSmall),
            const SizedBox(height: 2),
            Text(row.detail.isEmpty ? '${row.comparisons} duels' : '${row.detail} · ${row.comparisons} duels',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: context.t.bodySmall),
            const SizedBox(height: 6),
            GradientProgress(value: strength, height: 4, gradient: topicGradient(topic.accent)),
          ]),
        ),
        const SizedBox(width: 12),
        _Movement(move: move),
      ]),
    );
  }
}

class _Movement extends StatelessWidget {
  const _Movement({required this.move});
  final int? move;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final (icon, color, label) = switch (move) {
      null => (Icons.fiber_new_rounded, RankdColors.brand, ''),
      0 => (Icons.remove_rounded, c.muted, ''),
      final m when m > 0 => (Icons.arrow_upward_rounded, RankdColors.good, '$m'),
      final m => (Icons.arrow_downward_rounded, RankdColors.bad, '${-m}'),
    };
    return SizedBox(
      width: 38,
      child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        Icon(icon, size: 16, color: color),
        if (label.isNotEmpty) Text(label, style: TextStyle(fontFamily: body, fontWeight: FontWeight.w700, fontSize: 12.5, color: color)),
      ]),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.title, required this.body, this.action});
  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(40, 40, 40, 140),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 44, color: context.c.muted),
          const SizedBox(height: 14),
          Text(title, style: context.t.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(body, style: context.t.bodyMedium, textAlign: TextAlign.center),
          ?action,
        ]),
      );
}
