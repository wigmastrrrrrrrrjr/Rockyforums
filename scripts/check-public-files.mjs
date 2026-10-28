// this was created by an AI agent

import { execFileSync } from 'node:child_process';
import { existsSync } from 'node:fs';

const rootFiles = new Set([
  '.dockerignore',
  '.env.example',
  '.gitignore',
  '.prettierignore',
  '.prettierrc.json',
  'Dockerfile',
  'Index.html',
  'LICENSE',
  'LICENSE_SCOPE.md',
  'AI disclosure.md',
  'README.md',
  'SECURITY.md',
  'package.json',
  'package-lock.json',
]);
const directories = ['server/', 'scripts/', 'test/', 'supabase/', 'docs/', '.github/'];
const files = execFileSync(
  'git',
  ['ls-files', '--cached', '--others', '--exclude-standard', '-z'],
  { encoding: 'utf8' },
)
  .split('\0')
  .filter(Boolean);
const forbidden = files.filter(
  (file) =>
    existsSync(file) &&
    !rootFiles.has(file) &&
    !directories.some((directory) => file.startsWith(directory)),
);
if (forbidden.length) {
  console.error('Files outside the public backend boundary:', forbidden.join(', '));
  process.exitCode = 1;
} else console.log('Public backend boundary checked; private frontend files are excluded.');
