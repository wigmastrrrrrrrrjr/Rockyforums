// this was created by an AI agent

import { readdirSync } from 'node:fs';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';

function checkDirectory(directory) {
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) {
      checkDirectory(path);
      continue;
    }
    if (!/\.(?:mjs|js)$/.test(entry.name)) continue;
    const result = spawnSync(process.execPath, ['--check', path], { stdio: 'inherit' });
    if (result.status !== 0) process.exit(result.status ?? 1);
  }
}
for (const directory of ['server', 'scripts', 'test', 'supabase/functions'])
  checkDirectory(directory);
await import('./check-public-files.mjs');
