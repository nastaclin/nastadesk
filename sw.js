/* NastaDesk — Service Worker
 * Estratégia SEGURA para um app que faz deploy frequente (Vercel publica a cada merge):
 *  - Navegação/HTML: NETWORK-FIRST. Online, o cliente SEMPRE recebe a versão nova;
 *    o cache só entra em cena quando está offline. Isso evita "congelar" a clínica
 *    numa versão antiga.
 *  - Estáticos same-origin (ícones): cache-first (são estáveis/versionados).
 *  - Cross-origin (fontes Google, CDN do supabase-js, chamadas à API do Supabase):
 *    NÃO intercepta — deixa passar direto (evita respostas opacas em cache).
 *  - Cache versionado: ao trocar a VERSION, o activate limpa os caches antigos.
 */
const VERSION = 'nastadesk-v2-2026-08-30';
const CORE = [
  '/', '/index.html', '/manifest.json',
  '/icon-192.png', '/icon-512.png', '/apple-touch-icon.png', '/logo.png'
];

self.addEventListener('install', (event) => {
  self.skipWaiting();
  event.waitUntil(
    caches.open(VERSION).then((cache) => cache.addAll(CORE).catch(() => {}))
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.filter((k) => k !== VERSION).map((k) => caches.delete(k)));
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;

  let url;
  try { url = new URL(req.url); } catch (_) { return; }
  // Só mexe no mesmo domínio. Fontes/CDN/Supabase passam direto.
  if (url.origin !== self.location.origin) return;

  const isHTML = req.mode === 'navigate' ||
    (req.headers.get('accept') || '').includes('text/html');

  if (isHTML) {
    // NETWORK-FIRST: versão nova quando online; cache só como rede de segurança offline.
    event.respondWith((async () => {
      try {
        const fresh = await fetch(req);
        const cache = await caches.open(VERSION);
        cache.put(req, fresh.clone());
        return fresh;
      } catch (_) {
        const cached = await caches.match(req);
        return cached || (await caches.match('/index.html')) || Response.error();
      }
    })());
    return;
  }

  // Estáticos same-origin: cache-first com preenchimento sob demanda.
  event.respondWith((async () => {
    const cached = await caches.match(req);
    if (cached) return cached;
    try {
      const fresh = await fetch(req);
      if (fresh && fresh.status === 200 && fresh.type === 'basic') {
        const cache = await caches.open(VERSION);
        cache.put(req, fresh.clone());
      }
      return fresh;
    } catch (_) {
      return cached || Response.error();
    }
  })());
});
