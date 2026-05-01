import indexHtml from './index.html';
import privacyHtml from './privacy.html';
import iconPng from './icon.png';

const CACHE_CONTROL = 'public, max-age=3600';
const DOWNLOAD_VERSION = '2.0';
const DOWNLOAD_KEY = `Habits-${DOWNLOAD_VERSION}.dmg`;
const DOWNLOAD_SHA256 = 'e25701523f22f53b6880141aa9f2e5ee1f035f34050661bb0a90df5ec4acf7fd';

const HEADERS = {
  'X-Content-Type-Options': 'nosniff',
  'X-Frame-Options': 'DENY',
  'Referrer-Policy': 'no-referrer',
};

function htmlResponse(body) {
  return new Response(body, {
    headers: {
      ...HEADERS,
      'Content-Type': 'text/html;charset=UTF-8',
      'Cache-Control': CACHE_CONTROL,
    },
  });
}

function textResponse(body, status = 200) {
  return new Response(body, {
    status,
    headers: {
      ...HEADERS,
      'Content-Type': 'text/plain;charset=UTF-8',
      'Cache-Control': CACHE_CONTROL,
    },
  });
}

function checksumResponse(method) {
  return new Response(method === 'HEAD' ? null : `${DOWNLOAD_SHA256}  ${DOWNLOAD_KEY}\n`, {
    headers: {
      ...HEADERS,
      'Content-Type': 'text/plain;charset=UTF-8',
      'Cache-Control': 'public, max-age=86400',
    },
  });
}

async function downloadResponse(env, method) {
  const object = method === 'HEAD'
    ? await env.DOWNLOADS.head(DOWNLOAD_KEY)
    : await env.DOWNLOADS.get(DOWNLOAD_KEY);

  if (!object) return textResponse('Download not found', 404);

  const headers = new Headers(HEADERS);
  object.writeHttpMetadata(headers);
  headers.set('ETag', object.httpEtag);
  headers.set('Content-Length', object.size.toString());
  headers.set('Content-Type', 'application/x-apple-diskimage');
  headers.set('Content-Disposition', `attachment; filename="${DOWNLOAD_KEY}"`);
  headers.set('Cache-Control', 'public, max-age=86400');

  return new Response(method === 'HEAD' ? null : object.body, { headers });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname.replace(/\/+$/, '') || '/';

    if (request.method !== 'GET' && request.method !== 'HEAD') {
      return textResponse('Method not allowed', 405);
    }

    if (path === '/') return htmlResponse(indexHtml);
    if (path === '/privacy') return htmlResponse(privacyHtml);
    if (path === '/icon.png') {
      return new Response(iconPng, {
        headers: {
          ...HEADERS,
          'Content-Type': 'image/png',
          'Cache-Control': 'public, max-age=86400',
        },
      });
    }
    if (path === `/${DOWNLOAD_KEY}` || path === '/download') return downloadResponse(env, request.method);
    if (path === `/${DOWNLOAD_KEY}.sha256` || path === '/download.sha256') return checksumResponse(request.method);
    if (path === '/robots.txt') return textResponse('User-agent: *\nAllow: /\n');

    return textResponse('Not found', 404);
  },
};
