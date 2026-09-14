import { createPrivateKey, sign } from 'node:crypto';

export type AppleConfig = { appId: string; issuerId: string; keyId: string; privateKey: string };
export type Feedback = {
  kind: 'screenshot' | 'crash';
  appleAppId: string;
  submissionId: string;
  buildId: string | null;
  appVersion: string | null;
  buildNumber: string | null;
  submittedAt: string;
  deviceModel: string | null;
  osVersion: string | null;
  comment: string | null;
  assets: { name: string; mime: string; bytes: Uint8Array }[];
  omissions: string[];
};

type AppleResource = {
  id: string;
  attributes?: {
    createdDate?: string; comment?: string; deviceModel?: string; osVersion?: string;
    version?: string;
    screenshots?: { url?: string; expirationDate?: string }[];
    logText?: string;
  };
  relationships?: { build?: { data?: { id: string } | null } };
};
type AppleDocument = {
  data: AppleResource[];
  included?: AppleResource[];
  links?: { next?: string };
};

const API = 'https://api.appstoreconnect.apple.com';
const MAX_ASSET_BYTES = 8 * 1024 * 1024;

function token(config: AppleConfig): string {
  const now = Math.floor(Date.now() / 1000);
  const base64 = (value: object) => Buffer.from(JSON.stringify(value)).toString('base64url');
  const message = `${base64({ alg: 'ES256', kid: config.keyId, typ: 'JWT' })}.${base64({ iss: config.issuerId, iat: now, exp: now + 1200, aud: 'appstoreconnect-v1' })}`;
  const signature = sign('sha256', Buffer.from(message), { key: createPrivateKey(config.privateKey), dsaEncoding: 'ieee-p1363' }).toString('base64url');
  return `${message}.${signature}`;
}

function appleUrl(path: string): string {
  const url = new URL(path, API);
  if (url.origin !== API || !url.pathname.startsWith('/v1/')) throw new Error('Unexpected Apple API URL');
  return url.toString();
}

async function appleGet(path: string, config: AppleConfig, fetchImpl: typeof fetch, allowNotFound = false): Promise<Response> {
  const response = await fetchImpl(appleUrl(path), { headers: { Authorization: `Bearer ${token(config)}` } });
  if (!response.ok && !(allowNotFound && response.status === 404)) throw new Error(`Apple API HTTP ${response.status}`);
  return response;
}

async function bytesWithinLimit(response: Response): Promise<Uint8Array | null> {
  const length = Number(response.headers.get('content-length'));
  if (length > MAX_ASSET_BYTES) return null;
  if (!response.body) return new Uint8Array();
  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > MAX_ASSET_BYTES) return null;
      chunks.push(value);
    }
  } finally {
    await reader.cancel();
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  return bytes;
}

