import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import test from 'node:test';

test('poller rejects incomplete configuration without printing secrets', () => {
  const result = spawnSync(process.execPath, ['src/poll.ts'], {
    cwd: new URL('..', import.meta.url),
    encoding: 'utf8',
    env: { PATH: process.env.PATH, APPLE_PRIVATE_KEY: 'sensitive-key-text' },
  });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /configuration error: GH_FEEDBACK_REPO/);
  assert.doesNotMatch(result.stdout + result.stderr, /sensitive-key-text/);
});
