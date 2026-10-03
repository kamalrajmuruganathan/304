// ============================================================================
// Trace de référence du PROTOTYPE (moteur + IA JS validés) pour le test
// différentiel Dart (test/prototype_equivalence_test.dart).
//
//   node tools/diff-test/trace.js           # écrit test/fixtures/prototype_trace.json.gz
//   node tools/diff-test/trace.js --check   # CI : échoue si la trace n'est plus à jour
//
// Math.random est remplacé par mulberry32(graine) ; le test Dart injecte le
// même générateur dans Engine(rng: …) et rejoue les mêmes donnes avec les
// mêmes règles de pilotage : chaque coup, chaque enchère et chaque score
// doivent être identiques. À régénérer après toute modification des règles
// ou de l'IA du prototype.
// ============================================================================
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const html = fs.readFileSync(path.join(__dirname, '../../prototype/304.html'), 'utf8');
const start = html.indexOf('<script>') + '<script>'.length;
const end = html.indexOf('UI / CONTRÔLEUR');
const src = html.slice(start, html.lastIndexOf('\n', end)).replace(/\/\*\s*=*\s*$/, '');

function mulberry32(a) {
  return function () {
    a |= 0; a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const store = {};
const ctx = {
  console,
  localStorage: { getItem: k => store[k] ?? null, setItem: (k, v) => { store[k] = String(v); } },
  window: {},
  document: { querySelector: () => null, getElementById: () => null, addEventListener: () => {} },
};
const rnd = { fn: Math.random };
ctx.Math = Object.create(Math);
ctx.Math.random = () => rnd.fn();
vm.createContext(ctx);
vm.runInContext(src + '\n;globalThis.__api={Engine,botBid,botBid2,botChooseTrump,botPlay};', ctx);
const { Engine, botBid, botBid2, botChooseTrump, botPlay } = ctx.__api;

const k = c => c.s + c.r;

// empreinte FNV-1a 32 bits sur les unités UTF-16 (identique en Dart : codeUnits)
function fnv1a(str) {
  let h = 0x811c9dc5;
  for (let i = 0; i < str.length; i++) { h ^= str.charCodeAt(i); h = Math.imul(h, 0x01000193) >>> 0; }
  return h >>> 0;
}

// Une donne pilotée par l'IA, mêmes choix que le test Dart.
// mode : 'closed' | 'open' ; forcePCC : siège qui annonce PCC dès qu'il peut.
function fullHand(e, tr, mode, forcePCC) {
  e.newHand();
  let rc = 0;
  while (e.canRedeal() && rc < 8) { e.redeal(); rc++; tr.push('redeal'); }
  tr.push('deal ' + e.dealer + ' ' + e.hands.map(h => h.map(k).join(',')).join('|'));
  e.startBidding1();
  while (e.phase === 'bid1') {
    const s = e.bidTurn, v = botBid(e, s);
    tr.push('bid1 ' + s + ' ' + v);
    e.placeBid(v);
    if (e.phase === 'allpass') { tr.push('allpass'); return; }
  }
  const c1 = botChooseTrump(e, e.trumpMaker1);
  tr.push('trump1 ' + e.trumpMaker1 + ' ' + k(c1));
  e.chooseTrump1(c1);
  while (e.phase === 'bid2') {
    const s = e.bid2Turn;
    const v = (forcePCC !== null && s === forcePCC && e.canPCC()) ? 'PCC' : botBid2(e, s);
    tr.push('bid2 ' + s + ' ' + v);
    e.placeBid2(v);
  }
  if (e.phase === 'chooseTrumpPCC' || e.phase === 'chooseTrump2') {
    const c = botChooseTrump(e, e.trumpMaker);
    tr.push(e.phase + ' ' + e.trumpMaker + ' ' + k(c));
    e.phase === 'chooseTrumpPCC' ? e.chooseTrumpPCC(c) : e.chooseTrump2(c);
  }
  if (e.phase === 'preplay') {
    if (mode === 'open') e.startPlayOpen(); else e.startPlayClosed();
  }
  tr.push('play ' + e.phase + ' bid=' + e.bid + ' tm=' + e.trumpMaker + ' trump=' + e.trumpSuit + ' open=' + e.trumpOpen + ' pcc=' + !!e.pcc);
  if (e.phase === 'spoilt') return;
  let guard = 0;
  while (e.tricks.length < 8 && guard++ < 200) {
    const s = e.turn;
    let r;
    if (e.hands[s].length === 0 && s === e.trumpMaker && e.indicatorOnTable) {
      tr.push('lastInd ' + s); r = e.playLastIndicator(s);
    } else {
      const ch = botPlay(e, s);
      if (ch && ch.indicator) { tr.push('ind ' + s); r = e.playIndicatorToCut(s); }
      else { const c = ch.card || ch; tr.push('card ' + s + ' ' + k(c)); r = e.playCard(s, c); }
    }
    if (r && r.trickDone) tr.push('trick ' + r.winner + ' ' + r.points + ' ' + !!r.revealed + ' open=' + e.trumpOpen);
  }
  tr.push('score NS=' + e.pointsNS + ' EW=' + e.pointsEW + ' tricks=' + e.trickWinsNS + '/' + e.trickWinsEW +
          ' tokens=' + e.tokens.NS + '/' + e.tokens.EW + ' dealer=' + e.dealer);
}

const games = [];
for (let g = 0; g < 24; g++) {
  rnd.fn = mulberry32(1000 + g);
  const e = new Engine();
  const tr = [];
  let n = 0;
  while (e.tokens.NS > 0 && e.tokens.EW > 0 && n < 60) {
    const mode = n % 3 === 0 ? 'open' : 'closed';
    const forcePCC = (g % 4 === 0 && n % 5 === 2) ? (n % 4) : null;
    tr.push('# hand ' + n + ' ' + mode + ' pcc=' + forcePCC);
    fullHand(e, tr, mode, forcePCC);
    n++;
  }
  const log = e._log || [];
  games.push({ seed: 1000 + g, trace: tr, logCount: log.length, logHash: fnv1a(log.join('\n')) });
}
const out = path.join(__dirname, '../../test/fixtures/prototype_trace.json.gz');
const json = JSON.stringify({ games }) + '\n';
if (process.argv.includes('--check')) {
  const cur = fs.existsSync(out) ? require('zlib').gunzipSync(fs.readFileSync(out)).toString('utf8') : '';
  if (cur !== json) {
    console.error('Trace de référence périmée : relancer `node tools/diff-test/trace.js` et committer.');
    process.exit(1);
  }
  console.log('Trace de référence à jour ✓');
  process.exit(0);
}
fs.writeFileSync(out, require('zlib').gzipSync(json, { level: 9 }));
console.log(`${games.length} parties, ${games.reduce((a, g) => a + g.trace.filter(x => x.startsWith('# hand')).length, 0)} donnes -> test/fixtures/prototype_trace.json.gz`);
