// webgpu_canvas_probe.mjs — LA PRÉSENTATION D'UN CANVAS WEBGPU DANS LA VM
// (28/08/2026, en marge du chantier décodeur JPEG GPU de PXL-TurboHQ)
//
// Ce que cette sonde établit, en trois épreuves indépendantes :
//
//   A. le compute WGSL et le readback fonctionnent      → ✅ (déjà connu, §6)
//   B. un canvas 2D se composite et se capture          → ✅ (témoin)
//   C. un canvas WEBGPU ne se composite PAS, et le seul
//      fait de le présenter PERD LE DEVICE               → ❌ le constat
//
// C est isolé SANS AUCUN DÉCODAGE : `configure()` puis `getCurrentTexture()`
// en boucle suffisent. Ce n'est donc pas la faute du code applicatif.
//
// Conséquence pratique : dans cette VM, un banc ne peut prouver que ce qui
// se lit par `copyTextureToBuffer` + `mapAsync`. Tout ce qui passe par
// l'AFFICHAGE d'un canvas WebGPU est hors de portée et doit être vérifié
// sur une vraie machine.
//
//   node probes/webgpu_canvas_probe.mjs

import http from 'node:http';
import zlib from 'node:zlib';

const CHROMIUM = '/opt/pw-browsers/chromium';
const PLAYWRIGHT = '/opt/node22/lib/node_modules/playwright/index.mjs';

const HTML = `<!doctype html><meta charset="utf-8">
<style>body{margin:0;background:#888}canvas{display:block;width:120px;height:120px;margin:8px}</style>
<canvas id="gpu"></canvas>
<script type="module">
window.LOG = [];
const mapProbe = async (dev, tag) => {
  const b = dev.createBuffer({ size: 256, usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.MAP_READ });
  try { await b.mapAsync(GPUMapMode.READ); b.unmap(); window.LOG.push(tag + ' : OK'); }
  catch (e) { window.LOG.push(tag + ' : ' + e.message); }
};
const ad = await navigator.gpu.requestAdapter();
const dev = await ad.requestDevice();
window.__keep = { ad, dev };
dev.lost?.then(i => window.LOG.push('DEVICE PERDU : ' + (i?.message || '?')));

// ⚠ LE TÉMOIN 2D VIT DANS UNE PAGE À PART (piège attrapé en écrivant cette
// sonde). Mis dans la MÊME page, il ressortait blanc lui aussi : la perte du
// device casse la composition de TOUTE la page, pas seulement du canvas
// WebGPU. Un témoin contaminé ne témoigne de rien.
window.RUN1 = async () => {
  // A — avant tout canvas
  await mapProbe(dev, 'A  mapAsync avant tout canvas');

  // C — canvas WebGPU : clear rouge par render pass, puis N getCurrentTexture
  const gpu = document.getElementById('gpu');
  gpu.width = 64; gpu.height = 64;
  const ctx = gpu.getContext('webgpu');
  ctx.configure({ device: dev, format: 'rgba8unorm', alphaMode: 'opaque' });
  const e = dev.createCommandEncoder();
  const p = e.beginRenderPass({ colorAttachments: [{
    view: ctx.getCurrentTexture().createView(),
    loadOp: 'clear', storeOp: 'store', clearValue: { r: 1, g: 0, b: 0, a: 1 } }] });
  p.end();
  dev.queue.submit([e.finish()]);
  await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));
  window.__ctx = ctx;
  return window.LOG;
};

window.RUN2 = async (n) => {
  for (let i = 0; i < n; i++) {
    window.__ctx.getCurrentTexture();
    await new Promise(r => setTimeout(r, 5));
  }
  await mapProbe(dev, 'C  mapAsync après ' + n + ' getCurrentTexture');
  return window.LOG;
};
</script>`;

