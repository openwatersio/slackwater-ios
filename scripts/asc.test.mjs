import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

process.env.ASC_KEY_ID = 'TESTKEY';
process.env.ASC_ISSUER_ID = '00000000-0000-0000-0000-000000000000';
process.env.ASC_KEY = crypto.generateKeyPairSync('ec', { namedCurve: 'P-256' }).privateKey.export({ type: 'pkcs8', format: 'pem' });

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'asc-test-'));
const groupsFile = path.join(dir, 'groups.txt');
fs.writeFileSync(groupsFile, 'Beta\n');

const calls = [];
let externalName = 'Beta';
let externalState = 'READY_FOR_BETA_SUBMISSION';
let attached = false;
globalThis.fetch = async (url, options = {}) => {
  const pathname = new URL(url).pathname + new URL(url).search;
  calls.push([options.method ?? 'GET', pathname, String(url)]);
  let body;
  if (pathname.startsWith('/v1/apps?')) {
    body = { data: [{ id: 'app-1', attributes: { bundleId: 'io.openwaters.slackwater' } }] };
  } else if (pathname.startsWith('/v1/betaGroups?')) {
    body = { data: [
      { id: 'nightly', attributes: { name: 'Nightly', isInternalGroup: true } },
      { id: 'beta', attributes: { name: externalName, isInternalGroup: false } },
    ] };
  } else if (pathname.startsWith('/v1/builds?')) {
    body = {
      data: [{ id: 'build-48', attributes: { version: '48', processingState: 'VALID' }, relationships: {
        preReleaseVersion: { data: { id: 'train-115' } }, betaGroups: { data: attached ? [{ id: 'beta' }] : [] },
      } }],
      included: [
        { id: 'train-115', type: 'preReleaseVersions', attributes: { version: '1.15.0' } },
        { id: 'beta', type: 'betaGroups', attributes: { name: 'Beta' } },
      ],
    };
  } else if (pathname === '/v1/builds/build-48/buildBetaDetail') {
    body = { data: { attributes: { externalBuildState: externalState } } };
  } else if ((options.method ?? 'GET') === 'POST' && pathname.includes('/relationships/builds')) {
    attached = true;
    body = { data: {} };
  } else if ((options.method ?? 'GET') === 'POST' && pathname === '/v1/betaAppReviewSubmissions') {
    externalState = 'WAITING_FOR_BETA_REVIEW';
    body = { data: {} };
  } else {
    body = { data: {} };
  }
  return new Response(JSON.stringify(body), { status: 200 });
};

const output = [];
const originalLog = console.log;
console.log = (...args) => output.push(args.join(' '));

process.argv = ['node', 'asc.mjs', 'verify', '1.15.0', '48', groupsFile];
await import(`./asc.mjs?verify=${Date.now()}`);
assert.match(output.pop(), /1\.15\.0 \(48\).*Beta/);
assert.ok(calls.some(([, , url]) => url.includes('filter[version]=48')), 'lookup did not filter for the selected build');

externalName = 'beta';
process.argv = ['node', 'asc.mjs', 'verify', '1.15.0', '48', groupsFile];
await assert.rejects(import(`./asc.mjs?drift=${Date.now()}`), /expected external groups \[Beta\], found \[beta\]/);

externalName = 'Beta';
process.argv = ['node', 'asc.mjs', 'promote', '1.15.0', '48', groupsFile];
await import(`./asc.mjs?promote=${Date.now()}`);
assert.equal(calls.filter(([method]) => method === 'POST').length, 2, 'first promotion did not attach and submit exactly once');

process.argv = ['node', 'asc.mjs', 'promote', '1.15.0', '48', groupsFile];
await import(`./asc.mjs?rerun=${Date.now()}`);
assert.equal(calls.filter(([method]) => method === 'POST').length, 2, 'rerun repeated a completed mutation');

console.log = originalLog;
fs.rmSync(dir, { recursive: true });
console.log('App Store Connect promotion checks passed');
