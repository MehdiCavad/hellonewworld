import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/models.dart';
import '../../data/repository.dart';
import '../../data/saved_session.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../widgets/common.dart';
import 'topic_sheet.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final topics = ref.watch(topicsProvider);
    final resume = ref.watch(resumableProvider);
    final finished = ref.watch(sessionsProvider).where((s) => s.finished).length;

    return Aurora(
      child: RefreshIndicator(
        onRefresh: () => ref.refresh(topicsProvider.future),
        child: CustomScrollView(slivers: [
          SliverSafeArea(
            bottom: false,
            sliver: SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
                child: Row(children: [
                  const RankdMark(),
                  const SizedBox(width: 10),
                  Text('Rankd', style: context.t.headlineMedium),
                  const Spacer(),
                  if (topics.value?.source case final s? when s != Source.live) Pill(label: 'Offline', icon: Icons.cloud_off_rounded, color: c.muted),
                  IconButton(
                    tooltip: 'Settings',
                    onPressed: () => context.push('/settings'),
                    icon: Icon(Icons.tune_rounded, color: c.text2),
                  ),
                ]),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_greeting(), style: context.t.bodyMedium?.copyWith(color: c.muted, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text('What are we\nranking today?', style: context.t.displayMedium),
                if (finished > 0) ...[
                  const SizedBox(height: 10),
                  Text('$finished ranking${finished == 1 ? '' : 's'} finished so far.', style: context.t.bodyMedium),
                ],
              ]),
            ),
          ),
          if (resume != null)
            SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(20, 22, 20, 0), child: _ContinueCard(session: resume))),
          SliverToBoxAdapter(
            child: SectionTitle('Topics', trailing: Text('${topics.value?.value.length ?? ''}', style: context.t.bodySmall)),
          ),
          topics.when(
            loading: () => const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))),
            error: (e, _) => SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(24), child: Text('$e'))),
            data: (loaded) => SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 240,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: .82,
                ),
                itemCount: loaded.value.length,
                itemBuilder: (_, i) => TopicCard(topic: loaded.value[i], index: i),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  static String _greeting() {
    final h = DateTime.now().hour;
    return h < 5 ? 'Up late?' : h < 12 ? 'Good morning' : h < 18 ? 'Good afternoon' : 'Good evening';
  }
}

class TopicCard extends StatelessWidget {
  const TopicCard({super.key, required this.topic, required this.index});

  final Topic topic;
  final int index;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 420 + index * 60),
      curve: Curves.easeOutCubic,
      builder: (_, v, child) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 24 * (1 - v)), child: child)),
      child: Pressable(
        semanticLabel: '${topic.name}, ${topic.itemCount} options',
        onTap: () => showTopicSheet(context, topic),
        child: Container(
          decoration: BoxDecoration(
            gradient: topicGradient(topic.accent),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [BoxShadow(color: topic.accent.withValues(alpha: context.isDark ? .35 : .3), blurRadius: 26, offset: const Offset(0, 14))],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(children: [
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(center: Alignment(1, -1), radius: 1.2, colors: [Color(0x47FFFFFF), Color(0x00FFFFFF)]),
                ),
              ),
            ),
            Positioned(
              right: -14,
              top: 4,
              child: Transform.rotate(
                angle: .16,
                child: Text(topic.emoji, style: const TextStyle(fontSize: 86, shadows: [Shadow(color: Color(0x40000000), blurRadius: 20, offset: Offset(0, 10))])),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Spacer(),
                Text(topic.name,
                    style: const TextStyle(fontFamily: display, fontWeight: FontWeight.w800, fontSize: 22, height: 1.05, letterSpacing: -.6, color: Colors.white)),
                const SizedBox(height: 4),
                Text(topic.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: body, fontSize: 12.5, height: 1.3, color: Colors.white.withValues(alpha: .82))),
                const SizedBox(height: 12),
                Row(children: [
                  _GlassChip('${topic.itemCount} options'),
                  if (topic.hasPreviews) ...[const SizedBox(width: 6), const _GlassChip('♪ previews')],
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _GlassChip extends StatelessWidget {
  const _GlassChip(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: .2), borderRadius: BorderRadius.circular(99)),
        child: Text(label, style: const TextStyle(fontFamily: body, fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.white)),
      );
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.session});
  final SavedSession session;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final p = session.engine.progress();
    final pair = session.engine.current!;
    final accent = session.topic.accent;
    return Pressable(
      onTap: () => context.push('/play/${session.id}'),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: c.border),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: context.isDark ? .3 : .06), blurRadius: 30, offset: const Offset(0, 12))],
        ),
        child: Row(children: [
          SizedBox(
            width: 84,
            height: 64,
            child: Stack(children: [
              for (final (i, id) in pair.indexed)
                Positioned(
                  left: i * 30.0,
                  top: i * 6.0,
                  child: Transform.rotate(
                    angle: i == 0 ? -.08 : .08,
                    child: Container(
                      width: 46,
                      height: 58,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: c.surface, width: 2),
                        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 10, offset: Offset(0, 4))],
                      ),
                      child: ItemArt(
                        name: session.itemMeta[id]?.name ?? '',
                        imageUrl: session.itemMeta[id]?.image?.url,
                        accent: accent,
                        radius: 10,
                        monogramSize: 18,
                      ),
                    ),
                  ),
                ),
            ]),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('CONTINUE', style: context.t.labelSmall?.copyWith(letterSpacing: 1.2, color: RankdColors.brand)),
              const SizedBox(height: 2),
              Text('${session.topic.emoji} ${session.topic.name}', style: context.t.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 8),
              GradientProgress(value: p.ratio, gradient: topicGradient(accent)),
              const SizedBox(height: 6),
              Text('${p.rounds} of ${p.target} · ${session.level.name}', style: context.t.bodySmall),
            ]),
          ),
          const SizedBox(width: 8),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(gradient: topicGradient(accent), shape: BoxShape.circle),
            child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 26),
          ),
        ]),
      ),
    );
  }
}
