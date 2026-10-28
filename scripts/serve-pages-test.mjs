// this was created by an AI agent
// Short-lived test fixture; not an application preview or production server.
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
const files = new Set([
  'index.html',
  '404.html',
  'site-config.mjs',
  'loader.mjs',
  'read-document.mjs',
  'delivery.css',
]);
createServer(async (request, response) => {
  const path = new URL(request.url, 'http://fixture.invalid').pathname;
  const relative = path.startsWith('/Rockyforums/')
    ? path.slice('/Rockyforums/'.length) || 'index.html'
    : '';
  const found = files.has(relative);
  const file = found ? relative : '404.html';
  const body = await readFile(resolve('dist/pages', file));
  response.writeHead(found ? 200 : 404, {
    'Content-Type': file.endsWith('.html')
      ? 'text/html; charset=utf-8'
      : file.endsWith('.css')
        ? 'text/css'
        : 'application/javascript',
    'Cache-Control': 'no-store',
  });
  response.end(body);
}).listen(4177, '0.0.0.0');
