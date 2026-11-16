import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { syncReleases } from './release-sync.mjs';

function fixture(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'release-sync-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const git = (...args) => execFileSync('git', args, { cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
  git('init', '-b', 'main');
  git('config', 'user.name', 'Test'); git('config', 'user.email', 'test@example.com');
  git('commit', '--allow-empty', '-m', 'First');
  const old = git('rev-parse', 'HEAD');
  git('tag', 'nightly-1.15.0-74');
  git('commit', '--allow-empty', '-m', 'Second');
  const newest = git('rev-parse', 'HEAD');
  git('tag', '-a', 'nightly-1.16.0-86', '-m', 'Nightly');
  git('update-ref', 'refs/remotes/origin/main', newest);
  fs.mkdirSync(path.join(root, 'docs/release-notes'), { recursive: true });
  for (const [v, b] of [['1.15.0', '74'], ['1.16.0', '86']]) {
    fs.writeFileSync(path.join(root, `docs/release-notes/${v}.md`), `${v} (${b})\n\nAlerts on your Lock Screen.\n\n· A highlight.\n\nWorth testing: private beta instructions.\n`);
  }
  const releases = [], writes = [], remoteTags = new Map();
  let latest;
  let failCreate = false;
  let beforePublish = () => {};
  const run = (cmd, args) => {
    if (cmd === 'git') {
      if (args[0] === 'ls-remote') return [...remoteTags].map(([tag, sha]) => `${sha}\trefs/tags/${tag}`).join('\n');
      if (args[0] === 'push') {
        beforePublish();
        const [sha, ref] = args[2].split(':');
        const tag = ref.replace('refs/tags/', '');
        if (remoteTags.has(tag) && remoteTags.get(tag) !== sha) throw new Error(`${tag} conflict: remote tag already exists`);
        remoteTags.set(tag, sha);
        return '';
      }
      return git(...args);
    }
    assert.equal(cmd, 'gh');
    if (args[0] === 'api') {
      if (args[1].endsWith('/releases/latest')) return JSON.stringify({ tag_name: latest });
      assert.equal(args[1], 'repos/openwatersio/slackwater-ios/releases');
      return JSON.stringify([releases]);
    }
    writes.push(args);
    if (args[1] === 'create') {
      beforePublish();
      if (failCreate) { failCreate = false; throw new Error('GitHub unavailable'); }
      releases.push({ tag_name: args[2], draft: false, prerelease: false });
      if (!remoteTags.has(args[2])) remoteTags.set(args[2], args[args.indexOf('--target') + 1]);
      if (!git('tag', '--list', args[2])) git('tag', args[2], remoteTags.get(`${args[2]}^{}`) ?? remoteTags.get(args[2]));
      if (!args.includes('--latest=false')) latest = args[2];
    }
    if (args.includes('--latest')) latest = args[2];
    return '';
  };
  const rows = [
    { version: '1.16.0', build: '86', state: 'READY_FOR_DISTRIBUTION' },
    { version: '1.15.0', build: '74', state: 'REPLACED_WITH_NEW_VERSION' },
    { version: '1.0', build: '61', state: 'REPLACED_WITH_NEW_VERSION' },
  ];
  const sync = (extra = {}) => syncReleases({ rows, root, repo: 'openwatersio/slackwater-ios', run, log: () => {}, ...extra });
  return { root, git, old, newest, rows, releases, writes, remoteTags, sync,
    failNextCreate: () => { failCreate = true; }, latest: () => latest, setLatest: (v) => { latest = v; },
    beforePublish: (fn) => { beforePublish = fn; } };
}

test('backfills at exact Nightly commits, strips beta notes and selects the newest shipped version', (t) => {
  const f = fixture(t);
  f.sync();
  assert.deepEqual(f.releases.map((r) => r.tag_name), ['v1.15.0', 'v1.16.0']);
  assert.equal(f.git('rev-parse', 'v1.15.0'), f.old);
  assert.equal(f.git('rev-parse', 'v1.16.0'), f.newest);
  assert.equal(f.latest(), 'v1.16.0');
  for (const args of f.writes.filter((a) => a[1] === 'create')) {
    assert.equal(args[args.indexOf('--title') + 1], 'Alerts on your Lock Screen');
    assert.match(args[args.indexOf('--notes') + 1], /A highlight/);
    assert.doesNotMatch(args[args.indexOf('--notes') + 1], /Worth testing|private beta/);
  }
  const writes = f.writes.length;
  f.sync();
  assert.equal(f.writes.length, writes, 'rerun wrote matching releases');
});

test('dry run validates and reports both releases without GitHub or Git mutations', (t) => {
  const f = fixture(t), lines = [];
  f.sync({ dryRun: true, log: (line) => lines.push(line) });
  assert.equal(f.writes.length, 0);
  assert.equal(f.remoteTags.size, 0);
  assert.equal(f.git('tag', '--list', 'v*'), '');
  assert.ok(lines.some((line) => line.includes('v1.16.0') && line.includes('86')));
});

