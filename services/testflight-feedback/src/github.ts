import { createHash } from 'node:crypto';
import type { Feedback } from './apple.ts';

export type AssetRef = { id: number; name: string; url: string };
export type IssueDraft = { title: string; body: string; labels: string[] };
export type GithubConfig = { repository: string; workflowRepository: string; token: string };
type Marker = { source_key: string; phase: 'reserved' | 'creating' | 'complete'; issue_number: number | null; assets: AssetRef[] };

function issueLabels(kind: Feedback['kind'], appVersion: string | null): string[] {
  const version = /^[a-zA-Z0-9.-]{1,30}$/.test(appVersion ?? '') ? appVersion : 'unknown';
  return ['testflight-feedback', `source:${kind}`, 'needs-triage', `version:${version}`];
}

function hashKey(key: string): string {
  return createHash('sha256').update(key).digest('hex');
}

export async function lookupFeedbackStatus(
  config: GithubConfig, appId: string, kind: Feedback['kind'], submissionId: string, fetchImpl: typeof fetch = fetch,
): Promise<Marker['phase'] | null> {
  if (config.repository !== config.workflowRepository) throw new Error('private repository guard failed');
  const key = `${appId}:${kind}:${submissionId}`;
  const marker = await readMarker(config, `/contents/intake/${hashKey(key)}.json`, fetchImpl);
  if (marker && marker.value.source_key !== key) throw new Error('marker source mismatch');
  return marker?.value.phase ?? null;
}

export async function ensurePrivateRepository(config: GithubConfig, fetchImpl: typeof fetch = fetch): Promise<void> {
  if (!/^[\w.-]+\/[\w.-]+$/.test(config.repository) || config.repository !== config.workflowRepository) {
    throw new Error('private repository guard failed');
  }
  const response = await githubRequest(config, '', fetchImpl);
  if (!response.ok) throw new Error(`GitHub repository check failed: HTTP ${response.status}`);
  const repository = await response.json() as { private?: boolean; full_name?: string };
  if (!repository.private || repository.full_name !== config.repository) throw new Error('private repository guard failed');
}

function githubRequest(config: GithubConfig, path: string, fetchImpl: typeof fetch, init: RequestInit = {}): Promise<Response> {
  return fetchImpl(`https://api.github.com/repos/${config.repository}${path}`, {
    ...init,
    headers: {
      Authorization: `Bearer ${config.token}`,
      Accept: 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      ...(init.body ? { 'Content-Type': 'application/json' } : {}),
      ...init.headers,
    },
  });
}

function requireOk(response: Response, action: string): void {
  if (!response.ok) throw new Error(`${action} failed: HTTP ${response.status}`);
}

async function readMarker(config: GithubConfig, path: string, fetchImpl: typeof fetch): Promise<{ value: Marker; sha: string } | null> {
  const response = await githubRequest(config, path, fetchImpl);
  if (response.status === 404) return null;
  requireOk(response, 'read marker');
  const file = await response.json() as { content: string; sha: string };
  const value = JSON.parse(Buffer.from(file.content.replace(/\s/g, ''), 'base64').toString('utf8')) as Marker;
  return { value, sha: file.sha };
}

async function writeMarker(config: GithubConfig, path: string, value: Marker, fetchImpl: typeof fetch, sha?: string): Promise<string | null> {
  const response = await githubRequest(config, path, fetchImpl, {
    method: 'PUT',
    body: JSON.stringify({
      message: `testflight: ${value.phase} ${path.split('/').at(-1)}`,
      content: Buffer.from(JSON.stringify(value)).toString('base64'),
      ...(sha ? { sha } : {}),
    }),
  });
  if (response.status === 409 || response.status === 422) return null;
  requireOk(response, 'write marker');
  const result = await response.json() as { content?: { sha?: string } };
  if (!result.content?.sha) throw new Error('write marker returned no sha');
  return result.content.sha;
}

async function ensureLabels(config: GithubConfig, labels: string[], fetchImpl: typeof fetch): Promise<void> {
  for (const label of labels) {
    const response = await githubRequest(config, `/labels/${encodeURIComponent(label)}`, fetchImpl);
    if (response.ok) continue;
    if (response.status !== 404) throw new Error(`read label failed: HTTP ${response.status}`);
    const created = await githubRequest(config, '/labels', fetchImpl, {
      method: 'POST',
      body: JSON.stringify({ name: label, color: '7c8ea0' }),
    });
    if (!created.ok && created.status !== 422) throw new Error(`create label failed: HTTP ${created.status}`);
  }
}

