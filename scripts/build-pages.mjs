// this was created by an AI agent

import { mkdir, readFile, writeFile, copyFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { parseEnv } from 'node:util';
import { validateSiteConfig, deliveryPolicy } from '../server/pages/read-document.mjs';

const example = parseEnv(await readFile(new URL('../.env.example', import.meta.url), 'utf8'));
const basePath = process.env.PAGES_BASE_PATH ?? '/Rockyforums/';
const config = validateSiteConfig({
  supabaseUrl: process.env.SUPABASE_URL ?? example.SUPABASE_URL,
  publishableKey: process.env.SUPABASE_PUBLISHABLE_KEY ?? example.SUPABASE_PUBLISHABLE_KEY,
  basePath,
});
const policy = deliveryPolicy(config);
const shell = (await readFile(new URL('../server/pages/shell.html', import.meta.url), 'utf8'))
  .replaceAll('__BASE_PATH__', config.basePath)
  .replace('__DELIVERY_CSP__', policy);
const output = resolve('dist/pages');
await mkdir(output, { recursive: true });
for (const file of ['loader.mjs', 'read-document.mjs', 'delivery.css']) {
  await copyFile(new URL(`../server/pages/${file}`, import.meta.url), resolve(output, file));
}
await writeFile(resolve(output, 'index.html'), shell);
await writeFile(resolve(output, '404.html'), shell);
await writeFile(resolve(output, '.nojekyll'), '');
await writeFile(
  resolve(output, 'site-config.mjs'),
  `// this was created by an AI agent\nexport default Object.freeze(${JSON.stringify(config)});\n`,
);
console.log(
  'Built Pages delivery shell only; no application source, compiled UI or administrator credentials included.',
);
