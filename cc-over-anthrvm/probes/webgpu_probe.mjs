import { chromium } from 'playwright';
import http from 'http';

const log = (m) => console.log(`[${((Date.now() - t0) / 1000).toFixed(1)}s] ${m}`);
const t0 = Date.now();

const server = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/html' });
  res.end('<!DOCTYPE html><html><body>ok</body></html>');
});
await new Promise(r => server.listen(0, '127.0.0.1', r));
const PORT = server.address().port;
log(`serveur sur :${PORT}`);

const browser = await chromium.launch({
  headless: true,
  executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome',
  args: ['--enable-unsafe-webgpu', '--enable-features=Vulkan', '--use-webgpu-adapter=swiftshader', '--no-sandbox', '--no-proxy-server'],
});
log(`chromium lancé: ${browser.version()}`);
const page = await browser.newPage();
log('page créée');
try {
  await page.goto(`http://127.0.0.1:${PORT}/`, { timeout: 15000 });
  log(`goto OK — secure=${await page.evaluate('window.isSecureContext')}`);
} catch (e) {
  log(`goto ÉCHEC: ${e.message.slice(0, 120)}`);
  process.exit(1);
}

const result = await page.evaluate(`(async () => {
  const out = {};
  out.gpu = !!navigator.gpu;
  out.videoDecoder = typeof VideoDecoder !== 'undefined';
  if (navigator.gpu) {
    let a = await navigator.gpu.requestAdapter();
    if (!a) a = await navigator.gpu.requestAdapter({ forceFallbackAdapter: true });
    if (a) {
      const i = a.info || {};
      out.adapter = [i.vendor, i.architecture, i.description].filter(Boolean).join(' / ') || 'anonyme';
      out.fallback = a.isFallbackAdapter;
      const d = await a.requestDevice();
      const sh = d.createShaderModule({ code: '@group(0) @binding(0) var<storage, read_write> x: array<f32>; @compute @workgroup_size(8) fn main(@builtin(global_invocation_id) g: vec3u) { x[g.x] *= 2.0; }' });
      const b = d.createBuffer({ size: 32, usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_SRC | GPUBufferUsage.COPY_DST });
      const r = d.createBuffer({ size: 32, usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.MAP_READ });
      d.queue.writeBuffer(b, 0, new Float32Array([1,2,3,4,5,6,7,8]));
      const p = d.createComputePipeline({ layout: 'auto', compute: { module: sh, entryPoint: 'main' } });
      const bg = d.createBindGroup({ layout: p.getBindGroupLayout(0), entries: [{ binding: 0, resource: { buffer: b } }] });
      const e = d.createCommandEncoder();
      const ps = e.beginComputePass(); ps.setPipeline(p); ps.setBindGroup(0, bg); ps.dispatchWorkgroups(1); ps.end();
      e.copyBufferToBuffer(b, 0, r, 0, 32);
      d.queue.submit([e.finish()]);
      await r.mapAsync(GPUMapMode.READ);
      out.compute = Array.from(new Float32Array(r.getMappedRange()));
      try {
        d.createTexture({ size: [1920, 1080], format: 'r8unorm', usage: GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.RENDER_ATTACHMENT });
        out.ringTexture1080p = 'OK';
      } catch (err) { out.ringTexture1080p = err.message.slice(0, 60); }
    } else out.adapter = 'AUCUN';
  }
  if (out.videoDecoder) {
    out.codecs = {};
    for (const c of ['avc1.42001f', 'hev1.1.6.L93.B0', 'vp09.00.10.08', 'av01.0.04M.08']) {
      try { out.codecs[c] = (await VideoDecoder.isConfigSupported({ codec: c, codedWidth: 1920, codedHeight: 1080 })).supported; }
      catch (e) { out.codecs[c] = 'err'; }
    }
  }
  return out;
})()`);
log('résultat:');
console.log(JSON.stringify(result, null, 2));
await browser.close();
server.close();
process.exit(0);
