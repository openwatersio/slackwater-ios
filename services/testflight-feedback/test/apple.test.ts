import assert from 'node:assert/strict';
import { generateKeyPairSync } from 'node:crypto';
import { test } from 'node:test';
import { listFeedback, type AppleConfig, type Feedback } from '../src/apple.ts';

const { privateKey } = generateKeyPairSync('ec', { namedCurve: 'P-256' });
const config: AppleConfig = {
  appId: 'app-123', issuerId: 'issuer', keyId: 'key',
  privateKey: privateKey.export({ format: 'pem', type: 'pkcs8' }).toString(),
};

async function collect(fetchImpl: typeof fetch, shouldLoad?: (kind: Feedback['kind'], submissionId: string) => boolean | Promise<boolean>): Promise<Feedback[]> {
  const feedback: Feedback[] = [];
  for await (const item of listFeedback(config, fetchImpl, shouldLoad)) feedback.push(item);
  return feedback;
}

test('scans screenshot pages, downloads images, and excludes tester identity', async () => {
  const calls: string[] = [];
  const fetchImpl: typeof fetch = async (input, init) => {
    const url = String(input);
    calls.push(url);
    if (url === 'https://images.apple.com/private-1') {
      assert.equal(init?.headers, undefined);
      return new Response(Uint8Array.of(1, 2, 3), { headers: { 'content-type': 'image/png' } });
    }
    assert.match(String((init?.headers as Record<string, string>)?.Authorization), /^Bearer /);
    if (url.includes('/preReleaseVersion')) return Response.json({ data: { type: 'preReleaseVersions', id: 'version-1', attributes: { version: '1.2.3' } } });
    if (url.includes('betaFeedbackScreenshotSubmissions') && !url.includes('cursor=')) return Response.json({
      data: [{ type: 'betaFeedbackScreenshotSubmissions', id: 'shot-1', attributes: {
        createdDate: '2026-09-13T00:00:00Z', comment: 'Button freezes', deviceModel: 'iPhone 16', osVersion: '26.0',
        email: 'should-not-copy@example.com', screenshots: [{ url: 'https://images.apple.com/private-1', expirationDate: '2099-09-14T00:00:00Z', width: 100, height: 200 }],
      }, relationships: { build: { data: { type: 'builds', id: 'build-1' } }, tester: { data: { type: 'betaTesters', id: 'tester-1' } } } }],
      included: [{ type: 'builds', id: 'build-1', attributes: { version: '456' } }],
      links: { self: url, next: 'https://api.appstoreconnect.apple.com/v1/apps/app-123/betaFeedbackScreenshotSubmissions?cursor=second' },
    });
    if (url.includes('betaFeedbackScreenshotSubmissions') && url.includes('cursor=')) return Response.json({ data: [], links: { self: url } });
    if (url.includes('betaFeedbackCrashSubmissions')) return Response.json({ data: [], links: { self: url } });
    throw Error(`unexpected URL ${url}`);
  };

  const feedback = await collect(fetchImpl);
  assert.deepEqual(feedback, [{
    kind: 'screenshot', appleAppId: 'app-123', submissionId: 'shot-1', buildId: 'build-1', appVersion: '1.2.3', buildNumber: '456',
    submittedAt: '2026-09-13T00:00:00Z', deviceModel: 'iPhone 16', osVersion: '26.0', comment: 'Button freezes',
    assets: [{ name: 'screenshot-1.png', mime: 'image/png', bytes: Uint8Array.of(1, 2, 3) }], omissions: [],
  }]);
  assert.equal(calls.filter(url => url.includes('betaFeedbackScreenshotSubmissions')).length, 2);
  assert.equal(calls.some(url => url.includes('tester') || url.includes('email')), false);
});

test('keeps crash report when its log is unavailable', async () => {
  const fetchImpl: typeof fetch = async (input, init) => {
    const url = String(input);
    if (url.includes('betaFeedbackScreenshotSubmissions')) return Response.json({ data: [], links: { self: url } });
    if (url.includes('betaFeedbackCrashSubmissions') && url.endsWith('/crashLog')) return new Response('', { status: 404 });
    if (url.includes('betaFeedbackCrashSubmissions')) return Response.json({ data: [{
      type: 'betaFeedbackCrashSubmissions', id: 'crash-1', attributes: { createdDate: '2026-09-13T01:00:00Z', comment: 'crashed', deviceModel: 'iPad', osVersion: '26.0' },
      relationships: { build: { data: null } },
    }], links: { self: url } });
    throw Error(`unexpected URL ${url}`);
  };
  const feedback = await collect(fetchImpl);
  assert.equal(feedback.length, 1);
  assert.equal(feedback[0]?.kind, 'crash');
  assert.equal(feedback[0]?.buildId, null);
  assert.deepEqual(feedback[0]?.assets, []);
  assert.deepEqual(feedback[0]?.omissions, ['crash-log-unavailable']);
});

