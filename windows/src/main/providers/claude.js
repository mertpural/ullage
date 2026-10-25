'use strict';
// Claude: token geçmişi ~/.claude/projects kayıtlarından, 5 saatlik ve haftalık limit Anthropic'in
// (resmi olmayan) kullanım uç noktasından, Claude Code'un kendi oturumuyla okunur.
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync, execFile } = require('child_process');
const { walk, request, isoMs } = require('../util');
const statusline = require('../statusline');
const cliprobe = require('../cliprobe');

const STATUS_FRESH = 15 * 60 * 1000; // durum satırı dosyası bundan yeniyse ağa hiç gidilmez
const BACKOFF_MIN = 5 * 60 * 1000;   // hız sınırına (429) çarpınca en az 5 dakika bekle
let memo = null;                      // { at, result }

/** Anthropic'e iki sorgu arasındaki en kısa süre (kapat-aç yapsan da korunur, son deneme zamanı saklanır).
 *  Yeni yerel Claude kullanımı varsa 1 dakika, yoksa 10 dakika: limit yalnızca kullanınca değişir. */
function minInterval(store) {
  const last = store.kv('claudeLastAttempt') || 0;
  return store.latestEvent('claude') > last - 5000 ? 60 * 1000 : 10 * 60 * 1000;
}

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

/** ~/.claude/.credentials.json'u okur; dosya yoksa ya da bozuksa undefined. */
function readCredentials() {
  try { return JSON.parse(fs.readFileSync(path.join(os.homedir(), '.claude', '.credentials.json'), 'utf8')); } catch { return undefined; }
}

/** Girişin durumu, arayüzün doğru yönergeyi göstermesi için: 'ok' | 'expired' | 'signed-out' | 'no-file'.
 *  Dosya var ama claudeAiOauth yoksa (yalnızca MCP girişi) Claude Code'a hiç giriş yapılmamış demektir. */
function loginState(creds, now = Date.now()) {
  if (creds === undefined) return 'no-file';
  const o = creds && creds.claudeAiOauth;
  if (!o || !o.accessToken) return 'signed-out';
  if (o.expiresAt && o.expiresAt < now) return 'expired';
  return 'ok';
}

