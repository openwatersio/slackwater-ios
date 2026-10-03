// The App Store listing, read from the repo and shaped into App Store Connect
// request bodies. No network and no credentials, so asc.mjs's App Store
// commands can be tested offline (appstore.test.mjs).
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

// Apple's field limits (developer.apple.com/help/app-store-connect →
// Reference → App information). Keywords count bytes, the rest characters.
const LIMITS = {
  name: 30, subtitle: 30, promotionalText: 170, description: 4000, whatsNew: 4000,
};
const KEYWORD_BYTES = 100;

// Multi-line fields are arrays of lines in the JSON, so the file stays readable.
const text = (v) => (Array.isArray(v) ? v.join('\n') : v);

export function loadListing(file = new URL('../docs/appstore-listing.json', import.meta.url)) {
  const l = JSON.parse(fs.readFileSync(file, 'utf8'));
  l.versionLocalization.description = text(l.versionLocalization.description);
  l.reviewDetail.notes = text(l.reviewDetail.notes);
  const fields = { ...l.appInfoLocalization, ...l.versionLocalization };
  for (const [k, max] of Object.entries(LIMITS)) {
    if (fields[k] !== undefined && [...fields[k]].length > max) throw new Error(`${k} is ${[...fields[k]].length} characters, limit ${max}`);
  }
  if (Buffer.byteLength(fields.keywords) > KEYWORD_BYTES) throw new Error(`keywords are ${Buffer.byteLength(fields.keywords)} bytes, limit ${KEYWORD_BYTES}`);
  return l;
}

// What's New is the release notes above "Worth testing:", minus the version
// line and the blank line after it (docs/release-notes/README.md).
export function whatsNew(notes, version) {
  const lines = notes.split('\n');
  // Exactly the version, or the version and its build: "1.14.0 (45)" but never "1.14.01".
  const head = lines[0] === version || lines[0].startsWith(`${version} `);
  if (!head || lines[1] !== '') throw new Error(`release notes for ${version} must open with the version line and a blank line`);
  const end = lines.findIndex((line) => line.startsWith('Worth testing:'));
  // Without the marker the beta instructions would publish too.
  if (end < 0) throw new Error(`release notes for ${version} have no "Worth testing:" line`);
  const s = lines.slice(2, end).join('\n').trim();
  if (!s) throw new Error(`release notes for ${version} have nothing above "Worth testing:"`);
  if ([...s].length > LIMITS.whatsNew) throw new Error(`What's New is ${[...s].length} characters, limit ${LIMITS.whatsNew}`);
  return s;
}

// A JSON:API request body. rels maps each relationship name to [type, id].
export function body(type, { id, attributes, rels } = {}) {
  const data = { type };
  if (id) data.id = id;
  if (attributes) data.attributes = attributes;
  if (rels) data.relationships = Object.fromEntries(Object.entries(rels).map(([k, [t, i]]) => [k, { data: { type: t, id: i } }]));
  return { data };
}

// The first version of an app has no What's New; App Store Connect rejects the field.
export const versionLocalizationAttributes = (l, whatsNew) => ({ ...l.versionLocalization, ...(whatsNew && { whatsNew }) });

// The phone number stays out of the public repo. Unset, the API leaves it as is.
export const reviewDetailAttributes = (l, phone) => ({ ...l.reviewDetail, ...(phone && { contactPhone: phone }) });

export const categoryRels = (l) => ({
  primaryCategory: ['appCategories', l.appInfo.primaryCategory],
  secondaryCategory: ['appCategories', l.appInfo.secondaryCategory],
});

// One entry per directory scripts/screenshots.sh writes. The display types
// are the API's names for the 6.9" iPhone and 13" iPad slots; the sizes are
// what Apple accepts for each, portrait or landscape.
export const SCREENSHOT_SETS = [
  { dir: 'iphone-6.9', type: 'APP_IPHONE_67', sizes: [[1320, 2868], [1290, 2796], [1260, 2736]] },
  { dir: 'ipad-13', type: 'APP_IPAD_PRO_3GEN_129', sizes: [[2064, 2752], [2048, 2732]] },
];

// Width and height from a PNG's IHDR chunk.
export function pngSize(buf) {
  if (buf.readUInt32BE(12) !== 0x49484452) throw new Error('not a PNG');
  return [buf.readUInt32BE(16), buf.readUInt32BE(20)];
}

// Every PNG in dir, in file-name order, checked before anything on App Store
// Connect is deleted to make room for them.
export function screenshotFiles(dir, sizes) {
  const names = fs.readdirSync(dir).filter((f) => f.endsWith('.png')).sort();
  if (names.length < 1 || names.length > 10) throw new Error(`${dir} has ${names.length} PNGs; App Store Connect takes 1 to 10`);
  return names.map((name) => {
    const bytes = fs.readFileSync(path.join(dir, name));
    const [w, h] = pngSize(bytes);
    if (!sizes.some(([a, b]) => (w === a && h === b) || (w === b && h === a))) {
      throw new Error(`${name} is ${w}×${h}; this slot takes ${sizes.map((s) => s.join('×')).join(', ')}`);
    }
    return { name, bytes, checksum: crypto.createHash('md5').update(bytes).digest('hex') };
  });
}

// Slice a file into the parts App Store Connect's upload operations ask for.
export function chunks(bytes, ops) {
  const covered = ops.reduce((n, op) => n + op.length, 0);
  if (covered !== bytes.length) throw new Error(`upload operations cover ${covered} of ${bytes.length} bytes`);
  return ops.map((op) => ({
    method: op.method,
    url: op.url,
    headers: Object.fromEntries((op.requestHeaders ?? []).map((h) => [h.name, h.value])),
    body: bytes.subarray(op.offset, op.offset + op.length),
  }));
}
