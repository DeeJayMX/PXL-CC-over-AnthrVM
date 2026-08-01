import { chromium } from 'playwright';
import http from 'http';

const server = http.createServer((req, res) => { res.writeHead(200, { 'Content-Type': 'text/html' }); res.end('<html><body>ok</body></html>'); });
await new Promise(r => server.listen(0, '127.0.0.1', r));
const PORT = server.address().port;

const browser = await chromium.launch({
  headless: true,
  executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome',
  args: ['--enable-unsafe-webgpu', '--enable-features=Vulkan', '--use-webgpu-adapter=swiftshader', '--no-sandbox', '--no-proxy-server'],
});
const page = await browser.newPage();
await page.goto(`http://127.0.0.1:${PORT}/`);

const result = await page.evaluate(`(async () => {
  const a = await navigator.gpu.requestAdapter() || await navigator.gpu.requestAdapter({ forceFallbackAdapter: true });
  const L = a.limits;
  const out = { limits: {
    maxBufferSize_MB: Math.round(L.maxBufferSize / 1048576),
    maxStorageBufferBindingSize_MB: Math.round(L.maxStorageBufferBindingSize / 1048576),
    maxTextureDimension2D: L.maxTextureDimension2D,
    maxTextureArrayLayers: L.maxTextureArrayLayers,
  }};
  const d = await a.requestDevice();
  // Ring PXL : slots NV12 1080p (Y r8unorm 1920x1080 + UV rg8unorm 960x540)
  // = ~3.1 Mo/slot. On alloue par paliers et on écrit dedans pour forcer le commit.
  const TB = GPUTextureUsage.TEXTURE_BINDING, CD = GPUTextureUsage.COPY_DST;
  const texs = [];
  const yData = new Uint8Array(1920 * 1080).fill(128);
  let allocated = 0, oom = null;
  const targets = [100, 300, 600, 1000, 1500];
  for (const target of targets) {
    d.pushErrorScope('out-of-memory');
    for (let i = allocated; i < target; i++) {
      const y = d.createTexture({ size: [1920, 1080], format: 'r8unorm', usage: TB | CD });
      const uv = d.createTexture({ size: [960, 540], format: 'rg8unorm', usage: TB | CD });
      d.queue.writeTexture({ texture: y }, yData, { bytesPerRow: 1920 }, { width: 1920, height: 1080 });
      texs.push(y, uv);
    }
    await d.queue.onSubmittedWorkDone();
    const err = await d.popErrorScope();
    if (err) { oom = 'OOM à ~' + target + ' slots: ' + err.message.slice(0, 60); break; }
    allocated = target;
  }
  out.slotsAlloues = allocated;
  out.MoEquivalents = Math.round(allocated * 3.11);
  out.oom = oom || 'aucun jusqu\\'à ' + allocated + ' slots';
  return out;
})()`);
console.log(JSON.stringify(result, null, 2));
await browser.close(); server.close(); process.exit(0);
