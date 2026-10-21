// 304 — service worker : l'appli web s'installe et la partie solo marche sans
// internet. Stratégie « réseau d'abord » : en ligne, toujours la dernière
// version (et la copie de secours est mise à jour) ; hors ligne, la copie.
// La liste des fichiers à copier dès l'installation (precache.json) est écrite
// à la construction (.github/workflows/pages.yml). Changer la stratégie ?
// Incrémenter CACHE.
const CACHE = 'game304-v1';

self.addEventListener('install', (event) => {
  self.skipWaiting();
  event.waitUntil((async () => {
    try {
      const all = await (await fetch('precache.json', {cache: 'no-store'})).json();
      // une seule version de CanvasKit : celle que ce navigateur chargera
      const chromium = /Chrome|Chromium|CriOS|Edg\//.test(self.navigator.userAgent);
      const list = all.filter((f) => !f.startsWith('canvaskit/') ||
        (chromium ? f.startsWith('canvaskit/chromium/') : !f.includes('/chromium/')));
      const cache = await caches.open(CACHE);
      // fichier par fichier : un échec n'empêche pas les autres
      await Promise.all(['./', ...list].map((u) =>
        cache.add(new Request(u, {cache: 'reload'})).catch(() => {})));
    } catch (e) {
      // pas de liste (développement) : la copie se fera au fil des visites
    }
  })());
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    for (const k of await caches.keys()) {
      if (k !== CACHE) await caches.delete(k);
    }
    await self.clients.claim();
  })());
});

// polices tamoule / cingalaise (Google Fonts) : gardées aussi
const FONTS = /^https:\/\/fonts\.(gstatic|googleapis)\.com\//;

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  const same = url.origin === self.location.origin;
  if (!same && !FONTS.test(req.url)) return; // serveur de jeu, etc.
  if (url.protocol !== 'https:' && url.protocol !== 'http:') return;
  event.respondWith((async () => {
    const cache = await caches.open(CACHE);
    try {
      const res = await fetch(req);
      if (res && (res.ok || res.type === 'opaque')) {
        cache.put(req, res.clone()).catch(() => {});
      }
      return res;
    } catch (e) {
      // hors ligne : la copie (une page ?table=… ou ?daily=1 -> l'appli)
      const hit = await cache.match(req, {ignoreSearch: req.mode === 'navigate'});
      if (hit) return hit;
      if (req.mode === 'navigate') {
        const home = await cache.match('./');
        if (home) return home;
      }
      throw e;
    }
  })());
});
