// Captures d'écran des stores (docs/store/screenshots) depuis le build web.
//   flutter build web --release --no-web-resources-cdn --base-href /304/app/
//   (servir build/web sous http://127.0.0.1:8767/304/app/)
//   node tools/store-shots/run.js <appareil> <langue> [dossier de sortie]
// appareil : phone (1080×1920) | tablet7 (1200×1920) | tablet10 (1600×2560)
// Thèmes : accueil et enchères en Cristal, jeu en Nuit, résultat en Temple.
// Relançable : une capture déjà présente n'est pas refaite.
const fs = require('fs');
const path = require('path');
const { chromium } = require(process.env.PLAYWRIGHT || 'playwright');

const [device = 'phone', lang = 'fr', outArg] = process.argv.slice(2);
const root = path.resolve(__dirname, '../..');
const out = outArg || path.join(root, 'docs/store/screenshots',
  device === 'phone' ? lang : `${device}/${lang}`);
const URL = process.env.URL || 'http://127.0.0.1:8767/304/app/';
const DEV = {
  phone: { viewport: { width: 360, height: 640 }, deviceScaleFactor: 3, hand: 0.76 },
  tablet7: { viewport: { width: 600, height: 960 }, deviceScaleFactor: 2, hand: 0.82 },
  tablet10: { viewport: { width: 800, height: 1280 }, deviceScaleFactor: 2, hand: 0.84 },
}[device];
const arb = JSON.parse(fs.readFileSync(path.join(root, `lib/l10n/app_${lang}.arb`), 'utf8'));

async function open(b, skin) {
  const ctx = await b.newContext({
    viewport: DEV.viewport, deviceScaleFactor: DEV.deviceScaleFactor,
    isMobile: true, hasTouch: true, locale: lang === 'fr' ? 'fr-FR' : lang,
    serviceWorkers: 'block',
  });
  const p = await ctx.newPage();
  p.errs = [];
  p.on('pageerror', e => p.errs.push(e.message));
  await p.addInitScript(([s, l]) => {
    localStorage.setItem('flutter.theme304', JSON.stringify(s));
    localStorage.setItem('flutter.lang304', JSON.stringify(l));
    localStorage.setItem('flutter.speed304', '0.5');
  }, [skin, lang]);
  await p.goto(URL);
  await p.waitForSelector('flt-semantics-placeholder', { state: 'attached', timeout: 90000 });
  await p.waitForTimeout(3000);
  return { ctx, p };
}

async function a11y(p) {
  await p.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
  await p.waitForTimeout(700);
  const vp = p.viewportSize();
  for (let k = 0; k < 3 && (await p.evaluate(() => document.querySelectorAll('flt-semantics').length)) === 0; k++) {
    await p.touchscreen.tap(Math.round(vp.width / 2), Math.round(vp.height / 2));
    await p.waitForTimeout(600);
  }
}

const has = async (p, txt) => (await p.getByText(txt, { exact: false }).count()) > 0;
const btn = (p, name) => p.getByRole('button', { name, exact: true });

/// Lance une partie rapide et joue jusqu'à [stop] (renvoie true si atteint).
async function play(p, stop, { bidShot } = {}) {
  await p.getByRole('button', { name: new RegExp(arb.quickPlay) }).first().click({ timeout: 10000 });
  await p.waitForTimeout(1500);
  const vp = p.viewportSize();
  let follows = 0, bidTaken = false;
  for (let i = 0; i < 300; i++) {
    if (await stop(p, follows)) return true;
    if (await btn(p, arb.pass).count()) {
      if (bidShot && !bidTaken) { bidTaken = true; await bidShot(p); return true; }
      try { await btn(p, arb.pass).first().click({ timeout: 3000 }); } catch (e) {}
      await p.waitForTimeout(300);
      continue;
    }
    for (const b of [arb.closedGame, arb.keep]) {
      const l = btn(p, b);
      if (await l.count()) { try { await l.first().click({ timeout: 3000 }); } catch (e) {} }
    }
    // donne finie sans la capture voulue : donne suivante
    const next = btn(p, arb.nextDeal);
    if (await next.count()) { try { await next.first().click({ timeout: 3000 }); } catch (e) {} await p.waitForTimeout(800); continue; }
    if (await has(p, arb.youFollow)) follows++;
    const y = Math.round(vp.height * DEV.hand);
    for (let x = vp.width * 0.12; x <= vp.width * 0.88; x += vp.width * 0.05) {
      await p.touchscreen.tap(Math.round(x), y);
    }
    await p.waitForTimeout(400);
  }
  return false;
}

(async () => {
  fs.mkdirSync(out, { recursive: true });
  const b = await chromium.launch({ args: process.env.HTTPS_PROXY
    ? ['--proxy-server=' + process.env.HTTPS_PROXY, '--proxy-bypass-list=127.0.0.1;localhost'] : [] });
  const shot = (p, name) => p.screenshot({ path: path.join(out, name) });
  const need = n => !fs.existsSync(path.join(out, n));
  const errs = [];

  if (need('1-home.png') || need('2-bidding.png')) {
    const { ctx, p } = await open(b, 'cristal');
    await shot(p, '1-home.png');
    await a11y(p);
    await play(p, async () => false, {
      bidShot: async pp => { await pp.waitForTimeout(400); await shot(pp, '2-bidding.png'); },
    });
    errs.push(...p.errs);
    await ctx.close();
  }
  if (need('3-play.png')) {
    const { ctx, p } = await open(b, 'nuit');
    await a11y(p);
    // 1re fois que c'est à vous de suivre : cartes sur la table, main presque pleine
    await play(p, async (pp, follows) => {
      if (follows >= 1 && await has(pp, arb.youFollow)) { await pp.waitForTimeout(500); await shot(pp, '3-play.png'); return true; }
      return false;
    });
    errs.push(...p.errs);
    await ctx.close();
  }
  if (need('4-result.png')) {
    const { ctx, p } = await open(b, 'temple');
    await a11y(p);
    await play(p, async pp => {
      if (await has(pp, arb.nextDeal) || await has(pp, arb.playAgain)) { await pp.waitForTimeout(900); await shot(pp, '4-result.png'); return true; }
      return false;
    });
    errs.push(...p.errs);
    await ctx.close();
  }
  await b.close();
  const missing = ['1-home.png', '2-bidding.png', '3-play.png', '4-result.png'].filter(need);
  console.log(`${device}/${lang} : manquantes=${JSON.stringify(missing)} erreurs JS=${JSON.stringify(errs)}`);
  process.exit(missing.length || errs.length ? 1 : 0);
})();
