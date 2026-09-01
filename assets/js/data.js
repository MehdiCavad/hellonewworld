/* Seed catalogue.
 *
 * Items are written as "Name|meta|tier" to keep the file compact.
 *   tier 1 = household names, 2 = well known, 3 = deeper cuts.
 * The level a player picks decides which tiers are unlocked, so a higher
 * level means both more items and more obscure ones.
 *
 * This is the local stand-in for the content database. Swap `Data.loadTopic`
 * for a fetch() against a real API later; nothing else needs to change.
 */
(function (global) {
  'use strict';

  var RAW = {
    movies: {
      name: 'Movies',
      emoji: '🎬',
      blurb: 'All-time cinema',
      items: [
        'The Godfather|1972|1', 'The Shawshank Redemption|1994|1', 'Pulp Fiction|1994|1',
        'The Dark Knight|2008|1', 'Forrest Gump|1994|1', 'Inception|2010|1',
        'Fight Club|1999|1', 'The Matrix|1999|1', 'Goodfellas|1990|1',
        'Titanic|1997|1', 'Interstellar|2014|1', 'Gladiator|2000|1',
        'Schindler\'s List|1993|2', 'Se7en|1995|2', 'The Silence of the Lambs|1991|2',
        'Saving Private Ryan|1998|2', 'The Departed|2006|2', 'Casablanca|1942|2',
        'Parasite|2019|2', 'Whiplash|2014|2', 'The Prestige|2006|2',
        'No Country for Old Men|2007|2', 'Django Unchained|2012|2', 'Léon: The Professional|1994|2',
        'Apocalypse Now|1979|3', 'Taxi Driver|1976|3', 'There Will Be Blood|2007|3',
        'City of God|2002|3', 'Come and See|1985|3', 'Seven Samurai|1954|3',
        'In the Mood for Love|2000|3', 'Stalker|1979|3', 'Andrei Rublev|1966|3',
        'Paris, Texas|1984|3', 'The Hunt|2012|3', 'A Separation|2011|3'
      ]
    },
    actors: {
      name: 'Actors',
      emoji: '🎭',
      blurb: 'Screen legends',
      items: [
        'Anthony Hopkins|Wales|1', 'Al Pacino|USA|1', 'Robert De Niro|USA|1',
        'Meryl Streep|USA|1', 'Leonardo DiCaprio|USA|1', 'Tom Hanks|USA|1',
        'Denzel Washington|USA|1', 'Morgan Freeman|USA|1', 'Cate Blanchett|Australia|1',
        'Daniel Day-Lewis|UK|1', 'Joaquin Phoenix|USA|1', 'Christian Bale|UK|1',
        'Gary Oldman|UK|2', 'Viola Davis|USA|2', 'Frances McDormand|USA|2',
        'Philip Seymour Hoffman|USA|2', 'Tilda Swinton|UK|2', 'Javier Bardem|Spain|2',
        'Marion Cotillard|France|2', 'Mahershala Ali|USA|2', 'Oscar Isaac|USA|2',
        'Toni Collette|Australia|2', 'Ralph Fiennes|UK|2', 'Michael Fassbender|Ireland|2',
        'Isabelle Huppert|France|3', 'Toshiro Mifune|Japan|3', 'Setsuko Hara|Japan|3',
        'Klaus Kinski|Germany|3', 'Song Kang-ho|South Korea|3', 'Mads Mikkelsen|Denmark|3',
        'Vincent Cassel|France|3', 'Gian Maria Volontè|Italy|3'
      ]
    },
    footballers: {
      name: 'Footballers',
      emoji: '⚽',
      blurb: 'The greatest of all time',
      items: [
        'Lionel Messi|Argentina|1', 'Cristiano Ronaldo|Portugal|1', 'Diego Maradona|Argentina|1',
        'Pelé|Brazil|1', 'Ronaldinho|Brazil|1', 'Zinedine Zidane|France|1',
        'Ronaldo Nazário|Brazil|1', 'Johan Cruyff|Netherlands|1', 'Kylian Mbappé|France|1',
        'Andrés Iniesta|Spain|2', 'Xavi Hernández|Spain|2', 'Franz Beckenbauer|Germany|2',
        'Paolo Maldini|Italy|2', 'Thierry Henry|France|2', 'Roberto Baggio|Italy|2',
        'Michel Platini|France|2', 'Erling Haaland|Norway|2', 'Luka Modrić|Croatia|2',
        'Gerd Müller|Germany|2', 'Alfredo Di Stéfano|Argentina|2',
        'Garrincha|Brazil|3', 'Ferenc Puskás|Hungary|3', 'Lev Yashin|USSR|3',
        'Bobby Charlton|England|3', 'Romário|Brazil|3', 'George Best|N. Ireland|3',
        'Socrates|Brazil|3', 'Marco van Basten|Netherlands|3'
      ]
    },
    music: {
      name: 'Music Artists',
      emoji: '🎸',
      blurb: 'Bands and solo acts',
      items: [
        'The Beatles|UK|1', 'Queen|UK|1', 'Pink Floyd|UK|1', 'Michael Jackson|USA|1',
        'Led Zeppelin|UK|1', 'Bob Dylan|USA|1', 'Nirvana|USA|1', 'Radiohead|UK|1',
        'The Rolling Stones|UK|1', 'Beyoncé|USA|1',
        'David Bowie|UK|2', 'Prince|USA|2', 'Metallica|USA|2', 'Daft Punk|France|2',
        'Kendrick Lamar|USA|2', 'Amy Winehouse|UK|2', 'Johnny Cash|USA|2',
        'Stevie Wonder|USA|2', 'Massive Attack|UK|2', 'Fleetwood Mac|UK/USA|2',
        'Talking Heads|USA|3', 'Portishead|UK|3', 'Joy Division|UK|3',
        'Nina Simone|USA|3', 'Aphex Twin|UK|3', 'Sigur Rós|Iceland|3',
        'Fela Kuti|Nigeria|3', 'Tom Waits|USA|3', 'Cocteau Twins|UK|3'
      ]
    },
    food: {
      name: 'Food',
      emoji: '🍽️',
      blurb: 'Dishes worth arguing about',
      items: [
        'Pizza|Italy|1', 'Sushi|Japan|1', 'Burger|USA|1', 'Pasta Carbonara|Italy|1',
        'Kebab|Türkiye|1', 'Ramen|Japan|1', 'Tacos|Mexico|1', 'Fried Chicken|USA|1',
        'Dumplings|China|1', 'Plov|Azerbaijan|1',
        'Dolma|Azerbaijan|2', 'Pad Thai|Thailand|2', 'Paella|Spain|2', 'Pho|Vietnam|2',
        'Shawarma|Levant|2', 'Lasagna|Italy|2', 'Biryani|India|2', 'Khinkali|Georgia|2',
        'Bibimbap|South Korea|2', 'Falafel|Levant|2',
        'Düşbərə|Azerbaijan|3', 'Qutab|Azerbaijan|3', 'Okonomiyaki|Japan|3',
        'Ceviche|Peru|3', 'Injera with Doro Wat|Ethiopia|3', 'Poutine|Canada|3',
        'Borscht|Ukraine|3', 'Laksa|Malaysia|3'
      ]
    },
    languages: {
      name: 'Programming Languages',
      emoji: '💻',
      blurb: 'Settle it once and for all',
      items: [
        'Python|1991|1', 'JavaScript|1995|1', 'Java|1995|1', 'C|1972|1',
        'C++|1985|1', 'TypeScript|2012|1', 'Go|2009|1', 'Rust|2010|1',
        'C#|2000|1', 'SQL|1974|1',
        'Kotlin|2011|2', 'Swift|2014|2', 'PHP|1995|2', 'Ruby|1995|2',
        'Scala|2004|2', 'R|1993|2', 'Dart|2011|2', 'Bash|1989|2',
        'Elixir|2011|3', 'Haskell|1990|3', 'Clojure|2007|3', 'Erlang|1986|3',
        'OCaml|1996|3', 'Lisp|1958|3', 'Fortran|1957|3', 'Zig|2016|3',
        'Prolog|1972|3', 'Smalltalk|1972|3'
      ]
    },
    cities: {
      name: 'Cities',
      emoji: '🌍',
      blurb: 'Where would you rather be',
      items: [
        'Tokyo|Japan|1', 'Paris|France|1', 'New York|USA|1', 'London|UK|1',
        'Rome|Italy|1', 'Istanbul|Türkiye|1', 'Barcelona|Spain|1', 'Dubai|UAE|1',
        'Baku|Azerbaijan|1', 'Singapore|Singapore|1',
        'Lisbon|Portugal|2', 'Prague|Czechia|2', 'Vienna|Austria|2', 'Seoul|South Korea|2',
        'Amsterdam|Netherlands|2', 'Copenhagen|Denmark|2', 'Kyoto|Japan|2',
        'Tbilisi|Georgia|2', 'Marrakesh|Morocco|2', 'Buenos Aires|Argentina|2',
        'Sheki|Azerbaijan|3', 'Valparaíso|Chile|3', 'Tallinn|Estonia|3',
        'Hanoi|Vietnam|3', 'Ljubljana|Slovenia|3', 'Bergen|Norway|3',
        'Samarkand|Uzbekistan|3', 'Cartagena|Colombia|3'
      ]
    },
    series: {
      name: 'TV Series',
      emoji: '📺',
      blurb: 'Binge-worthy or overrated',
      items: [
        'Breaking Bad|2008|1', 'Game of Thrones|2011|1', 'The Sopranos|1999|1',
        'The Wire|2002|1', 'Friends|1994|1', 'Chernobyl|2019|1',
        'Stranger Things|2016|1', 'Sherlock|2010|1', 'The Office (US)|2005|1',
        'True Detective|2014|2', 'Better Call Saul|2015|2', 'Fargo|2014|2',
        'Mr. Robot|2015|2', 'Peaky Blinders|2013|2', 'Dark|2017|2',
        'Band of Brothers|2001|2', 'Succession|2018|2', 'The Crown|2016|2',
        'The Leftovers|2014|3', 'Twin Peaks|1990|3', 'Deadwood|2004|3',
        'Six Feet Under|2001|3', 'Rectify|2013|3', 'The Bureau|2015|3',
        'Babylon Berlin|2017|3', 'Halt and Catch Fire|2014|3'
      ]
    }
  };

  /* Levels decide how deep the pool goes and how long the session runs. */
  var LEVELS = [
    { id: 'casual',   name: 'Casual',   emoji: '🌱', tiers: [1],       size: 8,  rounds: 14, blurb: 'Household names only. A few minutes.' },
    { id: 'standard', name: 'Standard', emoji: '🔥', tiers: [1, 2],    size: 16, rounds: 34, blurb: 'The usual suspects plus some depth.' },
    { id: 'expert',   name: 'Expert',   emoji: '🧠', tiers: [1, 2, 3], size: 24, rounds: 60, blurb: 'Deeper cuts. You need to know your stuff.' },
    { id: 'marathon', name: 'Marathon', emoji: '🏆', tiers: [1, 2, 3], size: 0,  rounds: 0,  blurb: 'Everything in the topic. Take your time.' }
  ];

  function slug(text) {
    return String(text).toLowerCase()
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/^-+|-+$/g, '') || 'item';
  }

  function parseItem(raw, topicId, index) {
    var parts = String(raw).split('|');
    var name = (parts[0] || '').trim();
    return {
      id: topicId + ':' + slug(name) + ':' + index,
      name: name,
      meta: (parts[1] || '').trim(),
      tier: Number(parts[2]) || 1
    };
  }

  var topics = Object.keys(RAW).map(function (id) {
    var raw = RAW[id];
    return {
      id: id,
      name: raw.name,
      emoji: raw.emoji,
      blurb: raw.blurb,
      builtIn: true,
      items: raw.items.map(function (row, i) { return parseItem(row, id, i); })
    };
  });

  /* Builds a topic object from a user-supplied list of names. */
  function makeCustomTopic(name, emoji, lines) {
    var id = 'custom-' + slug(name) + '-' + Date.now().toString(36);
    var items = lines
      .map(function (line) { return String(line).trim(); })
      .filter(Boolean)
      .map(function (line, i) {
        var bits = line.split('|');
        return {
          id: id + ':' + slug(bits[0]) + ':' + i,
          name: bits[0].trim(),
          meta: (bits[1] || '').trim(),
          tier: 1
        };
      });
    return {
      id: id,
      name: name.trim(),
      emoji: emoji || '⭐',
      blurb: items.length + ' options',
      builtIn: false,
      items: items
    };
  }

  /* Picks the pool for a topic + level: filter by tier, then take the most
   * prominent `size` items (tier order preserves the "famous first" idea)
   * with a shuffle inside each tier so repeat sessions are not identical. */
  function buildPool(topic, level, rng) {
    var random = rng || Math.random;
    var allowed = topic.items.filter(function (item) {
      return level.tiers.indexOf(item.tier) !== -1;
    });
    var byTier = {};
    allowed.forEach(function (item) {
      (byTier[item.tier] = byTier[item.tier] || []).push(item);
    });
    var ordered = [];
    Object.keys(byTier).sort().forEach(function (tier) {
      var bucket = byTier[tier].slice();
      for (var i = bucket.length - 1; i > 0; i--) {
        var j = Math.floor(random() * (i + 1));
        var tmp = bucket[i]; bucket[i] = bucket[j]; bucket[j] = tmp;
      }
      ordered = ordered.concat(bucket);
    });
    var size = level.size > 0 ? Math.min(level.size, ordered.length) : ordered.length;
    return ordered.slice(0, size);
  }

  /* Rounds needed when the level does not fix a number (Marathon). */
  function roundsFor(level, poolSize) {
    if (level.rounds > 0) return Math.min(level.rounds, maxUsefulRounds(poolSize));
    return maxUsefulRounds(poolSize);
  }

  function maxUsefulRounds(n) {
    if (n < 2) return 0;
    return Math.max(n, Math.round(n * Math.log2(n) * 0.9));
  }

  var Data = {
    topics: topics,
    levels: LEVELS,
    getTopic: function (id) {
      for (var i = 0; i < topics.length; i++) {
        if (topics[i].id === id) return topics[i];
      }
      return null;
    },
    getLevel: function (id) {
      for (var i = 0; i < LEVELS.length; i++) {
        if (LEVELS[i].id === id) return LEVELS[i];
      }
      return LEVELS[1];
    },
    countForLevel: function (topic, level) {
      var allowed = topic.items.filter(function (item) {
        return level.tiers.indexOf(item.tier) !== -1;
      });
      return level.size > 0 ? Math.min(level.size, allowed.length) : allowed.length;
    },
    buildPool: buildPool,
    roundsFor: roundsFor,
    maxUsefulRounds: maxUsefulRounds,
    makeCustomTopic: makeCustomTopic,
    slug: slug
  };

  if (typeof module !== 'undefined' && module.exports) module.exports = Data;
  global.Data = Data;
})(typeof globalThis !== 'undefined' ? globalThis : this);