test('validates all releases before writing and refuses mismatched stable tags', (t) => {
  const f = fixture(t);
  f.remoteTags.set('v1.16.0', f.old);
  assert.throws(() => f.sync(), /v1.16.0.*conflict/);
  assert.equal(f.writes.length, 0);
  assert.equal(f.remoteTags.get('v1.16.0'), f.old);
});

test('missing notes, mismatched build headers, and missing Nightly tags fail visibly', (t) => {
  const f = fixture(t), file = path.join(f.root, 'docs/release-notes/1.16.0.md');
  fs.writeFileSync(file, '1.16.0 (85)\n\nOther build.\n\nWorth testing: beta');
  assert.throws(() => f.sync(), /86.*notes|notes.*86/);
  fs.unlinkSync(file);
  assert.throws(() => f.sync(), /ENOENT|notes/);
  f.git('tag', '-d', 'nightly-1.16.0-86');
  assert.throws(() => f.sync(), /nightly-1.16.0-86/);
  assert.equal(f.writes.length, 0);
});

test('repairs Latest on a matching release and retries a failed publication', (t) => {
  const f = fixture(t);
  f.failNextCreate();
  assert.throws(() => f.sync(), /GitHub unavailable/);
  f.sync();
  assert.equal(f.releases.length, 2);
  f.writes.length = 0;
  // Publishing an older record must not make it Latest.
  f.sync({ rows: [f.rows[1]] });
  assert.equal(f.latest(), 'v1.16.0');
  assert.equal(f.writes.length, 0);
});

test('existing draft or prerelease with a stable tag is a conflict', (t) => {
  const f = fixture(t);
  f.git('tag', 'v1.15.0', f.old);
  f.remoteTags.set('v1.15.0', f.old);
  f.releases.push({ tag_name: 'v1.15.0', draft: true, prerelease: false });
  assert.throws(() => f.sync(), /v1.15.0.*conflict/);
  assert.equal(f.writes.length, 0);
});

test('refuses a conflicting remote tag that appears after validation', (t) => {
  const f = fixture(t);
  f.beforePublish(() => { f.remoteTags.set('v1.15.0', f.newest); });
  assert.throws(() => f.sync(), /v1.15.0.*conflict/);
  assert.equal(f.releases.length, 0);
});

test('repairs Latest when all stable releases already exist', (t) => {
  const f = fixture(t);
  f.sync();
  f.setLatest('v1.14.0');
  f.writes.length = 0;
  f.sync();
  assert.equal(f.latest(), 'v1.16.0');
  assert.equal(f.writes.length, 1);
  assert.equal(f.writes[0][1], 'edit');
});

test('completes a matching remote tag with no release and verifies it on creation', (t) => {
  const f = fixture(t);
  f.remoteTags.set('v1.15.0', f.old);
  f.sync();
  assert.ok(f.writes.filter((a) => a[1] === 'create').every((a) => a.includes('--verify-tag')));
});

test('rereads Latest after publication instead of downgrading a concurrent newer release', (t) => {
  const f = fixture(t);
  f.releases.push({ tag_name: 'v1.14.0', draft: false, prerelease: false });
  f.setLatest('v1.14.0');
  f.beforePublish(() => f.setLatest('v1.17.0'));
  f.sync();
  assert.equal(f.latest(), 'v1.17.0');
});

test('creating historical releases never replaces an already newer Latest', (t) => {
  const f = fixture(t);
  f.releases.push({ tag_name: 'v1.17.0', draft: false, prerelease: false });
  f.setLatest('v1.17.0');
  f.sync();
  assert.equal(f.latest(), 'v1.17.0');
  assert.ok(f.writes.filter((a) => a[1] === 'create').every((a) => a.includes('--latest=false')));
});

test('rejects malformed or duplicate Apple records and unshipped versions', (t) => {
  const f = fixture(t);
  for (const rows of [[{ version: '../oops', build: '86', state: 'READY_FOR_DISTRIBUTION' }],
    [f.rows[0], f.rows[0]], [{ ...f.rows[0], state: 'IN_REVIEW' }]]) {
    assert.throws(() => f.sync({ rows }), /invalid|duplicate|shipped/);
  }
  assert.equal(f.writes.length, 0);
});

test('local CLI publication is refused before reading credentials', () => {
  assert.throws(() => execFileSync(process.execPath, [new URL('./release-sync.mjs', import.meta.url).pathname], {
    env: { ...process.env, GITHUB_ACTIONS: '' }, stdio: 'pipe',
  }), (error) => /local runs must use --dry-run/.test(error.stderr.toString()));
});

test('resolves annotated stable remote tags to their peeled commit', (t) => {
  const f = fixture(t);
  f.remoteTags.set('v1.15.0', 'a'.repeat(40));
  f.remoteTags.set('v1.15.0^{}', f.old);
  f.sync();
  assert.equal(f.releases[0].tag_name, 'v1.15.0');
});
