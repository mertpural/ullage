'use strict';
// Antigravity: token kayıtları yerel konuşma veritabanlarından (SQLite, protobuf blobları),
// limit ise IDE açıkken çalışan yerel dil sunucusundan okunur.
const fs = require('fs');
const os = require('os');
const path = require('path');
const { walk, run, request } = require('../util');

// ---- şemasız asgari protobuf okuyucu (yalnızca varint ve uzunluk-önekli alanlar)
function pbFields(buf) {
  const out = [];
  let i = 0;
  const varint = () => {
    let r = 0, mul = 1, n = 0;
    while (i < buf.length) {
      const b = buf[i++];
      r += (b & 0x7f) * mul; mul *= 128; n++;
      if (b < 0x80) return r;
      if (n > 9) return null;
    }
    return null;
  };
  while (i < buf.length) {
    const key = varint(); if (key == null) break;
    const field = Math.floor(key / 8), wire = key % 8;
    if (wire === 0) { const v = varint(); if (v == null) return out; out.push([field, 'v', v]); }
    else if (wire === 2) { const l = varint(); if (l == null || i + l > buf.length) return out; out.push([field, 'b', buf.subarray(i, i + l)]); i += l; }
    else if (wire === 1) i += 8;
    else if (wire === 5) i += 4;
    else return out;
  }
  return out;
}
const pbBytes = (f, n) => { const x = f.find((e) => e[0] === n && e[1] === 'b'); return x ? x[2] : null; };
const pbVar = (f, n) => { const x = f.find((e) => e[0] === n && e[1] === 'v'); return x ? x[2] : null; };

let SQL = null;
async function sqlJs() {
  if (!SQL) {
    const init = require('sql.js');
    const dist = path.dirname(require.resolve('sql.js'));
    SQL = await init({ locateFile: (f) => path.join(dist, f).replace('app.asar', 'app.asar.unpacked') });
  }
  return SQL;
}

const convDir = () => path.join(os.homedir(), '.gemini', 'antigravity-ide', 'conversations');

async function ingest(store) {
  for (const f of walk(convDir(), (n) => n.endsWith('.db'))) {
    if (store.mtime(f.file) === f.mtimeMs) continue;
    let db;
    try {
      const S = await sqlJs();
      db = new S.Database(fs.readFileSync(f.file));
      const res = db.exec('SELECT idx, data FROM gen_metadata');
      const name = path.basename(f.file);
      for (const row of (res[0] ? res[0].values : [])) {
        const [idx, blob] = row;
        const m1 = pbBytes(pbFields(Buffer.from(blob)), 1); if (!m1) continue;
        const m = pbFields(m1);
        const usage = pbBytes(m, 4), timing = pbBytes(m, 9); if (!usage || !timing) continue;
        const t = pbBytes(pbFields(timing), 4); if (!t) continue;
        const secs = pbVar(pbFields(t), 1); if (secs == null) continue;
        const u = pbFields(usage);
        const modelB = pbBytes(m, 19);
        store.upsert('antigravity', `${name}|${idx}`, secs * 1000, modelB ? Buffer.from(modelB).toString('utf8') : '',
          pbVar(u, 1) || 0, pbVar(u, 3) || 0, pbVar(u, 2) || 0, pbVar(u, 5) || 0);
      }
      store.setMtime(f.file, f.mtimeMs);
    } catch { /* bozuk ya da kilitli veritabanı: sonraki turda tekrar denenir */ } finally { if (db) db.close(); }
  }
}

// ---- yerel dil sunucusu (limit)
async function findServers() {
  const servers = [];
  const flag = (cmd, name) => { const m = cmd.match(new RegExp(`--${name}[ =]([^ ]+)`)); return m ? m[1] : null; };
  if (process.platform === 'win32') {
    const out = await run('powershell', ['-NoProfile', '-Command',
      "Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'language_server' -and $_.CommandLine -match 'antigravity' } | ForEach-Object { \"$($_.ProcessId)`t$($_.CommandLine)\" }"]);
    for (const line of out.split(/\r?\n/)) {
      const [pid, cmd] = line.split('\t'); if (!pid || !cmd) continue;
      const csrf = flag(cmd, 'csrf_token'); if (csrf) servers.push({ pid: Number(pid), csrf });
    }
  } else {
    const out = await run('/bin/ps', ['-ax', '-o', 'pid=,command=']);
    for (const line of out.split('\n')) {
      if (!line.includes('language_server') || !line.includes('antigravity')) continue;
      const pid = Number(line.trim().split(/\s+/)[0]); const csrf = flag(line, 'csrf_token');
      if (pid && csrf) servers.push({ pid, csrf });
    }
  }
  return servers;
}

