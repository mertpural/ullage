'use strict';
// Codex: limit ve token ~/.codex/sessions kayıtlarından. Kayıtlar .jsonl ya da sıkıştırılmış .jsonl.zst olabilir.
const fs = require('fs');
const os = require('os');
const path = require('path');
const fzstd = require('fzstd');
const { walk, isoMs } = require('../util');

/** Büyük dosyaların tamamını tek metne çevirmeden, tampondaki satırları sırayla verir. */
function forEachLine(buf, start, end, cb) {
  let i = start;
  while (i < end) {
    let j = buf.indexOf(0x0a, i);
    if (j < 0 || j >= end) j = end;
    if (j > i) cb(buf.toString('utf8', i, j));
    i = j + 1;
  }
}

const root = () => path.join(os.homedir(), '.codex', 'sessions');
const files = () => walk(root(), (n) => n.endsWith('.jsonl') || n.endsWith('.jsonl.zst'));

function readSession(file) {
  try {
    const raw = fs.readFileSync(file);
    return file.endsWith('.zst') ? Buffer.from(fzstd.decompress(raw)) : raw;
  } catch { return null; }
}

function ingest(store) {
  if (!store.kv('codexIngestV1')) { store.resetProvider('codex', '.codex'); store.kv('codexIngestV1', true); }
  for (const f of files()) {
    if (store.mtime(f.file) === f.mtimeMs) continue; // değişmemiş dosyayı atla
    const data = readSession(f.file);
    if (!data) continue;
    const start = store.offset(f.file);
    const lastNL = data.lastIndexOf(0x0a);
    if (data.length > start && lastNL >= start) {
      let model = 'codex';
      let prevTotal = store.fileTotal(f.file) || 0;
      const name = path.basename(f.file);
      forEachLine(data, start, lastNL + 1, (line) => {
        let o; try { o = JSON.parse(line); } catch { return; }
        const p = o.payload; if (!p) return;
        if (o.type === 'turn_context' && p.model) { model = p.model; return; }
        if (p.type !== 'token_count' || !p.info) return;
        const last = p.info.last_token_usage, tot = p.info.total_token_usage && p.info.total_token_usage.total_tokens;
        const ts = isoMs(o.timestamp);
        if (!last || typeof tot !== 'number' || ts == null || typeof o.ordinal !== 'number') return;
        if (tot === prevTotal) return; // aynı toplamı taşıyan tekrar olaylar çift sayılmasın
        prevTotal = tot;
        const input = last.input_tokens || 0, cached = last.cached_input_tokens || 0;
        store.upsert('codex', `${name}|${o.ordinal}`, ts, model, Math.max(0, input - cached), last.output_tokens || 0, 0, cached);
      });
      store.setFileTotal(f.file, prevTotal);
      store.setOffset(f.file, lastNL + 1);
    }
    store.setMtime(f.file, f.mtimeMs);
  }
}

function latestRateLimits(data) {
  let best = null;
  forEachLine(data, 0, data.length, (line) => {
    if (!line.includes('rate_limits')) return;
    let o; try { o = JSON.parse(line); } catch { return; }
    const rl = o.payload && o.payload.rate_limits; const ts = isoMs(o.timestamp);
    if (!rl || ts == null) return;
    if (!best || ts > best.ts) {
      const win = (w) => (w && typeof w.used_percent === 'number' && typeof w.resets_at === 'number') ? { used: w.used_percent, resets: w.resets_at * 1000 } : null;
      best = { ts, primary: win(rl.primary), secondary: win(rl.secondary) };
    }
  });
  return best;
}

function read(store) {
  ingest(store);
  const now = Date.now();
  const list = files().sort((a, b) => b.mtimeMs - a.mtimeMs);
  // En yeni dosyadan başla, ilk limit kaydında dur: eski dosyalar daha eski değer taşır.
  let latest = null;
  for (const f of list) {
    const data = readSession(f.file);
    const r = data && latestRateLimits(data);
    if (r) { latest = r; break; }
  }
  if (!latest) return { limitConfidence: 'none', tokenConfidence: 'none', extra: [], notes: ['Codex kayıtlarında limit bilgisi bulunamadı.'] };
  const left = (w) => (!w ? null : (w.resets <= now ? 1 : Math.max(0, Math.min(1, 1 - w.used / 100))));
  const sod = new Date(); sod.setHours(0, 0, 0, 0);
  const u = {
    fiveHourLeft: left(latest.primary), weeklyLeft: left(latest.secondary),
    fiveHourReset: latest.primary && latest.primary.resets, weeklyReset: latest.secondary && latest.secondary.resets,
    todayTokens: store.billableSince('codex', sod.getTime()),
    limitConfidence: 'exact', tokenConfidence: 'exact', extra: [],
    notes: [`Limit ve token: Codex oturum kayıtlarından (son kayıt ${new Date(latest.ts).toLocaleString('tr-TR')}).`],
  };
  if (latest.primary && latest.primary.resets <= now) u.notes.push('Son kayıttan beri 5 saatlik pencere sıfırlandı; yeni kullanım olmadığı için %100 gösteriliyor.');
  if (latest.secondary && latest.secondary.resets <= now) u.notes.push('Haftalık pencere sıfırlandı; yeni kullanım olmadığı için %100 gösteriliyor.');
  return u;
}

module.exports = { read, ingest };
