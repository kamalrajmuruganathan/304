// Test d'interface automatique du prototype : charge prototype/304.html dans un
// navigateur simulé (jsdom), joue des donnes complètes en cliquant comme un humain
// (enchères, atout, ouvert/fermé, cartes, Conseil, Dernier pli, Réglages), passe
// en anglais en cours de route, et échoue sur toute erreur JS, blocage ou texte
// français resté en mode EN.   Usage :  npm install  &&  DEALS=40 node run.js
const {JSDOM,VirtualConsole}=require('jsdom');
const fs=require('fs');
const html=fs.readFileSync(require('path').join(__dirname,'../../prototype/304.html'),'utf8');
const errors=[]; const vc=new VirtualConsole();
vc.on('jsdomError',e=>errors.push('jsdomError: '+(e.message||e)));
vc.on('error',e=>errors.push('console.error: '+e));
const dom=new JSDOM(html,{runScripts:'dangerously',url:'https://example.org/',pretendToBeVisual:true,virtualConsole:vc,
  beforeParse(w){ const nodeST=setTimeout; w.setTimeout=(f)=>nodeST(()=>{try{f()}catch(e){errors.push('timer: '+e.stack.split('\n').slice(0,3).join(' | '))}},0);
    w.confirm=()=>true; w.onerror=(m,s,l,c,e)=>errors.push('onerror: '+m+' @'+l+' STACK: '+(e&&e.stack?e.stack.split('\n').slice(0,6).join(' <- '):'')); }});
const w=dom.window, d=w.document;
let hands=0, lastSig='', idle=0, clicks=0, hints=0, lastTricks=0, settings=0, frMsgsInEN=[], langSwitched=false;
const FRENCH=/À vous|réfléchit|Enchère|Meilleure|Personne|Vous gagnez|pose l'atout|choisit un|Preneur :|Dernier pli :|Suivez|entamez|Atout encore|Tout le monde/;
const pick=a=>a[Math.floor(Math.random()*a.length)];
function step(){
  const home=d.getElementById('home'); if(home){ home.querySelector('button.primary').click(); return true; }
  const fs2=d.querySelector('.fs-overlay'); if(fs2){ const b=[...fs2.querySelectorAll('button')].pop(); b.click(); return true; }
  const cont=d.getElementById('cont'); if(cont){ hands++; cont.click(); 
    if(hands===Math.floor(Number(process.env.DEALS||40)/2) && !langSwitched){ w.setLang(process.env.L||'en'); langSwitched=true; } return true; }
  const btns=[...d.querySelectorAll('#controls button')].filter(b=>!b.disabled);
  const aux=btns.filter(b=>b.onclick===w.showPlayHint||b.onclick===w.openLastTrick||/💡/.test(b.textContent)); // indépendant de la langue
  const act=btns.filter(b=>!aux.includes(b));
  // exerce parfois les bonus
  if(aux.length && Math.random()<0.15){ const b=pick(aux); if(b.onclick===w.openLastTrick) lastTricks++; else hints++; b.click(); return true; }
  if(Math.random()<0.01){ w.openSettings(); settings++; return true; }
  const hand=[...d.querySelectorAll('#seat-S .card.play')];
  if(hand.length && !act.length){ pick(hand).click(); clicks++; return true; }
  if(act.length){ // évite PCC la plupart du temps
    const nonPcc=act.filter(b=>!/Partner Close Caps/.test(b.textContent));
    const b=(nonPcc.length && Math.random()<0.97)?pick(nonPcc):pick(act); b.click(); clicks++; return true; }
  if(hand.length){ pick(hand).click(); clicks++; return true; }
  return false;
}
function sig(){ return (d.getElementById('msg')||{}).textContent+'|'+d.querySelectorAll('#trick .card').length+'|'+d.querySelectorAll('#seat-S .card').length+'|'+hands; }
function loop(){
  if(langSwitched){ const m=(d.getElementById('msg')||{}).textContent||''; const probe=m.replace(/Partner Close Caps|Caps|AI|[A-Z]?\d+/g,''); if(FRENCH.test(m) || (process.env.L && process.env.L!=='en' && /[A-Za-z]{3,}/.test(probe))) frMsgsInEN.push(m.slice(0,90)); }
  const acted=step(); const s=sig();
  if(!acted && s===lastSig){ idle++; } else idle=0; lastSig=s;
  if(hands>=Number(process.env.DEALS||40) || idle>400 || errors.length>5) return done();
  setTimeout(loop,1);
}
function done(){
  console.log(`Donnes terminées via l'interface : ${hands}`);
  console.log(`Clics : ${clicks} | Conseils : ${hints} | Dernier pli : ${lastTricks} | Réglages ouverts : ${settings}`);
  console.log(idle>400 ? 'BLOCAGE détecté ! msg = '+d.getElementById('msg').textContent : 'Aucun blocage ✓');
  console.log(errors.length? 'ERREURS :\n  '+[...new Set(errors)].slice(0,8).join('\n  ') : 'Aucune erreur JavaScript ✓');
  const uniq=[...new Set(frMsgsInEN)];
  console.log(uniq.length? 'Messages restés en français en mode EN :\n  '+uniq.slice(0,10).join('\n  ') : 'Mode EN : aucun message du déroulé resté en français ✓');
  process.exit((idle>400||errors.length||uniq.length)?1:0);
}
setTimeout(loop,50);
