// Minimal App Store Connect API client — JWT (ES256) + the few calls TestFlight
// and the App Store listing need.
import crypto from 'node:crypto';
import fs from 'node:fs';
import {
  body, categoryRels, chunks, loadListing, reviewDetailAttributes, SCREENSHOT_SETS,
  screenshotFiles, versionLocalizationAttributes, whatsNew,
} from './appstore.mjs';

// Credentials come from the environment: repo secrets in the Nightly
// workflow, `op run` or an exported shell locally. See docs/testflight.md.
// Read on first use, so a dry run needs none.
const env = (name) => process.env[name] || (() => { throw new Error(`${name} is not set`); })();

const flags = process.argv.slice(2).filter((a) => a.startsWith('--'));
const unknown = flags.filter((f) => f !== '--dry-run' && f !== '--yes');
// A mistyped --dry-run must not fall through to a real run.
if (unknown.length) throw new Error(`unknown flag ${unknown.join(' ')}`);
const DRY_RUN = flags.includes('--dry-run');
const YES = flags.includes('--yes');
// With no key a dry run cannot read the record, so it plans against an empty
// one: every lookup misses and every write is a create.
const OFFLINE = DRY_RUN && !process.env.ASC_KEY_ID;
let dryRunCreates = 0;

const b64u = (buf) => Buffer.from(buf).toString('base64url');

function jwt() {
  const header = { alg: 'ES256', kid: env('ASC_KEY_ID'), typ: 'JWT' };
  const now = Math.floor(Date.now() / 1000);
  const payload = { iss: env('ASC_ISSUER_ID'), iat: now, exp: now + 900, aud: 'appstoreconnect-v1' };
  const signingInput = `${b64u(JSON.stringify(header))}.${b64u(JSON.stringify(payload))}`;
  const key = crypto.createPrivateKey(env('ASC_KEY'));
  // ieee-p1363 gives the raw r||s signature JWT ES256 requires (not DER)
  const sig = crypto.sign('sha256', Buffer.from(signingInput), { key, dsaEncoding: 'ieee-p1363' });
  return `${signingInput}.${b64u(sig)}`;
}

