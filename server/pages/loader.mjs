// this was created by an AI agent
// Generic hosting adapter only. Application HTML/CSS/JS comes from the published database release.
import { readPublishedDocument, validateSiteConfig, deliveryPolicy } from './read-document.mjs';
import publicConfig from './site-config.mjs';

function unavailable(error) {
  console.warn('Frontend delivery unavailable:', error.name);
  document.title = 'Rockyforums — temporarily unavailable';
  const main = document.createElement('main');
  main.className = 'delivery-status';
  const heading = document.createElement('h1');
  heading.textContent = 'Rockyforums could not load';
  const explanation = document.createElement('p');
  explanation.textContent =
    'The site is temporarily unavailable. Your account has not been changed. Please try again shortly.';
  const retry = document.createElement('button');
  retry.type = 'button';
  retry.textContent = 'Try again';
  retry.addEventListener('click', () => location.reload());
  main.append(heading, explanation, retry);
  document.body.replaceChildren(main);
}

async function load() {
  const config = validateSiteConfig(publicConfig);
  const gateway = `${config.supabaseUrl}/functions/v1/frontend-assets`;
  const policy = deliveryPolicy(config);
  // Pages cannot set frame-ancestors response headers. Do not expose the account UI in a frame.
  if (window.self !== window.top) throw new Error('Embedded account pages are not supported');
  const { releaseId, html } = await readPublishedDocument(config);
  const published = new DOMParser().parseFromString(html, 'text/html');
  if (!published.querySelector('#root') || published.querySelector('base'))
    throw new Error('Unsupported document');
  const routing = published.querySelector('meta[name="rockyforums-routing"]');
  if (config.basePath !== '/' && routing?.content !== 'base-path-v1') {
    throw new Error('Published release does not support a project base path');
  }
  const canonicalPrefix = `/_frontend/${releaseId}/`;
  function assetUrl(value) {
    const url = new URL(value, location.origin);
    if (
      url.origin === location.origin &&
      url.pathname.startsWith(canonicalPrefix) &&
      !url.search &&
      !url.hash
    ) {
      return gateway + url.pathname;
    }
    if (url.href.startsWith(gateway + canonicalPrefix) && !url.search && !url.hash) return url.href;
    throw new Error('Unexpected published asset URL');
  }
  const scripts = [];
  for (const script of published.querySelectorAll('script')) {
    if (script.type !== 'module' || !script.getAttribute('src') || script.textContent.trim()) {
      throw new Error('Published document must use external modules');
    }
    scripts.push({ src: assetUrl(script.getAttribute('src')), integrity: script.integrity });
    script.remove();
  }
  if (scripts.length !== 1) throw new Error('Expected one application entry module');
  for (const link of published.querySelectorAll('link[href]'))
    link.href = assetUrl(link.getAttribute('href'));
  for (const meta of published.querySelectorAll(
    'meta[http-equiv="Content-Security-Policy"], meta[name="rockyforums-base-path"]',
  ))
    meta.remove();
  const csp = document.createElement('meta');
  csp.httpEquiv = 'Content-Security-Policy';
  csp.content = policy;
  const basePath = document.createElement('meta');
  basePath.name = 'rockyforums-base-path';
  basePath.content = config.basePath.replace(/\/$/, '') || '/';
  const referrer = document.createElement('meta');
  referrer.name = 'referrer';
  referrer.content = 'strict-origin-when-cross-origin';
  published.head.prepend(csp, basePath, referrer);
  const statusStyles = document.createElement('link');
  statusStyles.rel = 'stylesheet';
  statusStyles.href = `${config.basePath}delivery.css`;
  published.head.append(statusStyles);
  document.replaceChild(
    document.importNode(published.documentElement, true),
    document.documentElement,
  );
  document.documentElement.dataset.frontendRelease = releaseId;
  for (const descriptor of scripts) {
    const script = document.createElement('script');
    script.type = 'module';
    script.crossOrigin = 'anonymous';
    script.src = descriptor.src;
    if (descriptor.integrity) script.integrity = descriptor.integrity;
    script.addEventListener('error', () =>
      unavailable(new Error('Application module unavailable')),
    );
    document.head.append(script);
  }
}

load().catch(unavailable);