test('records an omission when a screenshot submission has no downloadable image', async () => {
  const fetchImpl: typeof fetch = async input => {
    const url = String(input);
    if (url.includes('betaFeedbackScreenshotSubmissions')) return Response.json({ data: [{
      type: 'betaFeedbackScreenshotSubmissions', id: 'shot-2',
      attributes: { createdDate: '2026-09-13T02:00:00Z', comment: 'Image missing', screenshots: [] },
      relationships: { build: { data: null } },
    }], links: { self: url } });
    if (url.includes('betaFeedbackCrashSubmissions')) return Response.json({ data: [], links: { self: url } });
    throw Error(`unexpected URL ${url}`);
  };
  const feedback = await collect(fetchImpl);
  assert.deepEqual(feedback[0]?.omissions, ['screenshot-unavailable']);
});

test('preserves feedback when its prerelease version is no longer available', async () => {
  const fetchImpl: typeof fetch = async input => {
    const url = String(input);
    if (url.includes('/preReleaseVersion')) return new Response('', { status: 404 });
    if (url.includes('betaFeedbackScreenshotSubmissions')) return Response.json({ data: [{
      type: 'betaFeedbackScreenshotSubmissions', id: 'shot-3',
      attributes: { createdDate: '2026-09-13T03:00:00Z', screenshots: [] },
      relationships: { build: { data: { type: 'builds', id: 'build-3' } } },
    }], included: [{ type: 'builds', id: 'build-3', attributes: { version: '789' } }], links: { self: url } });
    if (url.includes('betaFeedbackCrashSubmissions')) return Response.json({ data: [], links: { self: url } });
    throw Error(`unexpected URL ${url}`);
  };
  const feedback = await collect(fetchImpl);
  assert.equal(feedback[0]?.buildNumber, '789');
  assert.equal(feedback[0]?.appVersion, null);
  assert.deepEqual(feedback[0]?.omissions, ['app-version-unavailable', 'screenshot-unavailable']);
});

test('skips already-recorded feedback before downloading its private assets', async () => {
  const checked: string[] = [];
  const fetchImpl: typeof fetch = async input => {
    const url = String(input);
    if (url.includes('old-image')) throw Error('old screenshot should not be fetched');
    if (url.includes('betaFeedbackScreenshotSubmissions')) return Response.json({ data: [
      { type: 'betaFeedbackScreenshotSubmissions', id: 'old', attributes: { createdDate: '2026-09-12T00:00:00Z', screenshots: [{ url: 'https://images.apple.com/old-image', expirationDate: '2099-01-01T00:00:00Z' }] } },
      { type: 'betaFeedbackScreenshotSubmissions', id: 'new', attributes: { createdDate: '2026-09-13T00:00:00Z', screenshots: [] } },
    ], links: { self: url } });
    if (url.includes('betaFeedbackCrashSubmissions')) return Response.json({ data: [], links: { self: url } });
    throw Error(`unexpected URL ${url}`);
  };
  const feedback = await collect(fetchImpl, async (kind, id) => { checked.push(`${kind}:${id}`); return id !== 'old'; });
  assert.deepEqual(checked, ['screenshot:old', 'screenshot:new']);
  assert.deepEqual(feedback.map(item => item.submissionId), ['new']);
});

test('renews Apple JWT for later pages after an old token would expire', async () => {
  const originalNow = Date.now;
  let now = Date.UTC(2026, 8, 13);
  const issuedAt: number[] = [];
  Date.now = () => now;
  try {
    const fetchImpl: typeof fetch = async (input, init) => {
      const url = String(input);
      const jwt = String((init?.headers as Record<string, string>)?.Authorization).replace(/^Bearer /, '');
      const payload = JSON.parse(Buffer.from(jwt.split('.')[1]!, 'base64url').toString()) as { iat: number; exp: number };
      issuedAt.push(payload.iat);
      assert.equal(payload.exp - payload.iat, 1200);
      if (url.includes('betaFeedbackScreenshotSubmissions') && !url.includes('cursor=')) {
        now += 25 * 60 * 1000;
        return Response.json({ data: [], links: { self: url, next: 'https://api.appstoreconnect.apple.com/v1/apps/app-123/betaFeedbackScreenshotSubmissions?cursor=second' } });
      }
      if (url.includes('betaFeedbackScreenshotSubmissions') || url.includes('betaFeedbackCrashSubmissions')) return Response.json({ data: [], links: { self: url } });
      throw Error(`unexpected URL ${url}`);
    };
    await collect(fetchImpl);
    assert.deepEqual(issuedAt, [Math.floor(Date.UTC(2026, 8, 13) / 1000), Math.floor(Date.UTC(2026, 8, 13) / 1000) + 1500, Math.floor(Date.UTC(2026, 8, 13) / 1000) + 1500]);
  } finally {
    Date.now = originalNow;
  }
});
