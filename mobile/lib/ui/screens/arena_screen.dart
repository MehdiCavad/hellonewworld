import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/models.dart';
import '../../data/saved_session.dart';
import '../../engine/ranking_engine.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../widgets/common.dart';

/// The arena: two options side by side, tap the one you prefer.
///
/// Taps are applied to the engine synchronously and the next pair animates
/// in afterwards, so a fast player never loses an answer to an animation.
class ArenaScreen extends ConsumerStatefulWidget {
  const ArenaScreen({super.key, required this.sessionId});
  final String sessionId;

  @override
  ConsumerState<ArenaScreen> createState() => _ArenaScreenState();
}

class _ArenaScreenState extends ConsumerState<ArenaScreen> {
  final _player = AudioPlayer();
  final _focus = FocusNode();
  String? _playing;
  String? _flash;
  Timer? _flashTimer;

  @override
  void dispose() {
    _player.dispose();
    _focus.dispose();
    _flashTimer?.cancel();
    super.dispose();
  }

  SavedSession? get _session => ref.read(sessionsProvider.notifier).byId(widget.sessionId);

  void _answer(String? winnerId) {
    final s = _session;
    if (s == null || s.engine.current == null) return;
    HapticFeedback.lightImpact();
    _stopAudio();
    final label = winnerId == null ? 'Too close to call' : '✓ ${s.itemMeta[winnerId]?.name ?? ''}';
    ref.read(sessionsProvider.notifier).mutate(s.id, (e) => e.submit(winnerId));
    _showFlash(label);
    if (s.finished) _goToResults();
  }

  void _skip() {
    _stopAudio();
    ref.read(sessionsProvider.notifier).mutate(widget.sessionId, (e) => e.skip());
    _showFlash('Skipped');
  }

  void _undo() {
    if ((_session?.engine.history.isEmpty ?? true)) return;
    _stopAudio();
    ref.read(sessionsProvider.notifier).mutate(widget.sessionId, (e) => e.undo());
    _showFlash('Undone');
  }

  void _finishEarly() {
    ref.read(sessionsProvider.notifier).mutate(widget.sessionId, (e) => e.finishNow());
    _goToResults();
  }

  void _goToResults() {
    HapticFeedback.mediumImpact();
    Future.delayed(const Duration(milliseconds: 260), () {
      if (mounted) context.pushReplacement('/results/${widget.sessionId}');
    });
  }

