import assert from 'node:assert/strict';
import test from 'node:test';
import { ingestFeedback, lookupFeedbackStatus, reconcileMarkers, renderIssue } from '../src/github.ts';

const feedback = {
  kind: 'screenshot' as const,
  appleAppId: '123',
  submissionId: 'abc',
  buildId: 'build-1',
  appVersion: '1.2.3',
  buildNumber: '456',
  submittedAt: '2026-09-13T12:00:00Z',
  deviceModel: 'iPhone',
  osVersion: '26',
  comment: 'Contact me at person@example.com\n\`\`\`\n@someone',
  assets: [],
  omissions: [],
};

test('private issue keeps verbatim feedback out of title and labels', () => {
  const issue = renderIssue(feedback, [], '0123456789abcdef');
  assert.equal(issue.title, '[TestFlight screenshot] 1.2.3 (456) · 0123456789ab');
  assert.deepEqual(issue.labels, ['testflight-feedback', 'source:screenshot', 'needs-triage', 'version:1.2.3']);
  assert.match(issue.body, /"source_key":"123:screenshot:abc"/);
  assert.match(issue.body, /person@example\.com/);
  assert.doesNotMatch(issue.title + issue.labels.join(' '), /person@example\.com|@someone/);
  assert.match(issue.body, /\`\`\`\`/);
});

test('refuses to write to a public repository', async () => {
  const methods: string[] = [];
  const fakeFetch: typeof fetch = async (_input, init) => {
    methods.push(init?.method ?? 'GET');
    return Response.json({ full_name: 'openwatersio/feedback', private: false });
  };
  await assert.rejects(
    ingestFeedback({ repository: 'openwatersio/feedback', workflowRepository: 'openwatersio/feedback', token: 'test' }, feedback, fakeFetch),
    /private repository/,
  );
  assert.deepEqual(methods, ['GET']);
});

test('status lookup skips an already completed source key', async () => {
  const key = '123:screenshot:abc';
  const fakeFetch: typeof fetch = async (_input, init) => {
    assert.equal(init?.method ?? 'GET', 'GET');
    return Response.json({
      sha: 'sha',
      content: Buffer.from(JSON.stringify({ source_key: key, phase: 'complete', issue_number: 5, assets: [] })).toString('base64'),
    });
  };
  const config = { repository: 'openwatersio/feedback', workflowRepository: 'openwatersio/feedback', token: 'test' };
  assert.equal(await lookupFeedbackStatus(config, '123', 'screenshot', 'abc', fakeFetch), 'complete');
});

test('a retry keeps an uploaded asset and does not duplicate the issue', async () => {
  let marker: { content: string; sha: string } | null = null;
  const issues: Array<{ title: string; body: string; labels: string[] }> = [];
  const assets: Array<{ id: number; name: string; state: string; browser_download_url: string }> = [];
  let releaseCreated = false;
  let releaseTag = '';
  let failLabelOnce = true;
  const fakeFetch: typeof fetch = async (input, init) => {
    const url = new URL(String(input));
    const method = init?.method ?? 'GET';
    if (url.pathname === '/repos/openwatersio/feedback' && method === 'GET') {
      return Response.json({ full_name: 'openwatersio/feedback', private: true });
    }
    if (url.pathname.includes('/contents/intake/')) {
      if (method === 'GET') return marker ? Response.json(marker) : new Response(null, { status: 404 });
      const request = JSON.parse(String(init?.body));
      if (marker && request.sha !== marker.sha) return Response.json({}, { status: 409 });
      marker = { content: request.content, sha: String(Date.now()) };
      return Response.json({ content: { sha: marker.sha } }, { status: request.sha ? 200 : 201 });
    }
    if (url.pathname.includes('/labels/') && method === 'GET') {
      if (failLabelOnce) { failLabelOnce = false; return Response.json({}, { status: 500 }); }
      return Response.json({ name: decodeURIComponent(url.pathname.split('/').at(-1)!) });
    }
    if (url.pathname.includes('/releases/tags/testflight-feedback-') && method === 'GET') {
      releaseTag = url.pathname.split('/').at(-1)!;
      return releaseCreated ? Response.json({ id: 1 }) : new Response(null, { status: 404 });
    }
    if (url.pathname.endsWith('/releases') && method === 'POST') {
      releaseCreated = true;
      return Response.json({ id: 1 }, { status: 201 });
    }
    if (url.pathname.endsWith('/releases/1/assets') && method === 'GET') return Response.json(assets);
    if (url.pathname.endsWith('/releases/1/assets') && method === 'POST') {
      assert.equal(url.host, 'uploads.github.com');
      const name = url.searchParams.get('name')!;
      const asset = { id: assets.length + 1, name, state: 'uploaded', browser_download_url: `https://github.com/openwatersio/feedback/releases/download/${releaseTag}/${name}` };
      assets.push(asset);
      return Response.json(asset, { status: 201 });
    }
    if (url.pathname === '/repos/openwatersio/feedback/issues' && method === 'POST') {
      const request = JSON.parse(String(init?.body));
      issues.push(request);
      return Response.json({ number: issues.length, labels: request.labels.map((name: string) => ({ name })) }, { status: 201 });
    }
    throw new Error(`unexpected ${method} ${url.pathname}`);
  };
  const config = { repository: 'openwatersio/feedback', workflowRepository: 'openwatersio/feedback', token: 'test' };
  const withImage = { ...feedback, assets: [{ name: 'screenshot-1.png', mime: 'image/png', bytes: new Uint8Array([137, 80, 78, 71]) }] };
  await assert.rejects(ingestFeedback(config, withImage, fakeFetch));
  const afterExpiry = { ...feedback, assets: [], omissions: ['screenshot-1-unavailable'] };
  assert.equal(await ingestFeedback(config, afterExpiry, fakeFetch), 'created');
  assert.equal(await ingestFeedback(config, afterExpiry, fakeFetch), 'duplicate');
  assert.equal(issues.length, 1);
  assert.equal(assets.length, 1);
  assert.match(issues[0].body, /person@example\.com/);
  assert.match(issues[0].body, /github\.com\/openwatersio\/feedback\/releases\/download/);
  assert.doesNotMatch(issues[0].title, /person@example\.com/);
  assert.doesNotMatch(Buffer.from(marker!.content, 'base64').toString(), /person@example\.com/);
});

