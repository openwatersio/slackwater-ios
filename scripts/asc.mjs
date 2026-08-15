// Minimal App Store Connect API client — JWT (ES256) + the few calls TestFlight setup needs.
import crypto from 'node:crypto';
import fs from 'node:fs';

const KEY_ID = 'VM6W5HP585';
const ISSUER = '69a6de81-5896-47e3-e053-5b8c7c11a4d1';
const P8 = `${process.env.HOME}/.appstoreconnect/private_keys/AuthKey_${KEY_ID}.p8`;

const b64u = (buf) => Buffer.from(buf).toString('base64url');

function jwt() {
  const header = { alg: 'ES256', kid: KEY_ID, typ: 'JWT' };
  const now = Math.floor(Date.now() / 1000);
  const payload = { iss: ISSUER, iat: now, exp: now + 900, aud: 'appstoreconnect-v1' };
  const signingInput = `${b64u(JSON.stringify(header))}.${b64u(JSON.stringify(payload))}`;
  const key = crypto.createPrivateKey(fs.readFileSync(P8));
  // ieee-p1363 gives the raw r||s signature JWT ES256 requires (not DER)
  const sig = crypto.sign('sha256', Buffer.from(signingInput), { key, dsaEncoding: 'ieee-p1363' });
  return `${signingInput}.${b64u(sig)}`;
}

async function api(method, path, body) {
  const res = await fetch(`https://api.appstoreconnect.apple.com${path}`, {
    method,
    headers: { Authorization: `Bearer ${jwt()}`, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let json; try { json = JSON.parse(text); } catch { json = { raw: text }; }
  if (!res.ok) throw new Error(`${method} ${path} -> ${res.status}: ${text.slice(0, 500)}`);
  return json;
}

const [cmd, ...args] = process.argv.slice(2);

if (cmd === 'create-cert') {
  const csr = fs.readFileSync(args[0], 'utf8');
  const r = await api('POST', '/v1/certificates', {
    data: { type: 'certificates', attributes: { certificateType: 'DISTRIBUTION', csrContent: csr } },
  });
  fs.writeFileSync(args[1], Buffer.from(r.data.attributes.certificateContent, 'base64'));
  console.log('cert:', r.data.id, r.data.attributes.serialNumber, '->', args[1]);
} else if (cmd === 'builds') {
  // What TestFlight actually holds, which is the only place the version story
  // can be checked: project.yml states an intent, this is the outcome.
  const r = await api('GET', '/v1/builds?limit=10&sort=-uploadedDate&include=preReleaseVersion,betaGroups');
  const inc = (id) => r.included?.find((i) => i.id === id);
  for (const b of r.data) {
    const v = inc(b.relationships?.preReleaseVersion?.data?.id)?.attributes?.version ?? '?';
    const groups = (b.relationships?.betaGroups?.data ?? []).map((g) => inc(g.id)?.attributes?.name ?? g.id);
    console.log(`${v} (${b.attributes.version})  ${b.attributes.processingState}  ${b.attributes.uploadedDate}  [${groups.join(', ')}]`);
  }
} else if (cmd === 'promote') {
  // Put a build in front of the external testers. Two steps, because
  // "Friends & Family" is an EXTERNAL group behind a public link: adding the
  // build to the group is not enough, Apple has to beta-review it first. The
  // internal "Nightly" group needs none of this — it has hasAccessToAllBuilds
  // and every upload lands there on its own, which is why this command exists
  // only for the external side.
  const group = args[1] ?? 'Friends & Family';
  const groups = await api('GET', '/v1/betaGroups?limit=20');
  const g = groups.data.find((x) => x.attributes.name === group);
  if (!g) throw new Error(`no beta group named "${group}"`);

  // A build is not addable until processing finishes, and processing outlives
  // the upload by 5-15 min — so wait rather than fail on a race the caller
  // cannot see. A named build is not even LISTED for the first few minutes,
  // which is a wait too: throwing there is what made testflight.sh pass no
  // build number, and a bare promote then grabs whatever build is newest.
  let build;
  for (let i = 0; i < 60; i++) {
    const r = await api('GET', '/v1/builds?limit=10&sort=-uploadedDate');
    build = args[0] ? r.data.find((b) => b.attributes.version === args[0]) : r.data[0];
    if (!build && !args[0]) throw new Error('no builds on App Store Connect');
    if (!build) {
      console.log(`build ${args[0]}: not listed yet, waiting…`);
      await new Promise((r) => setTimeout(r, 30_000));
      continue;
    }
    if (build.attributes.processingState === 'VALID') break;
    console.log(`build ${build.attributes.version}: ${build.attributes.processingState}, waiting…`);
    await new Promise((r) => setTimeout(r, 30_000));
  }
  if (!build) throw new Error(`build ${args[0]} never appeared on App Store Connect (30 min)`);
  if (build.attributes.processingState !== 'VALID') {
    throw new Error(`build ${build.attributes.version} still ${build.attributes.processingState} after 30 min`);
  }

  await api('POST', `/v1/betaGroups/${g.id}/relationships/builds`, {
    data: [{ type: 'builds', id: build.id }],
  });
  console.log(`build ${build.attributes.version} -> ${group}`);

  if (!g.attributes.isInternalGroup) {
    await api('POST', '/v1/betaAppReviewSubmissions', {
      data: {
        type: 'betaAppReviewSubmissions',
        relationships: { build: { data: { type: 'builds', id: build.id } } },
      },
    });
    console.log('submitted for Apple beta review — testers get it once approved');
  }
} else if (cmd === 'create-profile') {
  const [bundleIdRes, certId, outPath] = args;
  const b = await api('GET', `/v1/bundleIds?filter[identifier]=${bundleIdRes}`);
  const bundleId = b.data[0].id;
  // delete a stale same-name profile if present (idempotent reruns)
  const existing = await api('GET', `/v1/profiles?filter[name]=Slackwater%20App%20Store`);
  for (const p of existing.data) await api('DELETE', `/v1/profiles/${p.id}`);
  const r = await api('POST', '/v1/profiles', {
    data: {
      type: 'profiles',
      attributes: { name: 'Slackwater App Store', profileType: 'IOS_APP_STORE' },
      relationships: {
        bundleId: { data: { type: 'bundleIds', id: bundleId } },
        certificates: { data: [{ type: 'certificates', id: certId }] },
      },
    },
  });
  fs.writeFileSync(outPath, Buffer.from(r.data.attributes.profileContent, 'base64'));
  console.log('profile:', r.data.id, r.data.attributes.uuid, '->', outPath);
} else {
  console.log('usage: asc.mjs builds | promote [buildNumber] [groupName] | create-cert <csr> <out.cer> | create-profile <bundleIdentifier> <certId> <out.mobileprovision>');
}
