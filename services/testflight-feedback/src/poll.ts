import { listFeedback, type AppleConfig } from './apple.ts';
import { ensurePrivateRepository, ingestFeedback, lookupFeedbackStatus, reconcileMarkers, type GithubConfig } from './github.ts';

class ConfigError extends Error {
  readonly variable: string;
  constructor(variable: string) {
    super('missing configuration');
    this.variable = variable;
  }
}

function required(name: string): string {
  const value = process.env[name];
  if (!value) throw new ConfigError(name);
  return value;
}

async function main(): Promise<void> {
  const mode = process.argv[2] ?? 'scan';
  if (mode !== 'scan' && mode !== 'reconcile') throw new Error('unsupported mode');
  const github: GithubConfig = {
    repository: required('GH_FEEDBACK_REPO'),
    workflowRepository: required('GITHUB_REPOSITORY'),
    token: required('GITHUB_TOKEN'),
  };
  await ensurePrivateRepository(github);
  if (mode === 'reconcile') {
    const result = await reconcileMarkers(github);
    console.log(`reconciled=${result.repaired} unresolved=${result.unresolved}`);
    if (result.unresolved) process.exitCode = 1;
    return;
  }
  const apple: AppleConfig = {
    appId: required('APPLE_APP_ID'),
    issuerId: required('APPLE_ISSUER_ID'),
    keyId: required('APPLE_KEY_ID'),
    privateKey: required('APPLE_PRIVATE_KEY'),
  };
  const counts = { created: 0, duplicate: 0, pending: 0 };
  for await (const feedback of listFeedback(apple, fetch, async (kind, submissionId) => {
    const phase = await lookupFeedbackStatus(github, apple.appId, kind, submissionId);
    if (phase === 'complete') { counts.duplicate++; return false; }
    if (phase === 'creating') { counts.pending++; return false; }
    return true;
  })) {
    const outcome = await ingestFeedback(github, feedback);
    counts[outcome]++;
  }
  console.log(`created=${counts.created} duplicate=${counts.duplicate} pending=${counts.pending}`);
  if (counts.pending) process.exitCode = 1;
}

main().catch(error => {
  if (error instanceof ConfigError) console.error(`configuration error: ${error.variable}`);
  else console.error(`intake failed: ${error instanceof Error ? error.name : 'UnknownError'}`);
  process.exitCode = 1;
});