async function api(method, path, payload) {
  // A dry run prints each write and answers it with the resource it sent, so
  // later steps can name it. Reads still go out when there is a key to sign
  // them, except under a resource the dry run only pretended to create.
  if (DRY_RUN && method !== 'GET') {
    console.log(`${method} ${path}${payload ? `\n${JSON.stringify(payload, null, 2)}` : ''}`);
    return { data: { ...payload?.data, id: payload?.data?.id ?? `<new ${payload?.data?.type} ${++dryRunCreates}>` } };
  }
  if (OFFLINE || (DRY_RUN && path.includes('<'))) return { data: [] };
  const res = await fetch(`https://api.appstoreconnect.apple.com${path}`, {
    method,
    headers: { Authorization: `Bearer ${jwt()}`, 'Content-Type': 'application/json' },
    body: payload ? JSON.stringify(payload) : undefined,
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
  if (OFFLINE) return '<app>';
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
async function waitForBuild(version) {
  let build;
  for (let i = 0; i < 60; i++) {
    const r = await api('GET', `/v1/builds?filter[app]=${await appId()}&limit=10&sort=-uploadedDate`);
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

// ── App Store ────────────────────────────────────────────────────────────────
// The listing is docs/appstore-listing.json and each version's What's New is
// its release notes; docs/appstore.md is the per-release procedure. Every
// command finds what exists and PATCHes it, so a rerun converges.

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const fail = (message) => { throw new Error(message); };
// A dry run with no key reads nothing, so it stands a placeholder in for what
// a real run would find.
const need = (found, type, message, attributes = {}) => found ?? (OFFLINE ? { id: `<${type}>`, attributes } : fail(message));

// appStoreState is deprecated; appVersionState replaces it.
const versionState = (v) => v.attributes.appVersionState ?? v.attributes.appStoreState;
const EDITABLE = ['PREPARE_FOR_SUBMISSION', 'DEVELOPER_REJECTED', 'REJECTED', 'METADATA_REJECTED', 'INVALID_BINARY'];

async function iosVersions() {
  const r = await api('GET', `/v1/apps/${await appId()}/appStoreVersions?filter[platform]=IOS&limit=200`);
  return r.data;
}

// An app has one editable version at a time, and a new app record starts with
// a "1.0" placeholder in it. Renaming that version is what the UI's version
// field does; POSTing a second one 409s.
async function ensureVersion(versionString) {
  const all = await iosVersions();
  const v = all.find((x) => x.attributes.versionString === versionString)
    ?? all.find((x) => EDITABLE.includes(versionState(x)));
  const attributes = { versionString, releaseType: 'MANUAL', copyright: loadListing().version.copyright };
  if (!v) {
    const r = await api('POST', '/v1/appStoreVersions', body('appStoreVersions', {
      attributes: { platform: 'IOS', ...attributes },
      rels: { app: ['apps', await appId()] },
    }));
    console.log(`version ${versionString}: created, manual release`);
    return { ...r.data, first: all.length === 0 };
  }
  if (!EDITABLE.includes(versionState(v))) fail(`version ${versionString} is ${versionState(v)}; its listing can no longer change`);
  await api('PATCH', `/v1/appStoreVersions/${v.id}`, body('appStoreVersions', { id: v.id, attributes }));
  const was = v.attributes.versionString;
  console.log(`version ${versionString}: ${was === versionString ? 'updated' : `renamed from ${was}`}, manual release`);
  return { ...v, attributes: { ...v.attributes, ...attributes }, first: all.length === 1 };
}

async function findVersion(versionString, states = EDITABLE) {
  const all = await iosVersions();
  const v = need(all.find((x) => x.attributes.versionString === versionString), 'appStoreVersions',
    `no version ${versionString}; asc.mjs version ${versionString} creates it`, { versionString });
  if (!OFFLINE && !states.includes(versionState(v))) fail(`version ${versionString} is ${versionState(v)}, not ${states.join(' or ')}`);
  // Any other version is one that already shipped, so this one has a What's New.
  return { ...v, first: all.length <= 1 };
}

// Find the localization for the listing's locale and PATCH it, or POST it
// under its parent. The API refuses locale in a PATCH.
async function upsertLocalization(type, listPath, parentRel, locale, attributes) {
  const found = (await api('GET', `${listPath}?filter[locale]=${locale}`)).data[0];
  if (found) {
    await api('PATCH', `/v1/${type}/${found.id}`, body(type, { id: found.id, attributes }));
    return found;
  }
  return (await api('POST', `/v1/${type}`, body(type, { attributes: { locale, ...attributes }, rels: parentRel }))).data;
}

// Name, subtitle, privacy policy URL, categories, and content rights. They
// live on the app, not the version, and the live app info is read-only once a
// version ships, so this edits the one waiting for review.
async function pushAppInfo(l) {
  const app = await appId();
  await api('PATCH', `/v1/apps/${app}`, body('apps', { id: app, attributes: l.app }));
  const infos = (await api('GET', `/v1/apps/${app}/appInfos`)).data;
  const info = need(infos.find((i) => EDITABLE.includes(i.attributes.state ?? i.attributes.appStoreState)), 'appInfos',
    'no editable app info; one appears with a version in Prepare for Submission');
  await api('PATCH', `/v1/appInfos/${info.id}`, body('appInfos', { id: info.id, rels: categoryRels(l) }));
  await upsertLocalization('appInfoLocalizations', `/v1/appInfos/${info.id}/appInfoLocalizations`,
    { appInfo: ['appInfos', info.id] }, l.locale, l.appInfoLocalization);
  console.log(`app info: ${l.appInfoLocalization.name}, ${l.appInfo.primaryCategory}/${l.appInfo.secondaryCategory}`);
}

async function pushVersionLocalization(v, l) {
  const version = v.attributes.versionString;
  let notes;
  if (v.first) {
    console.log(`version ${version}: the app's first version has no What's New, skipping it`);
  } else {
    const file = new URL(`../docs/release-notes/${version}.md`, import.meta.url);
    if (!fs.existsSync(file)) fail(`no docs/release-notes/${version}.md; What's New comes from it`);
    notes = whatsNew(fs.readFileSync(file, 'utf8'), version);
  }
  const loc = await upsertLocalization('appStoreVersionLocalizations', `/v1/appStoreVersions/${v.id}/appStoreVersionLocalizations`,
    { appStoreVersion: ['appStoreVersions', v.id] }, l.locale, versionLocalizationAttributes(l, notes));
  console.log(`version ${version}: ${l.locale} description, keywords, promotional text, URLs${notes ? ', What\'s New' : ''}`);
  return loc;
}

async function pushReviewDetail(v, l) {
  const phone = process.env.ASC_REVIEW_PHONE;
  if (!phone) console.log('ASC_REVIEW_PHONE is not set, so the request leaves the review contact phone out');
  const attributes = reviewDetailAttributes(l, phone);
  const r = await api('GET', `/v1/appStoreVersions/${v.id}?include=appStoreReviewDetail`);
  const id = r.data.relationships?.appStoreReviewDetail?.data?.id;
  if (id) {
    await api('PATCH', `/v1/appStoreReviewDetails/${id}`, body('appStoreReviewDetails', { id, attributes }));
  } else {
    await api('POST', '/v1/appStoreReviewDetails', body('appStoreReviewDetails', {
      attributes, rels: { appStoreVersion: ['appStoreVersions', v.id] },
    }));
  }
  console.log(`version ${v.attributes.versionString}: review contact and notes`);
}

async function attachBuild(v, number) {
  const version = v.attributes.versionString;
  const r = await api('GET', `/v1/builds?filter[app]=${await appId()}&filter[version]=${number}&filter[preReleaseVersion.version]=${version}`);
  const b = need(r.data[0], 'builds', `no build ${version} (${number}) on App Store Connect`);
  const a = b.attributes;
  if (!OFFLINE && (a.processingState !== 'VALID' || a.expired || a.buildAudienceType === 'INTERNAL_ONLY')) {
    fail(`build ${version} (${number}) is ${a.processingState}${a.expired ? ', expired' : ''}${a.buildAudienceType === 'INTERNAL_ONLY' ? ', internal only' : ''}`);
  }
  await api('PATCH', `/v1/appStoreVersions/${v.id}/relationships/build`, { data: { type: 'builds', id: b.id } });
  console.log(`version ${version}: build ${number}`);
}

// Replace each display type's set with the PNGs in dir/<set.dir>, in name
// order. Every file is checked before anything is deleted.
async function pushScreenshots(loc, dir) {
  const todo = SCREENSHOT_SETS.filter((set) => {
    const ok = fs.existsSync(`${dir}/${set.dir}`);
    if (!ok) console.log(`no ${dir}/${set.dir}: ${set.type} screenshots left as they are`);
    return ok;
  }).map((set) => ({ ...set, files: screenshotFiles(`${dir}/${set.dir}`, set.sizes) }));
  if (!todo.length) fail(`no screenshots under ${dir}`);

  for (const set of todo) {
    const sets = await api('GET', `/v1/appStoreVersionLocalizations/${loc.id}/appScreenshotSets?filter[screenshotDisplayType]=${set.type}`);
    const s = sets.data[0] ?? (await api('POST', '/v1/appScreenshotSets', body('appScreenshotSets', {
      attributes: { screenshotDisplayType: set.type },
      rels: { appStoreVersionLocalization: ['appStoreVersionLocalizations', loc.id] },
    }))).data;
    for (const old of (await api('GET', `/v1/appScreenshotSets/${s.id}/appScreenshots?limit=50`)).data) {
      await api('DELETE', `/v1/appScreenshots/${old.id}`);
    }
    const ids = [];
    for (const f of set.files) ids.push(await uploadScreenshot(s.id, f));
    // Upload order is not a documented guarantee of display order; this is.
    await api('PATCH', `/v1/appScreenshotSets/${s.id}/relationships/appScreenshots`,
      { data: ids.map((id) => ({ type: 'appScreenshots', id })) });
    if (!DRY_RUN) await waitForScreenshots(s.id, ids.length);
    console.log(`${set.type}: ${set.files.map((f) => f.name).join(', ')}`);
  }
}

// Reserve, PUT the parts the reservation names, then commit with the MD5.
async function uploadScreenshot(setId, f) {
  const r = await api('POST', '/v1/appScreenshots', body('appScreenshots', {
    attributes: { fileName: f.name, fileSize: f.bytes.length },
    rels: { appScreenshotSet: ['appScreenshotSets', setId] },
  }));
  if (DRY_RUN) {
    console.log(`PUT ${f.name}, ${f.bytes.length} bytes, in the parts the reservation returns`);
  } else {
    for (const part of chunks(f.bytes, r.data.attributes.uploadOperations)) {
      const res = await fetch(part.url, { method: part.method, headers: part.headers, body: part.body });
      if (!res.ok) fail(`${part.method} ${f.name} part -> ${res.status}: ${(await res.text()).slice(0, 300)}`);
    }
  }
  await api('PATCH', `/v1/appScreenshots/${r.data.id}`, body('appScreenshots', {
    id: r.data.id, attributes: { uploaded: true, sourceFileChecksum: f.checksum },
  }));
  return r.data.id;
}

// App Store Connect checks an image after the commit; a wrong one turns FAILED
// here instead of at submission. The set must hold exactly the uploads, since
// an empty list would otherwise pass as all COMPLETE.
async function waitForScreenshots(setId, count) {
  for (let i = 0; i < 60; i++) {
    const shots = (await api('GET', `/v1/appScreenshotSets/${setId}/appScreenshots?limit=50`)).data;
    const state = (s) => s.attributes.assetDeliveryState?.state;
    const failed = shots.filter((s) => state(s) === 'FAILED');
    if (failed.length) fail(failed.map((s) => `${s.attributes.fileName}: ${JSON.stringify(s.attributes.assetDeliveryState.errors)}`).join('\n'));
    if (shots.length === count && shots.every((s) => state(s) === 'COMPLETE')) return;
    await sleep(5_000);
  }
  fail(`screenshot set ${setId} did not reach ${count} COMPLETE screenshots in 5 min`);
}

// Only the version goes in the submission. One already holding anything else,
// say an in-app purchase, is left for a person to sort out in the UI.
async function submitForReview(v) {
  const app = await appId();
  const open = (await api('GET', `/v1/reviewSubmissions?filter[app]=${app}&filter[platform]=IOS&filter[state]=READY_FOR_REVIEW,WAITING_FOR_REVIEW,IN_REVIEW,UNRESOLVED_ISSUES`)).data;
  const busy = open.find((s) => s.attributes.state !== 'READY_FOR_REVIEW');
  if (busy) fail(`review submission ${busy.id} is ${busy.attributes.state}; see App Store Connect`);
  const sub = open[0] ?? (await api('POST', '/v1/reviewSubmissions', body('reviewSubmissions', {
    attributes: { platform: 'IOS' }, rels: { app: ['apps', app] },
  }))).data;
  const items = (await api('GET', `/v1/reviewSubmissions/${sub.id}/items?include=appStoreVersion`)).data;
  const others = items.filter((i) => i.relationships?.appStoreVersion?.data?.id !== v.id);
  if (others.length) fail(`review submission ${sub.id} already holds ${others.length} other item(s); see App Store Connect`);
  if (!items.length) {
    await api('POST', '/v1/reviewSubmissionItems', body('reviewSubmissionItems', {
      rels: { reviewSubmission: ['reviewSubmissions', sub.id], appStoreVersion: ['appStoreVersions', v.id] },
    }));
  }
  await api('PATCH', `/v1/reviewSubmissions/${sub.id}`, body('reviewSubmissions', { id: sub.id, attributes: { submitted: true } }));
  console.log(`version ${v.attributes.versionString}: submitted for App Review`);
}

// The labels publish straight to the product page, with no review. One
// declaration per device family; this edits the draft, making one if needed.
async function pushAccessibility(l) {
  const app = await appId();
  for (const deviceFamily of ['IPHONE', 'IPAD']) {
    const drafts = await api('GET', `/v1/apps/${app}/accessibilityDeclarations?filter[deviceFamily]=${deviceFamily}&filter[state]=DRAFT`);
    const d = drafts.data[0] ?? (await api('POST', '/v1/accessibilityDeclarations', body('accessibilityDeclarations', {
      attributes: { deviceFamily }, rels: { app: ['apps', app] },
    }))).data;
    await api('PATCH', `/v1/accessibilityDeclarations/${d.id}`, body('accessibilityDeclarations', {
      id: d.id, attributes: { ...l.accessibility, publish: true },
    }));
    console.log(`accessibility ${deviceFamily}: published ${Object.keys(l.accessibility).filter((k) => l.accessibility[k]).join(', ')}`);
  }
}

// The commands that reach an audience: a person has to say so.
const confirm = (what) => DRY_RUN || YES || fail(`${what}; pass --yes to do it, or --dry-run to see the requests`);

const [cmd, ...args] = process.argv.slice(2).filter((a) => !a.startsWith('--'));
const APP_STORE = ['prepare', 'version', 'app-info', 'localization', 'review-details', 'attach-build', 'screenshots', 'submit', 'release', 'accessibility'];
if (DRY_RUN && !APP_STORE.includes(cmd)) fail(`--dry-run works with ${APP_STORE.join(', ')}`);
if (DRY_RUN) console.log(OFFLINE ? '# dry run, no ASC key: nothing read, every lookup misses' : '# dry run: reads are real, writes are printed, not sent');
const SHOTS = '/tmp/slackwater-appstore';

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
} else if (cmd === 'promote') {
  // Put a build in front of the external testers. Two steps, because an
  // external group sits behind a public link: adding the build to the group is
  // not enough, Apple has to beta-review it first. The internal "Nightly" group
  // needs none of this — it has hasAccessToAllBuilds and every upload lands
  // there on its own, which is why this command exists only for the external
  // side.
  // With no group named, promote to EVERY external group. Naming one was the
  // old default, and it silently shipped an asymmetry: build 27 reached three
  // groups, build 28 reached two, because a second external group had been
  // added and nothing in the release path knew about it. Discovering them beats
  // a hardcoded list precisely because that is the failure mode: a new group
  // needs no code change to get releases.
  const named = args[1];
  const groups = await api('GET', `/v1/betaGroups?filter[app]=${await appId()}&limit=20`);
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
} else if (cmd === 'prepare') {
  // Everything App Review reads, in the order the UI would fill it in.
  const [version, build, dir = SHOTS] = args;
  if (!version || !build) fail('usage: asc.mjs prepare <version> <build> [screenshotDir]');
  const l = loadListing();
  const v = await ensureVersion(version);
  await pushAppInfo(l);
  const loc = await pushVersionLocalization(v, l);
  await pushReviewDetail(v, l);
  await attachBuild(v, build);
  await pushScreenshots(loc, dir);
} else if (cmd === 'version') {
  await ensureVersion(args[0] ?? fail('usage: asc.mjs version <version>'));
} else if (cmd === 'app-info') {
  await pushAppInfo(loadListing());
} else if (cmd === 'localization') {
  await pushVersionLocalization(await findVersion(args[0] ?? fail('usage: asc.mjs localization <version>')), loadListing());
} else if (cmd === 'review-details') {
  await pushReviewDetail(await findVersion(args[0] ?? fail('usage: asc.mjs review-details <version>')), loadListing());
} else if (cmd === 'attach-build') {
  if (!args[1]) fail('usage: asc.mjs attach-build <version> <build>');
  await attachBuild(await findVersion(args[0]), args[1]);
} else if (cmd === 'screenshots') {
  const l = loadListing();
  const v = await findVersion(args[0] ?? fail('usage: asc.mjs screenshots <version> [screenshotDir]'));
  const loc = need((await api('GET', `/v1/appStoreVersions/${v.id}/appStoreVersionLocalizations?filter[locale]=${l.locale}`)).data[0],
    'appStoreVersionLocalizations', `no ${l.locale} localization; asc.mjs localization ${args[0]} creates it`);
  await pushScreenshots(loc, args[1] ?? SHOTS);
} else if (cmd === 'submit') {
  const version = args[0] ?? fail('usage: asc.mjs submit <version> --yes');
  confirm(`submit sends ${version} to App Review`);
  await submitForReview(await findVersion(version));
} else if (cmd === 'release') {
  // Manual release parks an approved version in Pending Developer Release;
  // this is the button that puts it on sale.
  const version = args[0] ?? fail('usage: asc.mjs release <version> --yes');
  confirm(`release puts ${version} on the App Store`);
  const v = await findVersion(version, ['PENDING_DEVELOPER_RELEASE']);
  await api('POST', '/v1/appStoreVersionReleaseRequests', body('appStoreVersionReleaseRequests', {
    rels: { appStoreVersion: ['appStoreVersions', v.id] },
  }));
  console.log(`version ${version}: released`);
} else if (cmd === 'accessibility') {
  confirm('accessibility publishes the labels to the product page');
  await pushAccessibility(loadListing());
} else {
  console.log('usage: asc.mjs builds | promote [buildNumber] [groupName — default: all external groups] | notes <buildNumber> <file> | create-cert <csr> <out.cer> | create-profile <bundleIdentifier> <certId> <out.mobileprovision> [profileName] | install-profiles <name>...');
  console.log('App Store (docs/appstore.md), each with --dry-run: prepare <version> <build> [screenshotDir] | version <version> | app-info | localization <version> | review-details <version> | attach-build <version> <build> | screenshots <version> [screenshotDir] | submit <version> --yes | release <version> --yes | accessibility --yes');
}