async function storeAssets(config: GithubConfig, feedback: Feedback, hash: string, fetchImpl: typeof fetch): Promise<AssetRef[]> {
  const tag = `testflight-feedback-${hash}`;
  let releaseResponse = await githubRequest(config, `/releases/tags/${tag}`, fetchImpl);
  if (releaseResponse.status === 404) {
    if (!feedback.assets.length) return [];
    releaseResponse = await githubRequest(config, '/releases', fetchImpl, {
      method: 'POST',
      body: JSON.stringify({ tag_name: tag, name: tag, draft: false, prerelease: true, make_latest: 'false' }),
    });
    if (releaseResponse.status === 422) releaseResponse = await githubRequest(config, `/releases/tags/${tag}`, fetchImpl);
  }
  requireOk(releaseResponse, 'get private release');
  const release = await releaseResponse.json() as { id?: number };
  if (!release.id) throw new Error('private release missing ID');
  const existing: Array<{ id: number; name: string; state: string }> = [];
  for (let page = 1; ; page++) {
    const response = await githubRequest(config, `/releases/${release.id}/assets?per_page=100&page=${page}`, fetchImpl);
    requireOk(response, 'list private assets');
    const batch = await response.json() as typeof existing;
    existing.push(...batch);
    if (batch.length < 100) break;
  }
  const uploaded: typeof existing = [];
  for (const asset of existing) {
    if (asset.state === 'starter') {
      // GitHub may leave an empty starter asset after HTTP 502: https://docs.github.com/en/rest/releases/assets#upload-a-release-asset
      const removed = await githubRequest(config, `/releases/assets/${asset.id}`, fetchImpl, { method: 'DELETE' });
      if (removed.status !== 204 && removed.status !== 404) throw new Error(`delete starter asset failed: HTTP ${removed.status}`);
      continue;
    }
    if (asset.state !== 'uploaded') throw new Error('private asset has unknown state');
    uploaded.push(asset);
  }
  const refs: AssetRef[] = uploaded
    .filter(asset => asset.name.startsWith(`${hash}-`))
    .map(asset => ({
      id: asset.id,
      name: asset.name.slice(hash.length + 1),
      url: `https://github.com/${config.repository}/releases/download/${tag}/${encodeURIComponent(asset.name)}`,
    }));
  for (const asset of feedback.assets) {
    const name = `${hash}-${asset.name.replace(/[^a-zA-Z0-9._-]/g, '_').slice(0, 100)}`;
    let stored = uploaded.find(item => item.name === name);
    if (!stored) {
      const upload = await fetchImpl(`https://uploads.github.com/repos/${config.repository}/releases/${release.id}/assets?name=${encodeURIComponent(name)}`, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${config.token}`,
          Accept: 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
          'Content-Type': asset.mime,
          'Content-Length': String(asset.bytes.byteLength),
        },
        body: Buffer.from(asset.bytes),
      });
      requireOk(upload, 'upload private asset');
      stored = await upload.json() as { id: number; name: string; state: string };
    }
    if (!stored.id || stored.state !== 'uploaded') throw new Error('private asset is not uploaded');
    if (!refs.some(ref => ref.id === stored.id)) refs.push({
      id: stored.id, name: asset.name,
      url: `https://github.com/${config.repository}/releases/download/${tag}/${encodeURIComponent(name)}`,
    });
  }
  return refs;
}

export async function ingestFeedback(config: GithubConfig, feedback: Feedback, fetchImpl: typeof fetch = fetch): Promise<'created' | 'duplicate' | 'pending'> {
  await ensurePrivateRepository(config, fetchImpl);
  const key = sourceKey(feedback);
  const path = `/contents/intake/${sourceHash(feedback)}.json`;
  let marker = await readMarker(config, path, fetchImpl);
  if (marker && marker.value.source_key !== key) throw new Error('marker source mismatch');
  if (marker?.value.phase === 'complete') return 'duplicate';
  if (marker?.value.phase === 'creating') return 'pending';
  if (!marker) {
    const value: Marker = { source_key: key, phase: 'reserved', issue_number: null, assets: [] };
    const sha = await writeMarker(config, path, value, fetchImpl);
    if (!sha) return 'pending';
    marker = { value, sha };
  }
  const assets = await storeAssets(config, feedback, sourceHash(feedback), fetchImpl);
  const draft = renderIssue(feedback, assets);
  await ensureLabels(config, draft.labels, fetchImpl);
  const creating: Marker = { ...marker.value, phase: 'creating', assets };
  const creatingSha = await writeMarker(config, path, creating, fetchImpl, marker.sha);
  if (!creatingSha) return 'pending';
  const issueResponse = await githubRequest(config, '/issues', fetchImpl, {
    method: 'POST',
    body: JSON.stringify(draft),
  });
  requireOk(issueResponse, 'create issue');
  const issue = await issueResponse.json() as { number?: number; labels?: Array<{ name: string }> };
  if (!issue.number || !draft.labels.every(label => issue.labels?.some(applied => applied.name === label))) {
    throw new Error('created issue missing number or labels');
  }
  const complete: Marker = { ...creating, phase: 'complete', issue_number: issue.number };
  if (!await writeMarker(config, path, complete, fetchImpl, creatingSha)) throw new Error('complete marker conflict');
  return 'created';
}

