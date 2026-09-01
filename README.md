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
   challenger, the flow you described).
4. **Compare** — two options at a time. You can also call a tie, skip a pair you
   have no opinion on, or undo the last answer.
5. **Get your ranking** — podium, full table with relative strength, win/loss
   record, CSV export and a copy-the-top-10 button. Everything is saved, so you
   can leave mid-session and come back, or refine a finished ranking further.

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
