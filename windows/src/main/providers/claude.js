'use strict';
// Claude: token geçmişi ~/.claude/projects kayıtlarından, 5 saatlik ve haftalık limit Anthropic'in
// (resmi olmayan) kullanım uç noktasından, Claude Code'un kendi oturumuyla okunur.
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync, execFile } = require('child_process');
const { walk, request, isoMs } = require('../util');

const MIN_INTERVAL = 60 * 1000;      // iki gerçek sorgu arası en az 1 dakika (kapat-aç yapsan da korunur)
const BACKOFF_MIN = 5 * 60 * 1000;   // hız sınırına (429) çarpınca en az 5 dakika bekle
let memo = null;                      // { at, result }

/** Oturum anahtarı süresi dolduğunda Claude Code'un kendisine yeniletir: tek satırlık bir Haiku isteği çalıştırır, Claude Code
 *  anahtarı kendi yenileyip yazar. Anahtarlara bu uygulama dokunmaz. En sık 30 dakikada bir denenir. */
function refreshLoginViaCLI(store, enabled) {
  if (enabled === false) return Promise.resolve(false);
  const now = Date.now();
  if (now - (store.kv('claudeLoginRefreshAt') || 0) < 30 * 60 * 1000) return Promise.resolve(false);
  store.kv('claudeLoginRefreshAt', now);
  return new Promise((resolve) => {
    execFile('claude', ['-p', '--model', 'haiku', '--no-session-persistence', '--tools', '', '--', 'Reply with only: ok'],
      { timeout: 90000, windowsHide: true, shell: process.platform === 'win32', cwd: os.tmpdir() }, (err) => resolve(!err));
  });
}

function ingest(store) {
  const root = path.join(os.homedir(), '.claude', 'projects');
  for (const f of walk(root, (n) => n.endsWith('.jsonl'))) {
    const start = store.offset(f.file);
    if (f.size <= start) continue;
    let buf;
    try {
      const fd = fs.openSync(f.file, 'r');
      buf = Buffer.alloc(f.size - start);
      fs.readSync(fd, buf, 0, buf.length, start);
      fs.closeSync(fd);
    } catch { continue; }
    const lastNL = buf.lastIndexOf(0x0a);
    if (lastNL < 0) continue; // yarım yazılmış satırı sonraki tura bırak
    for (const line of buf.subarray(0, lastNL + 1).toString('utf8').split('\n')) {
      if (!line.includes('"usage"')) continue;
      let o; try { o = JSON.parse(line); } catch { continue; }
      const m = o.message;
      if (o.type !== 'assistant' || !m || !m.usage || !m.id) continue;
      const ts = isoMs(o.timestamp);
      if (ts == null) continue;
      const u = m.usage;
      store.upsert('claude', `${m.id}|${o.requestId || ''}`, ts, m.model || '',
        u.input_tokens || 0, u.output_tokens || 0, u.cache_creation_input_tokens || 0, u.cache_read_input_tokens || 0);
    }
    store.setOffset(f.file, start + lastNL + 1);
  }
}