/** Claude Code oturumu: Windows/Linux'ta ~/.claude/.credentials.json, macOS'ta Keychain. */
function loadToken() {
  const o = (readCredentials() || {}).claudeAiOauth;
  if (o && o.accessToken) return { token: o.accessToken, expires: o.expiresAt || null };
  if (process.platform === 'darwin') {
    try {
      const out = execFileSync('/usr/bin/security', ['find-generic-password', '-s', 'Claude Code-credentials', '-w'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
      const o = JSON.parse(out).claudeAiOauth;
      if (o && o.accessToken) return { token: o.accessToken, expires: o.expiresAt || null };
    } catch { /* izin verilmedi ya da yok */ }
  }
  return null;
}

/** Sıra: (varsa) durum satırı dosyası, sonra Anthropic kullanım uç noktası, o da işe yaramazsa Claude Code komutuyla ölçüm. */
async function fetchLimits(store, opts = {}) {
  const now = Date.now();
  // Claude Code'un durum satırından yazılan yerel dosya tazeyse ağa hiç gidilmez.
  const local = opts.statusDir ? statusline.read(opts.statusDir) : null;
  if (local && now - local.at < STATUS_FRESH) {
    const prev = store.kv('claudeLast');
    if (!prev || prev.at !== local.at || prev.src !== 'statusline') store.kv('claudeLast', local); // son iyi değer kalıcı saklanır
    return { ok: true, ...local };
  }
  let result = await fetchViaApi(store, opts, now);
  if (opts.cliProbe !== false) {
    const probed = await maybeProbe(store, result, now);
    if (probed) { result = probed; memo = { at: now, result }; }
  }
  return result;
}

const PROBE_GAP = 5 * 60 * 1000;      // iki ölçüm arası en az 5 dakika (kalıcı, yeniden başlatmada da korunur)
// Değer bundan eskiyse ölçüm aday olur: Anthropic sorgusu ya da komuttan gelen değer için 90 sn, durum satırı dosyasından gelen için 15 dk.
// Sıklığı yalnızca PROBE_GAP belirler; aday eşiği 10 dakika olsaydı aktif kullanımda değer fiilen 10 dakika eski kalırdı.
const PROBE_STALE = 90 * 1000;
const PROBE_STALE_STATUSLINE = 15 * 60 * 1000;
const PROBE_BLOCK = 60 * 60 * 1000;   // komut limit yüzdesi vermiyorsa (eski Claude Code) bu süre bir daha denenmez
let probing = false;

/** Claude Code komutuyla (`claude -p`) ölçer: yalnızca sonuç yoksa, hız sınırı beklemesi varsa ya da son değer eskiyse VE
 *  son değerden / son ölçümden sonra yeni yerel Claude kullanımı olduysa. Yeni kullanım yoksa hiç çalıştırılmaz. */
async function maybeProbe(store, result, now) {
  if (probing || now < (store.kv('claudeProbeBlockedUntil') || 0)) return null;
  const lastProbe = store.kv('claudeLastProbe') || 0;
  if (now - lastProbe < PROBE_GAP) return null;
  const lastGood = result.ok ? result.at : 0;
  const waiting = now < (store.kv('claudeBackoffUntil') || 0);
  const staleAfter = result.src === 'statusline' ? PROBE_STALE_STATUSLINE : PROBE_STALE;
  if (!(!result.ok || waiting || now - lastGood > staleAfter)) return null;
  if (!(store.latestEvent('claude') > Math.max(lastGood, lastProbe))) return null;
  probing = true;
  try {
    store.kv('claudeLastProbe', now);
    const { limits, seen } = await cliprobe.measure();
    if (!limits) { if (seen) store.kv('claudeProbeBlockedUntil', now + PROBE_BLOCK); return null; }
    const rec = { at: Date.now(), ...limits };
    store.kv('claudeLast', rec);
    return { ok: true, ...rec };
  } finally { probing = false; }
}

async function fetchViaApi(store, opts, now) {
  if (memo && now - memo.at < minInterval(store)) return memo.result;
  const stored = store.kv('claudeLast');
  const withStored = (err) => (stored ? { ok: true, ...stored } : { ok: false, error: err });

  if (now < (store.kv('claudeBackoffUntil') || 0)) return withStored('Anthropic hız sınırı uyguladı; biraz sonra yeniden denenecek');
  if (now - (store.kv('claudeLastAttempt') || 0) < minInterval(store) && stored) return { ok: true, ...stored };
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

/** Elle yenilemede önbelleği atlar; ama gerçek sorgu yine en sık `minInterval` süresinde bir yapılır (Anthropic hız sınırı). */
function invalidate(store) {
  if (Date.now() - (store.kv('claudeLastAttempt') || 0) > minInterval(store)) { memo = null; store.kv('claudeLastAttempt', 0); }
}

/** macOS'ta giriş Keychain'de olabilir; diğer sistemlerde yalnızca dosyaya bakılır. */
function currentLoginState() {
  if (process.platform === 'darwin' && loadToken()) return 'ok';
  return loginState(readCredentials());
}

const LOGIN_NOTES = {
  'signed-out': 'Claude Code girişi yok. Terminalde `claude` çalıştır, /login yaz.',
  'no-file': 'Claude Code kurulu değil ya da hiç giriş yapılmamış (.credentials.json yok).',
  expired: 'Claude Code oturumunun süresi dolmuş; Claude Code\'u açınca yenilenir.',
};

async function read(store, opts = {}) {
  ingest(store);
  const now = Date.now();
  const sod = new Date(); sod.setHours(0, 0, 0, 0);
  const u = { limitConfidence: 'none', tokenConfidence: 'exact', todayTokens: store.billableSince('claude', sod.getTime()),
    cacheReadToday: store.cacheReadSince('claude', sod.getTime()), loginState: currentLoginState(), extra: [], notes: [
      'Token: ~/.claude kayıtlarından (Claude Code ve Desktop), cache okumaları hariç.',
    ] };
  const r = await fetchLimits(store, opts);
  if (r.ok) {
    // Sıfırlanma saati geçmiş pencere yenilenmiştir: eski değer yerine %100.
    u.fiveHourLeft = r.five == null ? null : (r.fiveReset && r.fiveReset <= now ? 1 : r.five);
    u.weeklyLeft = r.week == null ? null : (r.weekReset && r.weekReset <= now ? 1 : r.week);
    u.fiveHourReset = r.fiveReset; u.weeklyReset = r.weekReset;
    // Limit yalnızca Claude kullanılınca değişir: değerden sonra yerel kullanım yoksa eski sayılmaz.
    const usedSince = store.latestEvent('claude') > r.at + 90 * 1000;
    if (now - r.at < 10 * 60 * 1000 || !usedSince) {
      u.limitConfidence = 'exact';
      if (r.src === 'statusline' || r.src === 'probe') u.loginState = 'ok'; // değer Claude Code'dan geldi, OAuth dosyası gerekmedi
      u.notes.push(r.src === 'statusline' ? 'Limit: Claude Code\'un durum satırından (yerel, ağ gerekmez).'
        : r.src === 'probe' ? 'Limit: Claude Code komutundan ölçüldü (tek satırlık küçük bir istek).'
          : 'Limit: Anthropic kullanım uç noktasından (resmi olmayan, Claude Code oturumuyla).');
    } else {
      u.limitConfidence = 'estimate';
      u.staleSince = r.at;
      u.notes.push(r.src === 'statusline'
        ? 'Claude Code\'un durum satırından son alınan değer gösteriliyor; Claude Code çalışınca güncellenir.'
        : r.src === 'probe' ? 'Claude Code komutuyla son ölçülen değer gösteriliyor; yeni Claude kullanımı olunca yeniden ölçülür.'
          : 'Anthropic hız sınırı uyguladığı için son alınan değer gösteriliyor; güncel olmayabilir.');
    }
  } else {
    u.notes.push(LOGIN_NOTES[u.loginState] || `Limit yüzdesi alınamadı: ${r.error}`);
  }
  // Eski bir değer varsa limit gösterilse bile girişin durumunu not olarak ekle.
  if (r.ok && LOGIN_NOTES[u.loginState]) u.notes.push(LOGIN_NOTES[u.loginState]);
  return u;
}

module.exports = { read, invalidate, ingest, loginState, minInterval, maybeProbe };
