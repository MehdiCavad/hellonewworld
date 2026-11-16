# Rankd app (Flutter)

Rank anything, two at a time. Flutter 3.50 / Dart 3.14, Riverpod, go_router.

## Run

```bash
cd mobile
flutter pub get
flutter test                                   # engine parity tests
flutter run --dart-define=RANKD_API=http://10.0.2.2:5080   # Android emulator → API on your machine
flutter run -d chrome                          # web, API defaults to http://localhost:5080
```

Start the API first (see `../server/README.md`). The app also works with no server at all: it falls back to the
last catalogue it downloaded, then to the catalogue bundled in `assets/data/catalogue.json`, and uploads your
rankings once it is back online.

## Layout

| Path | What it holds |
|---|---|
| `lib/engine/ranking_engine.dart` | Dart port of the ranking engine. Matches the server and the original prototype answer for answer (see `test/engine_test.dart`). |
| `lib/data/` | API client, offline-first repository, models, saved sessions |
| `lib/state/providers.dart` | Riverpod providers: catalogue, sessions, theme, onboarding |
| `lib/theme/theme.dart` | Design tokens (dark and light), type scale, gradients |
| `lib/ui/screens/` | Onboarding, Play (topics), topic sheet, arena, results, community, history, settings |
| `lib/ui/widgets/common.dart` | Shared pieces: aurora background, gradient button, glass bar, item art |

## Screens

- **Onboarding**: three pages, skippable.
- **Play**: topic grid and a "continue" card for the last unfinished ranking.
- **Topic sheet**: choose a level (Casual, Standard, Expert, Marathon) and a style (Smart duels or King of the hill).
- **Arena**: tap a card or use ← / →; T for a tie, S to skip, U to undo. Song topics play 30-second previews.
- **Results**: podium, full list with strength bars, dimmed rows where data is thin, refine with 10 more, copy the top 10.
- **Community**: everyone's answers per topic, with movement since the last run.
- **History** and **Settings** (theme, connection status, delete my data, credits and licences).

Fonts are Inter and Bricolage Grotesque, bundled under the SIL Open Font License.