/** Claude Code oturumu: Windows/Linux'ta ~/.claude/.credentials.json, macOS'ta Keychain. */
function loadToken() {
  try {
    const j = JSON.parse(fs.readFileSync(path.join(os.homedir(), '.claude', '.credentials.json'), 'utf8'));
    const o = j.claudeAiOauth;
    if (o && o.accessToken) return { token: o.accessToken, expires: o.expiresAt || null };
  } catch { /* dosya yok */ }
  if (process.platform === 'darwin') {
    try {
      const out = execFileSync('/usr/bin/security', ['find-generic-password', '-s', 'Claude Code-credentials', '-w'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
      const o = JSON.parse(out).claudeAiOauth;
      if (o && o.accessToken) return { token: o.accessToken, expires: o.expiresAt || null };
    } catch { /* izin verilmedi ya da yok */ }
  }
  return null;
}

async function fetchLimits(store, opts = {}) {
  const now = Date.now();
  if (memo && now - memo.at < MIN_INTERVAL) return memo.result;
  const stored = store.kv('claudeLast');
  const withStored = (err) => (stored ? { ok: true, ...stored } : { ok: false, error: err });

  if (now < (store.kv('claudeBackoffUntil') || 0)) return withStored('Anthropic hız sınırı uyguladı; biraz sonra yeniden denenecek');
  if (now - (store.kv('claudeLastAttempt') || 0) < MIN_INTERVAL && stored) return { ok: true, ...stored };
  store.kv('claudeLastAttempt', now);

  let tok = loadToken();
  if (tok && tok.expires && tok.expires < now + 120000 && await refreshLoginViaCLI(store, opts.refreshLogin)) tok = loadToken() || tok;
  if (!tok) { const r = withStored('Claude Code oturumu bulunamadı (önce Claude Code ile giriş yap)'); memo = { at: now, result: r }; return r; }
  const res = await request({
    host: 'api.anthropic.com', path: '/api/oauth/usage',
    headers: { Authorization: `Bearer ${tok.token}`, 'anthropic-beta': 'oauth-2025-04-20', Accept: 'application/json' },
  });
  let result;
  if (!res) result = withStored('Ağ hatası');
  else if (res.status === 429) {
    const ra = Number(res.headers['retry-after']);
    store.kv('claudeBackoffUntil', now + Math.max(BACKOFF_MIN, Number.isFinite(ra) ? ra * 1000 : 0));
    result = withStored('Anthropic hız sınırı uyguladı (429)');
  } else if (res.status === 401) { await refreshLoginViaCLI(store, opts.refreshLogin); result = withStored('Oturum süresi dolmuş; Claude Code\'u açınca yenilenir'); }
  else if (res.status !== 200 || !res.json) result = withStored(`Uç nokta ${res.status} döndürdü`);
  else {
    const w = (k) => {
      const v = res.json[k];
      if (!v || typeof v.utilization !== 'number') return null;
      return { left: Math.max(0, Math.min(1, 1 - v.utilization / 100)), reset: v.resets_at ? isoMs(v.resets_at) : null };
    };
    const five = w('five_hour'), week = w('seven_day');
    if (!five && !week) result = withStored('Yanıtta limit alanı yok');
    else {
      const rec = { at: now, five: five && five.left, week: week && week.left, fiveReset: five && five.reset, weekReset: week && week.reset };
      store.kv('claudeLast', rec);
      result = { ok: true, ...rec };
    }
  }
  memo = { at: now, result };
  return result;
}

/** Elle yenilemede önbelleği atlar; gerçek sorgu en sık 30 saniyede bir yapılır. */
function invalidate(store) {
  if (Date.now() - (store.kv('claudeLastAttempt') || 0) > 30 * 1000) { memo = null; store.kv('claudeLastAttempt', 0); }
}

async function read(store, opts = {}) {
  ingest(store);
  const now = Date.now();
  const sod = new Date(); sod.setHours(0, 0, 0, 0);
  const u = { limitConfidence: 'none', tokenConfidence: 'exact', todayTokens: store.billableSince('claude', sod.getTime()), extra: [], notes: [
    'Token: ~/.claude kayıtlarından (Claude Code ve Desktop), cache okumaları hariç.',
  ] };
  const r = await fetchLimits(store, opts);
  if (r.ok) {
    // Sıfırlanma saati geçmiş pencere yenilenmiştir: eski değer yerine %100.
    u.fiveHourLeft = r.five == null ? null : (r.fiveReset && r.fiveReset <= now ? 1 : r.five);
    u.weeklyLeft = r.week == null ? null : (r.weekReset && r.weekReset <= now ? 1 : r.week);
    u.fiveHourReset = r.fiveReset; u.weeklyReset = r.weekReset;
    if (now - r.at < 10 * 60 * 1000) {
      u.limitConfidence = 'exact';
      u.notes.push('Limit: Anthropic kullanım uç noktasından (resmi olmayan, Claude Code oturumuyla).');
    } else {
      u.limitConfidence = 'estimate';
      u.staleSince = r.at;
      u.notes.push('Anthropic hız sınırı uyguladığı için son alınan değer gösteriliyor; güncel olmayabilir.');
    }
  } else {
    u.notes.push(`Limit yüzdesi alınamadı: ${r.error}`);
  }
  return u;
}

module.exports = { read, invalidate, ingest };
