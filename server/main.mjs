// this was created by an AI agent

import { DatabaseAssetStore } from './asset-store.mjs';
import { createWebsiteServer } from './http.mjs';

const supabaseUrl = process.env.SUPABASE_URL;
const store = new DatabaseAssetStore({
  supabaseUrl,
  publishableKey: process.env.SUPABASE_PUBLISHABLE_KEY,
});
const port = Number(process.env.PORT ?? 8080);
if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('Invalid PORT.');
const server = createWebsiteServer({
  store,
  supabaseUrl,
  allowPreviewEmbedding: process.env.ALLOW_PREVIEW_EMBEDDING === 'true',
});
server.requestTimeout = 20_000;
server.headersTimeout = 10_000;
server.listen(port, process.env.HOST ?? '0.0.0.0', () => {
  console.log(`Database-backed website listening on port ${port}`);
});
for (const signal of ['SIGTERM', 'SIGINT']) {
  process.on(signal, () => server.close(() => process.exit(0)));
}
