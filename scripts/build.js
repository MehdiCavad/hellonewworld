#!/usr/bin/env node
/* Build: one self-contained HTML file.
 *
 * The app has no build step to run — index.html plus assets/ is the site.
 * This script exists for the other way people want to ship it: a single file
 * that works from a double-click, a USB stick, an email, or the WebView of a
 * mobile shell (Capacitor, Cordova), with no server and no relative paths.
 *
 *   node scripts/build.js                 -> dist/rankd.html
 *   node scripts/build.js --no-download   -> also drop the CSV button, for
 *                                            sandboxes that block downloads
 *
 * No dependencies, no minification: the output is the source, inlined, and
 * stays readable so a maintainer can debug the built file directly.
 */
'use strict';

var fs = require('fs');
var path = require('path');

var root = path.join(__dirname, '..');
var read = function (p) { return fs.readFileSync(path.join(root, p), 'utf8'); };
var noDownload = process.argv.indexOf('--no-download') !== -1;

var html = read('index.html');
var css = read('assets/css/app.css');
var scripts = ['data.js', 'engine.js', 'storage.js', 'media.js', 'app.js'];

/* Every <script src> in index.html must be one we inline, in that order, so
 * the build cannot silently drop a module someone adds later. */
var referenced = [];
html.replace(/<script src="assets\/js\/([^"]+)"><\/script>/g, function (_, file) {
  referenced.push(file);
  return '';
});
if (referenced.join(',') !== scripts.join(',')) {
  console.error('index.html references [' + referenced + '] but the build inlines [' + scripts + ']');
  process.exit(1);
}

var out = html
  .replace('<link rel="stylesheet" href="assets/css/app.css">', '<style>\n' + css + '\n</style>')
  .replace(/\s*<script src="assets\/js\/[^"]+"><\/script>/g, '')
  .replace('</body>', '<script>\n' + scripts.map(function (file) {
    return '/* ===== assets/js/' + file + ' ===== */\n' + read('assets/js/' + file);
  }).join('\n') + '\n</script>\n</body>');

if (noDownload) {
  var before = out;
  out = out
    .replace(/\s*<button class="btn" id="csvBtn">[^<]*<\/button>/, '')
    .replace("    el('csvBtn').addEventListener('click', downloadCsv);\n", '');
  if (out === before) {
    console.error('--no-download: CSV button not found; index.html or app.js changed shape');
    process.exit(1);
  }
}

/* Sanity: nothing external is left that the single file would need. */
var leftovers = out.match(/(src|href)="assets\//g);
if (leftovers) {
  console.error('Built file still references assets/: ' + leftovers.join(', '));
  process.exit(1);
}

var distDir = path.join(root, 'dist');
if (!fs.existsSync(distDir)) fs.mkdirSync(distDir);
var target = path.join(distDir, noDownload ? 'rankd-nodownload.html' : 'rankd.html');
fs.writeFileSync(target, out);
console.log(path.relative(root, target) + '  ' + (out.length / 1024).toFixed(1) + ' KB' +
  (noDownload ? '  (CSV download removed)' : ''));
