/* Local persistence.
 *
 * Everything lives in localStorage under one namespace, with an in-memory
 * fallback so the app still runs in private windows or wherever storage is
 * blocked. Sessions are stored whole, exactly as the engine produces them, so
 * moving to a server later is a matter of swapping these four functions for
 * fetch() calls — nothing above this layer knows where the data lives.
 */
(function (global) {
  'use strict';

  var PREFIX = 'rankd.v1.';
  var KEY_SESSIONS = PREFIX + 'sessions';
  var KEY_TOPICS = PREFIX + 'topics';
  var KEY_PREFS = PREFIX + 'prefs';
  var KEY_MEDIA = PREFIX + 'media2';
  var MAX_SESSIONS = 60;

  var memory = {};
  var available = (function () {
    try {
      var probe = PREFIX + 'probe';
      global.localStorage.setItem(probe, '1');
      global.localStorage.removeItem(probe);
      return true;
    } catch (err) {
      return false;
    }
  })();

  function read(key, fallback) {
    try {
      var raw = available ? global.localStorage.getItem(key) : memory[key];
      if (!raw) return fallback;
      var parsed = JSON.parse(raw);
      return parsed === null || parsed === undefined ? fallback : parsed;
    } catch (err) {
      return fallback;
    }
  }

  function write(key, value) {
    var raw = JSON.stringify(value);
    try {
      if (available) global.localStorage.setItem(key, raw);
      else memory[key] = raw;
      return true;
    } catch (err) {
      /* Most likely the quota: keep going in memory rather than losing the
       * session the user is in the middle of. */
      memory[key] = raw;
      return false;
    }
  }

  function allSessions() {
    var list = read(KEY_SESSIONS, []);
    return Array.isArray(list) ? list : [];
  }

  function saveSession(session) {
    var list = allSessions().filter(function (item) { return item.id !== session.id; });
    list.unshift(session);
    list.sort(function (a, b) { return (b.updatedAt || 0) - (a.updatedAt || 0); });
    write(KEY_SESSIONS, list.slice(0, MAX_SESSIONS));
    return session;
  }

  function getSession(id) {
    var list = allSessions();
    for (var i = 0; i < list.length; i++) {
      if (list[i].id === id) return list[i];
    }
    return null;
  }

  function deleteSession(id) {
    write(KEY_SESSIONS, allSessions().filter(function (item) { return item.id !== id; }));
  }

  function customTopics() {
    var list = read(KEY_TOPICS, []);
    return Array.isArray(list) ? list : [];
  }

  function saveTopic(topic) {
    var list = customTopics().filter(function (item) { return item.id !== topic.id; });
    list.unshift(topic);
    write(KEY_TOPICS, list);
    return topic;
  }

  function deleteTopic(id) {
    write(KEY_TOPICS, customTopics().filter(function (item) { return item.id !== id; }));
    allSessions().forEach(function (session) {
      if (session.topicId === id) deleteSession(session.id);
    });
  }

  function prefs() {
    var value = read(KEY_PREFS, {});
    return value && typeof value === 'object' ? value : {};
  }

  function savePrefs(patch) {
    var next = prefs();
    Object.keys(patch).forEach(function (key) { next[key] = patch[key]; });
    write(KEY_PREFS, next);
    return next;
  }

  function mediaCache() {
    var value = read(KEY_MEDIA, {});
    return value && typeof value === 'object' ? value : {};
  }

  function saveMediaCache(cache) {
    write(KEY_MEDIA, cache);
  }

  var Storage = {
    persistent: available,
    mediaCache: mediaCache,
    saveMediaCache: saveMediaCache,
    allSessions: allSessions,
    getSession: getSession,
    saveSession: saveSession,
    deleteSession: deleteSession,
    customTopics: customTopics,
    saveTopic: saveTopic,
    deleteTopic: deleteTopic,
    prefs: prefs,
    savePrefs: savePrefs
  };

  if (typeof module !== 'undefined' && module.exports) module.exports = Storage;
  global.Storage = Storage;
})(typeof globalThis !== 'undefined' ? globalThis : this);
