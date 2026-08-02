#!/usr/bin/env node
// Sonde « piloter une interface » — la VM peut-elle SERVIR une UI, la MANIPULER comme un
// opérateur, et RELIRE ce que le serveur a reçu ? C'est ce qui permet de valider une console
// web sans le matériel qu'elle pilote.
//
//   npm i playwright            # le binaire Chromium est déjà là, seul le paquet manque
//   node probes/ui_probe.mjs [--keep]
//
// Ce que la sonde prouve, dans l'ordre :
//   1. Chromium présent et lançable            4. gestes synthétiques (pointer + clavier)
//   2. page servie en contexte sécurisé        5. le SERVEUR voit bien les commandes
//   3. rendu réel (capture PNG relisible)      6. SSE : le push serveur -> page fonctionne
//
// ⚠️ Deux pièges (DOSSIER_VM.md §6) :
//   - /opt/pw-browsers/chromium est un lien STABLE vers le binaire : ne pas coder la révision.
//   - le contournement de proxy : mesuré le 02/08, `proxy: {server:'direct://'}` — que le
//     dossier prescrivait — ECHOUE en ERR_PROXY_CONNECTION_FAILED. Le lancement par DEFAUT
//     marche (127.0.0.1 est dans no_proxy) ; `--no-proxy-server` marche aussi et le garantit.

import http from 'node:http';
import fs from 'node:fs';
import { existsSync, realpathSync } from 'node:fs';

const CHROME = '/opt/pw-browsers/chromium';
const PORT = 8731;
const SHOT = '/tmp/ui_probe.png';
const KEEP = process.argv.includes('--keep');

let ok = 0, ko = 0;
const sec = (t) => console.log(`\n\x1b[1m── ${t}\x1b[0m`);
const pass = (m, x = '') => { console.log(`  \x1b[32mOK\x1b[0m   ${m}${x && '  ' + x}`); ok++; };
const fail = (m, x = '') => { console.log(`  \x1b[31mNON\x1b[0m  ${m}${x && '  ' + x}`); ko++; };

// ── 1. Chromium ────────────────────────────────────────────────────────────────
sec('Chromium');
if (existsSync(CHROME)) pass('binaire présent', `${CHROME} -> ${realpathSync(CHROME)}`);
else fail('binaire absent', CHROME);

let chromium;
try {
  ({ chromium } = await import('playwright'));
  pass('paquet playwright importable');
} catch {
  fail('paquet playwright absent', 'npm i playwright  (NE PAS lancer playwright install)');
  process.exit(1);
}

// ── page de test : un carré qu'on déplace, qui POSTe sa position ───────────────
const PAGE = `<!doctype html><meta charset=utf-8><title>sonde</title>
<style>body{margin:0;background:#0d1117;font:14px sans-serif;color:#eef2f6;height:100vh}
#stage{position:relative;width:800px;height:450px;margin:20px;border:1px solid #ff6a9e}
#box{position:absolute;left:40px;top:40px;width:200px;height:112px;background:#3ddc97;
     opacity:.6;cursor:move;touch-action:none}#out{margin:20px;color:#eec06a}</style>
<div id=stage><div id=box></div></div><div id=out>—</div><script>
const box=document.getElementById('box'),out=document.getElementById('out');let n=0;
box.addEventListener('pointerdown',e=>{e.preventDefault();
  const sx=e.clientX-box.offsetLeft, sy=e.clientY-box.offsetTop;
  const mv=ev=>{box.style.left=(ev.clientX-sx)+'px';box.style.top=(ev.clientY-sy)+'px';
    fetch('/api/rect',{method:'POST',headers:{'Content-Type':'application/json'},
      body:JSON.stringify({x:box.offsetLeft,y:box.offsetTop,n:++n})});};
  const up=()=>{removeEventListener('pointermove',mv);removeEventListener('pointerup',up);};
  addEventListener('pointermove',mv);addEventListener('pointerup',up);});
addEventListener('keydown',e=>{if(e.key==='r'){box.style.left='40px';box.style.top='40px';
  fetch('/api/rect',{method:'POST',headers:{'Content-Type':'application/json'},
    body:JSON.stringify({x:40,y:40,n:++n,key:'r'})});}});
new EventSource('/api/events').onmessage=e=>{out.textContent='SSE: '+e.data;};
</script>`;

