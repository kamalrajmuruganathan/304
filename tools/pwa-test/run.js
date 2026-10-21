// Test de l'appli web installable / hors ligne (web/sw.js), dans Chromium.
// 1. flutter build web --release --no-web-resources-cdn --base-href /304/app/
//    && bash tool/precache.sh build/web
// 2. mkdir -p /tmp/site/304 && cp -r build/web /tmp/site/304/app
//    && (cd /tmp/site && python3 -m http.server 8765 --bind 127.0.0.1 &)
// 3. node tools/pwa-test/run.js /tmp   (captures d'écran dans ce dossier)
// Vérifie : service worker actif et copie faite ; rechargement hors ligne ;
// partie solo lancée hors ligne ; lien ?daily=1 hors ligne ; 0 erreur JS.
let chromium;
try {
  ({ chromium } = require('playwright'));
} catch (_) {
  ({ chromium } = require('/opt/node-tools/node_modules/playwright'));
}
(async () => {
  const S = process.argv[2];
  const browser = await chromium.launch({ executablePath: process.env.CHROMIUM || undefined,
    args: ['--proxy-server=' + (process.env.HTTPS_PROXY || 'direct://'), '--proxy-bypass-list=127.0.0.1;localhost'] });
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2 });
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', e => errors.push('pageerror ' + e.message));
  page.on('console', m => { if (m.type() === 'error') errors.push('console ' + m.text()); });
  const url = 'http://127.0.0.1:8765/304/app/';
  await page.goto(url);
  await page.waitForSelector('flutter-view, flt-glass-pane', { timeout: 60000 });
  // service worker actif et copie faite
  await page.evaluate(() => navigator.serviceWorker.ready);
  let cached = 0;
  for (let i = 0; i < 60; i++) {
    cached = await page.evaluate(async () => {
      const c = await caches.open('game304-v1');
      return (await c.keys()).length;
    });
    if (cached >= 20) break;
    await page.waitForTimeout(500);
  }
  const reg = await page.evaluate(async () => (await navigator.serviceWorker.getRegistration())?.active?.scriptURL);
  console.log('SW', reg, 'fichiers en cache', cached);
  console.log('pwa fns', await page.evaluate(() => [typeof pwaCanInstall, typeof pwaInstall, pwaStandalone()]));
  await page.waitForTimeout(3000);
  await page.screenshot({ path: S + '/pwa_online.png' });
  // hors ligne
  await ctx.setOffline(true);
  await page.reload();
  await page.waitForSelector('flutter-view, flt-glass-pane', { timeout: 60000 });
  await page.waitForTimeout(4000);
  const reg2 = await page.evaluate(async () => (await navigator.serviceWorker.getRegistration())?.active?.scriptURL);
  console.log('SW après rechargement hors ligne', reg2);
  // accessibilité Flutter : boutons cliquables par leur texte
  await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
  await page.waitForTimeout(1500);
  const btn = page.getByText('Quick Play vs Bots');
  await btn.first().click();
  await page.waitForTimeout(6000);
  await page.screenshot({ path: S + '/pwa_offline_game.png' });
  // lien ?daily=1 hors ligne : la page vient de la copie
  await page.goto(url + '?daily=1');
  await page.waitForSelector('flutter-view, flt-glass-pane', { timeout: 60000 });
  await page.waitForTimeout(5000);
  await page.screenshot({ path: S + '/pwa_offline_daily.png' });
  console.log('erreurs', JSON.stringify(errors.filter(e => !/fonts\.g|ERR_INTERNET_DISCONNECTED|Failed to load resource/.test(e))));
  const bad = errors.filter(e => !/fonts\.g|ERR_INTERNET_DISCONNECTED|Failed to load resource/.test(e));
  if (cached < 20 || !reg2 || bad.length) process.exitCode = 1;
  await browser.close();
})().catch(e => { console.error('ECHEC', e); process.exit(1); });
