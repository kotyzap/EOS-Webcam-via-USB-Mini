#!/usr/bin/env node
// EOS Webcam - Canon live view over USB as a local MJPEG stream with a browser UI.
// Author: Pavel Kotyza <kotyza@gmail.com> - 4xs.dev
// Needs: brew install gphoto2.   Run: node eos-webcam.js   then open http://127.0.0.1:8809
const http = require('http');
const { spawn, spawnSync } = require('child_process');
const fs = require('fs');
const os = require('os');

const PORT = 8809;
const GPHOTO = '/opt/homebrew/bin/gphoto2';
const BOUNDARY = Buffer.from([0xff, 0xd9, 0xff, 0xd8]); // JPEG end + next JPEG start

let proc = null, buf = Buffer.alloc(0), lastErr = '', battery = null;
let frames = 0, fps = 0, lastCount = 0, last = null, served = 0;
const clients = new Set();

// Picture adjustments in percent (mirror: 0 or 1), applied as CSS filters by the preview page and the /view page (virtual camera).
// Kept in ~/.eos-webcam.json so they survive restarts.
const ADJUST_FILE = os.homedir() + '/.eos-webcam.json';
const RANGE = { brightness: [50, 150], contrast: [50, 150], saturation: [0, 200], mirror: [0, 1] };
const adjust = { brightness: 100, contrast: 100, saturation: 100, mirror: 0 };
function setAdjust(get) {
  for (const k in RANGE) {
    const v = get(k);
    if (v === null || v === undefined || v === '' || !Number.isFinite(Number(v))) continue;
    adjust[k] = Math.min(RANGE[k][1], Math.max(RANGE[k][0], Math.round(Number(v))));
  }
}
try { const saved = JSON.parse(fs.readFileSync(ADJUST_FILE, 'utf8')); setAdjust((k) => saved[k]); } catch (e) {}

setInterval(() => { fps = frames - lastCount; lastCount = frames; }, 1000);

function onFrame(jpg) {
  frames++; last = jpg;
  for (const res of clients) {
    res.write(`--eosframe7d1c9a42\r\nContent-Type: image/jpeg\r\nContent-Length: ${jpg.length}\r\n\r\n`);
    res.write(jpg);
    res.write('\r\n');
  }
}

function start() {
  if (proc) return;
  lastErr = ''; buf = Buffer.alloc(0);
  spawnSync('pkill', ['-9', 'ptpcamerad']); // macOS grabs the camera first; release it
  // Battery level can only be read while the stream is not running, so read it once here.
  const b = spawnSync(GPHOTO, ['--get-config', 'batterylevel'], { encoding: 'utf8', timeout: 6000 });
  const m = /Current:\s*(.+)/.exec(b.stdout || '');
  battery = m ? m[1].trim() : null;
  spawnSync('pkill', ['-9', 'ptpcamerad']);
  const p = spawn(GPHOTO, ['--capture-movie', '--stdout']);
  proc = p;
  p.stdout.on('data', (d) => {
    buf = Buffer.concat([buf, d]);
    let i;
    while ((i = buf.indexOf(BOUNDARY)) !== -1) {
      onFrame(buf.subarray(0, i + 2));
      buf = buf.subarray(i + 2);
    }
  });
  p.stderr.on('data', (d) => { lastErr = d.toString().trim().split('\n').pop(); });
  p.on('error', (e) => { lastErr = e.message; if (proc === p) proc = null; });
  p.on('exit', (code) => { if (!code) lastErr = ''; if (proc === p) proc = null; });
}

function stop() { if (proc) proc.kill('SIGINT'); }

