// Pure Node built-ins. Run after `dart compile js tool/database_web_smoke.dart ...`.
import { createServer } from 'node:http';
import { spawn } from 'node:child_process';
import { readFile, mkdtemp, rm } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { tmpdir } from 'node:os';
import { setTimeout as delay } from 'node:timers/promises';

const root = resolve(import.meta.dirname, '../build/web-smoke');
const chrome = process.env.CHROME_EXECUTABLE ?? (process.platform === 'darwin' ? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' : 'google-chrome');
const profile = await mkdtemp(join(tmpdir(), 'koi-database-chrome-'));
const server = createServer(async (request, response) => {
  const pathname = new URL(request.url, 'http://localhost').pathname;
  const file = pathname === '/' ? 'index.html' : pathname.slice(1);
  if (file.includes('..')) { response.writeHead(400).end(); return; }
  try {
    const bytes = await readFile(join(root, file));
    const type = file.endsWith('.wasm') ? 'application/wasm' : file.endsWith('.js') ? 'text/javascript' : file.endsWith('.html') ? 'text/html; charset=utf-8' : 'application/octet-stream';
    // Default exercises the SharedWorker + IndexedDB fallback; --isolated exercises OPFS.
    const headers = process.argv.includes('--isolated') ? { 'Cross-Origin-Opener-Policy': 'same-origin', 'Cross-Origin-Embedder-Policy': 'require-corp' } : {};
    response.writeHead(200, {'Content-Type': type, ...headers}).end(bytes);
  } catch { response.writeHead(404).end(); }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const url = `http://127.0.0.1:${server.address().port}`;
const browser = spawn(chrome, ['--headless', '--no-first-run', '--no-default-browser-check', '--remote-debugging-port=0', `--user-data-dir=${profile}`, 'about:blank'], {stdio: ['ignore', 'ignore', 'pipe']});
let browserErrors = '';
browser.stderr.on('data', bytes => { browserErrors = (browserErrors + bytes).slice(-8000); });
let socket;
try {
  let port;
  const deadline = Date.now() + 120000;
  while (!port && Date.now() < deadline) {
    try { port = Number((await readFile(join(profile, 'DevToolsActivePort'), 'utf8')).split('\n')[0]); } catch { await delay(100); }
  }
  if (!port) throw new Error(`Chrome did not start: ${browserErrors}`);
  const tab = await fetch(`http://127.0.0.1:${port}/json/new?${encodeURIComponent(url)}`, {method:'PUT'}).then(response => response.json());
  socket = new WebSocket(tab.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => { socket.addEventListener('open', resolve, {once:true}); socket.addEventListener('error', reject, {once:true}); });
  let sequence = 0;
  const pending = new Map();
  socket.addEventListener('message', event => {
    const message = JSON.parse(event.data);
    if (pending.has(message.id)) { const {resolve, reject} = pending.get(message.id); pending.delete(message.id); message.error ? reject(message.error) : resolve(message.result); }
  });
  const command = (method, params) => new Promise((resolve,reject) => { const id=++sequence;pending.set(id,{resolve,reject});socket.send(JSON.stringify({id,method,params})); });
  let report;
  while (!report && Date.now() < deadline) {
    const result = await command('Runtime.evaluate', {expression: "document.documentElement.getAttribute('data-test-result')", returnByValue:true});
    if (result.result.value) report = JSON.parse(result.result.value); else await delay(250);
  }
  if (!report) throw new Error('Database smoke timed out');
  console.log(JSON.stringify(report, null, 2));
  if (report.status !== 'passed') process.exitCode = 1;
} catch(error) { console.error(error); process.exitCode=1; }
finally {
  socket?.close();
  browser.kill('SIGTERM');
  await new Promise(resolve => { if(browser.exitCode !== null) resolve(); else browser.once('exit',resolve); });
  await new Promise(resolve => server.close(resolve));
  await rm(profile, {recursive:true,force:true});
}