  void _showFlash(String text) {
    setState(() => _flash = text);
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _flash = null);
    });
  }

  Future<void> _toggleAudio(Item item) async {
    if (_playing == item.id) return _stopAudio();
    final url = item.audio?.url;
    if (url == null) return;
    setState(() => _playing = item.id);
    try {
      await _player.setUrl(url);
      unawaited(_player.play());
      _player.playerStateStream.firstWhere((s) => s.processingState == ProcessingState.completed).then((_) {
        if (mounted && _playing == item.id) setState(() => _playing = null);
      });
    } catch (_) {
      if (mounted) setState(() => _playing = null);
    }
  }

  void _stopAudio() {
    if (_playing == null) return;
    _player.stop();
    setState(() => _playing = null);
  }

  Future<void> _confirmFinish() async {
    final c = context.c;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Finish now?', style: ctx.t.displaySmall),
          const SizedBox(height: 8),
          Text('You will get the ranking as it stands. Items with few answers are marked as low data, and you can refine later.',
              style: ctx.t.bodyMedium),
          const SizedBox(height: 22),
          GradientButton(label: 'Show my ranking', icon: Icons.emoji_events_rounded, onTap: () => Navigator.pop(ctx, true)),
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Keep going', style: TextStyle(color: c.text2))),
        ]),
      ),
    );
    if (ok == true) _finishEarly();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final pair = _session?.engine.current;
    if (pair == null) return KeyEventResult.ignored;
    switch (e.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        _answer(pair[0]);
      case LogicalKeyboardKey.arrowRight:
        _answer(pair[1]);
      case LogicalKeyboardKey.keyT || LogicalKeyboardKey.arrowDown:
        _answer(null);
      case LogicalKeyboardKey.keyS:
        _skip();
      case LogicalKeyboardKey.keyU || LogicalKeyboardKey.backspace:
        _undo();
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(sessionsProvider);
    final s = _session;
    final c = context.c;
    if (s == null) {
      return const Scaffold(body: Center(child: Text('This ranking no longer exists.')));
    }
    final e = s.engine;
    final pair = e.current;
    final p = e.progress();
    final accent = s.topic.accent;
    final champion = e.mode == PairingMode.gauntlet ? e.champion : null;

    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        body: Aurora(
          accent: accent,
          child: SafeArea(
            child: Column(children: [
              // ---- Header ----
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
                child: Row(children: [
                  IconButton(tooltip: 'Close', onPressed: () => context.pop(), icon: Icon(Icons.close_rounded, color: c.text2)),
                  Expanded(
                    child: Column(children: [
                      Text('${s.topic.emoji}  ${s.topic.name}', style: context.t.titleSmall),
                      Text('${s.level.name} · ${e.mode == PairingMode.smart ? 'Smart duels' : 'King of the hill'}', style: context.t.bodySmall),
                    ]),
                  ),
                  Pressable(
                    onTap: _confirmFinish,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(99)),
                      child: Text('Finish', style: context.t.labelMedium),
                    ),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Row(children: [
                  Expanded(child: GradientProgress(value: p.ratio, height: 8, gradient: topicGradient(accent))),
                  const SizedBox(width: 12),
                  Text('${p.rounds}/${p.target}', style: context.t.labelMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                ]),
              ),
              const SizedBox(height: 18),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(
                  _flash ?? (e.history.isEmpty ? 'Which do you prefer?' : _prompts[e.history.length % _prompts.length]),
                  key: ValueKey(_flash ?? 'prompt${e.history.length}'),
                  style: context.t.headlineMedium?.copyWith(color: _flash != null ? accent : c.text),
                ),
              ),
              const SizedBox(height: 16),

              // ---- The duel ----
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: pair == null
                      ? const Center(child: CircularProgressIndicator())
                      : Stack(alignment: Alignment.center, children: [
                          Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            for (final (i, id) in pair.indexed) ...[
                              if (i == 1) const SizedBox(width: 12),
                              Expanded(
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 340),
                                  switchInCurve: Curves.easeOutBack,
                                  switchOutCurve: Curves.easeIn,
                                  transitionBuilder: (child, anim) => FadeTransition(
                                    opacity: anim,
                                    child: ScaleTransition(scale: Tween(begin: .9, end: 1.0).animate(anim), child: child),
                                  ),
                                  child: _OptionCard(
                                    key: ValueKey(id),
                                    item: s.itemMeta[id] ?? Item(id: id, name: e.items[id]?.name ?? id),
                                    topic: s.topic,
                                    isChampion: id == champion,
                                    playing: _playing == id,
                                    onTap: () => _answer(id),
                                    onAudio: () => _toggleAudio(s.itemMeta[id]!),
                                  ),
                                ),
                              ),
                            ],
                          ]),
                          IgnorePointer(
                            child: Container(
                              width: 54,
                              height: 54,
                              decoration: BoxDecoration(
                                color: c.bg,
                                shape: BoxShape.circle,
                                border: Border.all(color: c.border, width: 1.5),
                                boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 20, offset: Offset(0, 8))],
                              ),
                              alignment: Alignment.center,
                              child: ShaderMask(
                                shaderCallback: (r) => topicGradient(accent).createShader(r),
                                child: const Text('VS', style: TextStyle(fontFamily: display, fontWeight: FontWeight.w800, fontSize: 18, color: Colors.white)),
                              ),
                            ),
                          ),
                        ]),
                ),
              ),

              // ---- Actions ----
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
                child: Row(children: [
                  _ActionButton(icon: Icons.undo_rounded, label: 'Undo', onTap: e.history.isEmpty ? null : _undo),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Pressable(
                      onTap: pair == null ? null : () => _answer(null),
                      child: Container(
                        height: 56,
                        decoration: BoxDecoration(
                          color: c.surface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: c.border),
                        ),
                        alignment: Alignment.center,
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.balance_rounded, size: 20, color: c.text2),
                          const SizedBox(width: 8),
                          Text('Too close to call', style: context.t.labelLarge),
                        ]),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _ActionButton(icon: Icons.skip_next_rounded, label: 'Skip', onTap: pair == null ? null : _skip),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  static const _prompts = ['And now?', 'This one or that one?', 'Your pick?', 'Tough one?', 'Go with your gut.'];
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    super.key,
    required this.item,
    required this.topic,
    required this.isChampion,
    required this.playing,
    required this.onTap,
    required this.onAudio,
  });

  final Item item;
  final Topic topic;
  final bool isChampion;
  final bool playing;
  final VoidCallback onTap;
  final VoidCallback onAudio;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      scale: .95,
      haptic: false,
      semanticLabel: 'Choose ${item.name}',
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: (isChampion ? RankdColors.gold : topic.accent).withValues(alpha: context.isDark ? .32 : .26),
              blurRadius: 34,
              offset: const Offset(0, 16),
            ),
          ],
          border: isChampion ? Border.all(color: RankdColors.gold, width: 2.5) : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(isChampion ? 27.5 : 30),
          child: Stack(fit: StackFit.expand, children: [
            ItemArt(name: item.name, imageUrl: item.image?.url, accent: topic.accent, emoji: topic.emoji, radius: 0, monogramSize: 58),
            // Scrim for legible text over any image.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [.45, 1],
                  colors: [Color(0x00000000), Color(0xC0000000)],
                ),
              ),
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 16,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  item.name,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: display, fontWeight: FontWeight.w800, fontSize: 21, height: 1.05, letterSpacing: -.5, color: Colors.white),
                ),
                if (item.detail.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(item.detail, style: TextStyle(fontFamily: body, fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white.withValues(alpha: .8))),
                ],
              ]),
            ),
            if (isChampion)
              Positioned(
                top: 12,
                left: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: RankdColors.gold, borderRadius: BorderRadius.circular(99)),
                  child: const Text('👑 Champion', style: TextStyle(fontFamily: body, fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF3A2A00))),
                ),
              ),
            if (item.audio != null)
              Positioned(
                top: 10,
                right: 10,
                child: Pressable(
                  semanticLabel: playing ? 'Stop preview' : 'Play preview',
                  onTap: onAudio,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: .45), shape: BoxShape.circle),
                    child: Icon(playing ? Icons.stop_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 26),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      semanticLabel: label,
      onTap: onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: onTap == null ? .4 : 1,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: c.border)),
          child: Icon(icon, color: c.text2),
        ),
      ),
    );
  }
}
