import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'state/providers.dart';
import 'theme/theme.dart';
import 'ui/screens/arena_screen.dart';
import 'ui/screens/community_screen.dart';
import 'ui/screens/history_screen.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/onboarding_screen.dart';
import 'ui/screens/results_screen.dart';
import 'ui/screens/settings_screen.dart';
import 'ui/screens/shell.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final onboarded = ref.read(onboardedProvider);
      if (!onboarded && state.matchedLocation != '/welcome') return '/welcome';
      return null;
    },
    routes: [
      GoRoute(path: '/welcome', builder: (_, _) => const OnboardingScreen()),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/', builder: (_, _) => const HomeScreen())]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/community', builder: (_, s) => CommunityScreen(initialSlug: s.uri.queryParameters['topic'])),
          ]),
          StatefulShellBranch(routes: [GoRoute(path: '/history', builder: (_, _) => const HistoryScreen())]),
        ],
      ),
      GoRoute(path: '/play/:id', builder: (_, s) => ArenaScreen(sessionId: s.pathParameters['id']!)),
      GoRoute(path: '/results/:id', builder: (_, s) => ResultsScreen(sessionId: s.pathParameters['id']!)),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
    ],
  );
});

class RankdApp extends ConsumerWidget {
  const RankdApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Rankd',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ref.watch(themeModeProvider),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
