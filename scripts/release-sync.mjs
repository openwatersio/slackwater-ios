import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { whatsNew } from './appstore.mjs';

const fail = (message) => { throw new Error(message); };
const shipped = new Set(['READY_FOR_DISTRIBUTION', 'READY_FOR_SALE', 'REPLACED_WITH_NEW_VERSION']);
const compare = (a, b) => a.localeCompare(b, 'en', { numeric: true });
const versionPattern = /^\d+\.\d+(?:\.\d+)?$/;
const minimumVersion = '1.15.0';

export function syncReleases({ rows, root, repo, run, dryRun = false, log = console.log }) {
  if (!/^[\w.-]+\/[\w.-]+$/.test(repo)) fail('invalid GitHub repository');
  const seen = new Set();
  for (const row of rows) {
    if (!versionPattern.test(row.version) || !/^\d+$/.test(row.build)) fail('invalid App Store version/build');
    if (!shipped.has(row.state)) fail(`version ${row.version} has not shipped`);
    if (seen.has(row.version)) fail(`duplicate App Store version ${row.version}`);
    seen.add(row.version);
  }
  // Apple's initial 1.0 shipped from the 1.14.0 Nightly train; preserve that manual release.
  const versions = rows.filter((r) => compare(r.version, minimumVersion) >= 0).sort((a, b) => compare(a.version, b.version));
  if (!versions.length) { log(`No App Store releases at or above ${minimumVersion}.`); return; }
  const releases = JSON.parse(run('gh', ['api', `repos/${repo}/releases`, '--paginate', '--slurp'])).flat();
  const remoteTags = new Map();
  for (const line of run('git', ['ls-remote', '--tags', 'origin', 'refs/tags/v*']).trim().split('\n').filter(Boolean)) {
    const [sha, ref] = line.split(/\s+/);
    const tag = ref.replace(/^refs\/tags\//, '').replace(/\^\{\}$/, '');
    if (ref.endsWith('^{}') || !remoteTags.has(tag)) remoteTags.set(tag, sha);
  }
  const plan = versions.map(({ version, build }) => {
    const tag = `v${version}`, nightly = `nightly-${version}-${build}`;
    let commit;
    try {
      commit = run('git', ['rev-parse', '--verify', `refs/tags/${nightly}^{commit}`]).trim();
      run('git', ['merge-base', '--is-ancestor', commit, 'refs/remotes/origin/main']);
    } catch (error) { fail(`Cannot verify ${nightly} on origin/main: ${error.message}`); }
    const hasTag = remoteTags.has(tag);
    if (hasTag && remoteTags.get(tag) !== commit) {
      fail(`${tag} conflict: does not point to ${nightly} (${commit}); refusing to move it`);
    }
    const release = releases.find((r) => r.tag_name === tag);
    if (release && (!hasTag || release.draft || release.prerelease)) fail(`${tag} conflict: expected a stable release at ${commit}`);
    if (release) return { tag, version, build, commit, exists: true };
    const notes = fs.readFileSync(path.join(root, `docs/release-notes/${version}.md`), 'utf8');
    const header = notes.split('\n')[0];
    if (header !== version && header !== `${version} (${build})`) fail(`release notes for ${version} must name build ${build} or omit the build`);
    const body = whatsNew(notes, version);
    const title = body.split('\n')[0].replace(/[.!?]+$/, '');
    return { tag, version, build, commit, hasTag, body, title };
  });
  // Validate the entire plan before publishing any part of it.
  for (const item of plan) {
    if (item.exists) { log(`${item.tag} (${item.build}): already matches ${item.commit}`); continue; }
    log(`${dryRun ? 'Would publish' : 'Publishing'} ${item.tag} (${item.build}) at ${item.commit}`);
    if (!dryRun) {
      // A non-forced push refuses a conflicting tag created after the remote snapshot.
      if (!item.hasTag) run('git', ['push', 'origin', `${item.commit}:refs/tags/${item.tag}`]);
      run('gh', ['release', 'create', item.tag, '--repo', repo, '--verify-tag',
        '--title', item.title, '--notes', item.body, '--latest=false']);
    }
  }
  const newest = plan.at(-1).tag;
  const hasStableRelease = releases.some((r) => !r.draft && !r.prerelease) || (!dryRun && plan.some((r) => !r.exists));
  const latest = hasStableRelease ? JSON.parse(run('gh', ['api', `repos/${repo}/releases/latest`])).tag_name : null;
  if (latest !== newest) {
    // A partial historical backfill must not downgrade an already newer Latest release.
    if (latest && versionPattern.test(latest.slice(1)) && compare(latest.slice(1), plan.at(-1).version) > 0) {
      log(`Keeping newer Latest release ${latest}.`);
    } else {
      log(`${dryRun ? 'Would mark' : 'Marking'} ${newest} as Latest`);
      if (!dryRun) run('gh', ['release', 'edit', newest, '--repo', repo, '--latest']);
    }
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  const args = process.argv.slice(2);
  if (args.some((a) => a !== '--dry-run')) fail('usage: node scripts/release-sync.mjs [--dry-run]');
  const dryRun = args.includes('--dry-run');
  if (!dryRun && (process.env.GITHUB_ACTIONS !== 'true' || process.env.GITHUB_WORKFLOW !== 'Sync App Store releases'
    || process.env.GITHUB_REF !== 'refs/heads/main' || process.env.GITHUB_REPOSITORY !== 'openwatersio/slackwater-ios')) {
    fail('Publish through the Sync App Store releases workflow on main; local runs must use --dry-run');
  }
  const root = fileURLToPath(new URL('../', import.meta.url));
  const run = (command, commandArgs) => execFileSync(command, commandArgs, {
    cwd: root, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024, timeout: 120_000,
    stdio: ['ignore', 'pipe', 'inherit'],
  });
  const log = (line) => {
    console.log(line);
    if (process.env.GITHUB_STEP_SUMMARY) fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, `${line}\n\n`);
  };
  const rows = JSON.parse(run(process.execPath, ['scripts/asc.mjs', 'appstore-releases', minimumVersion]));
  syncReleases({ rows, root, run, repo: process.env.GITHUB_REPOSITORY || 'openwatersio/slackwater-ios',
    dryRun, log });
}