export async function reconcileMarkers(config: GithubConfig, fetchImpl: typeof fetch = fetch): Promise<{ repaired: number; unresolved: number }> {
  await ensurePrivateRepository(config, fetchImpl);
  const directory = await githubRequest(config, '/contents/intake', fetchImpl);
  if (directory.status === 404) return { repaired: 0, unresolved: 0 };
  requireOk(directory, 'list markers');
  // ponytail: Contents lists at most 1,000 files here; shard markers if this beta reaches that scale.
  const files = await directory.json() as Array<{ path: string; type: string }>;
  const creating: Array<{ path: string; value: Marker; sha: string }> = [];
  for (const file of files) {
    if (file.type !== 'file' || !/^intake\/[a-f0-9]{64}\.json$/.test(file.path)) continue;
    const marker = await readMarker(config, `/contents/${file.path}`, fetchImpl);
    if (marker?.value.phase === 'creating') creating.push({ path: `/contents/${file.path}`, ...marker });
  }
  if (!creating.length) return { repaired: 0, unresolved: 0 };
  const issues: Array<{ number: number; body: string | null; labels?: Array<{ name: string }> }> = [];
  for (let page = 1; ; page++) {
    const response = await githubRequest(config, `/issues?state=all&per_page=100&page=${page}`, fetchImpl);
    requireOk(response, 'list private issues');
    const batch = await response.json() as typeof issues;
    issues.push(...batch);
    if (batch.length < 100) break;
  }
  let repaired = 0;
  let unresolved = 0;
  for (const marker of creating) {
    const matches = issues.flatMap(issue => {
      const block = issue.body?.match(/^<!-- testflight-feedback:v1\n([^\n]*)\n-->/);
      if (!block) return [];
      try {
        const meta = JSON.parse(block[1]) as { source_key?: string; feedback_type?: string; app_version?: string | null };
        return meta.source_key === marker.value.source_key ? [{ issue, meta }] : [];
      } catch { return []; }
    });
    if (matches.length !== 1) { unresolved++; continue; }
    const { issue, meta } = matches[0];
    if (meta.feedback_type !== 'screenshot' && meta.feedback_type !== 'crash') { unresolved++; continue; }
    const missing = issueLabels(meta.feedback_type, meta.app_version ?? null).filter(label => !issue.labels?.some(existing => existing.name === label));
    if (missing.length) {
      await ensureLabels(config, missing, fetchImpl);
      const applied = await githubRequest(config, `/issues/${issue.number}/labels`, fetchImpl, {
        method: 'POST',
        body: JSON.stringify({ labels: missing }),
      });
      requireOk(applied, 'repair private issue labels');
    }
    const complete: Marker = { ...marker.value, phase: 'complete', issue_number: issue.number };
    if (await writeMarker(config, marker.path, complete, fetchImpl, marker.sha)) repaired++;
    else unresolved++;
  }
  return { repaired, unresolved };
}

export function sourceKey(feedback: Feedback): string {
  return `${feedback.appleAppId}:${feedback.kind}:${feedback.submissionId}`;
}

export function sourceHash(feedback: Feedback): string {
  return hashKey(sourceKey(feedback));
}

export function renderIssue(feedback: Feedback, assets: AssetRef[], hash = sourceHash(feedback)): IssueDraft {
  const version = /^[a-zA-Z0-9.-]{1,30}$/.test(feedback.appVersion ?? '') ? feedback.appVersion : 'unknown';
  const build = /^[a-zA-Z0-9.-]{1,30}$/.test(feedback.buildNumber ?? '') ? feedback.buildNumber : 'unknown';
  const title = `[TestFlight ${feedback.kind}] ${version} (${build}) · ${hash.slice(0, 12)}`;
  const labels = issueLabels(feedback.kind, feedback.appVersion);
  const metadata = {
    source_key: sourceKey(feedback),
    apple_app_id: feedback.appleAppId,
    apple_submission_id: feedback.submissionId,
    apple_build_id: feedback.buildId,
    feedback_type: feedback.kind,
    app_version: feedback.appVersion,
    build_number: feedback.buildNumber,
    submitted_at: feedback.submittedAt,
    device_model: feedback.deviceModel,
    os_version: feedback.osVersion,
    private_asset_ids: assets.map(asset => asset.id),
    asset_omissions: feedback.omissions,
    triage_status: 'needs-triage',
    related_private_issue_numbers: [],
    public_issue_url: null,
  };
  const safeMetadata = JSON.stringify(metadata).replaceAll('<', '\\u003c').replaceAll('>', '\\u003e');
  const comment = feedback.comment ?? '';
  const longestFence = Math.max(3, ...Array.from(comment.matchAll(/`+/g), match => match[0].length + 1));
  const fence = '`'.repeat(longestFence);
  const assetLinks = assets.length
    ? assets.map(asset => `- [${asset.name}](${asset.url})`).join('\n')
    : '_No assets stored._';
  const body = `<!-- testflight-feedback:v1\n${safeMetadata}\n-->\n\n### Tester comment\n\n${fence}text\n${comment}\n${fence}\n\n### Private assets\n\n${assetLinks}\n`;
  return { title, body, labels };
}