test('a starter release asset is deleted and replaced before an issue links it', async () => {
  const hash = 'ef2cf020e12f3e15e9b7058a34e1d718c80d22e131ac6684b7f62255eea671b8';
  const name = `${hash}-screenshot-1.png`;
  let asset: { id: number; name: string; state: string } | null = { id: 1, name, state: 'starter' };
  let deleted = 0;
  let marker: { content: string; sha: string } | null = null;
  let issueAssetIds: number[] = [];
  const fakeFetch: typeof fetch = async (input, init) => {
    const url = new URL(String(input));
    const method = init?.method ?? 'GET';
    if (url.pathname === '/repos/openwatersio/feedback') return Response.json({ full_name: 'openwatersio/feedback', private: true });
    if (url.pathname.includes('/contents/intake/')) {
      if (method === 'GET') return marker ? Response.json(marker) : new Response(null, { status: 404 });
      const request = JSON.parse(String(init?.body));
      marker = { content: request.content, sha: String(Date.now()) };
      return Response.json({ content: { sha: marker.sha } }, { status: 201 });
    }
    if (url.pathname.includes('/releases/tags/')) return Response.json({ id: 1 });
    if (url.pathname.endsWith('/releases/1/assets') && method === 'GET') return Response.json(asset ? [asset] : []);
    if (url.pathname.endsWith('/releases/assets/1') && method === 'DELETE') {
      deleted++;
      asset = null;
      return new Response(null, { status: 204 });
    }
    if (url.pathname.endsWith('/releases/1/assets') && method === 'POST') {
      asset = { id: 2, name: url.searchParams.get('name')!, state: 'uploaded' };
      return Response.json(asset, { status: 201 });
    }
    if (url.pathname.includes('/labels/')) return Response.json({});
    if (url.pathname.endsWith('/issues') && method === 'POST') {
      const draft = JSON.parse(String(init?.body));
      issueAssetIds = JSON.parse(draft.body.match(/\n({[^\n]+})\n-->/)[1]).private_asset_ids;
      return Response.json({ number: 1, labels: draft.labels.map((label: string) => ({ name: label })) }, { status: 201 });
    }
    throw new Error(`unexpected ${method} ${url.pathname}`);
  };
  const config = { repository: 'openwatersio/feedback', workflowRepository: 'openwatersio/feedback', token: 'test' };
  const withImage = { ...feedback, assets: [{ name: 'screenshot-1.png', mime: 'image/png', bytes: new Uint8Array([1, 2, 3]) }] };
  assert.equal(await ingestFeedback(config, withImage, fakeFetch), 'created');
  assert.equal(deleted, 1);
  assert.deepEqual(issueAssetIds, [2]);
});

