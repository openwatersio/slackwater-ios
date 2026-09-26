import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import fs, { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

import {
  body, categoryRels, chunks, loadListing, pngSize, reviewDetailAttributes,
  screenshotFiles, SCREENSHOT_SETS, versionLocalizationAttributes, whatsNew,
} from './appstore.mjs';

const listingFile = new URL('../docs/appstore-listing.json', import.meta.url);
const withListing = (edit) => {
  const l = JSON.parse(fs.readFileSync(listingFile, 'utf8'));
  edit(l);
  const file = join(mkdtempSync(join(tmpdir(), 'listing-')), 'listing.json');
  writeFileSync(file, JSON.stringify(l));
  return file;
};

// A PNG signature and IHDR chunk are all pngSize and screenshotFiles read.
const png = (w, h) => {
  const b = Buffer.alloc(33);
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]).copy(b);
  b.writeUInt32BE(13, 8);
  b.write('IHDR', 12, 'latin1');
  b.writeUInt32BE(w, 16);
  b.writeUInt32BE(h, 20);
  return b;
};

test('the committed listing loads and fits every limit', () => {
  const l = loadListing();
  assert.equal(l.appInfoLocalization.name, 'Slackwater — Tides & Currents');
  assert.equal(l.versionLocalization.keywords.length, 98);
  // Arrays of lines become one string with the paragraph breaks kept.
  assert.match(l.versionLocalization.description, /^Every tide app.*\n\nNo spinner\./);
  assert.match(l.versionLocalization.description, /\nWORKS WHERE THERE IS NO SIGNAL\nThe predictions/);
  assert.match(l.reviewDetail.notes, /identically\.\n\nNo account/);
});

test('the listing loader rejects copy over Apple’s limits', () => {
  assert.throws(() => loadListing(withListing((l) => { l.appInfoLocalization.subtitle = 'x'.repeat(31); })), /subtitle is 31 characters, limit 30/);
  assert.throws(() => loadListing(withListing((l) => { l.versionLocalization.promotionalText = 'x'.repeat(171); })), /promotionalText/);
  // An em dash is one character but three bytes; keywords count bytes.
  assert.doesNotThrow(() => loadListing(withListing((l) => { l.appInfoLocalization.name = '—'.repeat(30); })));
  assert.throws(() => loadListing(withListing((l) => { l.versionLocalization.keywords = '—'.repeat(34); })), /keywords are 102 bytes/);
});

test('What’s New is the notes between the version line and Worth testing', () => {
  const notes = '1.15.0 (60)\n\nFaster maps.\n\n· One\n· Two\n\nWorth testing: the map.\n';
  assert.equal(whatsNew(notes, '1.15.0'), 'Faster maps.\n\n· One\n· Two');
  assert.equal(whatsNew('1.15.0\n\nFaster maps.\n\nWorth testing: x', '1.15.0'), 'Faster maps.');
  assert.throws(() => whatsNew('Faster maps.\n\nWorth testing: x', '1.15.0'), /version line/);
  assert.throws(() => whatsNew('1.15.01 (60)\n\nFaster maps.\n\nWorth testing: x', '1.15.0'), /version line/);
  assert.throws(() => whatsNew('1.15.0\n\nFaster maps.\n', '1.15.0'), /no "Worth testing:"/);
  assert.throws(() => whatsNew('1.15.0\n\nWorth testing: x', '1.15.0'), /nothing above/);
});

test('What’s New extraction matches the sed line in release-notes/README.md', () => {
  const file = new URL('../docs/release-notes/1.14.0.md', import.meta.url);
  const notes = fs.readFileSync(file, 'utf8');
  const sed = execFileSync('sed', ['-e', '1,2d', '-e', '/^Worth testing:/,$d', file.pathname], { encoding: 'utf8' }).trim();
  assert.equal(whatsNew(notes, '1.14.0'), sed);
  assert.match(whatsNew(notes, '1.14.0'), /^Welcome to the first release/);
});

test('request bodies follow JSON:API', () => {
  assert.deepEqual(body('appStoreVersions', {
    attributes: { platform: 'IOS', versionString: '1.14.0' },
    rels: { app: ['apps', '123'] },
  }), { data: {
    type: 'appStoreVersions',
    attributes: { platform: 'IOS', versionString: '1.14.0' },
    relationships: { app: { data: { type: 'apps', id: '123' } } },
  } });
  assert.deepEqual(body('reviewSubmissions', { id: 'r1', attributes: { submitted: true } }),
    { data: { type: 'reviewSubmissions', id: 'r1', attributes: { submitted: true } } });
});

test('payload builders pick the listing fields each resource takes', () => {
  const l = loadListing();
  assert.deepEqual(Object.keys(versionLocalizationAttributes(l)).sort(),
    ['description', 'keywords', 'marketingUrl', 'promotionalText', 'supportUrl']);
  assert.equal(versionLocalizationAttributes(l, 'New.').whatsNew, 'New.');
  assert.equal(reviewDetailAttributes(l).contactPhone, undefined);
  assert.equal(reviewDetailAttributes(l, '+1 555 0100').contactPhone, '+1 555 0100');
  assert.equal(reviewDetailAttributes(l).demoAccountRequired, false);
  assert.deepEqual(categoryRels(l), {
    primaryCategory: ['appCategories', 'WEATHER'],
    secondaryCategory: ['appCategories', 'NAVIGATION'],
  });
});

test('screenshots are read in name order and checked against the slot', () => {
  const dir = mkdtempSync(join(tmpdir(), 'shots-'));
  const iphone = SCREENSHOT_SETS.find((s) => s.type === 'APP_IPHONE_67');
  writeFileSync(join(dir, '02-tide-rising.png'), png(1320, 2868));
  writeFileSync(join(dir, '01-currents-slack.png'), png(2868, 1320));
  writeFileSync(join(dir, 'notes.txt'), 'ignored');
  const files = screenshotFiles(dir, iphone.sizes);
  assert.deepEqual(files.map((f) => f.name), ['01-currents-slack.png', '02-tide-rising.png']);
  assert.match(files[0].checksum, /^[0-9a-f]{32}$/);
  assert.deepEqual(pngSize(files[1].bytes), [1320, 2868]);

  writeFileSync(join(dir, '03-ipad.png'), png(2064, 2752));
  assert.throws(() => screenshotFiles(dir, iphone.sizes), /03-ipad.png is 2064×2752/);
  assert.throws(() => screenshotFiles(mkdtempSync(join(tmpdir(), 'empty-')), iphone.sizes), /0 PNGs/);
});

test('chunks slice the file exactly as the upload operations ask', () => {
  const bytes = Buffer.from('0123456789');
  const parts = chunks(bytes, [
    { method: 'PUT', url: 'https://a/1', offset: 0, length: 6, requestHeaders: [{ name: 'Content-Type', value: 'image/png' }] },
    { method: 'PUT', url: 'https://a/2', offset: 6, length: 4, requestHeaders: [] },
  ]);
  assert.deepEqual(parts.map((p) => p.body.toString()), ['012345', '6789']);
  assert.deepEqual(parts[0].headers, { 'Content-Type': 'image/png' });
  assert.equal(parts[1].url, 'https://a/2');
  assert.throws(() => chunks(bytes, [{ method: 'PUT', url: 'x', offset: 0, length: 6 }]), /cover 6 of 10 bytes/);
});
