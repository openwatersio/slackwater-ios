import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

// Run the real CLI with only Apple's HTTP service and polling delays replaced.
async function run(args, respond) {
  const saved = { fetch: globalThis.fetch, timeout: globalThis.setTimeout, argv: process.argv, log: console.log };
  const keys = ['ASC_KEY_ID', 'ASC_ISSUER_ID', 'ASC_KEY'];
  const env = keys.map((key) => process.env[key]);
  process.env.ASC_KEY_ID = 'TESTKEY';
  process.env.ASC_ISSUER_ID = 'test-issuer';
  process.env.ASC_KEY = crypto.generateKeyPairSync('ec', { namedCurve: 'P-256' }).privateKey.export({ type: 'pkcs8', format: 'pem' });
  const calls = [], output = [];
  globalThis.fetch = async (url, options = {}) => {
    const u = new URL(url);
    const call = { method: options.method ?? 'GET', path: u.pathname, query: u.searchParams, body: typeof options.body === 'string' ? JSON.parse(options.body) : options.body };
    calls.push(call);
    const data = call.path === '/v1/apps' ? { data: [{ id: 'app', attributes: { bundleId: 'io.openwaters.slackwater' } }] } : respond(call);
    assert.ok(data, `unexpected ${call.method} ${call.path}`);
    return new Response(JSON.stringify(data));
  };
  globalThis.setTimeout = (fn) => { queueMicrotask(fn); return 0; };
  console.log = (...parts) => output.push(parts.join(' '));
  process.argv = ['node', 'asc.mjs', ...args];
  try {
    await import(`./asc.mjs?appstore=${crypto.randomUUID()}`);
    return { calls, output };
  } finally {
    globalThis.fetch = saved.fetch;
    globalThis.setTimeout = saved.timeout;
    process.argv = saved.argv;
    console.log = saved.log;
    keys.forEach((key, i) => { if (env[i] === undefined) delete process.env[key]; else process.env[key] = env[i]; });
  }
}

const version = (state = 'PREPARE_FOR_SUBMISSION') => ({ id: 'version', attributes: { versionString: '1.15.0', appVersionState: state } });

test('a keyed prepare dry run plans app info for the version it would create', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'asc-dry-'));
  try {
    fs.mkdirSync(path.join(dir, 'iphone-6.3'));
    const png = Buffer.alloc(33);
    Buffer.from('89504e470d0a1a0a', 'hex').copy(png);
    png.writeUInt32BE(13, 8); png.write('IHDR', 12); png.writeUInt32BE(1206, 16); png.writeUInt32BE(2622, 20);
    fs.writeFileSync(path.join(dir, 'iphone-6.3', '01.png'), png);
    const { calls, output } = await run(['prepare', '1.14.0', '63', dir, '--dry-run'], (c) => {
      if (c.path.endsWith('/appStoreVersions')) return { data: [{ id: 'live', attributes: { versionString: '1.0', appVersionState: 'READY_FOR_DISTRIBUTION' } }] };
      if (c.path.endsWith('/appInfos')) return { data: [{ id: 'live-info', attributes: { state: 'READY_FOR_DISTRIBUTION' } }] };
      if (c.path === '/v1/builds') return { data: [{ id: 'build', attributes: { processingState: 'VALID', expired: false, buildAudienceType: 'APP_STORE_ELIGIBLE' } }] };
    });
    assert.ok(calls.every((c) => c.method === 'GET'), 'dry run sent a write');
    assert.ok(output.some((line) => line.includes('POST /v1/appInfoLocalizations')));
    assert.ok(output.some((line) => line.includes('APP_IPHONE_61')));
  } finally { fs.rmSync(dir, { recursive: true }); }
});

test('release can be retried after Apple starts or completes distribution', async () => {
  for (const state of ['PROCESSING_FOR_DISTRIBUTION', 'READY_FOR_DISTRIBUTION']) {
    const { calls } = await run(['release', '1.15.0', '--yes'], (c) => {
      if (c.path.endsWith('/appStoreVersions')) return { data: [version(state)] };
    });
    assert.ok(calls.every((c) => c.method === 'GET'), `${state} repeated the release request`);
  }
});

test('a manual release requests distribution and refuses an unapproved version', async () => {
  const { calls, output } = await run(['release', '1.15.0', '--yes'], (c) => {
    if (c.path.endsWith('/appStoreVersions')) return { data: [version('PENDING_DEVELOPER_RELEASE')] };
    if (c.path === '/v1/appStoreVersionReleaseRequests') return { data: { id: 'release' } };
  });
  assert.equal(calls.filter((c) => c.method === 'POST').length, 1);
  assert.match(output.at(-1), /release requested/);
  await assert.rejects(run(['release', '1.15.0', '--yes'], (c) => {
    if (c.path.endsWith('/appStoreVersions')) return { data: [version()] };
  }), /PREPARE_FOR_SUBMISSION/);
});

test('screenshot processing waits through empty and incomplete responses', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'asc-shots-'));
  let polls = 0, uploads = 0;
  try {
    fs.mkdirSync(path.join(dir, 'iphone-6.9'));
    const png = Buffer.alloc(33);
    Buffer.from('89504e470d0a1a0a', 'hex').copy(png);
    png.writeUInt32BE(13, 8); png.write('IHDR', 12); png.writeUInt32BE(1320, 16); png.writeUInt32BE(2868, 20);
    for (const name of ['01.png', '02.png']) fs.writeFileSync(path.join(dir, 'iphone-6.9', name), png);
    await run(['screenshots', '1.15.0', dir], (c) => {
      if (c.path.endsWith('/appStoreVersions')) return { data: [version()] };
      if (c.path.endsWith('/appStoreVersionLocalizations')) return { data: [{ id: 'locale' }] };
      if (c.path.endsWith('/appScreenshotSets')) return { data: [{ id: 'set' }] };
      if (c.path === '/v1/appScreenshots' && c.method === 'POST') return { data: { id: `shot-${++uploads}`, attributes: { uploadOperations: [{ method: 'PUT', url: 'https://uploads.apple.com/upload', offset: 0, length: 33 }] } } };
      if (c.path === '/upload') return { data: {} };
      if (c.method === 'PATCH') return { data: {} };
      if (c.path === '/v1/appScreenshotSets/set/appScreenshots') {
        if (!uploads) return { data: [] };
        const count = Math.min(polls++, 2);
        return { data: Array.from({ length: count }, (_, i) => ({ id: `shot-${i + 1}`, attributes: { assetDeliveryState: { state: 'COMPLETE' } } })) };
      }
    });
    assert.equal(polls, 3, 'accepted an empty or partial screenshot set');
  } finally { fs.rmSync(dir, { recursive: true }); }
});


test('submission, release and accessibility require confirmation before any request', async () => {
  for (const command of ['submit', 'release', 'accessibility']) {
    await assert.rejects(run([command, '1.15.0'], () => {
      assert.fail('made a request without confirmation');
    }), /pass --yes/);
  }
  await assert.rejects(run(['version', '1.15.0', '--dryrun'], () => {
    assert.fail('made a request with an unknown flag');
  }), /unknown flag/);
});