// ── minuscule lecteur de PNG (zlib), pour sonder les captures ──────────────
const PAETH = (a, b, c) => {
  const p = a + b - c, pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c);
  return (pa <= pb && pa <= pc) ? a : (pb <= pc ? b : c);
};
function centerPixel(buf) {
  let p = 8, w = 0, h = 0, ct = 0; const idat = [];
  while (p < buf.length) {
    const len = buf.readUInt32BE(p), type = buf.toString('ascii', p + 4, p + 8);
    const body = buf.subarray(p + 8, p + 8 + len);
    if (type === 'IHDR') { w = body.readUInt32BE(0); h = body.readUInt32BE(4); ct = body[9]; }
    else if (type === 'IDAT') idat.push(body);
    else if (type === 'IEND') break;
    p += 12 + len;
  }
  const ch = { 0: 1, 2: 3, 4: 2, 6: 4 }[ct];
  const raw = zlib.inflateSync(Buffer.concat(idat));
  const stride = w * ch, out = new Uint8Array(h * stride);
  let ro = 0;
  for (let y = 0; y < h; y++) {
    const f = raw[ro++], line = raw.subarray(ro, ro + stride); ro += stride;
    const cur = out.subarray(y * stride, (y + 1) * stride);
    const prev = y > 0 ? out.subarray((y - 1) * stride, y * stride) : null;
    for (let x = 0; x < stride; x++) {
      const a = x >= ch ? cur[x - ch] : 0, b = prev ? prev[x] : 0;
      const c = (prev && x >= ch) ? prev[x - ch] : 0, v = line[x];
      cur[x] = (f === 0 ? v : f === 1 ? v + a : f === 2 ? v + b
              : f === 3 ? v + ((a + b) >> 1) : v + PAETH(a, b, c)) & 0xff;
    }
  }
  const o = ((h >> 1) * w + (w >> 1)) * ch;
  return ch === 1 ? [out[o], out[o], out[o]] : [out[o], out[o + 1], out[o + 2]];
}

// ── déroulement ───────────────────────────────────────────────────────────
const srv = http.createServer((q, r) => { r.writeHead(200, { 'content-type': 'text/html' }); r.end(HTML); });
await new Promise(r => srv.listen(0, '127.0.0.1', r));

const { chromium } = await import(PLAYWRIGHT);
const browser = await chromium.launch({
  executablePath: CHROMIUM,
  proxy: { server: 'direct://' },              // piège n°2 du §6
  args: ['--enable-unsafe-webgpu', '--enable-features=Vulkan',
         '--use-webgpu-adapter=swiftshader', '--no-sandbox', '--no-proxy-server'],
});
const page = await browser.newPage();
await page.goto(`http://127.0.0.1:${srv.address().port}/`, { waitUntil: 'load' });
await page.waitForFunction(() => typeof window.RUN1 === 'function', null, { timeout: 20000 });

await page.evaluate(() => window.RUN1());

console.log('\n── capture d\'écran (ce que l\'œil verrait) ──');
const gpuPx = centerPixel(await page.locator('#gpu').screenshot());

// Témoin dans une PAGE À PART — voir le commentaire dans le script de la page.
const witness = await browser.newPage();
await witness.setContent('<style>body{margin:0;background:#888}'
  + 'canvas{display:block;width:120px;height:120px;margin:8px}</style>'
  + '<canvas id="two" width="64" height="64"></canvas>'
  + '<script>const c=document.getElementById("two").getContext("2d");'
  + 'c.fillStyle="#00ff00";c.fillRect(0,0,64,64);<\/script>');
const twoPx = centerPixel(await witness.locator('#two').screenshot());
await witness.close();
console.log(`  canvas WEBGPU, clear rouge  → ${gpuPx.join(',')}   (attendu 255,0,0)`);
console.log(`  canvas 2D,     vert         → ${twoPx.join(',')}   (attendu 0,255,0)`);

const log = await page.evaluate(() => window.RUN2(40));
console.log('\n── mapAsync ──');
for (const l of log) console.log('  ' + l);

const lost = log.some(l => /DEVICE PERDU/.test(l));
const witnessOk = twoPx[1] > 200 && twoPx[0] < 80;          // le 2D est bien vert
const gpuIsRed  = gpuPx[0] > 200 && gpuPx[1] < 60;          // le WebGPU est-il rouge ?
const verdict   = witnessOk && !gpuIsRed && lost;
console.log(`\n${verdict ? '✅' : '❓'} ${verdict
  ? 'CONFORME AU CONSTAT DU 28/08 : le canvas 2D se composite, le canvas WebGPU\n   n\'affiche RIEN, et le seul fait de le présenter PERD LE DEVICE.'
  : `DIFFÉRENT du constat du 28/08 — remesurer.\n   témoin 2D correct : ${witnessOk} · WebGPU rouge à l'écran : ${gpuIsRed} · device perdu : ${lost}`}`);

await browser.close(); srv.close();
