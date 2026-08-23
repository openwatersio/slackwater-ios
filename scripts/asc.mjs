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

// A build is not addable — or annotatable — until processing finishes, and
// processing outlives the upload by 5-15 min. A named build is not even LISTED
// for the first few minutes, which is a wait too: throwing there is what made
// testflight.sh pass no build number, and a bare promote then grabbed whatever
// build was newest (build 23's release promoted build 22 that way).
async function waitForBuild(version) {
  let build;
  for (let i = 0; i < 60; i++) {
    const r = await api('GET', '/v1/builds?limit=10&sort=-uploadedDate');
    build = version ? r.data.find((b) => b.attributes.version === version) : r.data[0];
    if (!build && !version) throw new Error('no builds on App Store Connect');
    if (!build) {
      console.log(`build ${version}: not listed yet, waiting…`);
    } else if (build.attributes.processingState === 'VALID') {
      return build;
    } else {
      console.log(`build ${build.attributes.version}: ${build.attributes.processingState}, waiting…`);
    }
    await new Promise((r) => setTimeout(r, 30_000));
  }
  if (!build) throw new Error(`build ${version} never appeared on App Store Connect (30 min)`);
  throw new Error(`build ${build.attributes.version} still ${build.attributes.processingState} after 30 min`);
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
  // With no group named, promote to EVERY external group. Naming one group was
  // the old default ('Friends & Family'), and it silently shipped an asymmetry:
  // build 27 reached three groups, build 28 reached two, because a second
  // external group ("OSS and Externals" — the one the slackwater.xyz landing
  // page links) had been added and nothing in the release path knew about it.
  // Discovering them beats a hardcoded list precisely because that is the
  // failure mode: a new group needs no code change to get releases.
  const named = args[1];
  const groups = await api('GET', '/v1/betaGroups?limit=20');
  let targets;
  if (named) {
    const g = groups.data.find((x) => x.attributes.name === named);
    if (!g) throw new Error(`no beta group named "${named}"`);
    targets = [g];
  } else {
    targets = groups.data.filter((x) => !x.attributes.isInternalGroup);
    if (!targets.length) throw new Error('no external beta groups to promote to');
  }

  const build = await waitForBuild(args[0]);

  for (const g of targets) {
    await api('POST', `/v1/betaGroups/${g.id}/relationships/builds`, {
      data: [{ type: 'builds', id: build.id }],
    });
    console.log(`build ${build.attributes.version} -> ${g.attributes.name}`);
  }

  // Beta review is per BUILD, not per group — submitting once per group 409s on
  // the second. One submission covers every external group the build is in.
  if (targets.some((g) => !g.attributes.isInternalGroup)) {
    await api('POST', '/v1/betaAppReviewSubmissions', {
      data: {
        type: 'betaAppReviewSubmissions',
        relationships: { build: { data: { type: 'builds', id: build.id } } },
      },
    });
    console.log('submitted for Apple beta review — testers get it once approved');
  }
} else if (cmd === 'notes') {
  // "What to Test", per build. The localizations are created with the build and
  // start empty — so this PATCHes them, it never POSTs a second one. Every
  // locale gets the same text; the app is English-only.
  const build = await waitForBuild(args[0]);
  const whatsNew = fs.readFileSync(args[1], 'utf8');
  const locs = await api('GET', `/v1/builds/${build.id}/betaBuildLocalizations`);
  for (const l of locs.data) {
    await api('PATCH', `/v1/betaBuildLocalizations/${l.id}`, {
      data: { type: 'betaBuildLocalizations', id: l.id, attributes: { whatsNew } },
    });
    console.log(`build ${build.attributes.version} notes -> ${l.attributes.locale}`);
  }
} else if (cmd === 'create-profile') {
  const [bundleIdRes, certId, outPath, profileName = 'Slackwater App Store'] = args;
  // filter[identifier] is a PREFIX match, not an exact one: it returns both
  // org.openwaters.slackwater and org.openwaters.slackwater.widgets, and the
  // appex sorts FIRST. Taking data[0] therefore bound the app's own profile to
  // the widget's bundle id — silently, since the profile still builds and is
  // still named "Slackwater App Store". Match the identifier exactly.
  const b = await api('GET', `/v1/bundleIds?filter[identifier]=${bundleIdRes}`);
  const match = b.data.find((x) => x.attributes.identifier === bundleIdRes);
  if (!match) throw new Error(`no bundle id exactly matching ${bundleIdRes}`);
  const bundleId = match.id;
  // The name was hardcoded while one profile existed. The appex needs its own
  // ("Slackwater Widgets App Store"), and hardcoding meant minting it DELETED
  // the app's profile and produced a second one wearing the app's name.
  // delete a stale same-name profile if present (idempotent reruns)
  const existing = await api('GET', `/v1/profiles?filter[name]=${encodeURIComponent(profileName)}`);
  for (const p of existing.data) await api('DELETE', `/v1/profiles/${p.id}`);
  const r = await api('POST', '/v1/profiles', {
    data: {
      type: 'profiles',
      attributes: { name: profileName, profileType: 'IOS_APP_STORE' },
      relationships: {
        bundleId: { data: { type: 'bundleIds', id: bundleId } },
        certificates: { data: [{ type: 'certificates', id: certId }] },
      },
    },
  });
  fs.writeFileSync(outPath, Buffer.from(r.data.attributes.profileContent, 'base64'));
  console.log('profile:', r.data.id, r.data.attributes.uuid, '->', outPath);
} else {
  console.log('usage: asc.mjs builds | promote [buildNumber] [groupName — default: all external groups] | notes <buildNumber> <file> | create-cert <csr> <out.cer> | create-profile <bundleIdentifier> <certId> <out.mobileprovision> [profileName]');
}
