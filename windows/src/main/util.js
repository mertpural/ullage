'use strict';
const fs = require('fs');
const path = require('path');
const https = require('https');
const { execFile } = require('child_process');

/** Klasörü dolaşıp koşula uyan dosyaları { file, mtimeMs, size } olarak döndürür. */
function walk(root, match) {
  const out = [];
  const stack = [root];
  while (stack.length) {
    const dir = stack.pop();
    let entries;
    try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { continue; }
    for (const e of entries) {
      const p = path.join(dir, e.name);
      if (e.isDirectory()) stack.push(p);
      else if (match(e.name)) {
        try { const st = fs.statSync(p); out.push({ file: p, mtimeMs: st.mtimeMs, size: st.size }); } catch { /* yoksay */ }
      }
    }
  }
  return out;
}

function run(cmd, args, opts = {}) {
  return new Promise((resolve) => {
    execFile(cmd, args, { timeout: 8000, maxBuffer: 20 * 1024 * 1024, windowsHide: true, ...opts }, (err, stdout) => resolve(err ? '' : String(stdout)));
  });
}

/** JSON döndüren basit HTTPS isteği. */
function request({ host, port, path: p, method = 'GET', headers = {}, body, insecure = false, timeout = 15000 }) {
  return new Promise((resolve) => {
    const req = https.request({
      host, port, path: p, method, headers, timeout,
      agent: insecure ? new https.Agent({ rejectUnauthorized: false }) : undefined,
    }, (res) => {
      const chunks = [];
      res.on('data', (c) => chunks.push(c));
      res.on('end', () => {
        const text = Buffer.concat(chunks).toString('utf8');
        let json = null; try { json = JSON.parse(text); } catch { /* json değil */ }
        resolve({ status: res.statusCode, headers: res.headers, text, json });
      });
    });
    req.on('timeout', () => { req.destroy(); resolve(null); });
    req.on('error', () => resolve(null));
    if (body) req.write(body);
    req.end();
  });
}

const isoMs = (s) => { const t = Date.parse(s); return Number.isNaN(t) ? null : t; };

module.exports = { walk, run, request, isoMs };