const PAGE = `<!doctype html><html lang="en" data-theme="light"><head><meta charset="utf-8">
<title>EOS Webcam</title><meta name="viewport" content="width=device-width,initial-scale=1">
<style>
:root{--bg:#f6f7f9;--fg:#1c1e21;--card:#fff;--line:#d9dce1;--acc:#0a66c2}
[data-theme=dark]{--bg:#16181c;--fg:#e8eaed;--card:#22252b;--line:#3a3f47;--acc:#5aa9f5}
body{margin:0;font:15px/1.4 -apple-system,system-ui,sans-serif;background:var(--bg);color:var(--fg)}
main{max-width:1000px;margin:0 auto;padding:16px}
header{display:flex;align-items:center;gap:8px;margin-bottom:12px}
h1{font-size:18px;margin:0;flex:1}
button{font:inherit;padding:6px 14px;border:1px solid var(--line);border-radius:6px;background:var(--card);color:var(--fg);cursor:pointer}
button.p{background:var(--acc);border-color:var(--acc);color:#fff}
#box{position:relative;aspect-ratio:3/2;background:#000;border-radius:8px;overflow:hidden;display:flex;align-items:center;justify-content:center;color:#9aa3ad}
#v{position:absolute;inset:0;width:100%;height:100%;object-fit:contain;display:none}
#adj{display:flex;flex-wrap:wrap;gap:8px 20px;align-items:center;margin:10px 0}
#adj label{display:flex;align-items:center;gap:8px}
#s{margin:10px 0;padding:8px 12px;background:var(--card);border:1px solid var(--line);border-radius:6px}
footer{opacity:.6;font-size:13px}
</style></head><body><main>
<header><h1>EOS Webcam</h1>
<button class="p" id="on">Start</button><button id="off">Stop</button>
<button id="fs">Fullscreen</button><button id="th">Dark</button></header>
<div id="box"><span>Camera is not live</span><img id="v" alt=""></div>
<div id="adj">
<label>Brightness <input type="range" id="brightness" min="50" max="150"></label>
<label>Contrast <input type="range" id="contrast" min="50" max="150"></label>
<label>Saturation <input type="range" id="saturation" min="0" max="200"></label>
<label><input type="checkbox" id="mirror"> Mirror</label>
<button id="reset">Reset</button></div>
<div id="s">Loading...</div>
<footer>4xs.dev - Pavel Kotyza</footer>
</main><script>
const $=(i)=>document.getElementById(i),root=document.documentElement;
function theme(t){root.dataset.theme=t;$('th').textContent=t==='dark'?'Light':'Dark';try{localStorage.theme=t}catch(e){}}
try{if(localStorage.theme)theme(localStorage.theme)}catch(e){}
$('th').onclick=()=>theme(root.dataset.theme==='dark'?'light':'dark');
$('fs').onclick=()=>$('box').requestFullscreen();
const post=(p)=>fetch(p,{method:'POST'}).then(poll);
$('on').onclick=()=>post('/api/start');
$('off').onclick=()=>post('/api/stop');
const keys=['brightness','contrast','saturation'];
function filter(a){$('v').style.filter='brightness('+a.brightness+'%) contrast('+a.contrast+'%) saturate('+a.saturation+'%)';
  $('v').style.transform=$('mirror').checked?'scaleX(-1)':''}
$('mirror').onchange=()=>{filter({brightness:$('brightness').value,contrast:$('contrast').value,saturation:$('saturation').value});
  fetch('/api/adjust?mirror='+($('mirror').checked?1:0),{method:'POST'})};
let dragging=null; // the slider being dragged on this page; it is not overwritten by poll()
keys.forEach((k)=>{$(k).onchange=()=>{dragging=null};$(k).oninput=()=>{dragging=k;const a={};keys.forEach((j)=>a[j]=$(j).value);filter(a);fetch('/api/adjust?'+k+'='+$(k).value,{method:'POST'})}});
$('reset').onclick=()=>fetch('/api/adjust?brightness=100&contrast=100&saturation=100',{method:'POST'}).then(poll);
let was=false;
async function poll(){
  try{
    const s=await (await fetch('/api/status')).json();
    was=s.running;
    // Follow changes made in the menu bar, except the slider being dragged here.
    keys.forEach((k)=>{if(k!==dragging)$(k).value=s.adjust[k]});
    $('mirror').checked=s.adjust.mirror===1;
    if(!dragging)filter(s.adjust);
    $('s').textContent=s.running?'Streaming - '+s.fps+' fps':'Stopped'+(s.error?' - '+s.error:'');
  }catch(e){was=false;$('s').textContent='Script is not running. Use Start camera in the menu bar or start.command.'}
}
setInterval(poll,1000);poll();
function draw(){
  const v=$('v');
  if(!was){v.style.display='none';return setTimeout(draw,500)}
  v.onload=()=>{v.style.display='block';setTimeout(draw,30)};
  v.onerror=()=>{v.style.display='none';setTimeout(draw,500)};
  v.src='/frame?'+Date.now();
}
draw();
</script></body></html>`;

// Bare full-frame view, used as the web page source in Isocast.
const VIEW = `<!doctype html><html><head><meta charset="utf-8"><style>
html,body{margin:0;height:100%;background:transparent;overflow:hidden}
img{width:100vw;height:100vh;object-fit:cover;display:none}
</style></head><body><img id="v"><script>
const v=document.getElementById('v');
function next(){v.src='/frame?'+Date.now()}
v.onload=()=>{v.style.display='block';setTimeout(next,30)};
v.onerror=()=>{v.style.display='none';setTimeout(next,1000)};
next();
function adjust(){fetch('/api/status').then((r)=>r.json()).then((s)=>{const a=s.adjust;
  v.style.filter='brightness('+a.brightness+'%) contrast('+a.contrast+'%) saturate('+a.saturation+'%)';
  v.style.transform=a.mirror===1?'scaleX(-1)':''}).catch(()=>{})}
setInterval(adjust,300);adjust();
</script></body></html>`;

http.createServer((req, res) => {
  const path = req.url.split('?')[0];
  if (path === '/') {
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(PAGE);
  } else if (path === '/view') {
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(VIEW);
  } else if (path === '/stream') {
    res.writeHead(200, { 'Content-Type': 'multipart/x-mixed-replace; boundary=eosframe7d1c9a42', 'Cache-Control': 'no-store' });
    clients.add(res);
    req.on('close', () => clients.delete(res));
  } else if (path === '/frame') {
    if (!last || !proc) { res.writeHead(503); return res.end(); }
    res.writeHead(200, { 'Content-Type': 'image/jpeg', 'Cache-Control': 'no-store' });
    res.end(last); served++;
  } else if (path === '/api/status') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ running: !!proc, fps, frames, served, battery, error: lastErr, adjust }));
  } else if (req.method === 'POST' && path === '/api/adjust') {
    const q = new URL(req.url, 'http://x').searchParams;
    setAdjust((k) => q.get(k));
    fs.writeFile(ADJUST_FILE, JSON.stringify(adjust), () => {});
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(adjust));
  } else if (req.method === 'POST' && (path === '/api/start' || path === '/api/stop')) {
    (path === '/api/start' ? start : stop)();
    res.writeHead(204); res.end();
  } else {
    res.writeHead(404); res.end();
  }
}).listen(PORT, '127.0.0.1', () => {
  console.log(`EOS Webcam: http://127.0.0.1:${PORT}`);
  start();
});

process.on('SIGINT', () => { stop(); setTimeout(() => process.exit(0), 500); });
