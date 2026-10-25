'use strict';
// Claude limitini Claude Code'un kendi komutundan ölçer: `claude -p` çalışırken akışa bir rate_limit_event satırı yazar,
// içindeki unifiedWindows alanı 5 saatlik ve haftalık KULLANILAN oranı verir (utilization 0-1, resetsAt epoch saniye).
// Not: bu alan yalnızca yeni Claude Code sürümlerinde var (2.1.218'de yok, denendi); yoksa sonuç boş döner.
const os = require('os');
const { spawn } = require('child_process');
const { isoMs } = require('./util');

// Windows'ta claude çoğunlukla bir .cmd dosyasıdır; bu yüzden komut bir kabuk üzerinden, boş "--tools" değeri tırnaklı çalıştırılır.
const COMMAND = 'claude -p "." --model haiku --output-format stream-json --verbose --no-session-persistence --tools "" --strict-mcp-config --disable-slash-commands';

const toMs = (r) => (typeof r === 'number' ? (r > 1e11 ? r : r * 1000) : typeof r === 'string' ? isoMs(r) : null);

/** rate_limit_info nesnesinden limitleri çıkarır (kalan = 1 - utilization); alan yoksa null. */
function limitsFromInfo(info) {
  const uw = (info && info.unifiedWindows) || {};
  const win = (k) => {
    const w = uw[k];
    if (!w || typeof w.utilization !== 'number') return null;
    return { left: Math.max(0, Math.min(1, 1 - w.utilization)), reset: toMs(w.resetsAt) };
  };
  let five = win('five_hour'), week = win('seven_day');
  // Üst düzey alan tek pencereyi (rateLimitType) anlatır; yalnızca utilization da veriyorsa kullanılır.
  if (info && typeof info.utilization === 'number') {
    const one = { left: Math.max(0, Math.min(1, 1 - info.utilization)), reset: toMs(info.resetsAt) };
    if (!five && info.rateLimitType === 'five_hour') five = one;
    if (!week && info.rateLimitType === 'seven_day') week = one;
  }
  if (!five && !week) return null;
  return { five: five && five.left, week: week && week.left, fiveReset: five && five.reset, weekReset: week && week.reset, src: 'probe' };
}

/** Akış çıktısını satır satır okur (CRLF olabilir). seen: rate_limit_event vardı mı, limits: içinde yüzde vardı mı (son geçerli olan). */
function parseOutput(text) {
  let seen = false, limits = null;
  for (const raw of String(text).split(/\r?\n/)) {
    const line = raw.trim();
    if (!line.startsWith('{') || !line.includes('rate_limit_event')) continue;
    let o; try { o = JSON.parse(line); } catch { continue; }
    if (!o || o.type !== 'rate_limit_event' || !o.rate_limit_info) continue;
    seen = true;
    const l = limitsFromInfo(o.rate_limit_info);
    if (l) limits = l;
  }
  return { seen, limits };
}

/** Komutu çalıştırır (cwd: geçici klasör, stdin kapalı, pencere yok) ve çıktıyı ayrıştırır. Hata ya da zaman aşımında { seen: false, limits: null }. */
function measure({ timeoutMs = 60000 } = {}) {
  return new Promise((resolve) => {
    let out = '', done = false;
    const finish = (r) => { if (!done) { done = true; clearTimeout(timer); resolve(r); } };
    let child;
    try { child = spawn(COMMAND, { shell: true, cwd: os.tmpdir(), stdio: ['ignore', 'pipe', 'ignore'], windowsHide: true }); } catch { return resolve({ seen: false, limits: null }); }
    const timer = setTimeout(() => { try { child.kill(); } catch { /* yoksay */ } finish({ seen: false, limits: null }); }, timeoutMs);
    child.stdout.setEncoding('utf8');
    child.stdout.on('data', (d) => { out += d; if (out.length > 20 * 1024 * 1024) out = out.slice(-5 * 1024 * 1024); });
    child.on('error', () => finish({ seen: false, limits: null }));
    child.on('close', () => finish(parseOutput(out)));
  });
}

module.exports = { measure, parseOutput, limitsFromInfo, COMMAND };
