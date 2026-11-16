import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/api_client.dart';
import '../../data/repository.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../widgets/common.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final mode = ref.watch(themeModeProvider);
    final source = ref.watch(topicsProvider).value?.source;
    final sessions = ref.watch(sessionsProvider);
    final pending = sessions.where((s) => s.dirty && s.uploadable).length;
    final attributions = ref.watch(attributionsProvider).value ?? const [];

    return Scaffold(
      body: Aurora(
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + 4, 16, 32 + MediaQuery.paddingOf(context).bottom),
          children: [
            Row(children: [
              IconButton(onPressed: () => context.pop(), icon: Icon(Icons.arrow_back_rounded, color: c.text2), tooltip: 'Back'),
              const SizedBox(width: 4),
              Text('Settings', style: context.t.headlineMedium),
            ]),
            const SizedBox(height: 14),
            _Group(title: 'Appearance', children: [
              Padding(
                padding: const EdgeInsets.all(6),
                child: Row(children: [
                  for (final (m, icon, label) in const [
                    (ThemeMode.dark, Icons.dark_mode_rounded, 'Dark'),
                    (ThemeMode.light, Icons.light_mode_rounded, 'Light'),
                    (ThemeMode.system, Icons.brightness_auto_rounded, 'System'),
                  ])
                    Expanded(
                      child: Pressable(
                        onTap: () => ref.read(themeModeProvider.notifier).set(m),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          height: 46,
                          margin: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            gradient: m == mode ? RankdColors.brandGradient : null,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(icon, size: 18, color: m == mode ? Colors.white : c.muted),
                            const SizedBox(width: 6),
                            Text(label,
                                style: TextStyle(
                                    fontFamily: body, fontWeight: FontWeight.w700, fontSize: 13.5, color: m == mode ? Colors.white : c.text2)),
                          ]),
                        ),
                      ),
                    ),
                ]),
              ),
            ]),
            _Group(title: 'Connection', children: [
              _Tile(
                icon: source == Source.live ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                iconColor: source == Source.live ? RankdColors.good : c.muted,
                title: source == Source.live ? 'Connected' : 'Offline',
                subtitle: source == Source.live
                    ? (pending == 0 ? 'Everything is uploaded' : '$pending ranking${pending == 1 ? '' : 's'} waiting to upload')
                    : 'Playing from the built-in catalogue',
              ),
              _Tile(icon: Icons.dns_rounded, title: 'Server', subtitle: apiBaseUrl),
            ]),
            _Group(title: 'Privacy', children: [
              _Tile(
                icon: Icons.fingerprint_rounded,
                title: 'Anonymous ID',
                subtitle: '${ref.watch(deviceIdProvider).substring(0, 8)}… · no account, no email',
              ),
              _Tile(
                icon: Icons.delete_forever_rounded,
                iconColor: RankdColors.bad,
                title: 'Delete my data',
                subtitle: 'Removes every ranking here and on the server',
                onTap: () => _confirmDelete(context, ref),
              ),
            ]),
            _Group(title: 'Credits', children: [
              for (final a in attributions) _Tile(icon: Icons.image_rounded, title: a.provider, subtitle: '${a.notice} · ${a.assets} files'),
              const _Tile(icon: Icons.font_download_rounded, title: 'Inter and Bricolage Grotesque', subtitle: 'SIL Open Font License 1.1'),
              _Tile(
                icon: Icons.article_rounded,
                title: 'Open-source licences',
                onTap: () => showLicensePage(context: context, applicationName: 'Rankd', applicationVersion: appVersion),
              ),
            ]),
            const SizedBox(height: 10),
            Center(child: Text('Rankd $appVersion', style: context.t.bodySmall?.copyWith(color: c.muted))),
          ],
        ),
      ),
    );
  }

  static Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final c = context.c;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + MediaQuery.paddingOf(ctx).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('🧹', style: TextStyle(fontSize: 44), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text('Delete everything?', style: ctx.t.headlineSmall, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text('Your rankings leave this device and the server, and your answers stop counting in the community rankings. This cannot be undone.',
              style: ctx.t.bodyMedium, textAlign: TextAlign.center),
          const SizedBox(height: 20),
          GradientButton(
            label: 'Delete my data',
            icon: Icons.delete_forever_rounded,
            gradient: const LinearGradient(colors: [RankdColors.bad, RankdColors.brand3]),
            onTap: () => Navigator.of(ctx).pop(true),
          ),
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text('Keep it', style: TextStyle(color: c.text2))),
        ]),
      ),
    );
    if (ok != true) return;
    await ref.read(sessionsProvider.notifier).deleteEverything();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Your data has been deleted')));
    }
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
          child: Text(title.toUpperCase(), style: context.t.labelSmall?.copyWith(letterSpacing: 1.2, color: c.muted)),
        ),
        Container(
          decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(22), border: Border.all(color: c.border)),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            for (final (i, w) in children.indexed) ...[
              if (i > 0) Divider(height: 1, indent: 58, color: c.border),
              w,
            ],
          ]),
        ),
      ]),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.title, this.subtitle, this.iconColor, this.onTap});
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? iconColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: (iconColor ?? c.text2).withValues(alpha: .14), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 18, color: iconColor ?? c.text2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: context.t.titleSmall),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!, style: context.t.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ]),
          ),
          if (onTap != null) Icon(Icons.chevron_right_rounded, color: c.muted),
        ]),
      ),
    );
  }
}
