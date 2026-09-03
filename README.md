# Rankd — rank anything, two at a time

A ranking app built on pairwise comparison. You pick a topic, pick a level, and
then answer one question over and over: **this one or that one?** After a few
dozen taps you get a full ranked list of the topic.

Live at **https://mehdicavad.github.io/hellonewworld/**

No build step, no dependencies, no backend. Open `index.html` and it runs — which
also means it drops straight into a mobile WebView if you want to ship it as an app.

## The flow

1. **Choose a topic** — Movies, Actors, Footballers, Music, Food, Programming
   Languages, Cities, TV Series, or one you create yourself.
2. **Choose a level** — this sets how many options enter the ranking *and* how
   deep the catalogue goes:

   | Level | Options | Taps | Catalogue |
   |---|---|---|---|
   | 🌱 Casual | 8 | ~14 | household names only |
   | 🔥 Standard | 16 | ~34 | plus well-known picks |
   | 🧠 Expert | 24 | ~60 | plus deeper cuts |
   | 🏆 Marathon | everything | sized to the pool | the full catalogue |

3. **Choose a style** — *Smart duels* (the app picks the pair it is least sure
   about) or *King of the hill* (your winner stays on and defends against a new
   challenger, the flow you described). In King of the hill the champion holds
   the same slot on screen and only the challenger swaps in, so you can keep
   your eye on the title that is winning.
4. **Compare** — two options side by side, at every screen size. You can also call a tie, skip a pair you
   have no opinion on, or undo the last answer.
5. **Get your ranking** — the winner, then the full table with relative strength, win/loss
   record, CSV export and a copy-the-top-10 button. Everything is saved, so you
   can leave mid-session and come back, or refine a finished ranking further.

## Photos, posters and previews

Every option can carry media, from one of two free, key-less sources chosen
per topic:

| Topic | Source | Shows |
|---|---|---|
| Movies, TV Series | iTunes Search API | store poster / season art |
| Songs | iTunes Search API | album cover **and a 30-second preview** you can play on the card |
| Actors, Footballers, Music Artists, Food, Languages, Cities, custom | Wikipedia `pageimages` → Wikimedia Commons | a freely licensed photo |

iTunes is loaded as JSONP (one request per option, spaced ~220 ms apart because
the API rate-limits bursts, the pair on screen first). Apple chooses the preview
segment — almost always the hook, but the app calls it a *preview* rather than
promising the chorus. Wikipedia is one batched request per pool; only
Commons-hosted files are used because those carry free licences. Everything is
cached in the browser for 30 days, misses included, and every failure degrades
to the plain text card: media is never on the ranking's critical path.

On the results page each option's name links to where its media came from —
the Wikipedia article or the store page.

Where a Wikipedia title is ambiguous, the catalogue carries it as a fourth
field (`Parasite|2019|2|Parasite (2019 film)`); custom topics accept the same
after a second `|`.

## Pairing rules

Beyond picking the most informative pair, two rules you can feel: an option
never appears in two consecutive rounds, and no pair is ever asked twice while
unasked pairs remain. King of the hill's champion is the deliberate exception
to the first — it is *supposed* to stay. Both bend only when the pool is too
small to obey them (three options, say).

## How the ranking is computed

The naive approach — count wins — is bad: beating the weakest option counts the
same as beating the strongest, and any option that happens to draw easy opponents
floats to the top. Rankd avoids that with two pieces.

**Bradley–Terry model.** Every option gets a hidden strength `p`, and the model
says option *i* beats *j* with probability `p_i / (p_i + p_j)`. After each answer
the engine refits *all* strengths against *every* comparison you have made, using
Hunter's MM iteration, regularised with a half-win/half-loss against a virtual
average opponent so that an undefeated or winless option still gets a finite
rating. Beating a strong option is therefore worth more than beating a weak one,
and one unlucky early answer does not permanently sink an option the way it does
under an online scheme like Elo.

Because ratings are always re-derived from the comparison history, the history is
the only state that matters. That is what makes undo exact and a session safe to
serialise and resume anywhere.

**Adaptive pairing.** Each round the engine scores every possible pair and serves
the cheapest one, where cost rewards options that are close in current rating
(the answer you cannot predict is the answer that tells you the most), penalises
pairs already asked, and penalises options the session has over-sampled. Ties in
cost are broken randomly, and the left/right side is randomised so screen
position never becomes part of the ranking.

In simulation against a hidden true order (see `tests/engine.test.js`), this
recovers the exact order of 16 items from a perfect answerer within the default
round budget, and stays within about one rank position per item when 10% of the
answers contradict the truth. At the same budget it beats king-of-the-hill
pairing, which is why *Smart duels* is the default.

## Project layout

```
index.html              screens and markup
assets/css/app.css      one dark theme, mobile-first
assets/js/data.js       topic catalogue, levels, pool building
assets/js/engine.js     Bradley-Terry fit, pairing, session mutations
assets/js/storage.js    localStorage persistence with in-memory fallback
assets/js/app.js        hash routing, rendering, keyboard input
tests/engine.test.js    23 tests: unit + convergence simulations
```

The layers are deliberately separate: `engine.js` is pure data-in/data-out with
no DOM access, and `storage.js` is the only file that knows where sessions live.

## Running it

```sh
open index.html          # it really does just work from the filesystem
npm start                # or serve it over http on :8080
npm test                 # run the engine test suite
```

## Where to take it next

The pieces are arranged so none of these require a rewrite:

- **Real content database.** Replace the `RAW` catalogue in `data.js` with a
  `fetch()` against your own API or something like TMDB. Items only need
  `{ id, name, meta, tier }`.
- **Accounts and sync.** Swap the four functions in `storage.js` for HTTP calls.
  Sessions are already plain JSON, keyed by id, with a timestamp.
- **Global rankings.** Every session records the full comparison history, which
  is exactly the input a cross-user Bradley–Terry fit needs — running the same
  `refit` over pooled histories gives you a community ranking alongside each
  person's own.
- **Mobile app.** Wrap as-is in a WebView, or port `engine.js` directly: it is
  plain ES5 with no browser APIs.
- **Images.** Options currently render as generated monogram tiles so the app
  stays offline and dependency-free. Adding a poster or photo URL per item is a
  change to `renderOption` alone.

## Build

There is nothing to build to run the site: `index.html` plus `assets/` is the
deployment, and GitHub Pages serves it as is. `npm run build` is for the other
way to ship it — one self-contained file:

```
npm run build            # dist/rankd.html — the whole app in one file
```

The result runs from a double-click, a USB stick, an email attachment, or the
WebView of a mobile shell such as Capacitor or Cordova, with no server and no
relative paths. It is the source inlined, not minified, so it stays debuggable.
`node scripts/build.js --no-download` also removes the CSV button, for sandboxes
that block page-initiated downloads.