async function portsOf(pid) {
  const ports = [];
  if (process.platform === 'win32') {
    const out = await run('netstat', ['-ano', '-p', 'TCP']);
    for (const line of out.split(/\r?\n/)) {
      const c = line.trim().split(/\s+/);
      if (c[3] === 'LISTENING' && Number(c[4]) === pid) { const m = c[1].match(/:(\d+)$/); if (m) ports.push(Number(m[1])); }
    }
  } else {
    const out = await run('/usr/sbin/lsof', ['-nP', '-iTCP', '-sTCP:LISTEN', '-a', '-p', String(pid)]);
    for (const line of out.split('\n')) { const m = line.match(/:(\d+) \(LISTEN\)/); if (m) ports.push(Number(m[1])); }
  }
  return ports;
}

function parseQuota(root) {
  const resp = root.response || root;
  const rows = [];
  for (const g of (resp.groups || [])) {
    const gname = String(g.displayName || 'Grup').replace(' Models', '').replace(' models', '').replace('Claude and GPT', 'Claude + GPT');
    for (const b of (g.buckets || [])) {
      const frac = (b.remaining && b.remaining.remainingFraction) ?? b.remainingFraction;
      if (typeof frac !== 'number') continue;
      const key = `${b.window || ''} ${b.bucketId || ''} ${b.displayName || ''}`.toLowerCase();
      const win = key.includes('week') ? 'Haftalık' : (/five|5|hour/.test(key) ? '5 saatlik' : (b.displayName || ''));
      rows.push({ title: `${gname} · ${win}`, left: Math.max(0, Math.min(1, frac)), reset: b.resetTime ? Date.parse(b.resetTime) : null });
    }
  }
  return rows;
}

async function fetchQuota() {
  const servers = await findServers();
  if (!servers.length) return { ok: false, error: 'Antigravity IDE çalışmıyor; açınca okunur' };
  const meta = JSON.stringify({ metadata: { ideName: 'antigravity', extensionName: 'antigravity', locale: 'en' } });
  const call = (port, method, csrf) => request({
    host: '127.0.0.1', port, path: `/exa.language_server_pb.LanguageServerService/${method}`, method: 'POST', insecure: true, timeout: 4000, body: meta,
    headers: { 'Content-Type': 'application/json', 'X-Codeium-Csrf-Token': csrf, 'Connect-Protocol-Version': '1' },
  });
  for (const s of servers) {
    for (const port of await portsOf(s.pid)) {
      const probe = await call(port, 'GetUnleashData', s.csrf);
      if (!probe || probe.status !== 200) continue;
      for (const method of ['RetrieveUserQuotaSummary']) {
        const r = await call(port, method, s.csrf);
        if (r && r.status === 200 && r.json) { const rows = parseQuota(r.json); if (rows.length) return { ok: true, rows }; }
      }
    }
  }
  return { ok: false, error: 'Yerel sunucudan kota okunamadı' };
}

async function read(store) {
  await ingest(store);
  const sod = new Date(); sod.setHours(0, 0, 0, 0);
  const total = store.billableSince('antigravity', 0);
  const u = { limitConfidence: 'none', tokenConfidence: 'none', extra: [], notes: [] };
  if (total > 0) {
    u.todayTokens = store.billableSince('antigravity', sod.getTime());
    u.tokenConfidence = 'estimate';
    u.notes.push('Token alanları (girdi, cache yazma, çıktı, cache okuma) kayıt yapısından çıkarıldı; Antigravity resmi bir şema yayınlamıyor, bu yüzden tahminidir.');
  } else u.notes.push('Yerel konuşma kayıtlarında token bulunamadı.');
  const q = await fetchQuota();
  if (q.ok) { u.extra = q.rows; u.limitConfidence = 'exact'; u.notes.push("Limit: Antigravity'nin yerel dil sunucusundan (IDE açıkken)."); }
  else u.notes.push(`Limit alınamadı: ${q.error}`);
  return u;
}

module.exports = { read, ingest, pbFields, parseQuota };
