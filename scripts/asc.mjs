// Minimal App Store Connect API client — JWT (ES256) + the few calls TestFlight setup needs.
import crypto from 'node:crypto';
import fs from 'node:fs';

// Credentials come from the environment: repo secrets in the Nightly
// workflow, `op run` or an exported shell locally. See docs/testflight.md.
const env = (name) => process.env[name] || (() => { throw new Error(`${name} is not set`); })();
const KEY_ID = env('ASC_KEY_ID');
const ISSUER = env('ASC_ISSUER_ID');
const P8 = env('ASC_KEY');

const b64u = (buf) => Buffer.from(buf).toString('base64url');

function jwt() {
  const header = { alg: 'ES256', kid: KEY_ID, typ: 'JWT' };
  const now = Math.floor(Date.now() / 1000);
  const payload = { iss: ISSUER, iat: now, exp: now + 900, aud: 'appstoreconnect-v1' };
  const signingInput = `${b64u(JSON.stringify(header))}.${b64u(JSON.stringify(payload))}`;
  const key = crypto.createPrivateKey(P8);
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

// The team holds other apps, and /v1/builds and /v1/betaGroups are team-wide:
// unfiltered, Slackwater would read, annotate, and promote their builds.
let appIdCache;
async function appId() {
  if (appIdCache) return appIdCache;
  const r = await api('GET', '/v1/apps?filter[bundleId]=io.openwaters.slackwater');
  const app = r.data.find((a) => a.attributes.bundleId === 'io.openwaters.slackwater');
  if (!app) throw new Error('no App Store Connect app for io.openwaters.slackwater');
  return (appIdCache = app.id);
}

// A build is not addable — or annotatable — until processing finishes, and
// processing outlives the upload by 5-15 min. A named build is not even LISTED
// for the first few minutes, which is a wait too: throwing there is what made
// testflight.sh pass no build number, and a bare promote then grabbed whatever
// build was newest (build 23's release promoted build 22 that way).
async function waitForBuild(version, buildNumber) {
  let build;
  for (let i = 0; i < 60; i++) {
    const r = await api('GET', `/v1/builds?filter[app]=${await appId()}&limit=10&sort=-uploadedDate&include=preReleaseVersion,betaGroups`);
    const included = (id) => r.included?.find((item) => item.id === id);
    build = r.data.find((candidate) => {
      const train = included(candidate.relationships?.preReleaseVersion?.data?.id)?.attributes?.version;
      return (!version || train === version) && (!buildNumber || candidate.attributes.version === String(buildNumber));
    });
    if (!build && !version && !buildNumber) throw new Error('no builds on App Store Connect');
    if (!build) {
      console.log(`build ${version ?? '*'} (${buildNumber ?? '*'}): not listed yet, waiting…`);
    } else if (build.attributes.processingState === 'VALID') {
      return build;
    } else {
      console.log(`build ${build.attributes.version}: ${build.attributes.processingState}, waiting…`);
    }
    await new Promise((r) => setTimeout(r, 30_000));
  }
  if (!build) throw new Error(`build ${version ?? '*'} (${buildNumber ?? '*'}) never appeared on App Store Connect (30 min)`);
  throw new Error(`build ${build.attributes.version} still ${build.attributes.processingState} after 30 min`);
}

async function externalGroups() {
  const response = await api('GET', `/v1/betaGroups?filter[app]=${await appId()}&limit=20`);
  return response.data.filter((group) => !group.attributes.isInternalGroup);
}

function expectedGroups(file) {
  const lines = fs.readFileSync(file, 'utf8').split('\n').map((line) => line.trim()).filter(Boolean);
  if (!lines.length || new Set(lines).size !== lines.length) throw new Error(`${file} must contain unique group names`);
  return lines.sort();
}

async function verifiedPromotion(version, buildNumber, groupFile) {
  if (!version || !/^\d+$/.test(buildNumber ?? '') || !groupFile) throw new Error('verify and promote require version, build number, and group file');
  const groups = await externalGroups();
  const expected = expectedGroups(groupFile);
  const actual = groups.map((group) => group.attributes.name).sort();
  if (JSON.stringify(expected) !== JSON.stringify(actual)) {
    throw new Error(`expected external groups [${expected.join(', ')}], found [${actual.join(', ')}]`);
  }
  const build = await waitForBuild(version, buildNumber);
  return { build, groups };
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
  const r = await api('GET', `/v1/builds?filter[app]=${await appId()}&limit=10&sort=-uploadedDate&include=preReleaseVersion,betaGroups`);
  const inc = (id) => r.included?.find((i) => i.id === id);
  for (const b of r.data) {
    const v = inc(b.relationships?.preReleaseVersion?.data?.id)?.attributes?.version ?? '?';
    const groups = (b.relationships?.betaGroups?.data ?? []).map((g) => inc(g.id)?.attributes?.name ?? g.id);
    console.log(`${v} (${b.attributes.version})  ${b.attributes.processingState}  ${b.attributes.uploadedDate}  [${groups.join(', ')}]`);
  }
} else if (cmd === 'verify') {
  const { build, groups } = await verifiedPromotion(args[0], args[1], args[2]);
  console.log(`${args[0]} (${args[1]}) ${build.id} [${groups.map((group) => group.attributes.name).join(', ')}]`);
} else if (cmd === 'promote') {
  // Put a build in front of the external testers. Two steps, because an
  // external group sits behind a public link: adding the build to the group is
  // not enough, Apple has to beta-review it first. The internal "Nightly" group
  // needs none of this — it has hasAccessToAllBuilds and every upload lands
  // there on its own, which is why this command exists only for the external
  // side.
  const { build, groups } = await verifiedPromotion(args[0], args[1], args[2]);
  const attached = new Set(build.relationships?.betaGroups?.data?.map((group) => group.id) ?? []);

  for (const g of groups.filter((group) => !attached.has(group.id))) {
    await api('POST', `/v1/betaGroups/${g.id}/relationships/builds`, {
      data: [{ type: 'builds', id: build.id }],
    });
    console.log(`build ${build.attributes.version} -> ${g.attributes.name}`);
  }

  const detail = await api('GET', `/v1/builds/${build.id}/buildBetaDetail`);
  const state = detail.data.attributes.externalBuildState;
  if (state === 'READY_FOR_BETA_SUBMISSION') {
    await api('POST', '/v1/betaAppReviewSubmissions', {
      data: {
        type: 'betaAppReviewSubmissions',
        relationships: { build: { data: { type: 'builds', id: build.id } } },
      },
    });
    console.log('submitted for Apple beta review — testers get it once approved');
  } else if (state === 'WAITING_FOR_BETA_REVIEW' || state === 'IN_BETA_TESTING') {
    console.log(`beta review already ${state.toLowerCase()}`);
  } else {
    throw new Error(`build ${args[0]} (${args[1]}) cannot submit for beta review from ${state}`);
  }
} else if (cmd === 'notes') {
  // "What to Test", per build. The localizations are created with the build and
  // start empty — so this PATCHes them, it never POSTs a second one. Every
  // locale gets the same text; the app is English-only.
  const build = await waitForBuild(undefined, args[0]);
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
  // io.openwaters.slackwater and io.openwaters.slackwater.widgets, and the
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
} else if (cmd === 'install-profiles') {
  // Download named profiles into Xcode's profile directory, so a fresh runner
  // needs no profile secrets and a re-mint needs no secret update.
  const dir = `${process.env.HOME}/Library/Developer/Xcode/UserData/Provisioning Profiles`;
  fs.mkdirSync(dir, { recursive: true });
  // Download everything before touching the directory, so a failed request
  // leaves the installed profiles as they were.
  const profiles = [];
  for (const name of args) {
    const r = await api('GET', `/v1/profiles?filter[name]=${encodeURIComponent(name)}&filter[profileState]=ACTIVE`);
    if (r.data.length !== 1) throw new Error(`expected one active profile named "${name}", found ${r.data.length}`);
    profiles.push({ name, ...r.data[0].attributes });
  }
  // PROVISIONING_PROFILE_SPECIFIER matches by name, so an older same-named
  // profile left on a local Mac (another team's, or a pre-capability mint)
  // makes the pick nondeterministic. The plist sits in the CMS envelope as text.
  const nameOf = (f) => fs.readFileSync(`${dir}/${f}`, 'latin1').match(/<key>Name<\/key>\s*<string>([^<]*)<\/string>/)?.[1];
  for (const f of fs.readdirSync(dir).filter((f) => f.endsWith('.mobileprovision'))) {
    if (args.includes(nameOf(f))) fs.rmSync(`${dir}/${f}`);
  }
  for (const { name, uuid, profileContent } of profiles) {
    fs.writeFileSync(`${dir}/${uuid}.mobileprovision`, Buffer.from(profileContent, 'base64'));
    console.log(`profile "${name}" -> ${uuid}`);
  }
} else {
  console.log('usage: asc.mjs builds | verify <version> <buildNumber> <groupFile> | promote <version> <buildNumber> <groupFile> | notes <buildNumber> <file> | create-cert <csr> <out.cer> | create-profile <bundleIdentifier> <certId> <out.mobileprovision> [profileName] | install-profiles <name>...');
}