// ── serveur local : sert la page, encaisse les POST, pousse du SSE ─────────────
const seen = [];
const sseClients = new Set();
const srv = http.createServer((req, res) => {
  if (req.url === '/api/rect' && req.method === 'POST') {
    let b = '';
    req.on('data', (c) => (b += c));
    req.on('end', () => { try { seen.push(JSON.parse(b)); } catch {} res.end('{}'); });
    return;
  }
  if (req.url === '/api/events') {
    res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-store' });
    sseClients.add(res);
    req.on('close', () => sseClients.delete(res));
    return;
  }
  res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
  res.end(PAGE);
});
await new Promise((r) => srv.listen(PORT, '127.0.0.1', r));

// ── 2-6. le navigateur joue l'opérateur ───────────────────────────────────────
sec('Interface');
const browser = await chromium.launch({
  executablePath: CHROME,
  // PAS de proxy:{server:'direct://'} — mesuré cassant le 02/08 (voir en-tête).
  args: ['--no-sandbox', '--no-proxy-server'],
});
const page = await browser.newPage({ viewport: { width: 1000, height: 640 } });
const jsErrors = [];
page.on('pageerror', (e) => jsErrors.push(e.message));

const t0 = Date.now();
await page.goto(`http://127.0.0.1:${PORT}/`, { waitUntil: 'load', timeout: 15000 });
pass('page servie et chargée', `${Date.now() - t0} ms`);

const secure = await page.evaluate(() => window.isSecureContext);
if (secure) pass('contexte sécurisé', 'http://127.0.0.1 suffit (ni about:blank ni data:)');
else fail('contexte NON sécurisé', 'navigator.gpu et VideoDecoder seraient absents');

// geste : glisser le carré de 300 px
const b = await page.locator('#box').boundingBox();
await page.mouse.move(b.x + b.width / 2, b.y + b.height / 2);
await page.mouse.down();
await page.mouse.move(b.x + b.width / 2 + 300, b.y + b.height / 2 + 120, { steps: 15 });
await page.mouse.up();
await page.waitForTimeout(250);

const moved = seen.filter((s) => !s.key);
if (moved.length >= 5) pass('geste synthétique reçu par le serveur', `${moved.length} POST`);
else fail('geste non transmis', `${moved.length} POST`);
const last = moved.at(-1);
if (last && last.x > 300) pass('position finale cohérente', `x=${last.x} y=${last.y}`);
else fail('position incohérente', JSON.stringify(last));

await page.keyboard.press('r');
await page.waitForTimeout(200);
if (seen.some((s) => s.key === 'r')) pass('raccourci clavier reçu');
else fail('raccourci clavier perdu');

// SSE : le serveur pousse, la page affiche
for (const c of sseClients) c.write('data: pousse-serveur\n\n');
await page.waitForTimeout(300);
const outTxt = await page.textContent('#out');
if (outTxt.includes('pousse-serveur')) pass('SSE serveur -> page', `"${outTxt}"`);
else fail('SSE non reçu', `"${outTxt}"`);

await page.screenshot({ path: SHOT });
const bytes = fs.statSync(SHOT).size;
if (bytes > 5000) pass('capture PNG écrite', `${SHOT} (${(bytes / 1024).toFixed(0)} Ko)`);
else fail('capture vide', SHOT);

if (jsErrors.length === 0) pass('aucune erreur JS');
else fail('erreurs JS', jsErrors.join(' | '));

await browser.close();
if (!KEEP) srv.close(); else console.log(`\n(serveur laissé sur http://127.0.0.1:${PORT}/)`);

sec('Bilan');
console.log(`  ${ok} OK · ${ko} à regarder`);
console.log('  La capture est relisible par l\'agent : c\'est ce qui ferme la boucle');
console.log('  (servir -> manipuler -> relire ce que le serveur a vu -> REGARDER le rendu).');
if (!KEEP) process.exit(ko ? 1 : 0);