export async function* listFeedback(
  config: AppleConfig,
  fetchImpl: typeof fetch = fetch,
  shouldLoad: (kind: Feedback['kind'], submissionId: string) => boolean | Promise<boolean> = () => true,
): AsyncGenerator<Feedback> {
  const versions = new Map<string, string | null>();
  for (const kind of ['screenshot', 'crash'] as const) {
    const resource = kind === 'screenshot' ? 'betaFeedbackScreenshotSubmissions' : 'betaFeedbackCrashSubmissions';
    const fields = `createdDate,comment,deviceModel,osVersion,${kind === 'screenshot' ? 'screenshots' : 'crashLog'},build`;
    const url = new URL(`/v1/apps/${encodeURIComponent(config.appId)}/${resource}`, API);
    url.searchParams.set(`fields[${resource}]`, fields);
    url.searchParams.set('include', 'build');
    url.searchParams.set('fields[builds]', 'version');
    url.searchParams.set('limit', '200');
    url.searchParams.set('sort', '-createdDate');
    let next: string | undefined = url.toString();
    const seen = new Set<string>();
    while (next) {
      if (seen.has(next)) throw new Error('Apple pagination cycle');
      seen.add(next);
      const page = await (await appleGet(next, config, fetchImpl)).json() as AppleDocument;
      if (!Array.isArray(page.data)) throw new Error('Invalid Apple feedback page');
      for (const item of page.data) {
        if (typeof item.id !== 'string' || typeof item.attributes?.createdDate !== 'string') throw new Error('Invalid Apple feedback item');
        if (!(await shouldLoad(kind, item.id))) continue;
        const buildId = item.relationships?.build?.data?.id ?? null;
        const buildNumber = page.included?.find(resource => resource.id === buildId)?.attributes?.version ?? null;
        let appVersion: string | null = null;
        if (buildId) {
          if (!versions.has(buildId)) {
            const versionResponse = await appleGet(`/v1/builds/${encodeURIComponent(buildId)}/preReleaseVersion?fields%5BpreReleaseVersions%5D=version`, config, fetchImpl, true);
            if (versionResponse.status === 404) versions.set(buildId, null);
            else {
              const version = await versionResponse.json() as { data?: { attributes?: { version?: string } } };
              versions.set(buildId, version.data?.attributes?.version ?? null);
            }
          }
          appVersion = versions.get(buildId) ?? null;
        }
        const feedback: Feedback = {
          kind, appleAppId: config.appId, submissionId: item.id, buildId, appVersion, buildNumber,
          submittedAt: item.attributes.createdDate, deviceModel: item.attributes.deviceModel ?? null,
          osVersion: item.attributes.osVersion ?? null, comment: item.attributes.comment ?? null,
          assets: [], omissions: [],
        };
        if (buildId && !appVersion) feedback.omissions.push('app-version-unavailable');
        if (kind === 'screenshot') {
          if (!item.attributes.screenshots?.length) feedback.omissions.push('screenshot-unavailable');
          for (const [index, screenshot] of (item.attributes.screenshots ?? []).entries()) {
            if (!screenshot.url || (screenshot.expirationDate && Date.parse(screenshot.expirationDate) <= Date.now())) {
              feedback.omissions.push(`screenshot-${index + 1}-unavailable`);
              continue;
            }
            const imageUrl = new URL(screenshot.url);
            if (imageUrl.protocol !== 'https:') throw new Error('Unexpected screenshot URL');
            const image = await fetchImpl(imageUrl.toString(), { redirect: 'error' });
            if (image.status === 403 || image.status === 404) { feedback.omissions.push(`screenshot-${index + 1}-unavailable`); continue; }
            if (!image.ok) throw new Error(`Apple screenshot HTTP ${image.status}`);
            const bytes = await bytesWithinLimit(image);
            if (!bytes) { feedback.omissions.push(`screenshot-${index + 1}-too-large`); continue; }
            const mime = image.headers.get('content-type')?.split(';')[0]?.toLowerCase() ?? 'application/octet-stream';
            const ext = mime === 'image/png' ? 'png' : mime === 'image/jpeg' ? 'jpg' : mime === 'image/heic' ? 'heic' : 'bin';
            feedback.assets.push({ name: `screenshot-${index + 1}.${ext}`, mime, bytes });
          }
        } else {
          const logResponse = await fetchImpl(appleUrl(`/v1/betaFeedbackCrashSubmissions/${encodeURIComponent(item.id)}/crashLog`), { headers: { Authorization: `Bearer ${token(config)}` } });
          if (logResponse.status === 404) feedback.omissions.push('crash-log-unavailable');
          else if (!logResponse.ok) throw new Error(`Apple crash log HTTP ${logResponse.status}`);
          else {
            const log = await logResponse.json() as { data?: { attributes?: { logText?: string } } };
            const text = log.data?.attributes?.logText;
            if (typeof text !== 'string') feedback.omissions.push('crash-log-unavailable');
            else {
              const bytes = new TextEncoder().encode(text);
              if (bytes.byteLength > MAX_ASSET_BYTES) feedback.omissions.push('crash-log-too-large');
              else feedback.assets.push({ name: 'crash-log.txt', mime: 'text/plain', bytes });
            }
          }
        }
        yield feedback;
      }
      next = page.links?.next;
    }
  }
}