test('an ambiguous issue response leaves a marker and blocks a second create', async () => {
  let marker: { content: string; sha: string } | null = null;
  let createCalls = 0;
  const fakeFetch: typeof fetch = async (input, init) => {
    const url = new URL(String(input));
    const method = init?.method ?? 'GET';
    if (url.pathname === '/repos/openwatersio/feedback') return Response.json({ full_name: 'openwatersio/feedback', private: true });
    if (url.pathname.includes('/contents/intake/')) {
      if (method === 'GET') return marker ? Response.json(marker) : new Response(null, { status: 404 });
      const request = JSON.parse(String(init?.body));
      marker = { content: request.content, sha: String(Date.now()) };
      return Response.json({ content: { sha: marker.sha } }, { status: 201 });
    }
    if (url.pathname.includes('/releases/tags/') && method === 'GET') return new Response(null, { status: 404 });
    if (url.pathname.includes('/labels/')) return Response.json({});
    if (url.pathname.endsWith('/issues') && method === 'POST') {
      createCalls++;
      throw new Error('response lost after issue creation');
    }
    throw new Error(`unexpected ${method} ${url.pathname}`);
  };
  const config = { repository: 'openwatersio/feedback', workflowRepository: 'openwatersio/feedback', token: 'test' };
  await assert.rejects(ingestFeedback(config, feedback, fakeFetch));
  assert.equal(await ingestFeedback(config, feedback, fakeFetch), 'pending');
  assert.equal(createCalls, 1);
  assert.equal(JSON.parse(Buffer.from(marker!.content, 'base64').toString()).phase, 'creating');
});

test('reconciliation binds an existing issue without creating another', async () => {
  const key = '123:screenshot:abc';
  const markerPath = `intake/${'a'.repeat(64)}.json`;
  let marker = { source_key: key, phase: 'creating', issue_number: null, assets: [] };
  let sha = 'old';
  const addedLabels: string[] = [];
  const fakeFetch: typeof fetch = async (input, init) => {
    const url = new URL(String(input));
    const method = init?.method ?? 'GET';
    if (url.pathname === '/repos/openwatersio/feedback') return Response.json({ full_name: 'openwatersio/feedback', private: true });
    if (url.pathname.endsWith('/contents/intake')) return Response.json([{ path: markerPath, type: 'file' }]);
    if (url.pathname.endsWith(`/contents/${markerPath}`) && method === 'GET') {
      return Response.json({ sha, content: Buffer.from(JSON.stringify(marker)).toString('base64') });
    }
    if (url.pathname.endsWith(`/contents/${markerPath}`) && method === 'PUT') {
      const request = JSON.parse(String(init?.body));
      assert.equal(request.sha, sha);
      marker = JSON.parse(Buffer.from(request.content, 'base64').toString());
      sha = 'new';
      return Response.json({ content: { sha } });
    }
    if (url.pathname.endsWith('/issues') && method === 'GET') {
      return Response.json([{ number: 7, body: `<!-- testflight-feedback:v1\n{"source_key":"${key}","feedback_type":"screenshot","app_version":"1.2.3"}\n-->\nprivate text`, labels: [
        { name: 'testflight-feedback' }, { name: 'source:screenshot' }, { name: 'version:1.2.3' },
      ] }]);
    }
    if (url.pathname.endsWith('/labels/needs-triage') && method === 'GET') return Response.json({ name: 'needs-triage' });
    if (url.pathname.endsWith('/issues/7/labels') && method === 'POST') {
      addedLabels.push(...JSON.parse(String(init?.body)).labels);
      return Response.json(addedLabels.map(name => ({ name })));
    }
    throw new Error(`unexpected ${method} ${url.pathname}`);
  };
  const config = { repository: 'openwatersio/feedback', workflowRepository: 'openwatersio/feedback', token: 'test' };
  assert.deepEqual(await reconcileMarkers(config, fakeFetch), { repaired: 1, unresolved: 0 });
  assert.equal(marker.phase, 'complete');
  assert.equal(marker.issue_number, 7);
  assert.deepEqual(addedLabels, ['needs-triage']);
});
